import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math' as math;
import '../models/ride_model.dart';
import '../models/user_model.dart';
import '../services/ride_service.dart';
import '../services/user_service.dart';
import '../services/routing_service.dart';
import '../services/pricing_service.dart';
import '../config/testing_flags.dart';
import '../utils/negotiation_utils.dart';
import '../utils/chat_utils.dart';
import '../models/transporter_offer_model.dart';
import 'active_ride_map_screen.dart';
import 'active_ride_tracking_screen.dart';
import 'chat_screen.dart';

class RequestDetailScreen extends StatefulWidget {
  final RideModel ride;

  const RequestDetailScreen({super.key, required this.ride});

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  final RideService _rideService = RideService();
  final UserService _userService = UserService();
  bool _isOffering = false;
  Set<Polyline> _routePolylines = {};
  bool _routeRequested = false;
  bool _lockNavigation = false;

  void _showNegotiationLockDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Negotiation in progress'),
        content: const Text(
          'You have an active negotiation for this delivery. '
          'Finish or cancel it before leaving this screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Track when transporter views this request
    _trackView();
    // Update last seen every 20 seconds while viewing
    _startViewerTracking();
  }

  void _trackView() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || widget.ride.id == null) return;
    try {
      if (user.uid == widget.ride.userId) {
        await _rideService.updateSenderLastViewed(widget.ride.id!);
      } else {
        await _rideService.trackRequestView(widget.ride.id!, user.uid);
      }
    } catch (e) {
      // Silently fail
    }
  }

  void _startViewerTracking() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && widget.ride.id != null) {
      // Update last seen every 20 seconds
      Future.delayed(const Duration(seconds: 20), () {
        if (mounted) {
          _rideService.updateViewerLastSeen(widget.ride.id!, user.uid);
          _startViewerTracking(); // Continue tracking
        }
      });
    }
  }

  @override
  void dispose() {
    // Stop tracking when screen is closed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final transporterId = user?.uid ?? '';

    return WillPopScope(
      onWillPop: () async {
        if (_lockNavigation) {
          _showNegotiationLockDialog();
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF1E40AF)),
            onPressed: () {
              if (_lockNavigation) {
                _showNegotiationLockDialog();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          title: Text(
            'Request Details',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E40AF),
            ),
          ),
        ),
        // Persist request details: stream live ride, fallback to initial so details don't disappear
        body: StreamBuilder<RideModel?>(
          stream: widget.ride.id != null
              ? _rideService.streamRideById(widget.ride.id!)
              : Stream.value(widget.ride),
          builder: (context, rideSnap) {
            final ride = rideSnap.data ?? widget.ride;
            _lockNavigation = negotiationInProgress(ride);
            return SafeArea(
              child: StreamBuilder<UserModel?>(
                stream: user != null
                    ? _userService.streamUser(user!.uid)
                    : Stream.value(null),
                builder: (context, userSnap) {
                  final userModel = userSnap.data;
                  final isTransporter =
                      user != null && user!.uid != ride.userId;
                final isSender = user != null && user!.uid == ride.userId;
                  final isDriver =
                      (userModel?.role ?? '').toLowerCase() == 'driver';
                  final verificationStatus =
                      (userModel?.verificationStatus ?? 'pending')
                          .toLowerCase();
                  final isVerified = verificationStatus == 'auto_verified' ||
                      verificationStatus == 'verified';
                  final canActAsTransporter =
                      TestingFlags.relaxTransporterVerification ||
                          !isDriver ||
                          isVerified;
                  bool senderViewedRecently = false;
                  if (ride.senderLastViewedAt != null) {
                    try {
                      final viewedAt =
                          DateTime.parse(ride.senderLastViewedAt!);
                      senderViewedRecently =
                          DateTime.now().difference(viewedAt).inMinutes <= 10;
                    } catch (_) {}
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      // Negotiation status: transporter view (sees sender activity + counters)
                      if (isTransporter &&
                            ride.status == 'pending' &&
                            ride.priceStatus == 'pending' &&
                            (ride.negotiatingTransporterId == null ||
                                ride.negotiatingTransporterId == transporterId)) ...[
                          if (ride.lastCounterOfferBy == 'transporter')
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: Colors.amber.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.schedule,
                                      color: Colors.amber.shade800, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Sender viewing, waiting for reply',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (senderViewedRecently)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.visibility,
                                      color: Colors.blue.shade800, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Sender has viewed',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blue.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Only the transporter in active negotiation sees sender's counter (works for any sender + multiple transporters)
                          if (ride.lastCounterOfferBy == 'sender' &&
                              ride.counterOffer != null &&
                              (ride.negotiatingTransporterId == null ||
                                  ride.negotiatingTransporterId == transporterId))
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.tag_faces,
                                      color: Colors.green.shade800, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.green.shade900,
                                        ),
                                        children: [
                                          const TextSpan(
                                            text: 'Sender\'s counter-offer: ',
                                          ),
                                          TextSpan(
                                            text:
                                                '\$${ride.counterOffer!.toStringAsFixed(2)}. '
                                                'You can accept or renegotiate.',
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.green.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        // Negotiation status: sender view (sees latest transporter counter-offer)
                        if (isSender &&
                            ride.status == 'pending' &&
                            ride.priceStatus == 'pending' &&
                            ride.lastCounterOfferBy == 'transporter' &&
                            ride.counterOffer != null) ...[
                          InkWell(
                            onTap: () => _showSenderOfferActions(context, ride),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.amber.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.attach_money,
                                      color: Colors.amber.shade800, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.amber.shade900,
                                        ),
                                        children: [
                                          const TextSpan(
                                            text: 'Transporter proposed: ',
                                          ),
                                          TextSpan(
                                            text:
                                                '\$${ride.counterOffer!.toStringAsFixed(2)}. ',
                                          ),
                                          const TextSpan(
                                            text:
                                                'Tap to accept, decline, or counter.',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chevron_right, size: 22, color: Colors.orange),
                                ],
                              ),
                            ),
                          ),
                        ],
                        // Package Description
              if (ride.packageDescription != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF2563EB).withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.inventory_2,
                            color: const Color(0xFF2563EB),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Package Description',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ride.packageDescription!,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E40AF),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Package Details Section
              Text(
                'Package Details',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E40AF),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    if (ride.packageType != null) ...[
                      _buildDetailRow(
                        Icons.category,
                        'Package Type',
                        ride.packageType!.toUpperCase(),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (ride.weight != null) ...[
                      _buildDetailRow(
                        Icons.scale,
                        'Weight',
                        '${ride.weight} kg',
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (ride.dimensions != null) ...[
                      _buildDetailRow(
                        Icons.straighten,
                        'Dimensions',
                        ride.dimensions!,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (ride.estimatedValue != null) ...[
                      _buildDetailRow(
                        Icons.attach_money,
                        'Estimated Value',
                        '\$${ride.estimatedValue!.toStringAsFixed(2)}',
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Locations Section
              Text(
                'Locations',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E40AF),
                ),
              ),
              const SizedBox(height: 12),
              
              // Map with route between pickup and dropoff
              if (ride.pickupLat != null &&
                  ride.pickupLng != null &&
                  ride.dropoffLat != null &&
                  ride.dropoffLng != null) ...[
                SizedBox(
                  height: 220,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(
                          (ride.pickupLat! + ride.dropoffLat!) / 2,
                          (ride.pickupLng! + ride.dropoffLng!) / 2,
                        ),
                        zoom: 12,
                      ),
                      markers: {
                        Marker(
                          markerId: const MarkerId('pickup'),
                          position: LatLng(ride.pickupLat!, ride.pickupLng!),
                          infoWindow: const InfoWindow(title: 'Pickup'),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueBlue,
                          ),
                        ),
                        Marker(
                          markerId: const MarkerId('dropoff'),
                          position: LatLng(ride.dropoffLat!, ride.dropoffLng!),
                          infoWindow: const InfoWindow(title: 'Dropoff'),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueRed,
                          ),
                        ),
                      },
                      polylines: _buildRoutePolylines(ride),
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: true,
                      compassEnabled: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Distance: ${_calculateDistanceKm(ride.pickupLat!, ride.pickupLng!, ride.dropoffLat!, ride.dropoffLng!).toStringAsFixed(1)} km',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Pickup Location
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                            'Pickup Location',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            ride.pickupLocation,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF1E40AF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              
              // Dropoff Location
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dropoff Location',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            ride.dropoffLocation,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF1E40AF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Price Section
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF2563EB).withOpacity(0.2),
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isSender ? 'Your original offer' : 'Sender\'s offer',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ride.price != null
                              ? '\$${ride.price!.toStringAsFixed(2)}'
                              : 'Not specified',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF2563EB),
                          ),
                        ),
                        // For the sender, always show the current amount on the table
                        if (isSender) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Current amount being negotiated / agreed',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            (() {
                              final current =
                                  ride.finalPrice ?? ride.counterOffer ?? ride.price;
                              if (current == null) return 'No amount set';
                              return '\$${current.toStringAsFixed(2)}';
                            })(),
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF15803D),
                            ),
                          ),
                        ],
                        // Permanently show the latest negotiated amount (for both sender and transporter)
                        if (ride.finalPrice != null || ride.counterOffer != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Negotiated amount',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '\$${(ride.finalPrice ?? ride.counterOffer)!.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF15803D),
                            ),
                          ),
                        ],
                        // Latest negotiated offer (visible to both sender and transporter)
                        if (ride.counterOffer != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            ride.lastCounterOfferBy == 'transporter'
                                ? 'Transporter\'s latest offer'
                                : 'Your latest counter-offer',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '\$${ride.counterOffer!.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: ride.lastCounterOfferBy == 'transporter'
                                  ? Colors.amber.shade800
                                  : Colors.green.shade700,
                            ),
                          ),
                        ],
                        if (isTransporter &&
                            userModel?.ratePer10Km != null &&
                            userModel!.ratePer10Km! > 0 &&
                            ride.pickupLat != null &&
                            ride.pickupLng != null &&
                            ride.dropoffLat != null &&
                            ride.dropoffLng != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Your rate for this trip',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '\$${PricingService.calculateDriverPriceForDistance(
                              PricingService.calculateDistance(
                                ride.pickupLat!, ride.pickupLng!,
                                ride.dropoffLat!, ride.dropoffLng!,
                              ),
                              userModel.ratePer10Km,
                            )!.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1E40AF),
                            ),
                          ),
                        ],
                        if (isTransporter && (ride.finalPrice != null || ride.counterOffer != null || ride.price != null)) ...[
                          const SizedBox(height: 10),
                          Text(
                            'You\'ll receive',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '\$${((ride.finalPrice ?? ride.counterOffer ?? ride.price)! * (1 - PricingService.platformFeePercentage)).toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF15803D),
                            ),
                          ),
                          Text(
                            'after ${(PricingService.platformFeePercentage * 100).toInt()}% platform fee',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                        if (ride.senderPaymentMethod != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: ride.senderPaymentMethod == 'ecocash'
                                  ? Colors.green.withOpacity(0.1)
                                  : Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: ride.senderPaymentMethod == 'ecocash'
                                    ? Colors.green
                                    : Colors.orange,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  ride.senderPaymentMethod == 'ecocash'
                                      ? Icons.account_balance_wallet
                                      : Icons.money,
                                  size: 18,
                                  color: ride.senderPaymentMethod == 'ecocash'
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Payment: ${ride.senderPaymentMethod == 'ecocash' ? 'EcoCash' : 'Cash'}',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: ride.senderPaymentMethod == 'ecocash'
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'OFFER',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Additional Notes
              if (ride.notes != null && ride.notes!.isNotEmpty) ...[
                Text(
                  'Additional Notes',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E40AF),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    ride.notes!,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Request Date
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Text(
                      'Requested: ${_formatDate(ride.createdAt)}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Action Buttons (for transporters): show when open or when pending (negotiating / sender accepted)
              if (user != null &&
                  user.uid != ride.userId &&
                  (ride.status == 'open' ||
                      (ride.status == 'pending' && ride.driverId == null))) ...[
                if (isTransporter && isDriver)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'You can accept at the suggested price or send a counter-offer.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                if (isTransporter && isDriver && !isVerified)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber.shade800, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Verify your documents (ID and selfie) to accept or negotiate offers.',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (isTransporter && isDriver && !isVerified) const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1E40AF),
                          side: const BorderSide(color: Color(0xFF1E40AF), width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(
                          'Back to Requests',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _isOffering || !canActAsTransporter
                            ? null
                            : () => _offerRequest(ride, transporterId),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                        ),
                        child: _isOffering
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                ride.priceStatus == 'accepted'
                                    ? 'Accept delivery'
                                    : 'Accept Offer',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _isOffering || !canActAsTransporter
                        ? null
                        : () => _showRenegotiateDialog(ride, transporterId),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                      side: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      (ride.negotiatingTransporterId == transporterId ||
                              ride.counterOffer == null)
                          ? 'Make offer / Counter-offer'
                          : 'Renegotiate Price',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _isOffering ? null : _declineRequest,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade400, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'Decline Request',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
              // Chat with counterparty:
              // - when a driver/acceptedTransporter is set, OR
              // - when there is an active negotiation (negotiatingTransporterId set while pending)
              if (ride.driverId != null ||
                  ride.acceptedTransporterId != null ||
                  (ride.status == 'pending' &&
                      ride.negotiatingTransporterId != null)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (!isChatAllowedForRide(ride)) {
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
                            builder: (_) => ChatScreen(ride: ride),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.chat, size: 20),
                    label: Text(
                      isTransporter ? 'Chat with Sender' : 'Chat with Transporter',
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                      side: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],

              // Sender "Proceed" button right after accepting the counter-offer.
              // At this point `driverId` may still be null because transporter must still accept.
              if (isSender &&
                  ride.status != 'cancelled' &&
                  (ride.finalPrice != null ||
                      ride.priceStatus == 'accepted')) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ActiveRideTrackingScreen(ride: ride),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Proceed',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
              // Transporter cancel (inDrive-style: driver can cancel, sender is notified)
              if (user != null &&
                  isTransporter &&
                  transporterId != null &&
                  (ride.acceptedTransporterId == transporterId || ride.driverId == transporterId) &&
                  ride.status != 'completed' &&
                  ride.status != 'cancelled') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => _showTransporterCancelDialog(context, ride),
                    icon: const Icon(Icons.cancel_outlined, size: 20),
                    label: const Text('Cancel delivery'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade400),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                value,
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
    );
  }

  Widget _buildPaymentMethodBadge(String? paymentMethod) {
    if (paymentMethod == null) return const SizedBox.shrink();
    
    final isEcoCash = paymentMethod.toLowerCase() == 'ecocash';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isEcoCash ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEcoCash ? Colors.green : Colors.orange,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isEcoCash ? Icons.account_balance_wallet : Icons.money,
            size: 16,
            color: isEcoCash ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 6),
          Text(
            isEcoCash ? 'EcoCash' : 'Cash',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isEcoCash ? Colors.green : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  // Calculate distance between two coordinates in km (Haversine formula)
  double _calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371; // km
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _deg2rad(double deg) {
    return deg * (math.pi / 180);
  }

  Future<void> _showSenderOfferActions(
      BuildContext context, RideModel ride) async {
    if (ride.id == null) return;

    try {
      // Find the active offer for the negotiating transporter so we know offerId
      final offers =
          await _rideService.streamOffersForRide(ride.id!).first;
      final activeOffer = offers.firstWhere(
        (o) =>
            o.transporterId == ride.negotiatingTransporterId &&
            o.status == 'pending',
        orElse: () => offers.firstWhere(
          (o) => o.transporterId == ride.negotiatingTransporterId,
          orElse: () => offers.first,
        ),
      );

      final TextEditingController counterController = TextEditingController(
        text: ride.counterOffer?.toStringAsFixed(2) ??
            ride.price?.toStringAsFixed(2) ??
            '',
      );

      await showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Transporter offer',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1E40AF),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Current offer: \$${ride.counterOffer?.toStringAsFixed(2) ?? '-'}',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Counter-offer (optional)',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E40AF),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: counterController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      prefixText: '\$',
                      hintText: 'Leave empty to just accept or decline',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            // Decline: no new amount
                            Navigator.of(ctx).pop();
                            try {
                              await _rideService.respondToCounterOffer(
                                ride.id!,
                                activeOffer.id!,
                                false,
                              );
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Offer declined'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error: ${e.toString()}'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                            side: BorderSide(color: Colors.red.shade300),
                          ),
                          child: Text(
                            'Decline',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            // Accept at current counterOffer
                            Navigator.of(ctx).pop();
                            try {
                              await _rideService.respondToCounterOffer(
                                ride.id!,
                                activeOffer.id!,
                                true,
                              );
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Offer accepted. Waiting for transporter to accept delivery.'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error: ${e.toString()}'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          child: Text(
                            'Accept',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            final text = counterController.text.trim();
                            final value = double.tryParse(text);
                            if (value == null ||
                                value < PricingService.minimumFloorPrice) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Minimum \$${PricingService.minimumFloorPrice.toStringAsFixed(2)}.',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                              return;
                            }
                            Navigator.of(ctx).pop();
                            try {
                              await _rideService.respondToCounterOffer(
                                ride.id!,
                                activeOffer.id!,
                                false,
                                senderCounterOffer: value,
                              );
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Counter-offer \$${value.toStringAsFixed(2)} sent.'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error: ${e.toString()}'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                          ),
                          child: Text(
                            'Counter',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading offer: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Build route polylines using actual road route
  Set<Polyline> _buildRoutePolylines(RideModel ride) {
    // If we already have a computed route, use it
    if (_routePolylines.isNotEmpty) {
      return _routePolylines;
    }

    // Otherwise, trigger async load once and show no line until it's ready
    if (!_routeRequested &&
        ride.pickupLat != null &&
        ride.pickupLng != null &&
        ride.dropoffLat != null &&
        ride.dropoffLng != null) {
      _routeRequested = true;
      _loadActualRoute(ride);
    }

    return <Polyline>{};
  }

  // Load actual route from Google Directions API
  void _loadActualRoute(RideModel ride) async {
    if (ride.pickupLat == null ||
        ride.pickupLng == null ||
        ride.dropoffLat == null ||
        ride.dropoffLng == null) {
      return;
    }

    try {
      final routingService = RoutingService();
      final route = await routingService.getRoute(
        originLat: ride.pickupLat!,
        originLng: ride.pickupLng!,
        destLat: ride.dropoffLat!,
        destLng: ride.dropoffLng!,
      );

      if (route != null && mounted) {
        setState(() {
          _routePolylines = {
            Polyline(
              polylineId: const PolylineId('route'),
              points: route.points,
              color: const Color(0xFF2563EB),
              width: 4,
            ),
          };
        });
      }
    } catch (e) {
      // If routing fails, don't draw a fallback straight line
    }
  }

  Future<void> _declineRequest() async {
    final rideId = widget.ride.id;
    final user = FirebaseAuth.instance.currentUser;
    if (rideId != null && user != null && user.uid != widget.ride.userId) {
      try {
        await _rideService.transporterDeclineRequest(rideId, user.uid);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You declined this request. It is now open to other transporters.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _offerRequest(RideModel ride, String transporterId) async {
    if (ride.id == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Request ID is missing'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isOffering = true;
    });

    try {
      // Create offer first
      await _rideService.createOrUpdateOffer(
        ride.id!,
        transporterId,
        priceOffer: ride.finalPrice ?? ride.counterOffer ?? ride.price,
      );

      // Actually accept the ride (this sets driverId and changes status to in_progress)
      await _rideService.acceptRide(ride.id!, transporterId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Request accepted successfully!',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Navigate to active ride map
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ActiveRideMapScreen(ride: ride),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isOffering = false;
        });
      }
    }
  }

  Future<void> _showTransporterCancelDialog(BuildContext context, RideModel ride) async {
    if (ride.id == null) return;
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Cancel delivery?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The sender will be notified. You can add a reason (optional).',
              style: GoogleFonts.inter(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g. Unable to complete',
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
            child: Text('Keep delivery', style: GoogleFonts.inter()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Cancel delivery', style: GoogleFonts.inter(color: Colors.red.shade700)),
          ),
        ],
      ),
    );
    final reason = reasonController.text.trim().isEmpty ? null : reasonController.text.trim();
    reasonController.dispose();
    if (confirmed != true || !mounted) return;
    try {
      await _rideService.cancelRideWithReason(
        ride.id!,
        cancelledBy: 'transporter',
        cancellationReason: reason,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivery cancelled. Sender has been notified.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showRenegotiateDialog(
      RideModel ride, String transporterId) async {
    // Use latest counter-offer (sender's or ours) as base so renegotiate reflects current amount
    final basePrice = ride.counterOffer ?? ride.price ?? 0.0;
    if (basePrice <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No offer amount to counter.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    final controller = TextEditingController(
      text: basePrice.toStringAsFixed(2),
    );

    await showDialog(
      context: context,
      builder: (dialogContext) {
        Future<void> sendCounterOffer(double value) async {
          setState(() => _isOffering = true);
          try {
            await _rideService.submitCounterOffer(
              ride.id!,
              transporterId,
              value,
            );
            if (mounted) {
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Counter offer \$${value.toStringAsFixed(2)} sent to sender.',
                  ),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: ${e.toString()}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          } finally {
            if (mounted) setState(() => _isOffering = false);
          }
        }

        return AlertDialog(
          title: Text(
            'Counter-Offer (inDrive style)',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1E40AF),
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sender\'s offer: \$${basePrice.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Quick counter (tap to send):',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E40AF),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _QuickCounterButton(
                        label: '+10%',
                        amount: basePrice * 1.10,
                        onPressed: _isOffering
                            ? null
                            : () => sendCounterOffer(basePrice * 1.10),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _QuickCounterButton(
                        label: '+20%',
                        amount: basePrice * 1.20,
                        onPressed: _isOffering
                            ? null
                            : () => sendCounterOffer(basePrice * 1.20),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _QuickCounterButton(
                        label: '+30%',
                        amount: basePrice * 1.30,
                        onPressed: _isOffering
                            ? null
                            : () => sendCounterOffer(basePrice * 1.30),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Or enter custom amount:',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E40AF),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Your price',
                    prefixText: '\$',
                    labelStyle: GoogleFonts.inter(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(color: Colors.grey.shade700),
              ),
            ),
            ElevatedButton(
              onPressed: _isOffering
                  ? null
                  : () async {
                      final value = double.tryParse(controller.text.trim());
                      if (value == null || value < PricingService.minimumFloorPrice) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Minimum \$${PricingService.minimumFloorPrice.toStringAsFixed(2)}.',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      await sendCounterOffer(value);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Send Offer',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Quick counter-offer button: +10%, +20%, +30% of sender's offer.
class _QuickCounterButton extends StatelessWidget {
  final String label;
  final double amount;
  final VoidCallback? onPressed;

  const _QuickCounterButton({
    required this.label,
    required this.amount,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF2563EB),
        side: const BorderSide(color: Color(0xFF2563EB)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
