import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/testing_flags.dart';
import 'package:flutter/foundation.dart';
import '../models/ride_model.dart';
import '../models/user_model.dart';
import '../models/transporter_offer_model.dart';
import 'messaging_service.dart';
import 'pricing_service.dart';
import 'notification_service.dart';
import 'user_service.dart';

/// inDrive-style negotiation: a state machine that manages a digital "handshake."
/// - open: rider proposed_price broadcast; drivers can counter (+10% / +20% / +30% or custom).
/// - pending + priceStatus pending: NEGOTIATING (counter-offers exchanged).
/// - pending + priceStatus accepted: rider locked on one driver; finalPrice set; driver must "Accept" to proceed.
/// - in_progress: both agreed; final_fare locked; commission = finalPrice * platformFeePercentage.
/// Concurrency: only the first driver the rider "Accepts" is linked (transaction + acceptedTransporterId).
class RideService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Create a new ride request. inDrive-style: broadcast to nearby drivers via push.
  Future<String> createRide(RideModel ride) async {
    try {
      final docRef = await _firestore.collection('rides').add(ride.toMap());
      final rideId = docRef.id;

      // Option B: Notify nearby drivers (push when request is created)
      if (ride.pickupLat != null && ride.pickupLng != null) {
        try {
          final userService = UserService();
          final nearbyDrivers = await userService.getNearbyDriversOnce(
            latitude: ride.pickupLat!,
            longitude: ride.pickupLng!,
            radiusKm: 25.0,
          );
          final notificationService = NotificationService();
          final priceStr = ride.price != null ? '\$${ride.price!.toStringAsFixed(2)} – ' : '';
          final message = '$priceStr${ride.pickupLocation} to ${ride.dropoffLocation}';
          for (final driver in nearbyDrivers) {
            await notificationService.createNotification(
              userId: driver.uid,
              type: 'new_request_nearby',
              title: 'New request near you',
              message: message,
              rideId: rideId,
              data: {'rideId': rideId},
            );
          }
        } catch (e) {
          debugPrint('Error notifying nearby drivers: $e');
        }
      }
      return rideId;
    } catch (e) {
      throw Exception('Error creating ride: $e');
    }
  }

  // Enforce only one active ride per user (open / pending / in progress / parcel_collected)
  Future<bool> userHasActiveRide(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection('rides')
          .where('userId', isEqualTo: userId)
          .where('status',
              whereIn: ['open', 'pending', 'in_progress', 'parcel_collected'])
          .limit(1)
          .get();
      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      throw Exception('Error checking active rides: $e');
    }
  }

  // Get user's rides with pagination
  Future<List<RideModel>> getUserRides(
    String userId, {
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query query = _firestore
          .collection('rides')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final querySnapshot = await query.get();

      return querySnapshot.docs
          .map((doc) => RideModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      throw Exception('Error getting user rides: $e');
    }
  }

  // Stream user's rides with pagination
  Stream<List<RideModel>> streamUserRides(String userId, {int limit = 50}) {
    return _firestore
        .collection('rides')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RideModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .toList());
  }

  // Update ride status
  Future<void> updateRideStatus(String rideId, String status, {String? driverId}) async {
    try {
      final updateData = <String, dynamic>{'status': status};
      if (driverId != null) updateData['driverId'] = driverId;
      if (status == 'completed') {
        updateData['completedAt'] = DateTime.now().toIso8601String();
      }

      await _firestore.collection('rides').doc(rideId).update(updateData);
    } catch (e) {
      throw Exception('Error updating ride status: $e');
    }
  }

  // Get ride by ID
  Future<RideModel?> getRide(String rideId) async {
    try {
      final doc = await _firestore.collection('rides').doc(rideId).get();
      if (doc.exists) {
        return RideModel.fromMap(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      throw Exception('Error getting ride: $e');
    }
  }

  /// One-time fetch of a ride by ID (e.g. for notification deep link).
  Future<RideModel?> getRideById(String rideId) async {
    final snapshot = await _firestore.collection('rides').doc(rideId).get();
    if (snapshot.exists && snapshot.data() != null) {
      return RideModel.fromMap(snapshot.data()!, snapshot.id);
    }
    return null;
  }

  // Stream a single ride by ID for real-time updates
  Stream<RideModel?> streamRideById(String rideId) {
    return _firestore
        .collection('rides')
        .doc(rideId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists) {
        return RideModel.fromMap(snapshot.data()!, snapshot.id);
      }
      return null;
    });
  }

  /// Transporter writes live GPS to the ride document so the sender's tracking map
  /// updates in real time via [streamRideById].
  Future<void> updateDriverLiveLocationOnRide(
    String rideId,
    double latitude,
    double longitude,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw Exception('Not signed in');
    }
    try {
      final rideRef = _firestore.collection('rides').doc(rideId);
      final snap = await rideRef.get();
      if (!snap.exists) throw Exception('Ride not found');
      final data = snap.data()!;
      final driverId = data['driverId'] as String?;
      final accepted = data['acceptedTransporterId'] as String?;
      final negotiating = data['negotiatingTransporterId'] as String?;
      final status = data['status'] as String? ?? '';
      final allowed = driverId == uid ||
          accepted == uid ||
          (status == 'pending' && (negotiating == uid || accepted == uid));
      if (!allowed) {
        throw Exception('Not assigned to this delivery');
      }
      await rideRef.update({
        'driverLiveLat': latitude,
        'driverLiveLng': longitude,
        'driverLocationUpdatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Error updating live location: $e');
    }
  }

  // Cancel ride (convenience wrapper)
  Future<void> cancelRide(String rideId) async {
    await cancelRideWithReason(rideId, cancelledBy: 'sender');
  }

  /// inDrive-style cancellation: free when open/pending (before driver committed);
  /// after driver accepted, cancel is "late" – notify driver and store reason.
  Future<void> cancelRideWithReason(
    String rideId, {
    required String cancelledBy,
    String? cancellationReason,
  }) async {
    final rideRef = _firestore.collection('rides').doc(rideId);
    final rideSnap = await rideRef.get();
    if (!rideSnap.exists) throw Exception('Ride not found');
    final data = rideSnap.data()!;
    final status = data['status'] as String? ?? 'open';
    final driverId = data['driverId'] as String?;

    final update = <String, dynamic>{
      'status': 'cancelled',
      'cancelledAt': DateTime.now().toIso8601String(),
      'cancelledBy': cancelledBy,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (cancellationReason != null && cancellationReason.isNotEmpty) {
      update['cancellationReason'] = cancellationReason;
    }
    await rideRef.update(update);

    // Notify the other party
    try {
      final notificationService = NotificationService();
      if (cancelledBy == 'transporter') {
        final senderId = data['userId'] as String?;
        if (senderId != null) {
          await notificationService.createNotification(
            userId: senderId,
            type: 'ride_cancelled',
            title: 'Driver cancelled',
            message: 'The transporter has cancelled this delivery. You can create a new request.',
            rideId: rideId,
            data: {'rideId': rideId, 'cancelledBy': cancelledBy},
          );
        }
      } else if (driverId != null && (status == 'in_progress' || status == 'parcel_collected')) {
        await notificationService.createNotification(
          userId: driverId,
          type: 'ride_cancelled',
          title: 'Request cancelled',
          message: 'The sender has cancelled this delivery.',
          rideId: rideId,
          data: {'rideId': rideId, 'cancelledBy': cancelledBy},
        );
      }
    } catch (e) {
      debugPrint('Error notifying of cancellation: $e');
    }
  }

  /// True if cancellation is "free" (inDrive: before driver is committed). After driver accepted, late cancel.
  bool isFreeCancellation(RideModel ride) {
    if (ride.status == 'cancelled') return false;
    return ride.driverId == null &&
        (ride.status == 'open' || (ride.status == 'pending' && ride.acceptedTransporterId == null));
  }

  // Get available rides for transporters (open, no driver assigned)
  // Rides are automatically excluded when:
  // Only 'open' rides are available. When an order is in negotiation (status 'pending'
  // or negotiatingTransporterId set), it is unavailable to other transporters.
  Stream<List<RideModel>> streamAvailableRides() {
    return _firestore
        .collection('rides')
        .where('status', isEqualTo: 'open')
        .snapshots()
        .map((snapshot) {
          // #region agent log
          try {
            final logData = {
              'sessionId': 'debug-session',
              'runId': 'run1',
              'hypothesisId': 'B,C,D',
              'location': 'ride_service.dart:156',
              'message': 'streamAvailableRides - query snapshot received',
              'data': {
                'totalDocs': snapshot.docs.length,
                'docs': snapshot.docs.map((doc) {
                  final d = doc.data();
                  return {
                    'id': doc.id,
                    'status': d['status'],
                    'driverId': d['driverId'],
                    'userId': d['userId'],
                  };
                }).toList(),
              },
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            };
            final logFile = File(r'c:\Users\ZETDC\Desktop\Boltlog\boltlog\.cursor\debug.log');
            logFile.writeAsStringSync('${jsonEncode(logData)}\n', mode: FileMode.append);
          } catch (_) {}
          // #endregion
          
          final rides = <RideModel>[];
          for (var doc in snapshot.docs) {
            final data = doc.data();
            // Only include rides where driverId is null, missing, or empty
            final driverId = data['driverId'];
            
            // #region agent log
            try {
              final logData2 = {
                'sessionId': 'debug-session',
                'runId': 'run1',
                'hypothesisId': 'D',
                'location': 'ride_service.dart:185',
                'message': 'Checking driverId filter',
                'data': {
                  'rideId': doc.id,
                  'driverId': driverId,
                  'driverIdType': driverId?.runtimeType.toString() ?? 'null',
                  'isNull': driverId == null,
                  'isEmptyString': driverId is String && driverId.isEmpty,
                  'willInclude': driverId == null || (driverId is String && driverId.isEmpty) || (driverId?.toString().trim().isEmpty ?? false),
                },
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              };
              final logFile = File(r'c:\Users\ZETDC\Desktop\Boltlog\boltlog\.cursor\debug.log');
              logFile.writeAsStringSync('${jsonEncode(logData2)}\n', mode: FileMode.append);
            } catch (_) {}
            // #endregion
            
            // Only include rides that are still open, have no driver, and are not in negotiation.
            // Rides in negotiation (status 'pending' or negotiatingTransporterId set) are unavailable to other transporters.
            final negotiatingTransporterId = data['negotiatingTransporterId']?.toString().trim();
            final isInNegotiation = negotiatingTransporterId != null && negotiatingTransporterId.isNotEmpty;
            if ((driverId == null ||
                (driverId is String && driverId.isEmpty) ||
                (driverId?.toString().trim().isEmpty ?? false)) &&
                data['status'] == 'open' &&
                !isInNegotiation) {
              try {
                final ride = RideModel.fromMap(data, doc.id);
                if (ride.negotiatingTransporterId != null &&
                    ride.negotiatingTransporterId!.trim().isNotEmpty) continue;
                if (ride.driverId == null && ride.status == 'open') {
                  rides.add(ride);
                  
                  // #region agent log
                  try {
                    final logData3 = {
                      'sessionId': 'debug-session',
                      'runId': 'run1',
                      'hypothesisId': 'D',
                      'location': 'ride_service.dart:213',
                      'message': 'Ride included in available rides',
                      'data': {'rideId': doc.id, 'status': ride.status},
                      'timestamp': DateTime.now().millisecondsSinceEpoch,
                    };
                    final logFile = File(r'c:\Users\ZETDC\Desktop\Boltlog\boltlog\.cursor\debug.log');
                    logFile.writeAsStringSync('${jsonEncode(logData3)}\n', mode: FileMode.append);
                  } catch (_) {}
                  // #endregion
                } else {
                  // #region agent log
                  try {
                    final logData4 = {
                      'sessionId': 'debug-session',
                      'runId': 'run1',
                      'hypothesisId': 'D',
                      'location': 'ride_service.dart:228',
                      'message': 'Ride excluded - driverId not null in model',
                      'data': {'rideId': doc.id, 'driverId': ride.driverId},
                      'timestamp': DateTime.now().millisecondsSinceEpoch,
                    };
                    final logFile = File(r'c:\Users\ZETDC\Desktop\Boltlog\boltlog\.cursor\debug.log');
                    logFile.writeAsStringSync('${jsonEncode(logData4)}\n', mode: FileMode.append);
                  } catch (_) {}
                  // #endregion
                }
              } catch (e) {
                // #region agent log
                try {
                  final logData5 = {
                    'sessionId': 'debug-session',
                    'runId': 'run1',
                    'hypothesisId': 'B',
                    'location': 'ride_service.dart:243',
                    'message': 'Error parsing ride document',
                    'data': {'rideId': doc.id, 'error': e.toString()},
                    'timestamp': DateTime.now().millisecondsSinceEpoch,
                  };
                  final logFile = File(r'c:\Users\ZETDC\Desktop\Boltlog\boltlog\.cursor\debug.log');
                  logFile.writeAsStringSync('${jsonEncode(logData5)}\n', mode: FileMode.append);
                } catch (_) {}
                // #endregion
                // Skip invalid documents
                continue;
              }
            } else {
              // #region agent log
              try {
                final logData6 = {
                  'sessionId': 'debug-session',
                  'runId': 'run1',
                  'hypothesisId': 'D',
                  'location': 'ride_service.dart:260',
                  'message': 'Ride excluded - driverId filter failed',
                  'data': {'rideId': doc.id, 'driverId': driverId},
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                };
                final logFile = File(r'c:\Users\ZETDC\Desktop\Boltlog\boltlog\.cursor\debug.log');
                logFile.writeAsStringSync('${jsonEncode(logData6)}\n', mode: FileMode.append);
              } catch (_) {}
              // #endregion
            }
          }
          
          // Sort by createdAt descending (newest first)
          rides.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          
          // #region agent log
          try {
            final logData7 = {
              'sessionId': 'debug-session',
              'runId': 'run1',
              'hypothesisId': 'C,E',
              'location': 'ride_service.dart:280',
              'message': 'streamAvailableRides - final result',
              'data': {
                'totalRides': rides.length,
                'rideIds': rides.map((r) => r.id ?? 'no-id').toList(),
              },
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            };
            final logFile = File(r'c:\Users\ZETDC\Desktop\Boltlog\boltlog\.cursor\debug.log');
            logFile.writeAsStringSync('${jsonEncode(logData7)}\n', mode: FileMode.append);
          } catch (_) {}
          // #endregion
          
          return rides;
        });
  }

  /// Transporter-specific negotiations that should remain visible even after logout.
  /// These are rides where the transporter is the active negotiatingTransporterId and
  /// the ride is still in the negotiation phase (priceStatus can be `pending` or `accepted`).
  Stream<List<RideModel>> streamTransporterNegotiations(String transporterId) {
    return _firestore
        .collection('rides')
        .where('status', isEqualTo: 'pending')
        .where('negotiatingTransporterId', isEqualTo: transporterId)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => RideModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
              .where((ride) =>
                  ride.priceStatus == 'pending' || ride.priceStatus == 'accepted')
              .toList();
        });
  }

  /// Transporter "active" items = accepted/in-progress deliveries + active negotiations.
  Stream<List<RideModel>> streamTransporterActiveItems(String transporterId) {
    final controller = StreamController<List<RideModel>>.broadcast();

    List<RideModel> _deliveries = [];
    List<RideModel> _negotiations = [];

    void emitMerged() {
      final byId = <String, RideModel>{};
      for (final r in _deliveries) {
        final id = r.id;
        if (id != null) byId[id] = r;
      }
      for (final r in _negotiations) {
        final id = r.id;
        if (id != null) byId[id] = r;
      }
      controller.add(byId.values.toList());
    }

    final sub1 = streamTransporterDeliveries(transporterId).listen(
      (data) {
        _deliveries = data;
        emitMerged();
      },
      onError: controller.addError,
    );
    final sub2 = streamTransporterNegotiations(transporterId).listen(
      (data) {
        _negotiations = data;
        emitMerged();
      },
      onError: controller.addError,
    );

    controller.onCancel = () async {
      await sub1.cancel();
      await sub2.cancel();
    };

    return controller.stream;
  }

  // Get transporter's active deliveries
  Stream<List<RideModel>> streamTransporterDeliveries(String transporterId) {
    return _firestore
        .collection('rides')
        .where('driverId', isEqualTo: transporterId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RideModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .where((ride) => ride.status == 'accepted' || 
                            ride.status == 'in_progress' || 
                            ride.status == 'parcel_collected')
            .toList());
  }

  // Get transporter's completed deliveries (for earnings calculation) with pagination
  Stream<List<RideModel>> streamTransporterCompletedDeliveries(
    String transporterId, {
    int limit = 50,
  }) {
    return _firestore
        .collection('rides')
        .where('driverId', isEqualTo: transporterId)
        .where('status', isEqualTo: 'completed')
        .orderBy('completedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RideModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .toList());
  }

  // --- Transporter offers (inDrive-style interest) ---

  CollectionReference<Map<String, dynamic>> _offerCollection(String rideId) {
    return _firestore
        .collection('rides')
        .doc(rideId)
        .collection('offers');
  }

  // Transporter expresses interest in a ride (creates or updates an offer)
  Future<void> createOrUpdateOffer(
    String rideId,
    String transporterId, {
    double? priceOffer,
  }) async {
    try {
      final offersRef = _offerCollection(rideId);
      final existing = await offersRef
          .where('transporterId', isEqualTo: transporterId)
          .limit(1)
          .get();

      final now = DateTime.now().toIso8601String();

      if (existing.docs.isNotEmpty) {
        await existing.docs.first.reference.update({
          'priceOffer': priceOffer,
          'updatedAt': now,
        });
      } else {
        await offersRef.add({
          'rideId': rideId,
          'transporterId': transporterId,
          'priceOffer': priceOffer,
          'status': 'pending',
          'createdAt': now,
          'updatedAt': now,
        });
      }
    } catch (e) {
      throw Exception('Error creating offer: $e');
    }
  }

  // Stream offers for a specific ride
  Stream<List<TransporterOfferModel>> streamOffersForRide(String rideId) {
    return _offerCollection(rideId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) =>
                TransporterOfferModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  // Mark selected and rejected offers when a transporter is chosen
  Future<void> markSelectedOffer(
      String rideId, String selectedOfferId) async {
    try {
      final offersRef = _offerCollection(rideId);
      final snapshot = await offersRef.get();

      for (final doc in snapshot.docs) {
        final newStatus =
            doc.id == selectedOfferId ? 'selected' : 'rejected';
        await doc.reference.update({
          'status': newStatus,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      throw Exception('Error updating offer statuses: $e');
    }
  }

  /// When sender declines an offer (without counter-offer), reject that offer and reopen the ride
  /// so it becomes visible to other transporters again.
  Future<void> rejectOfferAndReopenRide(String rideId, String offerId) async {
    try {
      final offerDoc = await _offerCollection(rideId).doc(offerId).get();
      if (!offerDoc.exists) return;
      final offerData = offerDoc.data() as Map<String, dynamic>?;
      final transporterId = offerData?['transporterId'] as String?;
      final rideSnap = await _firestore.collection('rides').doc(rideId).get();
      final senderUserId = rideSnap.data()?['userId'] as String?;

      await _firestore.collection('rides').doc(rideId).update({
        'status': 'open',
        'counterOffer': null,
        'priceStatus': null,
        'negotiatingTransporterId': null,
        'lastCounterOfferBy': null,
        'lastReopenReason': 'sender_declined',
        'updatedAt': DateTime.now().toIso8601String(),
      });
      await _offerCollection(rideId).doc(offerId).update({
        'status': 'rejected',
        'updatedAt': DateTime.now().toIso8601String(),
      });

      if (transporterId != null && senderUserId != null) {
        try {
          await NotificationService().createNotification(
            userId: transporterId,
            type: 'offer_declined',
            title: 'Offer Declined',
            message:
                'The sender has declined your offer. This request is open to other transporters.',
            rideId: rideId,
            data: {'rideId': rideId},
          );
          await MessagingService().sendSenderDeclinedServiceMessage(
            rideId: rideId,
            senderId: senderUserId,
            transporterId: transporterId,
          );
        } catch (e) {
          debugPrint('rejectOfferAndReopenRide notify/chat: $e');
        }
      }
    } catch (e) {
      throw Exception('Error rejecting offer and reopening ride: $e');
    }
  }

  /// When transporter declines the request, reopen the ride so it is visible to other transporters again.
  Future<void> transporterDeclineRequest(String rideId, String transporterId) async {
    try {
      final offersRef = _offerCollection(rideId);
      final snapshot = await offersRef
          .where('transporterId', isEqualTo: transporterId)
          .limit(1)
          .get();
      await _firestore.collection('rides').doc(rideId).update({
        'status': 'open',
        'counterOffer': null,
        'priceStatus': null,
        'negotiatingTransporterId': null,
        'lastCounterOfferBy': null,
        'lastReopenReason': 'transporter_declined',
        'updatedAt': DateTime.now().toIso8601String(),
      });
      for (final doc in snapshot.docs) {
        await doc.reference.update({
          'status': 'rejected',
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }

      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      final senderId = rideDoc.data()?['userId'] as String?;
      if (senderId != null) {
        try {
          await NotificationService().createNotification(
            userId: senderId,
            type: 'transporter_declined_request',
            title: 'Transporter Declined',
            message:
                'A transporter has declined your request. It is open again for other transporters.',
            rideId: rideId,
            data: {'rideId': rideId},
          );
          await MessagingService().sendTransporterDeclinedServiceMessage(
            rideId: rideId,
            transporterId: transporterId,
            senderId: senderId,
          );
        } catch (e) {
          debugPrint('transporterDeclineRequest notify/chat: $e');
        }
      }
    } catch (e) {
      throw Exception('Error declining request: $e');
    }
  }

  /// Clears [RideModel.lastReopenReason] after the sender has seen the transporter-decline UX.
  Future<void> clearLastReopenReason(String rideId) async {
    try {
      await _firestore.collection('rides').doc(rideId).update({
        'lastReopenReason': FieldValue.delete(),
      });
    } catch (e) {
      debugPrint('clearLastReopenReason: $e');
    }
  }

  // Accept a transport request
  // For direct acceptance (no negotiation): Deduction happens immediately
  // For negotiation: Deduction happens when sender accepts counter-offer (in respondToCounterOffer)
  Future<void> acceptRide(String rideId, String transporterId) async {
    try {
      await _firestore.runTransaction((transaction) async {
        final rideRef = _firestore.collection('rides').doc(rideId);
        final userRef = _firestore.collection('users').doc(transporterId);

        final rideSnap = await transaction.get(rideRef);
        if (!rideSnap.exists) {
          throw Exception('Ride not found');
        }
        final rideData = rideSnap.data() as Map<String, dynamic>;
        
        final rideStatus = rideData['status'] as String? ?? 'open';
        final priceStatus = rideData['priceStatus'] as String?;
        
        // Check if ride is available for acceptance
        // Can accept if: open, or pending with priceStatus == 'accepted' (sender approved)
        if (rideStatus != 'open' && !(rideStatus == 'pending' && priceStatus == 'accepted')) {
          throw Exception('Ride is no longer available for acceptance');
        }
        
        // Check if ride already has a driver
        if (rideData['driverId'] != null && (rideData['driverId'] as String).isNotEmpty) {
          throw Exception('Ride has already been accepted by another transporter');
        }
        
        // Lock-in: use finalPrice (agreed) else current counter-offer else rider's price.
        // NOTE (testing mode): fee calculation and wallet deductions are disabled for now.
        final price = (rideData['price'] as num?)?.toDouble() ?? 0.0;
        final counterOffer = (rideData['counterOffer'] as num?)?.toDouble();

        // Accept ride: move to in_progress; lock final fare if not set (use counterOffer when in negotiation).
        final updatePayload = <String, dynamic>{
          'driverId': transporterId,
          'status': 'in_progress',
          'updatedAt': DateTime.now().toIso8601String(),
        };
        if (rideData['finalPrice'] == null) {
          updatePayload['finalPrice'] = counterOffer ?? price;
        }
        transaction.update(rideRef, updatePayload);
      });

      // Add a message to the ride chat and notify transporter
      try {
        final rideDoc = await _firestore.collection('rides').doc(rideId).get();
        final rideData = rideDoc.data();
        final senderUserId = rideData?['userId'] as String?;
        if (senderUserId != null) {
          await MessagingService().sendTransporterSelectedMessage(
            rideId: rideId,
            senderId: senderUserId,
            transporterId: transporterId,
          );
          await NotificationService().createNotification(
            userId: transporterId,
            type: 'transporter_selected',
            title: 'You were selected',
            message: 'You have been selected for this delivery. Open the chat to coordinate pickup.',
            rideId: rideId,
            data: {'rideId': rideId},
          );
        }
      } catch (chatError) {
        debugPrint('Error sending transporter-selected chat message: $chatError');
      }
      
      // NOTE (testing mode): post-acceptance insufficient balance notifications are disabled.
    } catch (e) {
      throw Exception('Error accepting ride: $e');
    }
  }

  // Check balance and notify transporter if insufficient
  Future<bool> checkBalanceAndNotify(String transporterId, double requiredAmount) async {
    try {
      final userDoc = await _firestore.collection('users').doc(transporterId).get();
      if (!userDoc.exists) {
        return false;
      }
      
      final userData = userDoc.data() as Map<String, dynamic>? ?? {};
      double currentBalance = (userData['driverWalletBalance'] as num?)?.toDouble() ?? 0.0;
      
      if (currentBalance < requiredAmount) {
        // Notify transporter to top up
        final notificationService = NotificationService();
        await notificationService.createNotification(
          userId: transporterId,
          type: 'insufficient_balance',
          title: 'Insufficient Balance',
          message: 'Your wallet balance (\$${currentBalance.toStringAsFixed(2)}) is insufficient. Please top up \$${requiredAmount.toStringAsFixed(2)} to accept this request.',
          data: {
            'requiredAmount': requiredAmount,
            'currentBalance': currentBalance,
            'shortfall': requiredAmount - currentBalance,
          },
        );
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Error checking balance: $e');
      return false;
    }
  }

  // Deduct fee from transporter wallet (called after negotiation is accepted)
  Future<void> deductAcceptanceFee(String transporterId, double ridePrice) async {
    try {
      final fee = ridePrice * PricingService.platformFeePercentage;
      
      await _firestore.runTransaction((transaction) async {
        final userRef = _firestore.collection('users').doc(transporterId);
        final userSnap = await transaction.get(userRef);
        
        if (!userSnap.exists) {
          throw Exception('User not found');
        }
        
        final userData = userSnap.data() as Map<String, dynamic>;
        double currentBalance = (userData['driverWalletBalance'] as num?)?.toDouble() ?? 0.0;
        
        if (currentBalance < fee) {
          throw Exception('Insufficient balance for deduction');
        }
        
        final newBalance = currentBalance - fee;
        
        transaction.update(userRef, {
          'driverWalletBalance': newBalance,
        });
      });
    } catch (e) {
      throw Exception('Error deducting fee: $e');
    }
  }

  // Mark as picked up / parcel collected (notify sender so both see status)
  Future<void> markPickedUp(String rideId) async {
    final now = DateTime.now().toIso8601String();
    await _firestore.collection('rides').doc(rideId).update({
      'status': 'parcel_collected',
      'pickupMarkedByDriverAt': now,
      'updatedAt': now,
    });
    try {
      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      final userId = rideDoc.data()?['userId'] as String?;
      if (userId != null) {
        final notificationService = NotificationService();
        await notificationService.createNotification(
          userId: userId,
          type: 'parcel_collected',
          title: 'Parcel Collected',
          message:
              'The transporter collected your parcel. Please open the app and confirm pickup.',
          rideId: rideId,
        );
      }
    } catch (e) {
      debugPrint('Error notifying sender of parcel collected: $e');
    }
  }

  /// Sender acknowledges that they agree the parcel was collected.
  Future<void> senderConfirmParcelCollected(String rideId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');
    final ref = _firestore.collection('rides').doc(rideId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Ride not found');
    final data = snap.data()!;
    if (data['userId'] != uid) {
      throw Exception('Only the sender can confirm pickup');
    }
    final now = DateTime.now().toIso8601String();
    await ref.update({
      'pickupConfirmedBySenderAt': now,
      'updatedAt': now,
    });
  }

  /// Transporter marks delivery complete — [status] stays `parcel_collected` until [senderConfirmDeliveryComplete].
  Future<void> markDelivered(String rideId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');
    final ref = _firestore.collection('rides').doc(rideId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Ride not found');
    final data = snap.data()!;
    final driverId = data['driverId'] as String?;
    if (driverId != uid) {
      throw Exception('Only the assigned transporter can mark delivered');
    }
    if (data['deliveryMarkedByDriverAt'] != null &&
        (data['deliveryMarkedByDriverAt'] as String).isNotEmpty) {
      throw Exception('Already marked — waiting for sender to confirm delivery');
    }
    final now = DateTime.now().toIso8601String();
    await ref.update({
      'deliveryMarkedByDriverAt': now,
      'updatedAt': now,
    });
    final senderId = data['userId'] as String?;
    if (senderId != null) {
      try {
        await NotificationService().createNotification(
          userId: senderId,
          type: 'delivery_pending_sender_confirm',
          title: 'Confirm Delivery',
          message:
              'The transporter marked the parcel as delivered. Please confirm in the app to complete the trip.',
          rideId: rideId,
        );
      } catch (e) {
        debugPrint('notify sender delivery pending: $e');
      }
    }
  }

  /// Sender confirms receipt — sets [status] to `completed` and finalizes the trip.
  Future<void> senderConfirmDeliveryComplete(String rideId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');
    final ref = _firestore.collection('rides').doc(rideId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Ride not found');
    final data = snap.data()!;
    if (data['userId'] != uid) {
      throw Exception('Only the sender can confirm delivery');
    }
    if (data['deliveryMarkedByDriverAt'] == null) {
      throw Exception('Transporter has not marked delivery yet');
    }
    final now = DateTime.now().toIso8601String();
    await ref.update({
      'status': 'completed',
      'completedAt': now,
      'deliveryConfirmedBySenderAt': now,
      'updatedAt': now,
    });
    final driverId = data['driverId'] as String?;
    if (driverId != null) {
      try {
        await NotificationService().createNotification(
          userId: driverId,
          type: 'delivery_confirmed_by_sender',
          title: 'Delivery Confirmed',
          message: 'The sender confirmed receipt. This delivery is complete.',
          rideId: rideId,
        );
      } catch (e) {
        debugPrint('notify transporter delivery confirmed: $e');
      }
    }
  }

  // Track when the sender views the request (so transporter can see "Sender has viewed")
  Future<void> updateSenderLastViewed(String rideId) async {
    try {
      await _firestore.collection('rides').doc(rideId).update({
        'senderLastViewedAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Silently fail - not critical
    }
  }

  // Track when a transporter views a request
  Future<void> trackRequestView(String rideId, String transporterId) async {
    try {
      final viewersRef = _firestore
          .collection('rides')
          .doc(rideId)
          .collection('viewers')
          .doc(transporterId);
      
      await viewersRef.set({
        'transporterId': transporterId,
        'viewedAt': DateTime.now().toIso8601String(),
        'lastSeenAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Error tracking request view: $e');
    }
  }

  // Update last seen when transporter is still viewing
  Future<void> updateViewerLastSeen(String rideId, String transporterId) async {
    try {
      final viewerRef = _firestore
          .collection('rides')
          .doc(rideId)
          .collection('viewers')
          .doc(transporterId);
      
      await viewerRef.update({
        'lastSeenAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Silently fail - not critical
    }
  }

  // Stream online transporters viewing a request
  Stream<List<UserModel>> streamOnlineViewers(String rideId) {
    return _firestore
        .collection('rides')
        .doc(rideId)
        .collection('viewers')
        .snapshots()
        .asyncMap((viewersSnapshot) async {
      final onlineTransporters = <UserModel>[];
      
      for (var viewerDoc in viewersSnapshot.docs) {
        final viewerData = viewerDoc.data();
        final transporterId = viewerData['transporterId'] as String?;
        final lastSeenAt = viewerData['lastSeenAt'] as String?;
        
        if (transporterId == null) continue;
        
        // Check if viewer was active in last 30 seconds
        if (lastSeenAt != null) {
          final lastSeen = DateTime.parse(lastSeenAt);
          final now = DateTime.now();
          if (now.difference(lastSeen).inSeconds > 30) {
            continue; // Skip offline viewers
          }
        }
        
        // Get transporter user data
        try {
          final userDoc = await _firestore
              .collection('users')
              .doc(transporterId)
              .get();
          
          if (userDoc.exists) {
            final userData = userDoc.data()!;
            // Only include if online (isAvailable = true) and role is Driver
            if (userData['role'] == 'Driver' && 
                (userData['isAvailable'] ?? false) == true) {
              onlineTransporters.add(UserModel.fromMap(userData));
            }
          }
        } catch (e) {
          // Skip if user not found
          continue;
        }
      }
      
      return onlineTransporters;
    });
  }

  // Submit counter-offer (transporter submits counter-offer to sender)
  // Changes ride status to 'pending' to indicate negotiation in progress
  Future<void> submitCounterOffer(
    String rideId,
    String transporterId,
    double counterOffer,
  ) async {
    try {
      // Ensure transporter is verified before allowing negotiation
      final userDoc = await _firestore.collection('users').doc(transporterId).get();
      if (!userDoc.exists) {
        throw Exception('Transporter account not found');
      }
      final userData = userDoc.data() as Map<String, dynamic>;
      final role = (userData['role'] as String? ?? '').toLowerCase();
      final verificationStatus =
          (userData['verificationStatus'] as String? ?? '').toLowerCase();

      if (!TestingFlags.relaxTransporterVerification &&
          role == 'driver' &&
          verificationStatus != 'auto_verified' &&
          verificationStatus != 'verified') {
        throw Exception(
            'Your documents are still being verified. You cannot negotiate on requests yet.');
      }

      // Get ride to find sender ID
      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      if (!rideDoc.exists) {
        throw Exception('Ride not found');
      }
      final rideData = rideDoc.data() as Map<String, dynamic>;
      final senderId = rideData['userId'] as String?;
      
      // Update the ride with counter-offer; mark this transporter as the one in negotiation (works for any sender/transporter)
      await _firestore.collection('rides').doc(rideId).update({
        'counterOffer': counterOffer,
        'priceStatus': 'pending',
        'status': 'pending',
        'lastCounterOfferBy': 'transporter',
        'negotiatingTransporterId': transporterId,
        'lastReopenReason': FieldValue.delete(),
        'updatedAt': DateTime.now().toIso8601String(),
      });

      // Also create/update the offer in the offers subcollection
      await createOrUpdateOffer(
        rideId,
        transporterId,
        priceOffer: counterOffer,
      );

      // Notify sender about the counter-offer
      if (senderId != null) {
        final notificationService = NotificationService();
        await notificationService.createNotification(
          userId: senderId,
          type: 'counter_offer',
          title: 'New Price Offer',
          message: 'A transporter has made a counter-offer of \$${counterOffer.toStringAsFixed(2)}. You can accept, reject, or make your own offer.',
          rideId: rideId,
          data: {
            'counterOffer': counterOffer,
            'transporterId': transporterId,
            'rideId': rideId,
          },
        );
      }
    } catch (e) {
      throw Exception('Error submitting counter-offer: $e');
    }
  }

  // Sender sends counter-counter-offer (renegotiates)
  Future<void> sendSenderCounterOffer(
    String rideId,
    String offerId,
    double senderCounterOffer,
  ) async {
    try {
      final rideRef = _firestore.collection('rides').doc(rideId);
      final offerRef = _offerCollection(rideId).doc(offerId);

      await _firestore.runTransaction((transaction) async {
        final offerSnap = await transaction.get(offerRef);
        if (!offerSnap.exists) {
          throw Exception('Offer not found');
        }

        final offerData = offerSnap.data() as Map<String, dynamic>;
        final transporterId = offerData['transporterId'] as String?;

        if (transporterId == null) {
          throw Exception('Transporter ID not found in offer');
        }

        // Update ride with sender's counter-offer; keep this transporter as the one in negotiation
        transaction.update(rideRef, {
          'counterOffer': senderCounterOffer,
          'priceStatus': 'pending',
          'status': 'pending',
          'lastCounterOfferBy': 'sender',
          'negotiatingTransporterId': transporterId,
          'lastReopenReason': FieldValue.delete(),
          'updatedAt': DateTime.now().toIso8601String(),
        });

        // Update the offer with sender's counter-offer
        transaction.update(offerRef, {
          'priceOffer': senderCounterOffer,
          'status': 'pending', // Keep as pending
          'updatedAt': DateTime.now().toIso8601String(),
        });
      });

      // Notify transporter about sender's counter-offer
      final offerDoc = await _offerCollection(rideId).doc(offerId).get();
      final offerData = offerDoc.data();
      final transporterId = offerData?['transporterId'] as String?;

      if (transporterId != null) {
        final notificationService = NotificationService();
        await notificationService.createNotification(
          userId: transporterId,
          type: 'sender_counter_offer',
          title: 'Sender Made a Counter-Offer',
          message: 'The sender has made a counter-offer of \$${senderCounterOffer.toStringAsFixed(2)}. You can accept, reject, or make another offer.',
          rideId: rideId,
          data: {
            'counterOffer': senderCounterOffer,
            'rideId': rideId,
          },
        );
      }
    } catch (e) {
      throw Exception('Error sending sender counter-offer: $e');
    }
  }

  // Respond to counter-offer (sender accepts, rejects, or sends counter-offer)
  Future<void> respondToCounterOffer(
    String rideId,
    String offerId,
    bool accepted, {
    double? senderCounterOffer, // Optional: if sender wants to counter-offer
  }) async {
    try {
      final rideRef = _firestore.collection('rides').doc(rideId);
      final offerRef = _offerCollection(rideId).doc(offerId);

      await _firestore.runTransaction((transaction) async {
        // Get the offer to get the counter-offer price
        final offerSnap = await transaction.get(offerRef);
        if (!offerSnap.exists) {
          throw Exception('Offer not found');
        }

        final offerData = offerSnap.data() as Map<String, dynamic>;
        // Firestore stores numeric values as num (which may be int or double),
        // so we need to safely convert to double to avoid type cast errors.
        final counterOffer =
            (offerData['priceOffer'] as num?)?.toDouble();
        final transporterId = offerData['transporterId'] as String?;

        // If sender sent a counter-offer, handle it
        if (senderCounterOffer != null && !accepted) {
          if (transporterId == null) {
            throw Exception('Transporter ID not found in offer');
          }

          // Update ride with sender's counter-offer; this offer's transporter is the one in negotiation
          transaction.update(rideRef, {
            'counterOffer': senderCounterOffer,
            'priceStatus': 'pending',
            'status': 'pending',
            'lastCounterOfferBy': 'sender',
            'negotiatingTransporterId': transporterId,
            'lastReopenReason': FieldValue.delete(),
            'updatedAt': DateTime.now().toIso8601String(),
          });

          // Update the offer with sender's counter-offer
          transaction.update(offerRef, {
            'priceOffer': senderCounterOffer,
            'status': 'pending', // Keep as pending
            'updatedAt': DateTime.now().toIso8601String(),
          });

          // Notification will be sent after transaction
          return; // Exit early, don't process accept/reject
        }

        if (accepted) {
          if (transporterId == null) {
            throw Exception('Transporter ID not found in offer');
          }

          // Update ride with accepted counter-offer
          // When sender accepts, set priceStatus to 'accepted' but keep status as 'pending'
          final updateData = <String, dynamic>{
            'price': counterOffer,
            'finalPrice': counterOffer,
            'counterOffer': null,
            'priceStatus': 'accepted',
            'status': 'pending',
            'acceptedTransporterId': transporterId,
            'negotiatingTransporterId': transporterId, // keep for clarity; this transporter was chosen
            'lastReopenReason': FieldValue.delete(),
            'updatedAt': DateTime.now().toIso8601String(),
          };
          transaction.update(rideRef, updateData);

          // Mark this offer as selected
          transaction.update(offerRef, {
            'status': 'selected',
            'updatedAt': DateTime.now().toIso8601String(),
          });

          // Reject all other offers
          final allOffers = await _offerCollection(rideId).get();
          for (var doc in allOffers.docs) {
            if (doc.id != offerId) {
              transaction.update(doc.reference, {
                'status': 'rejected',
                'updatedAt': DateTime.now().toIso8601String(),
              });
            }
          }
          
          // Don't deduct fee yet - deduction happens when transporter accepts ride
          // Fee will be deducted in acceptRide() after sender has approved
        } else {
          // Decline: reopen as a normal open request (same idea as [rejectOfferAndReopenRide]).
          // Any transporter can see/offer again; sender home shows "Waiting for transporters".
          transaction.update(rideRef, {
            'counterOffer': null,
            'priceStatus': null,
            'status': 'open',
            'negotiatingTransporterId': null,
            'lastCounterOfferBy': null,
            'lastReopenReason': 'sender_declined',
            'updatedAt': DateTime.now().toIso8601String(),
          });

          transaction.update(offerRef, {
            'status': 'rejected',
            'updatedAt': DateTime.now().toIso8601String(),
          });
        }
      });

      // If sender accepted the counter-offer, notify transporter so they can take delivery
      if (accepted) {
        final offerDoc = await _offerCollection(rideId).doc(offerId).get();
        final offerData = offerDoc.data();
        final transporterId = offerData?['transporterId'] as String?;

        if (transporterId != null) {
          final rideDoc = await _firestore.collection('rides').doc(rideId).get();
          final rideData = rideDoc.data();
          final agreedPrice =
              (rideData?['price'] as num?)?.toDouble() ?? 0.0;
          final senderUserId = rideData?['userId'] as String?;

          final notificationService = NotificationService();
          await notificationService.createNotification(
            userId: transporterId,
            type: 'counter_offer_accepted',
            title: 'Offer Accepted',
            message:
                'The sender has accepted your offer of \$${agreedPrice.toStringAsFixed(2)}. You can now accept the delivery request.',
            rideId: rideId,
            data: {
              'price': agreedPrice,
              'rideId': rideId,
            },
          );

          if (senderUserId != null) {
            await MessagingService().sendTransporterSelectedMessage(
              rideId: rideId,
              senderId: senderUserId,
              transporterId: transporterId,
            );
          }
        }
      }

      // If sender sent a counter-offer, notify transporter
      if (senderCounterOffer != null && !accepted) {
        final offerDoc = await _offerCollection(rideId).doc(offerId).get();
        final offerData = offerDoc.data();
        final transporterId = offerData?['transporterId'] as String?;

        if (transporterId != null) {
          final notificationService = NotificationService();
          await notificationService.createNotification(
            userId: transporterId,
            type: 'sender_counter_offer',
            title: 'Sender Made a Counter-Offer',
            message: 'The sender has made a counter-offer of \$${senderCounterOffer.toStringAsFixed(2)}. You can accept, reject, or make another offer.',
            rideId: rideId,
            data: {
              'counterOffer': senderCounterOffer,
              'rideId': rideId,
            },
          );
        }
      }

      // If sender declined the counter-offer (no new amount), notify + chat message
      if (!accepted && senderCounterOffer == null) {
        final offerDoc = await _offerCollection(rideId).doc(offerId).get();
        final offerData = offerDoc.data();
        final transporterId = offerData?['transporterId'] as String?;
        final rideDoc = await _firestore.collection('rides').doc(rideId).get();
        final senderUserId = rideDoc.data()?['userId'] as String?;

        if (transporterId != null) {
          final notificationService = NotificationService();
          await notificationService.createNotification(
            userId: transporterId,
            type: 'counter_offer_declined',
            title: 'Offer Declined',
            message:
                'The sender has declined your offer. This request is now open to other transporters.',
            rideId: rideId,
            data: {
              'rideId': rideId,
            },
          );
          if (senderUserId != null) {
            try {
              await MessagingService().sendSenderDeclinedServiceMessage(
                rideId: rideId,
                senderId: senderUserId,
                transporterId: transporterId,
              );
            } catch (e) {
              debugPrint('sendSenderDeclinedServiceMessage: $e');
            }
          }
        }
      }
    } catch (e) {
      // If error is about insufficient balance, send notification
      if (e.toString().contains('Insufficient balance')) {
        try {
          final offerDoc = await _offerCollection(rideId).doc(offerId).get();
          final offerData = offerDoc.data();
          final transporterId = offerData?['transporterId'] as String?;
          
          if (transporterId != null) {
            final rideDoc = await _firestore.collection('rides').doc(rideId).get();
            final rideData = rideDoc.data();
            final agreed = (rideData?['finalPrice'] as num?)?.toDouble() ??
                (rideData?['price'] as num?)?.toDouble() ?? 0.0;
            final fee = agreed * PricingService.platformFeePercentage;
            
            final notificationService = NotificationService();
            await notificationService.createNotification(
              userId: transporterId,
              type: 'insufficient_balance',
              title: 'Insufficient Balance',
              message: 'Your wallet balance is insufficient. Please top up \$${fee.toStringAsFixed(2)} to accept this request.',
              rideId: rideId,
              data: {
                'requiredAmount': fee,
                'rideId': rideId,
              },
            );
          }
        } catch (notifError) {
          debugPrint('Error sending notification: $notifError');
        }
      }
      throw Exception('Error responding to counter-offer: $e');
    }
  }
}


