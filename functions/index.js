const functions = require("firebase-functions");
const admin = require("firebase-admin");
const vision = require("@google-cloud/vision");

admin.initializeApp();

const bucket = admin.storage().bucket("boltlog.firebasestorage.app");
const visionClient = new vision.ImageAnnotatorClient();

// #region agent log
async function agentDebugLog(hypothesisId, message, data, location) {
  try {
    await fetch(
      "http://127.0.0.1:7242/ingest/95f0f530-8027-4079-8e24-158242535564",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          id: `log_${Date.now()}_${Math.random().toString(36).slice(2)}`,
          runId: "initial",
          hypothesisId,
          location,
          message,
          data,
          timestamp: Date.now(),
        }),
      }
    );
  } catch (e) {
    // Swallow debug logging errors
  }
}
// #endregion

/**
 * Callable function: upload image to Storage.
 * Client sends: { path: string, imageBase64: string }
 * Returns: { path: string }
 * Requires: authenticated user (request.auth.uid)
 */
exports.uploadDriverImage = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be signed in to upload images"
    );
  }

  const { path, imageBase64 } = data;
  if (!path || !imageBase64) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "path and imageBase64 are required"
    );
  }

  // Validate path is under drivers/ or senders/
  if (!path.startsWith("drivers/") && !path.startsWith("senders/")) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Path must start with drivers/ or senders/"
    );
  }

  try {
    const buffer = Buffer.from(imageBase64, "base64");
    const file = bucket.file(path);
    await file.save(buffer, {
      metadata: { contentType: "image/jpeg" },
    });
    return { path };
  } catch (err) {
    console.error("Upload error:", err);
    throw new functions.https.HttpsError(
      "internal",
      err.message || "Upload failed"
    );
  }
});

/**
 * Firestore trigger: when a driver profile is created/updated and has
 * required documents (license + selfie), automatically verify the
 * account using a simple face-based check.
 */
exports.onDriverDocumentsUpdated = functions.firestore
  .document("users/{uid}")
  .onWrite(async (change, context) => {
    const after = change.after.exists ? change.after.data() : null;
    if (!after) {
      return null;
    }

    const role = (after.role || "").toLowerCase();
    if (role !== "driver") {
      return null;
    }

    const {
      driverLicenseImageUrl,
      selfieImageUrl,
      verificationStatus,
    } = after;

    const before = change.before.exists ? change.before.data() : null;
    if (before) {
      const {
        driverLicenseImageUrl: prevDriverLicenseImageUrl,
        selfieImageUrl: prevSelfieImageUrl,
      } = before;

      const licenseImageUnchanged =
        prevDriverLicenseImageUrl === driverLicenseImageUrl;
      const selfieImageUnchanged = prevSelfieImageUrl === selfieImageUrl;

      if (licenseImageUnchanged && selfieImageUnchanged) {
        return null;
      }
    }

    // #region agent log
    agentDebugLog(
      "H1_H3",
      "onDriverDocumentsUpdated entry",
      {
        role,
        hasDriverLicenseImage: !!driverLicenseImageUrl,
        hasSelfieImage: !!selfieImageUrl,
        existingVerificationStatus: verificationStatus || null,
      },
      "functions/index.js:onDriverDocumentsUpdated"
    );
    // #endregion

    // Only proceed when both ID and selfie images are present
    if (!driverLicenseImageUrl || !selfieImageUrl) {
      return null;
    }

    // Do not override if already verified/auto_verified
    if (
      verificationStatus === "verified" ||
      verificationStatus === "auto_verified"
    ) {
      return null;
    }

    const bucketName = "boltlog.firebasestorage.app";

    // Helper: analyze faces in an image and return basic stats
    async function analyzeFaces(gcsPath) {
      try {
        const gcsUri = `gs://${bucketName}/${gcsPath}`;
        const [result] = await visionClient.faceDetection(gcsUri);
        const faces = result.faceAnnotations || [];
        return {
          hasFace: faces.length > 0,
          faceCount: faces.length,
        };
      } catch (err) {
        console.error("Vision API error for", gcsPath, err);
        return {
          hasFace: false,
          faceCount: 0,
          error: err.message || String(err),
        };
      }
    }

    let autoVerified = false;

    try {
      const startId = Date.now();
      const startSelfie = Date.now();

      const [idAnalysis, selfieAnalysis] = await Promise.all([
        analyzeFaces(driverLicenseImageUrl),
        analyzeFaces(selfieImageUrl),
      ]);

      const idDurationMs = Date.now() - startId;
      const selfieDurationMs = Date.now() - startSelfie;

      // #region agent log
      agentDebugLog(
        "H2",
        "Vision face detection for license completed",
        {
          durationMs: idDurationMs,
          hasFace: idAnalysis.hasFace,
          faceCount: idAnalysis.faceCount,
        },
        "functions/index.js:onDriverDocumentsUpdated"
      );
      // #endregion

      // #region agent log
      agentDebugLog(
        "H2",
        "Vision face detection for selfie completed",
        {
          durationMs: selfieDurationMs,
          hasFace: selfieAnalysis.hasFace,
          faceCount: selfieAnalysis.faceCount,
        },
        "functions/index.js:onDriverDocumentsUpdated"
      );
      // #endregion

      // Make auto-verification easier: require a clear face only in the selfie.
      const selfieOk = !!selfieAnalysis.hasFace;
      const licenseOk = !!idAnalysis.hasFace;

      autoVerified = selfieOk;

      let finalStatus = autoVerified ? "auto_verified" : "needs_review";
      let verificationNotes = null;

      if (!selfieOk) {
        finalStatus = "needs_review";
        verificationNotes =
          "We could not clearly detect your face in the selfie. Please retake a selfie in good lighting with only your face visible.";
      } else if (!licenseOk) {
        // Selfie is fine, but license face detection is weak – allow auto verification but warn.
        finalStatus = "auto_verified";
        verificationNotes =
          "Your account is verified, but we could not clearly detect the face on your licence photo. If requested, please re-upload a clearer photo of your licence.";
      }

      // #region agent log
      agentDebugLog(
        "H1_H2",
        "Automatic verification decision",
        {
          autoVerified,
          finalStatus,
          selfieOk,
          licenseOk,
        },
        "functions/index.js:onDriverDocumentsUpdated"
      );
      // #endregion

      await change.after.ref.update({
        verificationStatus: finalStatus,
        verifiedAt: finalStatus === "auto_verified" ? new Date().toISOString() : null,
        verificationNotes,
      });
    } catch (err) {
      console.error("Error during automatic verification:", err);
      await change.after.ref.update({
        verificationStatus: "needs_review",
        verificationNotes:
          "Automatic verification error. Please contact support or re-upload your documents.",
      });
    }

    return null;
  });
