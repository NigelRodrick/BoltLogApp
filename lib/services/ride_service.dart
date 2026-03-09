import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/testing_flags.dart';
import 'package:flutter/foundation.dart';
import '../models/ride_model.dart';
import '../models/user_model.dart';
import '../models/transporter_offer_model.dart';
import 'notification_service.dart';

class RideService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Create a new ride request
  Future<String> createRide(RideModel ride) async {
    try {
      final docRef = await _firestore.collection('rides').add(ride.toMap());
      return docRef.id;
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

  // Cancel ride
  // Note: If transporter already accepted, the 2% fee is NOT refunded (as per business logic)
  Future<void> cancelRide(String rideId) async {
    await updateRideStatus(rideId, 'cancelled');
  }

  // Get available rides for transporters (open, no driver assigned)
  // Rides are automatically excluded when:
  // 1. Status changes from 'open' to 'in_progress' (when accepted)
  // 2. driverId is set (when accepted)
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
            
            // Only include rides that are still open and have no driver assigned
            // This ensures accepted rides (status='in_progress' or driverId set) are excluded
            if ((driverId == null || 
                (driverId is String && driverId.isEmpty) ||
                (driverId?.toString().trim().isEmpty ?? false)) &&
                data['status'] == 'open') {
              try {
                final ride = RideModel.fromMap(data, doc.id);
                // Double check the ride model also has null driverId and is still open
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
        
        // Get the final price (negotiated price if sender approved, or original price)
        final price = (rideData['price'] as num?)?.toDouble() ?? 0.0;
        final fee = price * 0.02;

        const allowedVerifiedStatuses = ['auto_verified', 'verified'];
        const driverRole = 'driver';

        final userSnap = await transaction.get(userRef);
        final userData = userSnap.data() as Map<String, dynamic>? ?? {};

        final userRole =
            (userData['role'] as String? ?? '').toLowerCase();
        final verificationStatus =
            (userData['verificationStatus'] as String? ?? '').toLowerCase();

        final relaxVerification = TestingFlags.relaxTransporterVerification;

        if (!relaxVerification &&
            userRole == driverRole &&
            !allowedVerifiedStatuses.contains(verificationStatus)) {
          throw Exception(
              'Your documents are still being verified. You cannot accept this request yet.');
        }

        double currentBalance =
            (userData['driverWalletBalance'] as num?)?.toDouble() ?? 0.0;

        // Check if sender has approved the negotiated amount
        final senderApproved = priceStatus == 'accepted';
        final hasCounterOffer = rideData['counterOffer'] != null || 
                                priceStatus == 'pending';

        if (!hasCounterOffer) {
          // Direct acceptance (no negotiation) - deduct immediately
          if (currentBalance < fee) {
            throw Exception('Insufficient balance. Required: \$${fee.toStringAsFixed(2)}, Available: \$${currentBalance.toStringAsFixed(2)}');
          }

          // Deduct fee for direct acceptance (non-refundable)
          final newBalance = currentBalance - fee;
          transaction.update(userRef, {
            'driverWalletBalance': newBalance,
          });
        } else if (senderApproved) {
          // Sender has approved the negotiated amount - deduct fee now
          if (currentBalance < fee) {
            throw Exception('Insufficient balance. Required: \$${fee.toStringAsFixed(2)}, Available: \$${currentBalance.toStringAsFixed(2)}');
          }

          // Deduct fee after sender approved (non-refundable)
          final newBalance = currentBalance - fee;
          transaction.update(userRef, {
            'driverWalletBalance': newBalance,
          });
        } else {
          // Negotiation still in progress - don't deduct yet, but check balance
          if (currentBalance < fee) {
            // Will notify after transaction
          }
        }

        // Accept ride - change status to 'in_progress'
        transaction.update(rideRef, {
          'driverId': transporterId,
          'status': 'in_progress',
          'updatedAt': DateTime.now().toIso8601String(),
        });
      });
      
      // After transaction, if there was negotiation and balance insufficient, notify
      try {
        final rideDoc = await _firestore.collection('rides').doc(rideId).get();
        final rideData = rideDoc.data();
        final hasCounterOffer = rideData?['counterOffer'] != null || 
                                rideData?['priceStatus'] == 'pending';
        
        if (hasCounterOffer) {
          final price = (rideData?['price'] as num?)?.toDouble() ?? 0.0;
          final fee = price * 0.02;
          
          final userDoc = await _firestore.collection('users').doc(transporterId).get();
          final userData = userDoc.data();
          double currentBalance = (userData?['driverWalletBalance'] as num?)?.toDouble() ?? 0.0;
          
          if (currentBalance < fee) {
            final notificationService = NotificationService();
            await notificationService.createNotification(
              userId: transporterId,
              type: 'insufficient_balance',
              title: 'Insufficient Balance',
              message: 'Your wallet balance (\$${currentBalance.toStringAsFixed(2)}) is insufficient. Please top up \$${fee.toStringAsFixed(2)} to complete this request.',
              rideId: rideId,
              data: {
                'requiredAmount': fee,
                'currentBalance': currentBalance,
                'shortfall': fee - currentBalance,
                'rideId': rideId,
              },
            );
          }
        }
      } catch (notifError) {
        debugPrint('Error sending notification: $notifError');
      }
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
      final fee = ridePrice * 0.02;
      
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
    await updateRideStatus(rideId, 'parcel_collected');
    try {
      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      final userId = rideDoc.data()?['userId'] as String?;
      if (userId != null) {
        final notificationService = NotificationService();
        await notificationService.createNotification(
          userId: userId,
          type: 'parcel_collected',
          title: 'Parcel Collected',
          message: 'Your parcel has been collected. Driver is on the way to deliver.',
          rideId: rideId,
        );
      }
    } catch (e) {
      debugPrint('Error notifying sender of parcel collected: $e');
    }
  }

  // Mark as delivered
  Future<void> markDelivered(String rideId) async {
    await updateRideStatus(rideId, 'completed');
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
      
      // Update the ride with counter-offer; transporter sent last so sender is viewing / waiting for reply
      await _firestore.collection('rides').doc(rideId).update({
        'counterOffer': counterOffer,
        'priceStatus': 'pending',
        'status': 'pending',
        'lastCounterOfferBy': 'transporter',
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

        // Update ride with sender's counter-offer - keep status as 'pending' (negotiation continues)
        transaction.update(rideRef, {
          'counterOffer': senderCounterOffer,
          'priceStatus': 'pending',
          'status': 'pending', // Keep in negotiation
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

          // Update ride with sender's counter-offer; sender sent last so waiting for transporter
          transaction.update(rideRef, {
            'counterOffer': senderCounterOffer,
            'priceStatus': 'pending',
            'status': 'pending',
            'lastCounterOfferBy': 'sender',
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
          
          // Check balance before accepting (deduction happens after negotiation)
          final rideSnap = await transaction.get(rideRef);
          final rideData = rideSnap.data() as Map<String, dynamic>;
          final finalPrice = counterOffer ?? (rideData['price'] as num?)?.toDouble() ?? 0.0;
          final fee = finalPrice * 0.02;
          
          // Check balance
          final userRef = _firestore.collection('users').doc(transporterId);
          final userSnap = await transaction.get(userRef);
          final userData = userSnap.data() as Map<String, dynamic>? ?? {};
          double currentBalance = (userData['driverWalletBalance'] as num?)?.toDouble() ?? 0.0;
          
          if (currentBalance < fee) {
            // Notify transporter about insufficient balance
            // We'll send notification after transaction, but throw error to prevent acceptance
            final notificationService = NotificationService();
            // Note: Notification will be sent after transaction fails
            throw Exception('Insufficient balance. Required: \$${fee.toStringAsFixed(2)}, Available: \$${currentBalance.toStringAsFixed(2)}');
          }
          
          // Update ride with accepted counter-offer
          // When sender accepts, set priceStatus to 'accepted' but keep status as 'pending'
          // Transporter must then accept the ride to proceed
          final updateData = <String, dynamic>{
            'price': counterOffer,
            'counterOffer': null,
            'priceStatus': 'accepted', // Sender approved the negotiated amount
            'status': 'pending', // Keep as pending until transporter accepts ride
            'acceptedTransporterId': transporterId, // So sender can chat with transporter before Accept
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
          // Reject the counter-offer - change status back to 'open' so ride is available again
          transaction.update(rideRef, {
            'counterOffer': null,
            'priceStatus': 'rejected',
            'status': 'open', // Negotiation cancelled, ride available again
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

      // If sender declined the counter-offer (no new amount), notify transporter
      if (!accepted && senderCounterOffer == null) {
        final offerDoc = await _offerCollection(rideId).doc(offerId).get();
        final offerData = offerDoc.data();
        final transporterId = offerData?['transporterId'] as String?;

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
            final price = (rideData?['price'] as num?)?.toDouble() ?? 0.0;
            final fee = price * 0.02;
            
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


