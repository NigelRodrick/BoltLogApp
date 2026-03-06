import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/message_model.dart';
import '../models/ride_model.dart';
import '../services/messaging_service.dart';

class ChatScreen extends StatefulWidget {
  final RideModel ride;

  const ChatScreen({super.key, required this.ride});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final MessagingService _messagingService = MessagingService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // Sender chats with driver (or accepted transporter during negotiation)
    final receiverId = currentUser.uid == widget.ride.userId
        ? (widget.ride.driverId ?? widget.ride.acceptedTransporterId)
        : widget.ride.userId;

    if (receiverId == null || receiverId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No transporter assigned yet'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final message = MessageModel(
      rideId: widget.ride.id!,
      senderId: currentUser.uid,
      receiverId: receiverId,
      message: _messageController.text.trim(),
      timestamp: DateTime.now(),
    );

    try {
      await _messagingService.sendMessage(message);
      _messageController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending message: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E40AF)), // Blue-700
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Chat',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E40AF), // Blue-700
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Messages list
            Expanded(
              child: StreamBuilder<List<MessageModel>>(
                stream: _messagingService.streamMessages(widget.ride.id!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error: ${snapshot.error}',
                        style: GoogleFonts.inter(color: Colors.red),
                      ),
                    );
                  }

                  final messages = snapshot.data ?? [];

                  if (messages.isEmpty) {
                    return Center(
                      child: Text(
                        'No messages yet',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMe = message.senderId == currentUser?.uid;
                      final transporterId = widget.ride.driverId ?? widget.ride.acceptedTransporterId;
                      final isTransporter = transporterId != null && message.senderId == transporterId;

                      // When sender is chatting with transporter, show a truck
                      // avatar for messages coming from the transporter.
                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (!isMe) ...[
                              // Avatar for the other side
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: isTransporter
                                    ? const Color(0xFF2563EB).withOpacity(0.1)
                                    : Colors.grey.shade200,
                                child: Icon(
                                  isTransporter
                                      ? Icons.local_shipping
                                      : Icons.person,
                                  size: 18,
                                  color: isTransporter
                                      ? const Color(0xFF2563EB)
                                      : Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.7,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? const Color(0xFF2563EB) // Blue-600
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message.message,
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      color: isMe
                                          ? Colors.white
                                          : const Color(
                                              0xFF1E40AF), // Blue-700
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      color: isMe
                                          ? Colors.white70
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            // Message input
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: GoogleFonts.inter(
                          color: Colors.grey.shade400,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: const Color(0xFF2563EB), // Blue-600
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send, color: Color(0xFF2563EB)), // Blue-600
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB).withOpacity(0.1), // Blue-600
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

