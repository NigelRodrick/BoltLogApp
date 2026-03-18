import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ride_model.dart';
import '../models/user_model.dart';
import '../services/ride_service.dart';
import '../services/user_service.dart';
import '../services/routing_service.dart';
import '../services/pricing_service.dart';
import '../config/testing_flags.dart';
import '../utils/ride_distance_utils.dart';
import 'active_ride_map_screen.dart';
import 'request_detail_screen.dart';

class TransporterDashboardScreen extends StatefulWidget {
  const TransporterDashboardScreen({super.key});

  @override
  State<TransporterDashboardScreen> createState() => _TransporterDashboardScreenState();
}

class _TransporterDashboardScreenState extends State<TransporterDashboardScreen> {
  GoogleMapController? _mapController;
  bool _isMapView = false; // Default to list view
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<RideModel> _rides = [];
  List<RideModel>? _cachedRides;

  @override
  void initState() {
    super.initState();
    // Set transporter as online when dashboard opens
    _setOnlineStatus();
  }

  void _setOnlineStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userService = UserService();
        await userService.updateDriverProfile(
          uid: user.uid,
          isAvailable: true,
        );
      } catch (e) {
        // Silently fail
      }
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
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Current Requests',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E40AF), // Blue-700
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Colors.orange.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Text(
                'TRANSPORTER',
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isMapView ? Icons.list : Icons.map,
              color: const Color(0xFF1E40AF),
            ),
            onPressed: () {
              setState(() {
                _isMapView = !_isMapView;
              });
            },
            tooltip: _isMapView ? 'List View' : 'Map View',
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<UserModel?>(
          stream: user != null ? UserService().streamUser(user!.uid) : Stream.value(null),
          builder: (context, userSnap) {
            final userModel = userSnap.data;
            final isDriver = (userModel?.role ?? '').toLowerCase() == 'driver';
            final verificationStatus = (userModel?.verificationStatus ?? 'pending').toLowerCase();
            final isVerified = verificationStatus == 'auto_verified' || verificationStatus == 'verified';
            // In testing mode, hide the licence verification banner entirely.
            final showVerificationBanner = !TestingFlags.relaxTransporterVerification &&
                isDriver &&
                !isVerified;

            return StreamBuilder<List<RideModel>>(
              stream: rideService.streamAvailableRides(),
              builder: (context, snapshot) {
                if (snapshot.data != null) _cachedRides = snapshot.data;
                final rides = snapshot.data ?? _cachedRides ?? [];
                if (snapshot.connectionState == ConnectionState.waiting &&
                    rides.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError && rides.isEmpty) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: GoogleFonts.inter(color: Colors.red),
                    ),
                  );
                }

                // Only show requests that match this transporter's vehicle type (when order has a type selected)
                final driverTruckType = userModel?.truckType;
                List<RideModel> filteredRides = rides
                    .where((ride) {
                      final orderType = ride.transportType;
                      if (orderType == null || orderType.isEmpty)
                        return true;
                      return driverTruckType != null &&
                          driverTruckType.isNotEmpty &&
                          orderType == driverTruckType;
                    })
                    .toList();
                // inDrive-style: only nearby requests, sorted by distance to pickup
                filteredRides = filterAndSortRidesByDistance(
                  filteredRides,
                  driverLat: userModel?.currentLat,
                  driverLng: userModel?.currentLng,
                  maxRadiusKm: defaultMaxRadiusKm,
                );

                _rides = filteredRides;

                Widget content;
                if (filteredRides.isEmpty) {
                  content = Center(
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
                          'No current requests',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'New transport requests will appear here',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  if (_isMapView) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _updateMapMarkers(filteredRides);
                    });
                    content = _buildMapView(
                      filteredRides,
                      user?.uid ?? '',
                      driverLat: userModel?.currentLat,
                      driverLng: userModel?.currentLng,
                    );
                  } else {
                    content = _buildListView(
                      filteredRides,
                      user?.uid ?? '',
                      driverLat: userModel?.currentLat,
                      driverLng: userModel?.currentLng,
                    );
                  }
                }

                Widget finalContent = content;

                if (showVerificationBanner) {
                  finalContent = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
                                'Licence ID still under verification. You can browse requests but must be verified to accept or negotiate.',
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
                      const SizedBox(height: 8),
                      Expanded(child: content),
                    ],
                  );
                }

                return Column(
                  children: [
                    Expanded(child: finalContent),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8, top: 4),
                      child: Text(
                        'Developed by Fidinsky Tech Solutions',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildMapView(
    List<RideModel> rides,
    String transporterId, {
    double? driverLat,
    double? driverLng,
  }) {
    // Calculate initial camera position based on rides
    LatLng? initialPosition;
    if (rides.isNotEmpty) {
      final firstRide = rides.first;
      if (firstRide.pickupLat != null && firstRide.pickupLng != null) {
        initialPosition = LatLng(firstRide.pickupLat!, firstRide.pickupLng!);
      }
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: initialPosition ?? const LatLng(-19.4500, 29.8167), // Gweru default
            zoom: 12,
          ),
          onMapCreated: (controller) {
            _mapController = controller;
            _updateMapMarkers(rides);
          },
          markers: _markers,
          polylines: _polylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: true,
          mapType: MapType.normal,
          compassEnabled: true,
        ),
        // Legend
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.location_on, color: const Color(0xFF2563EB), size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Pickup',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.red.shade400, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Dropoff',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _updateMapMarkers(List<RideModel> rides) async {
    final Set<Marker> markers = {};
    final Set<Polyline> polylines = {};

    for (int i = 0; i < rides.length; i++) {
      final ride = rides[i];
      
      // Get coordinates for pickup
      double? pickupLat = ride.pickupLat;
      double? pickupLng = ride.pickupLng;
      
      if (pickupLat == null || pickupLng == null) {
        try {
          final pickupLocations = await locationFromAddress(ride.pickupLocation);
          if (pickupLocations.isNotEmpty) {
            pickupLat = pickupLocations.first.latitude;
            pickupLng = pickupLocations.first.longitude;
          }
        } catch (e) {
          continue; // Skip this ride if geocoding fails
        }
      }

      // Get coordinates for dropoff
      double? dropoffLat = ride.dropoffLat;
      double? dropoffLng = ride.dropoffLng;
      
      if (dropoffLat == null || dropoffLng == null) {
        try {
          final dropoffLocations = await locationFromAddress(ride.dropoffLocation);
          if (dropoffLocations.isNotEmpty) {
            dropoffLat = dropoffLocations.first.latitude;
            dropoffLng = dropoffLocations.first.longitude;
          }
        } catch (e) {
          continue; // Skip this ride if geocoding fails
        }
      }

      if (pickupLat != null && pickupLng != null && dropoffLat != null && dropoffLng != null) {
        // Add pickup marker (blue)
        markers.add(
          Marker(
            markerId: MarkerId('pickup_${ride.id}_$i'),
            position: LatLng(pickupLat, pickupLng),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: InfoWindow(
              title: 'Pickup',
              snippet: ride.pickupLocation,
            ),
          ),
        );

        // Add dropoff marker (red)
        markers.add(
          Marker(
            markerId: MarkerId('dropoff_${ride.id}_$i'),
            position: LatLng(dropoffLat, dropoffLng),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(
              title: 'Dropoff',
              snippet: ride.dropoffLocation,
            ),
          ),
        );

        // Add route polyline between pickup and dropoff (actual road route)
        try {
          final routingService = RoutingService();
          final route = await routingService.getRoute(
            originLat: pickupLat,
            originLng: pickupLng,
            destLat: dropoffLat,
            destLng: dropoffLng,
          );
          if (route != null) {
            polylines.add(
              Polyline(
                polylineId: PolylineId('route_${ride.id}_$i'),
                points: route.points,
                color: const Color(0xFF2563EB),
                width: 3,
              ),
            );
          }
        } catch (e) {
          // If routing fails, skip drawing the route for this ride
        }
      }
    }

    // Fit bounds to show all markers
    if (markers.isNotEmpty && _mapController != null) {
      final bounds = _calculateBounds(markers);
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 100),
      );
    }

    setState(() {
      _markers = markers;
      _polylines = polylines;
    });
  }

  LatLngBounds _calculateBounds(Set<Marker> markers) {
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    for (var marker in markers) {
      final lat = marker.position.latitude;
      final lng = marker.position.longitude;
      minLat = minLat < lat ? minLat : lat;
      maxLat = maxLat > lat ? maxLat : lat;
      minLng = minLng < lng ? minLng : lng;
      maxLng = maxLng > lng ? maxLng : lng;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Widget _buildListView(
    List<RideModel> rides,
    String transporterId, {
    double? driverLat,
    double? driverLng,
  }) {
    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: rides.length,
        itemBuilder: (context, index) {
          final ride = rides[index];
          return _buildDeliveryCard(
            context,
            ride,
            transporterId,
            driverLat: driverLat,
            driverLng: driverLng,
          );
        },
      ),
    );
  }

  Widget _buildDeliveryCard(
    BuildContext context,
    RideModel ride,
    String transporterId, {
    double? driverLat,
    double? driverLng,
  }) {

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(transporterId).snapshots(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() as Map<String, dynamic>? ?? {};
        final driverBalance = (userData['driverWalletBalance'] as num?)?.toDouble() ?? 0.0;
        final ratePer10Km = (userData['ratePer10Km'] as num?)?.toDouble();
        final ridePrice = ride.price ?? 0.0;
        final requiredFee = ridePrice * 0.02;
        final canAccept = driverBalance >= requiredFee;
        double? distanceKm;
        double? yourRateForTrip;
        if (ride.pickupLat != null && ride.pickupLng != null && ride.dropoffLat != null && ride.dropoffLng != null) {
          distanceKm = PricingService.calculateDistance(
            ride.pickupLat!, ride.pickupLng!,
            ride.dropoffLat!, ride.dropoffLng!,
          );
          yourRateForTrip = PricingService.calculateDriverPriceForDistance(distanceKm, ratePer10Km);
        }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 2,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RequestDetailScreen(ride: ride),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Header with package info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (ride.packageDescription != null) ...[
                        Text(
                          ride.packageDescription!,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E40AF), // Blue-700
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Row(
                        children: [
                          if (ride.packageType != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB).withOpacity(0.1), // Blue-600
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                ride.packageType!.toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF2563EB), // Blue-600
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (ride.weight != null)
                            Text(
                              '${ride.weight} kg',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          if (driverLat != null &&
                              driverLng != null &&
                              distanceToPickupKm(ride, driverLat, driverLng) != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${distanceToPickupKm(ride, driverLat, driverLng)!.toStringAsFixed(1)} km away',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (ride.price != null || yourRateForTrip != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (ride.price != null) ...[
                        Text(
                          'Sender\'s offer',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          '\$${ride.price!.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF2563EB), // Blue-600
                          ),
                        ),
                      ],
                      if (yourRateForTrip != null) ...[
                        if (ride.price != null) const SizedBox(height: 6),
                        Text(
                          'Your rate for this trip',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          '\$${yourRateForTrip.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1E40AF), // Blue-700
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
            // Status Badge (Open)
            if (ride.status == 'open') ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.green,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'OPEN',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Transporter Payment Method
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
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      ride.senderPaymentMethod == 'ecocash'
                          ? Icons.account_balance_wallet
                          : Icons.money,
                      size: 16,
                      color: ride.senderPaymentMethod == 'ecocash'
                          ? Colors.green
                          : Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Payment: ${ride.senderPaymentMethod == 'ecocash' ? 'EcoCash' : 'Cash'}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
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
            const SizedBox(height: 16),
            // Pickup location
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_on,
                  size: 16,
                  color: const Color(0xFF2563EB), // Blue-600
                ),
                const SizedBox(width: 8),
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
                      Text(
                        ride.pickupLocation,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: const Color(0xFF1E40AF), // Blue-700
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Dropoff location
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_on,
                  size: 16,
                  color: Colors.red.shade400,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dropoff',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        ride.dropoffLocation,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: const Color(0xFF1E40AF), // Blue-700
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (ride.estimatedValue != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.attach_money,
                    size: 14,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Value: \$${ride.estimatedValue!.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
            // Payment Method Badge
            if (ride.senderPaymentMethod != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    ride.senderPaymentMethod!.toLowerCase() == 'ecocash'
                        ? Icons.account_balance_wallet
                        : Icons.money,
                    size: 14,
                    color: ride.senderPaymentMethod!.toLowerCase() == 'ecocash'
                        ? Colors.green
                        : Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: ride.senderPaymentMethod!.toLowerCase() == 'ecocash'
                          ? Colors.green.withOpacity(0.1)
                          : Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: ride.senderPaymentMethod!.toLowerCase() == 'ecocash'
                            ? Colors.green
                            : Colors.orange,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      'Payment: ${ride.senderPaymentMethod!.toLowerCase() == 'ecocash' ? 'EcoCash' : 'Cash'}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: ride.senderPaymentMethod!.toLowerCase() == 'ecocash'
                            ? Colors.green
                            : Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            // Quick counter-offer button
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () {
                  _showQuickCounterOfferDialog(context, ride, transporterId);
                },
                icon: const Icon(Icons.attach_money, size: 18),
                label: const Text('Make Counter Offer'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2563EB),
                  side: const BorderSide(color: Color(0xFF2563EB)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // View button - open request details for full info and negotiation
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RequestDetailScreen(ride: ride),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB), // Blue-600
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'View Request',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
      },
    );
  }

  void _showQuickCounterOfferDialog(BuildContext context, RideModel ride, String transporterId) {
    final controller = TextEditingController(
      text: ride.price?.toStringAsFixed(2) ?? '',
    );
    final rideService = RideService();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Make Counter Offer',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1E40AF),
          ),
        ),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Your price offer',
            prefixText: '\$',
            labelStyle: GoogleFonts.inter(),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
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
                if (ride.id != null) {
                  await rideService.submitCounterOffer(
                    ride.id!,
                    transporterId,
                    value,
                  );
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Counter offer sent successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
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
              'Send Offer',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}
