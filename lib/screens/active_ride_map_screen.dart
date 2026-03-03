import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../models/ride_model.dart';
import '../models/payment_model.dart';
import '../services/ride_service.dart';
import '../services/routing_service.dart';
import '../services/payment_service.dart';

class ActiveRideMapScreen extends StatefulWidget {
  final RideModel ride;

  const ActiveRideMapScreen({super.key, required this.ride});

  @override
  State<ActiveRideMapScreen> createState() => _ActiveRideMapScreenState();
}

class _ActiveRideMapScreenState extends State<ActiveRideMapScreen> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  double? _driverLat;
  double? _driverLng;
  double? _pickupLat;
  double? _pickupLng;
  double? _dropoffLat;
  double? _dropoffLng;
  bool _isLoading = true;
  bool _hasArrivedAtPickup = false;
  RouteInfo? _currentRouteInfo; // Store route info with traffic
  bool _hasArrivedAtDropoff = false;
  bool _isCollecting = false;
  bool _isDelivering = false;
  bool _isParcelCollected = false; // Track if parcel is already collected
  Timer? _locationTimer;
  final RideService _rideService = RideService();
  final PaymentService _paymentService = PaymentService();
  static const double _arrivalRadiusMeters = 50.0; // 50 meters radius to consider "arrived"

  @override
  void initState() {
    super.initState();
    _initializeMap();
    _startLocationTracking();
  }

  Future<void> _initializeMap() async {
    try {
      // Check if parcel is already collected
      _isParcelCollected = widget.ride.status == 'parcel_collected';

      // Get driver's current location
      await _getCurrentLocation();

      // Get coordinates for pickup
      _pickupLat = widget.ride.pickupLat;
      _pickupLng = widget.ride.pickupLng;

      if (_pickupLat == null || _pickupLng == null) {
        try {
          final locations = await locationFromAddress(widget.ride.pickupLocation);
          if (locations.isNotEmpty) {
            _pickupLat = locations.first.latitude;
            _pickupLng = locations.first.longitude;
          }
        } catch (e) {
          debugPrint('Error geocoding pickup: $e');
        }
      }

      // Get coordinates for dropoff
      _dropoffLat = widget.ride.dropoffLat;
      _dropoffLng = widget.ride.dropoffLng;

      if (_dropoffLat == null || _dropoffLng == null) {
        try {
          final locations = await locationFromAddress(widget.ride.dropoffLocation);
          if (locations.isNotEmpty) {
            _dropoffLat = locations.first.latitude;
            _dropoffLng = locations.first.longitude;
          }
        } catch (e) {
          debugPrint('Error geocoding dropoff: $e');
        }
      }

      if (mounted) {
        _updateMap();
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error initializing map: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startLocationTracking() {
    // Update location every 5 seconds
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _getCurrentLocation();
      // Update route with traffic info periodically
      _updateRouteWithTraffic();
      if (!_isParcelCollected) {
        _checkArrivalAtPickup();
      } else {
        _checkArrivalAtDropoff();
      }
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) return;

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (mounted) {
        setState(() {
          _driverLat = position.latitude;
          _driverLng = position.longitude;
        });
        _updateMap();
      }
    } catch (e) {
      debugPrint('Error getting current location: $e');
    }
  }

  void _checkArrivalAtPickup() {
    if (_driverLat == null || _driverLng == null || _pickupLat == null || _pickupLng == null) {
      return;
    }

    final distance = Geolocator.distanceBetween(
      _driverLat!,
      _driverLng!,
      _pickupLat!,
      _pickupLng!,
    );

    if (distance <= _arrivalRadiusMeters && !_hasArrivedAtPickup) {
      setState(() {
        _hasArrivedAtPickup = true;
      });
      
      // Show notification
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('You have arrived at the pickup location!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else if (distance > _arrivalRadiusMeters && _hasArrivedAtPickup) {
      setState(() {
        _hasArrivedAtPickup = false;
      });
    }
  }

  void _checkArrivalAtDropoff() {
    if (_driverLat == null || _driverLng == null || _dropoffLat == null || _dropoffLng == null) {
      return;
    }

    final distance = Geolocator.distanceBetween(
      _driverLat!,
      _driverLng!,
      _dropoffLat!,
      _dropoffLng!,
    );

    if (distance <= _arrivalRadiusMeters && !_hasArrivedAtDropoff) {
      setState(() {
        _hasArrivedAtDropoff = true;
      });
      
      // Show notification
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('You have arrived at the delivery location!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else if (distance > _arrivalRadiusMeters && _hasArrivedAtDropoff) {
      setState(() {
        _hasArrivedAtDropoff = false;
      });
    }
  }

  void _updateMap() {
    final Set<Marker> markers = {};
    final Set<Polyline> polylines = {};

    // Add driver's current location marker (green)
    if (_driverLat != null && _driverLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver_location'),
          position: LatLng(_driverLat!, _driverLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(
            title: 'Your Location',
            snippet: 'Driver current position',
          ),
        ),
      );
    }

    if (!_isParcelCollected) {
      // Show pickup location and route
      if (_pickupLat != null && _pickupLng != null) {
        markers.add(
          Marker(
            markerId: const MarkerId('pickup'),
            position: LatLng(_pickupLat!, _pickupLng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: InfoWindow(
              title: 'Pickup Location',
              snippet: widget.ride.pickupLocation,
            ),
          ),
        );
      }

      // Add route from driver to pickup (green line) - actual road route
      if (_driverLat != null && _driverLng != null && _pickupLat != null && _pickupLng != null) {
        _addRoutePolyline(
          polylines,
          const PolylineId('route_to_pickup'),
          _driverLat!,
          _driverLng!,
          _pickupLat!,
          _pickupLng!,
          Colors.green,
        );
      }
    } else {
      // Show dropoff location and route
      if (_dropoffLat != null && _dropoffLng != null) {
        markers.add(
          Marker(
            markerId: const MarkerId('dropoff'),
            position: LatLng(_dropoffLat!, _dropoffLng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(
              title: 'Delivery Location',
              snippet: widget.ride.dropoffLocation,
            ),
          ),
        );
      }

      // Add route from driver to dropoff (red/blue line) - actual road route
      if (_driverLat != null && _driverLng != null && _dropoffLat != null && _dropoffLng != null) {
        _addRoutePolyline(
          polylines,
          const PolylineId('route_to_dropoff'),
          _driverLat!,
          _driverLng!,
          _dropoffLat!,
          _dropoffLng!,
          Colors.red,
        );
      }
    }

    setState(() {
      _markers = markers;
      _polylines = polylines;
    });

    // Fit bounds to show driver and destination
    if (markers.length >= 2 && _mapController != null) {
      _fitBounds(markers);
    } else if (_driverLat != null && _driverLng != null && _mapController != null) {
      // Just center on driver if destination not available
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(LatLng(_driverLat!, _driverLng!)),
      );
    }
  }

  void _fitBounds(Set<Marker> markers) {
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

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 100),
    );
  }

  // Add route polyline using actual road route with traffic info
  void _addRoutePolyline(
    Set<Polyline> polylines,
    PolylineId polylineId,
    double originLat,
    double originLng,
    double destLat,
    double destLng,
    Color color,
  ) async {
    try {
      final routingService = RoutingService();
      // Get optimized route with traffic information
      final route = await routingService.getOptimizedRoute(
        originLat: originLat,
        originLng: originLng,
        destLat: destLat,
        destLng: destLng,
        optimization: RouteOptimization.fastest,
      );

      if (route != null) {
        // Store route info for displaying traffic
        setState(() {
          _currentRouteInfo = route;
        });

        polylines.add(
          Polyline(
            polylineId: polylineId,
            points: route.points,
            color: color,
            width: 5,
            patterns: [PatternItem.dash(20), PatternItem.gap(10)],
          ),
        );
      }

      // Update state to show the route
      if (mounted) {
        setState(() {
          _polylines = polylines;
        });
      }
    } catch (e) {
      // If routing fails, do not draw a fallback straight line
    }
  }

  Future<void> _confirmParcelCollected() async {
    setState(() {
      _isCollecting = true;
    });

    try {
      // Update ride status to parcel_collected
      await _rideService.markPickedUp(widget.ride.id!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Parcel collection confirmed!'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Update state to show dropoff route
        setState(() {
          _isParcelCollected = true;
          _hasArrivedAtPickup = false;
          _isCollecting = false;
        });
        _updateMap();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isCollecting = false;
        });
      }
    }
  }

  Future<void> _confirmParcelDelivered() async {
    setState(() {
      _isDelivering = true;
    });

    try {
      // Update ride status to completed
      await _rideService.markDelivered(widget.ride.id!);
      
      // Complete payment if cash on delivery
      try {
        final payment = await _paymentService.getPaymentForRide(widget.ride.id!);
        if (payment != null && payment.status == PaymentStatus.pending) {
          await _paymentService.completePayment(payment.id!);
        }
      } catch (e) {
        // Payment completion failed, but delivery is confirmed
        debugPrint('Error completing payment: $e');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Parcel delivery confirmed!'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Navigate back after a short delay
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isDelivering = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate initial camera position
    LatLng initialPosition = const LatLng(-19.4500, 29.8167); // Default Gweru
    if (_pickupLat != null && _pickupLng != null) {
      initialPosition = LatLng(_pickupLat!, _pickupLng!);
    } else if (_driverLat != null && _driverLng != null) {
      initialPosition = LatLng(_driverLat!, _driverLng!);
    }

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
          _isParcelCollected ? 'Navigate to Delivery' : 'Navigate to Pickup',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E40AF),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: initialPosition,
                    zoom: 14,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    _updateMap();
                  },
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: true,
                  mapType: MapType.normal,
                  compassEnabled: true,
                  onTap: (LatLng position) {
                    // Update driver location if manually tapped (for testing)
                  },
                ),
                // Distance indicator
                if ((!_isParcelCollected && _driverLat != null && _driverLng != null && _pickupLat != null && _pickupLng != null) ||
                    (_isParcelCollected && _driverLat != null && _driverLng != null && _dropoffLat != null && _dropoffLng != null))
                  Positioned(
                    top: 16,
                    left: 16,
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
                      child: Row(
                        children: [
                          Icon(
                            Icons.navigation,
                            color: const Color(0xFF2563EB),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _isParcelCollected ? 'Distance to Delivery' : 'Distance to Pickup',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Text(
                                  _getDistanceText(),
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF1E40AF),
                                  ),
                                ),
                                if (_currentRouteInfo != null && _currentRouteInfo!.hasTrafficDelay)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _currentRouteInfo!.trafficIcon,
                                          size: 12,
                                          color: _currentRouteInfo!.trafficColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${_currentRouteInfo!.trafficDelayMinutes} min delay',
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            color: _currentRouteInfo!.trafficColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if ((!_isParcelCollected && _hasArrivedAtPickup) || (_isParcelCollected && _hasArrivedAtDropoff))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'ARRIVED',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                // Location card (pickup or dropoff)
                Positioned(
                  bottom: ((!_isParcelCollected && _hasArrivedAtPickup) || (_isParcelCollected && _hasArrivedAtDropoff)) ? 100 : 16,
                  left: 16,
                  right: 16,
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                color: _isParcelCollected ? Colors.red.shade400 : const Color(0xFF2563EB),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isParcelCollected ? 'Delivery Location' : 'Pickup Location',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    Text(
                                      _isParcelCollected ? widget.ride.dropoffLocation : widget.ride.pickupLocation,
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
                          if (widget.ride.packageDescription != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              widget.ride.packageDescription!,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                // Confirm Parcel Collected button (shown when arrived at pickup)
                if (!_isParcelCollected && _hasArrivedAtPickup)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _isCollecting ? null : _confirmParcelCollected,
                        icon: _isCollecting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.check_circle, size: 24),
                        label: Text(
                          _isCollecting ? 'Confirming...' : 'Confirm Parcel Collected',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ),
                // Confirm Parcel Delivered button (shown when arrived at dropoff)
                if (_isParcelCollected && _hasArrivedAtDropoff)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _isDelivering ? null : _confirmParcelDelivered,
                        icon: _isDelivering
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.done_all, size: 24),
                        label: Text(
                          _isDelivering ? 'Confirming...' : 'Confirm Parcel Delivered',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  String _getDistanceText() {
    // If we have route info with traffic, use that
    if (_currentRouteInfo != null) {
      final distance = _currentRouteInfo!.distanceKm;
      final eta = _currentRouteInfo!.durationInTrafficMinutes ?? _currentRouteInfo!.durationMinutes;
      
      if (distance < 1) {
        return '${(distance * 1000).toStringAsFixed(0)} m • $eta min';
      } else {
        return '${distance.toStringAsFixed(1)} km • $eta min';
      }
    }
    
    // Fallback to straight-line distance
    if (_isParcelCollected) {
      if (_driverLat == null || _driverLng == null || _dropoffLat == null || _dropoffLng == null) {
        return 'Calculating...';
      }

      final distance = Geolocator.distanceBetween(
        _driverLat!,
        _driverLng!,
        _dropoffLat!,
        _dropoffLng!,
      );

      if (distance < 1000) {
        return '${distance.toStringAsFixed(0)} m';
      } else {
        return '${(distance / 1000).toStringAsFixed(1)} km';
      }
    } else {
      if (_driverLat == null || _driverLng == null || _pickupLat == null || _pickupLng == null) {
        return 'Calculating...';
      }

      final distance = Geolocator.distanceBetween(
        _driverLat!,
        _driverLng!,
        _pickupLat!,
        _pickupLng!,
      );

      if (distance < 1000) {
        return '${distance.toStringAsFixed(0)} m';
      } else {
        return '${(distance / 1000).toStringAsFixed(1)} km';
      }
    }
  }

  // Update route with current traffic information
  Future<void> _updateRouteWithTraffic() async {
    if (!_isParcelCollected) {
      if (_driverLat != null && _driverLng != null && _pickupLat != null && _pickupLng != null) {
        await _refreshRoute(_driverLat!, _driverLng!, _pickupLat!, _pickupLng!);
      }
    } else {
      if (_driverLat != null && _driverLng != null && _dropoffLat != null && _dropoffLng != null) {
        await _refreshRoute(_driverLat!, _driverLng!, _dropoffLat!, _dropoffLng!);
      }
    }
  }

  // Refresh route with latest traffic data
  Future<void> _refreshRoute(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) async {
    try {
      final routingService = RoutingService();
      final route = await routingService.getOptimizedRoute(
        originLat: originLat,
        originLng: originLng,
        destLat: destLat,
        destLng: destLng,
        optimization: RouteOptimization.fastest,
      );

      if (route != null && mounted) {
        setState(() {
          _currentRouteInfo = route;
        });
      }
    } catch (e) {
      // Silently fail - keep existing route
    }
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }
}
