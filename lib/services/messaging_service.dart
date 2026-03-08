import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message_model.dart';

/// Result of a messages stream update; includes cache metadata for offline UX.
class MessagesSnapshot {
  final List<MessageModel> messages;
  final bool isFromCache;

  MessagesSnapshot(this.messages, this.isFromCache);
}

class MessagingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Send a message (queued when offline; syncs when back online)
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

  // Stream messages with cache metadata so UI can show offline/syncing state
  Stream<MessagesSnapshot> streamMessages(String rideId, {int limit = 100}) {
    return _firestore
        .collection('rides')
        .doc(rideId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .limitToLast(limit)
        .snapshots()
        .map((snapshot) {
      final messages = snapshot.docs
          .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
          .toList();
      return MessagesSnapshot(messages, snapshot.metadata.isFromCache);
    });
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

