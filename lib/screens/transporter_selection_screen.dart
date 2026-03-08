import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/ride_model.dart';
import '../models/transporter_offer_model.dart';
import '../models/user_model.dart';
import '../services/ride_service.dart';

class TransporterSelectionScreen extends StatefulWidget {
  final String rideId;

  const TransporterSelectionScreen({
    super.key,
    required this.rideId,
  });

  @override
  State<TransporterSelectionScreen> createState() => _TransporterSelectionScreenState();
}

class _TransporterSelectionScreenState extends State<TransporterSelectionScreen> {
  RideModel? _cachedRide;
  List<TransporterOfferModel>? _cachedOffers;
  bool _senderViewRecorded = false;

  @override
  void initState() {
    super.initState();
    // When sender opens this screen, record view so transporter can see "Sender has viewed"
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_senderViewRecorded) return;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      _senderViewRecorded = true;
      RideService().updateSenderLastViewed(widget.rideId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rideService = RideService();
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Choose Transporter',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E40AF),
          ),
        ),
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Request details: persist last loaded ride (orders in negotiating)
            StreamBuilder<RideModel?>(
              stream: rideService.streamRideById(widget.rideId),
              builder: (context, snapshot) {
                if (snapshot.data != null) _cachedRide = snapshot.data;
                final ride = snapshot.data ?? _cachedRide;
                if (ride == null) {
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: const Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Loading request details…',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final isOwner = currentUser?.uid == ride.userId;
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Request',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ride.packageDescription ?? 'Transport request',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1E40AF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${ride.pickupLocation} → ${ride.dropoffLocation}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      if (ride.price != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Your offer: \$${ride.price!.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF2563EB),
                          ),
                        ),
                      ],
                      // Persistent status: sender sent counter-offer, waiting for transporter
                      if (isOwner && ride.status == 'pending' && ride.priceStatus == 'pending' && ride.lastCounterOfferBy == 'sender') ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.schedule, size: 18, color: Colors.amber.shade800),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Waiting for transporter to respond',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (!isOwner) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Only the sender can choose a transporter.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.red.shade400,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            Expanded(
              child: StreamBuilder<List<TransporterOfferModel>>(
                stream: rideService.streamOffersForRide(widget.rideId),
                builder: (context, snapshot) {
                  if (snapshot.data != null) _cachedOffers = snapshot.data;
                  final offers = snapshot.data ?? _cachedOffers ?? [];
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      offers.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (offers.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.local_shipping,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Waiting for transporters…',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'You will see transporters here as they offer to collect your parcel.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: offers.length,
                    itemBuilder: (context, index) {
                      final offer = offers[index];
                      return _OfferCard(
                        rideId: widget.rideId,
                        offer: offer,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferCard extends StatefulWidget {
  final String rideId;
  final TransporterOfferModel offer;

  const _OfferCard({
    required this.rideId,
    required this.offer,
  });

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  bool _isSelecting = false;

  @override
  Widget build(BuildContext context) {
    final rideService = RideService();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.offer.transporterId)
              .snapshots(),
          builder: (context, userSnapshot) {
            UserModel? transporter;
            if (userSnapshot.data?.data() != null) {
              transporter = UserModel.fromMap(userSnapshot.data!.data()!);
            }

            final status = widget.offer.status;
            final isSelected = status == 'selected';
            final isRejected = status == 'rejected';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFF2563EB).withOpacity(0.1),
                      child: Icon(
                        Icons.local_shipping,
                        color: const Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            transporter?.displayName ?? 'Transporter',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1E40AF),
                            ),
                          ),
                          if (transporter?.truckType != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              transporter!.truckType!,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.offer.priceOffer != null)
                      Text(
                        '\$${widget.offer.priceOffer!.toStringAsFixed(2)}',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF2563EB),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (isSelected)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Selected',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF15803D),
                          ),
                        ),
                      )
                    else if (isRejected)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Not selected',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.red.shade600,
                          ),
                        ),
                      )
                    else
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('rides')
                            .doc(widget.rideId)
                            .snapshots(),
                        builder: (context, rideSnapshot) {
                          final rideData = rideSnapshot.data?.data();
                          final priceStatus = rideData?['priceStatus'] as String?;
                          final counterOffer = rideData?['counterOffer'] as num?;
                          final originalPrice = rideData?['price'] as num?;
                          
                          // Check if this offer has a counter-offer or if sender needs to respond
                          final hasCounterOffer = counterOffer != null && 
                                                   priceStatus == 'pending' &&
                                                   widget.offer.priceOffer == counterOffer.toDouble();
                          final senderApproved = priceStatus == 'accepted' &&
                                                widget.offer.priceOffer == (rideData?['price'] as num?)?.toDouble();
                          
                          return Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (hasCounterOffer) ...[
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.amber.withOpacity(0.3),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          'Counter-Offer Received',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.amber.shade800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '\$${counterOffer.toStringAsFixed(2)}',
                                          style: GoogleFonts.inter(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF2563EB),
                                          ),
                                        ),
                                        if (originalPrice != null)
                                          Text(
                                            'Your offer: \$${originalPrice.toStringAsFixed(2)}',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (senderApproved) ...[
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.green.withOpacity(0.3),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.check_circle, 
                                          color: Colors.green, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'You approved this amount. Transporter can now accept the ride.',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: Colors.green.shade800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        height: 44,
                                        child: ElevatedButton(
                                          onPressed: _isSelecting
                                              ? null
                                              : () async {
                                                  setState(() {
                                                    _isSelecting = true;
                                                  });
                                                  try {
                                                    if (hasCounterOffer) {
                                                      // Accept the counter-offer
                                                      await rideService.respondToCounterOffer(
                                                        widget.rideId,
                                                        widget.offer.id,
                                                        true,
                                                      );
                                                      if (!mounted) return;
                                                      ScaffoldMessenger.of(context)
                                                          .showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                              'Counter-offer accepted! Transporter can now accept the ride.'),
                                                          backgroundColor: Colors.green,
                                                        ),
                                                      );
                                                    } else {
                                                      // Direct acceptance (no negotiation)
                                                      await rideService.acceptRide(
                                                        widget.rideId,
                                                        widget.offer.transporterId,
                                                      );
                                                      await rideService.markSelectedOffer(
                                                        widget.rideId,
                                                        widget.offer.id,
                                                      );
                                                      if (!mounted) return;
                                                      ScaffoldMessenger.of(context)
                                                          .showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                              'Transporter selected successfully!'),
                                                          backgroundColor: Colors.green,
                                                        ),
                                                      );
                                                      Navigator.of(context).pop();
                                                    }
                                                  } catch (e) {
                                                    if (!mounted) return;
                                                    ScaffoldMessenger.of(context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                            'Error: ${e.toString()}'),
                                                        backgroundColor: Colors.red,
                                                      ),
                                                    );
                                                  } finally {
                                                    if (mounted) {
                                                      setState(() {
                                                        _isSelecting = false;
                                                      });
                                                    }
                                                  }
                                                },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF2563EB),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            elevation: 0,
                                          ),
                                          child: _isSelecting
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<Color>(
                                                            Colors.white),
                                                  ),
                                                )
                                              : Text(
                                                  hasCounterOffer ? 'Accept Offer' : 'Select',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      height: 44,
                                      child: OutlinedButton(
                                        onPressed: _isSelecting
                                            ? null
                                            : () => _showCounterOfferDialog(
                                                context, 
                                                widget.rideId, 
                                                widget.offer.id,
                                                counterOffer?.toDouble(),
                                                originalPrice?.toDouble(),
                                              ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFF2563EB),
                                          side: const BorderSide(
                                            color: Color(0xFF2563EB),
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                        ),
                                        child: Text(
                                          hasCounterOffer ? 'Counter-Offer' : 'Negotiate',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      height: 44,
                                      child: OutlinedButton(
                                        onPressed: _isSelecting
                                            ? null
                                            : () async {
                                                setState(() {
                                                  _isSelecting = true;
                                                });
                                                try {
                                                  if (hasCounterOffer) {
                                                    // Reject counter-offer
                                                    await rideService.respondToCounterOffer(
                                                      widget.rideId,
                                                      widget.offer.id,
                                                      false,
                                                    );
                                                  } else {
                                                    // Reject offer
                                                    await FirebaseFirestore.instance
                                                        .collection('rides')
                                                        .doc(widget.rideId)
                                                        .collection('offers')
                                                        .doc(widget.offer.id)
                                                        .update({
                                                      'status': 'rejected',
                                                      'updatedAt': DateTime.now()
                                                          .toIso8601String(),
                                                    });
                                                  }

                                                  if (!mounted) return;
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                          'Offer declined.'),
                                                      backgroundColor: Colors.orange,
                                                    ),
                                                  );
                                                } catch (e) {
                                                  if (!mounted) return;
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                          'Error: ${e.toString()}'),
                                                      backgroundColor: Colors.red,
                                                    ),
                                                  );
                                                } finally {
                                                  if (mounted) {
                                                    setState(() {
                                                      _isSelecting = false;
                                                    });
                                                  }
                                                }
                                              },
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.grey.shade800,
                                          side: BorderSide(
                                            color: Colors.grey.shade400,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                        ),
                                        child: Text(
                                          'Decline',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showCounterOfferDialog(
    BuildContext context,
    String rideId,
    String offerId,
    double? currentCounterOffer,
    double? originalPrice,
  ) {
    final controller = TextEditingController(
      text: currentCounterOffer?.toStringAsFixed(2) ?? originalPrice?.toStringAsFixed(2) ?? '',
    );
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
          'Make Counter-Offer',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (currentCounterOffer != null) ...[
              Text(
                'Transporter\'s offer: \$${currentCounterOffer.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Your counter-offer',
                hintText: 'Enter amount',
                prefixText: '\$',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: Colors.grey.shade700),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final text = controller.text.trim();
              final value = double.tryParse(text);
              if (value == null || value <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid price'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                final rideService = RideService();
                await rideService.sendSenderCounterOffer(
                  rideId,
                  offerId,
                  value,
                );
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Counter-offer of \$${value.toStringAsFixed(2)} sent to transporter.',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
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
              'Send',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

