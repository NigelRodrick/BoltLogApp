import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/ride_model.dart';
import '../services/ride_service.dart';
import 'chat_screen.dart';
import 'rating_screen.dart';

class ActiveRideTrackingScreen extends StatelessWidget {
  final RideModel ride;

  const ActiveRideTrackingScreen({super.key, required this.ride});

  String _getStatusLabel(String status, {bool isSender = false}) {
    switch (status) {
      case 'completed':
        return 'DELIVERED';
      case 'parcel_collected':
        return 'PARCEL COLLECTED';
      case 'in_progress':
        return 'IN TRANSIT';
      case 'pending':
        return 'NEGOTIATING';
      case 'open':
        return isSender ? 'WAITING FOR TRANSPORTERS' : 'OPEN';
      case 'cancelled':
        return 'CANCELLED';
      default:
        return status.toUpperCase();
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'parcel_collected':
        return Colors.purple;
      case 'in_progress':
        return Colors.blue;
      case 'pending':
        return Colors.amber;
      case 'open':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusMessage(String status, {bool isSender = false}) {
    switch (status) {
      case 'open':
        return isSender 
            ? 'Waiting for transporters to respond to your request...'
            : 'This request is open and available for acceptance';
      case 'pending':
        return isSender
            ? 'Price negotiation in progress. Waiting for transporter response...'
            : 'This request is being negotiated with the sender';
      case 'in_progress':
        return 'Driver is on the way to collect your parcel';
      case 'parcel_collected':
        return 'Your parcel has been collected! Driver is on the way to deliver';
      case 'completed':
        return 'Your parcel has been delivered successfully!';
      case 'cancelled':
        return 'This delivery has been cancelled';
      default:
        return 'Tracking your delivery...';
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'open':
        return Icons.access_time;
      case 'pending':
        return Icons.handshake;
      case 'in_progress':
        return Icons.local_shipping;
      case 'parcel_collected':
        return Icons.inventory_2;
      case 'completed':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rideService = RideService();
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E40AF)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Track Delivery',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E40AF),
          ),
        ),
      ),
      body: StreamBuilder<RideModel?>(
        stream: rideService.streamRideById(ride.id!),
        builder: (context, snapshot) {
          final currentRide = snapshot.data ?? ride;
          final status = currentRide.status;
          final isSender = user?.uid == currentRide.userId;
          final statusColor = _getStatusColor(status);
          final statusLabel = _getStatusLabel(status, isSender: isSender);
          final statusMessage = _getStatusMessage(status, isSender: isSender);
          final statusIcon = _getStatusIcon(status);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Status Icon
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            statusIcon,
                            size: 48,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Status Label
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            statusLabel,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Status Message
                        Text(
                          statusMessage,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Package Details
                if (currentRide.packageDescription != null) ...[
                  Text(
                    'Package Details',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E40AF),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentRide.packageDescription!,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1E40AF),
                            ),
                          ),
                          if (currentRide.weight != null || currentRide.packageType != null) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                if (currentRide.weight != null) ...[
                                  Icon(Icons.scale, size: 16, color: Colors.grey.shade600),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${currentRide.weight} kg',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                ],
                                if (currentRide.packageType != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      currentRide.packageType!.toUpperCase(),
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                // Locations
                Text(
                  'Locations',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E40AF),
                  ),
                ),
                const SizedBox(height: 12),
                // Pickup Location
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.location_on,
                            color: Color(0xFF2563EB),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pickup',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                currentRide.pickupLocation,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1E40AF),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Dropoff Location
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade400.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.location_on,
                            color: Colors.red.shade400,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Delivery',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                currentRide.dropoffLocation,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1E40AF),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Price
                if (currentRide.price != null) ...[
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Price',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1E40AF),
                            ),
                          ),
                          Text(
                            '\$${currentRide.price!.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF2563EB),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                // Progress Timeline
                Text(
                  'Progress',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E40AF),
                  ),
                ),
                const SizedBox(height: 12),
                _buildProgressTimeline(currentRide.status),
                // Action buttons
                if (currentRide.status != 'cancelled' && currentRide.driverId != null) ...[
                  const SizedBox(height: 24),
                  if (currentRide.status != 'completed')
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(ride: currentRide),
                            ),
                          );
                        },
                        icon: const Icon(Icons.chat, size: 20),
                        label: const Text('Chat with Driver'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF2563EB),
                          side: const BorderSide(color: Color(0xFF2563EB), width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  if (currentRide.status == 'completed') ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(ride: currentRide),
                                ),
                              );
                            },
                            icon: const Icon(Icons.chat, size: 20),
                            label: const Text('Chat'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF2563EB),
                              side: const BorderSide(color: Color(0xFF2563EB)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => RatingScreen(
                                    ride: currentRide,
                                    rateUserId: currentRide.driverId!,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.star, size: 20),
                            label: const Text('Rate Driver'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProgressTimeline(String currentStatus) {
    final steps = [
      {'status': 'pending', 'label': 'Request Sent', 'icon': Icons.send},
      {'status': 'accepted', 'label': 'Driver Accepted', 'icon': Icons.check_circle},
      {'status': 'in_progress', 'label': 'Driver En Route', 'icon': Icons.local_shipping},
      {'status': 'parcel_collected', 'label': 'Parcel Collected', 'icon': Icons.inventory_2},
      {'status': 'completed', 'label': 'Delivered', 'icon': Icons.check_circle},
    ];

    int currentIndex = steps.indexWhere((step) => step['status'] == currentStatus);
    if (currentIndex == -1) currentIndex = 0;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: steps.asMap().entries.map((entry) {
            final index = entry.key;
            final step = entry.value;
            final isCompleted = index <= currentIndex;
            final isCurrent = index == currentIndex;

            return Row(
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? (isCurrent
                            ? _getStatusColor(currentStatus).withOpacity(0.2)
                            : Colors.green.withOpacity(0.1))
                        : Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    step['icon'] as IconData,
                    size: 20,
                    color: isCompleted
                        ? (isCurrent ? _getStatusColor(currentStatus) : Colors.green)
                        : Colors.grey.shade400,
                  ),
                ),
                const SizedBox(width: 12),
                // Label
                Expanded(
                  child: Text(
                    step['label'] as String,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                      color: isCompleted
                          ? (isCurrent ? _getStatusColor(currentStatus) : Colors.grey.shade700)
                          : Colors.grey.shade400,
                    ),
                  ),
                ),
                // Check mark for completed
                if (index < currentIndex)
                  Icon(
                    Icons.check_circle,
                    size: 20,
                    color: Colors.green,
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
