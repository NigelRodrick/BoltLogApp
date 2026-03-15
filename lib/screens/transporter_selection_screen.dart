import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/ride_model.dart';
import '../models/transporter_offer_model.dart';
import '../models/user_model.dart';
import '../services/pricing_service.dart';
import '../services/ride_service.dart';
import '../services/routing_service.dart';
import '../services/user_service.dart';
import '../utils/negotiation_utils.dart';

/// Filters offers to transporters whose truckType matches the ride's transportType,
/// and sorts by default price (distance × rate) ascending so sender can compare charges.
Future<List<TransporterOfferModel>> _filterAndSortOffersByTransportTypeAndCharge(
  RideModel ride,
  List<TransporterOfferModel> offers,
  UserService userService,
) async {
  if (offers.isEmpty) return [];
  final uids = offers.map((o) => o.transporterId).toList();
  final users = await userService.getUsersByIds(uids);
  final rideType = ride.transportType;
  final hasCoords = ride.pickupLat != null &&
      ride.pickupLng != null &&
      ride.dropoffLat != null &&
      ride.dropoffLng != null;
  final distanceKm = hasCoords
      ? PricingService.calculateDistance(
          ride.pickupLat!,
          ride.pickupLng!,
          ride.dropoffLat!,
          ride.dropoffLng!,
        )
      : 0.0;

  final List<({TransporterOfferModel offer, double sortPrice})> withPrice = [];
  for (int i = 0; i < offers.length; i++) {
    final u = i < users.length ? users[i] : null;
    final matchesType = rideType == null ||
        rideType.isEmpty ||
        (u?.truckType != null && u!.truckType == rideType);
    if (!matchesType) continue;

    double sortPrice = double.infinity;
    if (hasCoords && u?.ratePer10Km != null && u!.ratePer10Km! > 0) {
      final p = PricingService.calculateDriverPriceForDistance(
        distanceKm,
        u.ratePer10Km,
      );
      if (p != null) sortPrice = p;
    }
    withPrice.add((offer: offers[i], sortPrice: sortPrice));
  }
  withPrice.sort((a, b) => a.sortPrice.compareTo(b.sortPrice));
  return withPrice.map((e) => e.offer).toList();
}

String _vehicleTypeLabel(String? type) {
  if (type == null || type.isEmpty) return 'Any';
  switch (type) {
    case 'bike_express':
      return 'Bike Express';
    case 'runner':
      return 'Runner';
    case 'pickup':
      return 'Pickup (1.2t)';
    case 'truck_5t':
      return 'Truck (5t)';
    case 'truck_10t':
      return 'Truck (10t)';
    case 'truck_20t':
      return 'Truck (20t)';
    default:
      return type;
  }
}

/// Sender sees nearby transporters (matching selected type) and their price rates.
class _NearbyTransportersSection extends StatelessWidget {
  final List<UserModel> drivers;
  final RideModel ride;
  final double distanceKm;

  const _NearbyTransportersSection({
    required this.drivers,
    required this.ride,
    required this.distanceKm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.people_outline, size: 18, color: Colors.grey.shade700),
              const SizedBox(width: 6),
              Text(
                'Transporters nearby (${_vehicleTypeLabel(ride.transportType)})',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E40AF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (drivers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No transporters of this type nearby. They will appear here when available.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            )
          else
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: drivers.length,
                itemBuilder: (context, index) {
                  final d = drivers[index];
                  final defaultPrice = PricingService.calculateDriverPriceForDistance(
                    distanceKm,
                    d.ratePer10Km,
                  );
                  return Container(
                    width: 160,
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          d.displayName ?? 'Transporter',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1E40AF),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (d.truckType != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            _vehicleTypeLabel(d.truckType),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                        if (d.ratePer10Km != null && d.ratePer10Km! > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            '\$${d.ratePer10Km!.toStringAsFixed(0)}/10 km',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                        if (defaultPrice != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Est. \$${defaultPrice.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF2563EB),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

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

    return WillPopScope(
      onWillPop: () async {
        if (_lockNavigation) {
          _showNegotiationLockDialog();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
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
                  _lockNavigation = negotiationInProgress(ride);

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
                        if (ride.price != null || ride.counterOffer != null) ...[
                          const SizedBox(height: 8),
                          if (ride.price != null)
                            Text(
                              'Your amount: \$${ride.price!.toStringAsFixed(2)}',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF2563EB),
                              ),
                            ),
                          if (ride.counterOffer != null &&
                              ride.priceStatus == 'pending') ...[
                            const SizedBox(height: 4),
                            Text(
                              ride.lastCounterOfferBy == 'transporter'
                                  ? 'Transporter proposed: \$${ride.counterOffer!.toStringAsFixed(2)}'
                                  : 'Your counter-offer: \$${ride.counterOffer!.toStringAsFixed(2)}',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: ride.lastCounterOfferBy == 'transporter'
                                    ? Colors.amber.shade800
                                    : Colors.green.shade700,
                              ),
                            ),
                          ],
                        ],
                        // Persistent status: sender sent counter-offer, waiting for transporter
                        if (isOwner &&
                            ride.status == 'pending' &&
                            ride.priceStatus == 'pending' &&
                            ride.lastCounterOfferBy == 'sender') ...[
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
                                Icon(Icons.schedule,
                                    size: 18, color: Colors.amber.shade800),
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
              // Sender sees transporters nearby (matching selected type) and their price rates
              if (_cachedRide != null &&
                  _cachedRide!.pickupLat != null &&
                  _cachedRide!.pickupLng != null)
                StreamBuilder<List<UserModel>>(
                  stream: UserService().getNearbyDrivers(
                    latitude: _cachedRide!.pickupLat!,
                    longitude: _cachedRide!.pickupLng!,
                    radiusKm: 25,
                  ),
                  builder: (context, driverSnapshot) {
                    final allDrivers = driverSnapshot.data ?? [];
                    final ride = _cachedRide!;
                    final orderType = ride.transportType;
                    final filtered = orderType == null || orderType.isEmpty
                        ? allDrivers
                        : allDrivers
                            .where((d) => d.truckType == orderType)
                            .toList();
                    final distanceKm = ride.dropoffLat != null &&
                            ride.dropoffLng != null
                        ? PricingService.calculateDistance(
                            ride.pickupLat!,
                            ride.pickupLng!,
                            ride.dropoffLat!,
                            ride.dropoffLng!,
                          )
                        : 0.0;
                    filtered.sort((a, b) {
                      final pa = PricingService.calculateDriverPriceForDistance(
                            distanceKm,
                            a.ratePer10Km,
                          ) ??
                          double.infinity;
                      final pb = PricingService.calculateDriverPriceForDistance(
                            distanceKm,
                            b.ratePer10Km,
                          ) ??
                          double.infinity;
                      return pa.compareTo(pb);
                    });
                    return _NearbyTransportersSection(
                      drivers: filtered,
                      ride: ride,
                      distanceKm: distanceKm,
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

                    final ride = _cachedRide;
                    if (ride == null) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final userService = UserService();
                    return FutureBuilder<List<TransporterOfferModel>>(
                      key: ValueKey(
                        '${ride.transportType ?? ''}_${offers.map((o) => o.id).join(',')}',
                      ),
                      future: _filterAndSortOffersByTransportTypeAndCharge(
                        ride,
                        offers,
                        userService,
                      ),
                      builder: (context, filterSnapshot) {
                        if (!filterSnapshot.hasData) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24.0),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        final filteredOffers = filterSnapshot.data!;
                        if (filteredOffers.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.filter_list,
                                    size: 64,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No ${_vehicleTypeLabel(ride.transportType).toLowerCase()} transporters yet',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    ride.transportType != null &&
                                            ride.transportType!.isNotEmpty
                                        ? 'Only transporters matching your selected vehicle type are shown. Others may still offer.'
                                        : 'Transporters will appear here as they offer.',
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
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Offers from transporters',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF1E40AF),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      if (ride.transportType != null &&
                                          ride.transportType!.isNotEmpty) ...[
                                        Icon(
                                          Icons.category,
                                          size: 16,
                                          color: Colors.grey.shade600,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '${_vehicleTypeLabel(ride.transportType)} • ',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                      Text(
                                        'Sorted by estimated price (distance × rate)',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: filteredOffers.length,
                                itemBuilder: (context, index) {
                                  final offer = filteredOffers[index];
                                  return _OfferCard(
                                    rideId: widget.rideId,
                                    offer: offer,
                                    ride: ride,
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfferCard extends StatefulWidget {
  final String rideId;
  final TransporterOfferModel offer;
  final RideModel ride;

  const _OfferCard({
    required this.rideId,
    required this.offer,
    required this.ride,
  });

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  bool _isSelecting = false;

  @override
  Widget build(BuildContext context) {
    final rideService = RideService();

    // Ride doc is single source of truth for negotiated amount on both screens
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('rides')
          .doc(widget.rideId)
          .snapshots(),
      builder: (context, rideSnapshot) {
        final rideData = rideSnapshot.data?.data();
        final rideCounterOffer =
            (rideData?['counterOffer'] as num?)?.toDouble();
        final rideLastBy = rideData?['lastCounterOfferBy'] as String?;
        final ridePriceStatus = rideData?['priceStatus'] as String?;
        final negotiatingTransporterId =
            rideData?['negotiatingTransporterId'] as String?;

        // Only this card is in active negotiation (works for any sender + multiple transporters)
        final isNegotiatingCard = negotiatingTransporterId == null ||
            negotiatingTransporterId == widget.offer.transporterId;

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('rides')
              .doc(widget.rideId)
              .collection('offers')
              .doc(widget.offer.id)
              .snapshots(),
          builder: (context, offerSnapshot) {
            final offerData = offerSnapshot.data?.data();
            final currentPriceOffer =
                (offerData?['priceOffer'] as num?)?.toDouble() ??
                    widget.offer.priceOffer;
            final currentStatus =
                (offerData?['status'] as String?) ?? widget.offer.status;

            // Show negotiated amount only on the card that is in negotiation
            final displayAmount = isNegotiatingCard
                ? (rideCounterOffer ?? currentPriceOffer)
                : currentPriceOffer;
            final displayLabel = isNegotiatingCard &&
                    ridePriceStatus == 'pending' &&
                    rideCounterOffer != null
                ? (rideLastBy == 'transporter'
                    ? 'Their offer'
                    : 'Your counter')
                : 'Their bid';

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

                final isSelected = currentStatus == 'selected';
                final isRejected = currentStatus == 'rejected';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: const Color(0xFF2563EB).withOpacity(0.1),
                          child: const Icon(
                            Icons.local_shipping,
                            color: Color(0xFF2563EB),
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
                              if (transporter?.rating != null) ...[
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.star,
                                      size: 14,
                                      color: Colors.amber.shade700,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      transporter!.rating!.toStringAsFixed(1),
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (transporter?.currentLat != null &&
                                  transporter?.currentLng != null &&
                                  widget.ride.pickupLat != null &&
                                  widget.ride.pickupLng != null)
                                _DriverEtaChip(
                                  originLat: transporter!.currentLat!,
                                  originLng: transporter.currentLng!,
                                  destLat: widget.ride.pickupLat!,
                                  destLng: widget.ride.pickupLng!,
                                ),
                              if (widget.ride.pickupLat != null &&
                                  widget.ride.pickupLng != null &&
                                  widget.ride.dropoffLat != null &&
                                  widget.ride.dropoffLng != null &&
                                  transporter?.ratePer10Km != null &&
                                  transporter!.ratePer10Km! > 0) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.route,
                                      size: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Default: \$${PricingService.calculateDriverPriceForDistance(
                                        PricingService.calculateDistance(
                                          widget.ride.pickupLat!,
                                          widget.ride.pickupLng!,
                                          widget.ride.dropoffLat!,
                                          widget.ride.dropoffLng!,
                                        ),
                                        transporter.ratePer10Km,
                                      )!.toStringAsFixed(2)} (distance × rate)',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                    if (displayAmount != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            displayLabel,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            '\$${displayAmount!.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: rideLastBy == 'sender'
                                  ? Colors.green.shade700
                                  : const Color(0xFF2563EB),
                            ),
                          ),
                        ],
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
                      isNegotiatingCard
                          ? StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('rides')
                            .doc(widget.rideId)
                            .snapshots(),
                        builder: (context, rideSnapshot) {
                          final rideData = rideSnapshot.data?.data();
                          final priceStatus =
                              rideData?['priceStatus'] as String?;
                          final counterOfferValue =
                              (rideData?['counterOffer'] as num?)?.toDouble();
                          final originalPriceValue =
                              (rideData?['price'] as num?)?.toDouble();

                          final hasCounterOffer =
                              counterOfferValue != null && priceStatus == 'pending';
                          final senderApproved = priceStatus == 'accepted';

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
                                          '\$${counterOfferValue!.toStringAsFixed(2)}',
                                          style: GoogleFonts.inter(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF2563EB),
                                          ),
                                        ),
                                        if (originalPriceValue != null)
                                          Text(
                                            'Your offer: \$${originalPriceValue.toStringAsFixed(2)}',
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
                                                counterOfferValue,
                                                originalPriceValue,
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
                                                    // Reject counter-offer; ride reopens to other transporters
                                                    await rideService.respondToCounterOffer(
                                                      widget.rideId,
                                                      widget.offer.id,
                                                      false,
                                                    );
                                                  } else {
                                                    // Reject offer and reopen ride so other transporters see it again
                                                    await rideService.rejectOfferAndReopenRide(
                                                      widget.rideId,
                                                      widget.offer.id,
                                                    );
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
                      )
                      : Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Another transporter is currently negotiating.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
          },
        );
      },
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

/// Shows driver ETA/distance to pickup using Distance Matrix API (inDrive-style).
class _DriverEtaChip extends StatelessWidget {
  final double originLat;
  final double originLng;
  final double destLat;
  final double destLng;

  const _DriverEtaChip({
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DistanceMatrixElement?>(
      future: RoutingService().getDistanceMatrixElement(
        originLat: originLat,
        originLng: originLng,
        destLat: destLat,
        destLng: destLng,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }
        final el = snapshot.data!;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(Icons.schedule, size: 12, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                '~${el.durationMinutes} min to pickup',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

