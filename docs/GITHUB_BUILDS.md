# Android APK & iOS builds on GitHub

Binaries are **not** stored in git. They are built in **GitHub Actions** and kept as **Artifacts** on each run.

## Get the APK (Android)

1. Open the repo on **GitHub** → **Actions**
2. Open workflow **Build Android APK**
3. Open the latest **green** run (or **Run workflow** to start one)
4. Scroll to **Artifacts** → download **`boltlog-apk`** (contains `app-release.apk`)

## Get the iOS archive

1. **Actions** → **Build iOS archive**
2. Latest successful run → **Artifacts** → **`boltlog-ios-archive`**

The CI build uses **`flutter build ipa --release --no-codesign`**. You still need **signing** (Apple Developer) to install on devices or submit to the App Store — use Xcode or Transporter with your certificates/profiles.

## When workflows run

- **Push to `main`** when relevant paths change (`lib/`, `android/` or `ios/`, `pubspec.yaml`, etc.)
- **Any time:** Actions → select the workflow → **Run workflow**

## Firestore rules deploy

See **`docs/FIREBASE_CI.md`** — separate workflow **Deploy Firestore rules**.
