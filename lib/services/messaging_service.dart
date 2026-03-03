import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message_model.dart';

class MessagingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Send a message
  Future<String> sendMessage(MessageModel message) async {
    try {
      final docRef = await _firestore
          .collection('rides')
          .doc(message.rideId)
          .collection('messages')
          .add(message.toMap());
      return docRef.id;
    } catch (e) {
      throw Exception('Error sending message: $e');
    }
  }

  // Stream messages for a ride with pagination
  Stream<List<MessageModel>> streamMessages(String rideId, {int limit = 100}) {
    return _firestore
        .collection('rides')
        .doc(rideId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .limitToLast(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  // Mark message as read
  Future<void> markAsRead(String rideId, String messageId) async {
    try {
      await _firestore
          .collection('rides')
          .doc(rideId)
          .collection('messages')
          .doc(messageId)
          .update({'isRead': true});
    } catch (e) {
      throw Exception('Error marking message as read: $e');
    }
  }
}

