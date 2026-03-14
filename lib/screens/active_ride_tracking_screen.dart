import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import '../models/ride_model.dart';
import '../services/ride_service.dart';
import '../services/routing_service.dart';
import '../services/pricing_service.dart';
import '../utils/chat_utils.dart';
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

  /// inDrive-style cancellation: free before driver committed; late cancel notifies driver and stores reason.
  static Future<void> _showCancelDialog(BuildContext context, RideModel ride) async {
    if (ride.id == null) return;
    final rideService = RideService();
    final isFree = rideService.isFreeCancellation(ride);
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            isFree ? 'Cancel request?' : 'Cancel anyway?',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isFree
                    ? 'You can cancel this request at no charge. No driver has been assigned yet.'
                    : 'The driver is already on the way. Cancelling may affect your rating. Are you sure?',
                style: GoogleFonts.inter(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: 'Reason (optional)',
                  hintText: 'e.g. Change of plans',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                maxLines: 2,
                style: GoogleFonts.inter(fontSize: 14),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Keep request', style: GoogleFonts.inter()),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Cancel request', style: GoogleFonts.inter(color: Colors.red.shade700)),
            ),
          ],
        );
      },
    );
    final reason = reasonController.text.trim().isEmpty ? null : reasonController.text.trim();
    reasonController.dispose();
    if (confirmed != true || !context.mounted) return;
    try {
      await rideService.cancelRideWithReason(
        ride.id!,
        cancelledBy: 'sender',
        cancellationReason: reason,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request cancelled'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not cancel: $e'), backgroundColor: Colors.red),
        );
      }
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
                // Map: pickup, dropoff, delivery route (persists with streamed currentRide)
                if (currentRide.driverId != null &&
                    currentRide.status != 'cancelled' &&
                    currentRide.status != 'open' &&
                    currentRide.status != 'pending')
                  _SenderTrackingMap(ride: currentRide, status: status),
                if (currentRide.driverId != null &&
                    currentRide.status != 'cancelled' &&
                    currentRide.status != 'open' &&
                    currentRide.status != 'pending')
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
                // Price (or negotiated amount)
                if (currentRide.price != null || currentRide.finalPrice != null) ...[
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
                            'Agreed amount',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1E40AF),
                            ),
                          ),
                          Text(
                            '\$${(currentRide.finalPrice ?? currentRide.price)!.toStringAsFixed(2)}',
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
                  const SizedBox(height: 12),
                  // Trip summary when completed (final fare + platform fee)
                  if (currentRide.status == 'completed') ...[
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
                              'Trip summary',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1E40AF),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildSummaryRow(
                              'Final fare',
                              (currentRide.finalPrice ?? currentRide.price) ?? 0,
                            ),
                            const SizedBox(height: 6),
                            _buildSummaryRow(
                              'Platform fee (${(PricingService.platformFeePercentage * 100).toInt()}%)',
                              ((currentRide.finalPrice ?? currentRide.price) ?? 0) *
                                  PricingService.platformFeePercentage,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
                // Cancel request (inDrive-style: free vs late cancel)
                if (currentRide.status != 'cancelled' &&
                    currentRide.status != 'completed' &&
                    currentRide.userId == user?.uid) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showCancelDialog(context, currentRide),
                      icon: const Icon(Icons.cancel_outlined, size: 20),
                      label: const Text('Cancel request'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade400),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
                // Action buttons
                if (currentRide.status != 'cancelled' && currentRide.driverId != null) ...[
                  const SizedBox(height: 24),
                  if (currentRide.status != 'completed')
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          if (!isChatAllowedForRide(currentRide)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Chat is no longer available for this delivery.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(ride: currentRide),
                              ),
                            );
                          }
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
                              if (!isChatAllowedForRide(currentRide)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Chat is no longer available for this delivery.'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(ride: currentRide),
                                  ),
                                );
                              }
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

  Widget _buildSummaryRow(String label, double amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: Colors.grey.shade700,
          ),
        ),
        Text(
          '\$${amount.toStringAsFixed(2)}',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1E40AF),
          ),
        ),
      ],
    );
  }
}

/// Persistent map for sender: shows pickup, dropoff, and delivery route (Google Directions).
class _SenderTrackingMap extends StatefulWidget {
  final RideModel ride;
  final String status;

  const _SenderTrackingMap({required this.ride, required this.status});

  @override
  State<_SenderTrackingMap> createState() => _SenderTrackingMapState();
}

class _SenderTrackingMapState extends State<_SenderTrackingMap> {
  GoogleMapController? _controller;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  double? _pickupLat;
  double? _pickupLng;
  double? _dropoffLat;
  double? _dropoffLng;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCoordsAndRoute();
  }

  Future<void> _loadCoordsAndRoute() async {
    double? pickupLat = widget.ride.pickupLat;
    double? pickupLng = widget.ride.pickupLng;
    double? dropoffLat = widget.ride.dropoffLat;
    double? dropoffLng = widget.ride.dropoffLng;

    if (pickupLat == null || pickupLng == null) {
      try {
        final locs = await locationFromAddress(widget.ride.pickupLocation);
        if (locs.isNotEmpty) {
          pickupLat = locs.first.latitude;
          pickupLng = locs.first.longitude;
        }
      } catch (e) {
        if (mounted) setState(() { _error = 'Pickup address could not be found.'; _loading = false; });
        return;
      }
    }
    if (dropoffLat == null || dropoffLng == null) {
      try {
        final locs = await locationFromAddress(widget.ride.dropoffLocation);
        if (locs.isNotEmpty) {
          dropoffLat = locs.first.latitude;
          dropoffLng = locs.first.longitude;
        }
      } catch (e) {
        if (mounted) setState(() { _error = 'Delivery address could not be found.'; _loading = false; });
        return;
      }
    }

    if (pickupLat == null || pickupLng == null || dropoffLat == null || dropoffLng == null) {
      if (mounted) setState(() { _loading = false; });
      return;
    }

    setState(() {
      _pickupLat = pickupLat;
      _pickupLng = pickupLng;
      _dropoffLat = dropoffLat;
      _dropoffLng = dropoffLng;
    });

    try {
      final routingService = RoutingService();
      final route = await routingService.getRoute(
        originLat: pickupLat,
        originLng: pickupLng,
        destLat: dropoffLat,
        destLng: dropoffLng,
        includeTraffic: false,
      );
      if (route != null && mounted) {
        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('delivery_route'),
              points: route.points,
              color: const Color(0xFF2563EB),
              width: 4,
            ),
          };
        });
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _markers = {
          Marker(
            markerId: const MarkerId('pickup'),
            position: LatLng(pickupLat!, pickupLng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: InfoWindow(title: 'Pickup', snippet: widget.ride.pickupLocation),
          ),
          Marker(
            markerId: const MarkerId('dropoff'),
            position: LatLng(dropoffLat!, dropoffLng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(title: 'Delivery', snippet: widget.ride.dropoffLocation),
          ),
        };
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
              const SizedBox(width: 12),
              Expanded(child: Text(_error!, style: GoogleFonts.inter(color: Colors.grey.shade700))),
            ],
          ),
        ),
      );
    }

    final statusLabel = widget.status == 'parcel_collected'
        ? 'Parcel collected – Driver on the way to deliver'
        : widget.status == 'completed'
            ? 'Delivered'
            : 'Driver on the way to collect your parcel';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xFF1E40AF).withOpacity(0.08),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.map, color: const Color(0xFF2563EB), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusLabel,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E40AF),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 220,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _pickupLat == null || _dropoffLat == null
                    ? const Center(child: Text('Unable to show map'))
                    : GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(_pickupLat!, _pickupLng!),
                          zoom: 12,
                        ),
                        onMapCreated: (c) {
                          _controller = c;
                          if (_pickupLat != null && _dropoffLat != null) {
                            final minLat = _pickupLat! < _dropoffLat! ? _pickupLat! : _dropoffLat!;
                            final maxLat = _pickupLat! > _dropoffLat! ? _pickupLat! : _dropoffLat!;
                            final minLng = _pickupLng! < _dropoffLng! ? _pickupLng! : _dropoffLng!;
                            final maxLng = _pickupLng! > _dropoffLng! ? _pickupLng! : _dropoffLng!;
                            _controller?.animateCamera(
                              CameraUpdate.newLatLngBounds(
                                LatLngBounds(
                                  southwest: LatLng(minLat, minLng),
                                  northeast: LatLng(maxLat, maxLng),
                                ),
                                48,
                              ),
                            );
                          }
                        },
                        markers: _markers,
                        polylines: _polylines,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: true,
                        mapType: MapType.normal,
                      ),
          ),
        ],
      ),
    );
  }
}
