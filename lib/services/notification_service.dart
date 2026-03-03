import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Initialize notifications
  Future<void> initialize() async {
    // Request permission
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted notification permission');
      
      // Get FCM token
      String? token = await _messaging.getToken();
      if (token != null) {
        debugPrint('FCM Token: $token');
        // Save token to Firestore when user logs in
      }
      
      // Handle token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        debugPrint('FCM Token refreshed: $newToken');
        // Update token in Firestore
      });
    } else {
      debugPrint('User declined or has not accepted notification permission');
    }

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');
      
      if (message.notification != null) {
        debugPrint('Message also contained a notification: ${message.notification}');
        // Show local notification
        _showLocalNotification(message);
      }
    });

    // Handle background messages (when app is terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('A new onMessageOpenedApp event was published!');
      debugPrint('Message data: ${message.data}');
      // Save notification to Firestore
      _saveNotificationFromMessage(message);
      // Navigation will be handled by the app based on notification data
    });

    // Check if app was opened from a notification
    RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('App opened from notification');
      debugPrint('Message data: ${initialMessage.data}');
      // Save notification to Firestore
      _saveNotificationFromMessage(initialMessage);
      // Navigation will be handled by the app based on notification data
    }
  }

  // Save FCM token to user document
  Future<void> saveTokenToUser(String userId, String token) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'fcmToken': token,
        'fcmTokenUpdatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  // Create notification in Firestore
  Future<void> createNotification({
    required String userId,
    required String type,
    required String title,
    required String message,
    String? rideId,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'type': type,
        'title': title,
        'message': message,
        'rideId': rideId,
        'data': data ?? {},
        'isRead': false,
        'createdAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error creating notification: $e');
    }
  }

  // Send notification when ride is accepted
  Future<void> notifyRideAccepted(String userId, String rideId, String driverName) async {
    await createNotification(
      userId: userId,
      type: 'delivery_accepted',
      title: 'Delivery Accepted',
      message: '$driverName has accepted your delivery request',
      rideId: rideId,
    );
  }

  // Send notification when ride status changes
  Future<void> notifyRideStatusChange(String userId, String rideId, String status) async {
    String title = 'Delivery Update';
    String message = '';
    
    switch (status) {
      case 'in_progress':
        message = 'Driver is on the way to collect your parcel';
        break;
      case 'parcel_collected':
        message = 'Your parcel has been collected';
        break;
      case 'completed':
        message = 'Your parcel has been delivered';
        break;
      default:
        message = 'Delivery status updated';
    }

    await createNotification(
      userId: userId,
      type: 'delivery_status',
      title: title,
      message: message,
      rideId: rideId,
      data: {'status': status},
    );
  }

  // Send notification when message is received
  Future<void> notifyNewMessage(String userId, String rideId, String senderName) async {
    await createNotification(
      userId: userId,
      type: 'message',
      title: 'New Message',
      message: '$senderName sent you a message',
      rideId: rideId,
    );
  }

  // Send notification when offer is received
  Future<void> notifyNewOffer(String userId, String rideId, String transporterName) async {
    await createNotification(
      userId: userId,
      type: 'offer',
      title: 'New Offer',
      message: '$transporterName made an offer on your request',
      rideId: rideId,
    );
  }

  // Show local notification (for foreground messages)
  void _showLocalNotification(RemoteMessage message) {
    // In a real implementation, you would use flutter_local_notifications
    // For now, we'll just log it
    debugPrint('Local notification: ${message.notification?.title} - ${message.notification?.body}');
    // Also save to Firestore so it appears in notifications screen
    _saveNotificationFromMessage(message);
  }

  // Save notification from FCM message to Firestore
  Future<void> _saveNotificationFromMessage(RemoteMessage message) async {
    try {
      final data = message.data;
      final userId = data['userId'] as String?;
      
      if (userId == null) {
        debugPrint('No userId in notification data');
        return;
      }

      await _firestore.collection('notifications').add({
        'userId': userId,
        'type': data['type'] ?? 'general',
        'title': message.notification?.title ?? data['title'] ?? 'Notification',
        'message': message.notification?.body ?? data['message'] ?? '',
        'rideId': data['rideId'],
        'data': data,
        'isRead': false,
        'createdAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error saving notification from message: $e');
    }
  }

  // Get FCM token
  Future<String?> getToken() async {
    return await _messaging.getToken();
  }
}

