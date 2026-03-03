import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';

class RoutingService {
  // Google Maps API key with Directions API enabled
  // For production, consider storing this in environment variables or secure storage
  static const String _apiKey = 'AIzaSyAuZTJgvpOr20n0yeK0s1OMQfiSSRWGSWI';
  static const String _directionsApiUrl = 'https://maps.googleapis.com/maps/api/directions/json';

  // Get route between two points using Google Directions API with traffic info
  Future<RouteInfo?> getRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    bool includeTraffic = true,
    bool alternatives = false,
  }) async {
    try {
      // Build API request URL with traffic and alternatives
      String url = '$_directionsApiUrl?origin=$originLat,$originLng&destination=$destLat,$destLng&key=$_apiKey&mode=driving';
      
      if (includeTraffic) {
        url += '&departure_time=now'; // Enable traffic information
      }
      
      if (alternatives) {
        url += '&alternatives=true'; // Get multiple route options
      }

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: AppConstants.connectionTimeoutSeconds),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final leg = route['legs'][0];
          
          // Decode polyline to get route points
          final encodedPolyline = route['overview_polyline']['points'];
          final points = _decodePolyline(encodedPolyline);
          
          // Extract distance
          final distanceMeters = leg['distance']['value'] as int;
          
          // Extract duration (with traffic if available)
          int durationSeconds = leg['duration']['value'] as int;
          int? durationInTrafficSeconds;
          String? trafficStatus;
          
          // Check for duration_in_traffic (includes traffic delays)
          if (leg.containsKey('duration_in_traffic')) {
            durationInTrafficSeconds = leg['duration_in_traffic']['value'] as int;
            
            // Calculate traffic delay
            final trafficDelay = durationInTrafficSeconds - durationSeconds;
            final trafficDelayMinutes = (trafficDelay / 60.0).round();
            
            // Determine traffic status
            if (trafficDelayMinutes <= 2) {
              trafficStatus = 'light';
            } else if (trafficDelayMinutes <= 10) {
              trafficStatus = 'moderate';
            } else {
              trafficStatus = 'heavy';
            }
          } else {
            // No traffic data available
            trafficStatus = 'unknown';
            durationInTrafficSeconds = durationSeconds;
          }
          
          return RouteInfo(
            points: points,
            distanceKm: distanceMeters / 1000.0,
            durationMinutes: (durationSeconds / 60.0).round(),
            durationInTrafficMinutes: durationInTrafficSeconds != null 
                ? (durationInTrafficSeconds / 60.0).round() 
                : null,
            distanceText: leg['distance']['text'] as String,
            durationText: leg['duration']['text'] as String,
            trafficStatus: trafficStatus,
            trafficDelayMinutes: durationInTrafficSeconds != null 
                ? ((durationInTrafficSeconds - durationSeconds) / 60.0).round() 
                : null,
          );
        }
      }
      
      // If API fails, return null to use fallback
      return null;
    } catch (e) {
      // If API fails, return null to use fallback
      return null;
    }
  }

  // Get multiple route alternatives with optimization
  Future<List<RouteInfo>> getRouteAlternatives({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    RouteOptimization optimization = RouteOptimization.fastest,
  }) async {
    try {
      // Request multiple alternatives
      final routes = await getRoute(
        originLat: originLat,
        originLng: originLng,
        destLat: destLat,
        destLng: destLng,
        includeTraffic: true,
        alternatives: true,
      );

      if (routes != null) {
        // For now, return single route (API returns alternatives in same response)
        // In full implementation, parse all routes from response
        return [routes];
      }
      
      return [];
    } catch (e) {
      return [];
    }
  }

  // Get optimized route based on criteria
  Future<RouteInfo?> getOptimizedRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    RouteOptimization optimization = RouteOptimization.fastest,
  }) async {
    final route = await getRoute(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
      includeTraffic: true,
      alternatives: optimization == RouteOptimization.fastest,
    );

    // Google Directions API already returns optimized routes
    // Fastest route is typically the first one
    return route;
  }

  // Decode Google Maps polyline string to list of LatLng points
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  // Get route distance (for pricing calculations)
  Future<double> getRouteDistance({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    final route = await getRoute(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
    );
    
    // Use route distance if available, otherwise fallback to straight-line
    return route?.distanceKm ?? 
           Geolocator.distanceBetween(originLat, originLng, destLat, destLng) / 1000.0;
  }

  // Get route with fallback to straight line
  Future<RouteInfo> getRouteWithFallback({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    bool includeTraffic = true,
  }) async {
    final route = await getRoute(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
      includeTraffic: includeTraffic,
    );
    
    // If route API fails, return straight line as fallback
    if (route == null) {
      final distanceKm = Geolocator.distanceBetween(
        originLat,
        originLng,
        destLat,
        destLng,
      ) / 1000.0;
      
      return RouteInfo(
        points: [
          LatLng(originLat, originLng),
          LatLng(destLat, destLng),
        ],
        distanceKm: distanceKm,
        durationMinutes: (distanceKm * 2).round(), // Rough estimate: 2 min per km
        distanceText: '${distanceKm.toStringAsFixed(1)} km',
        durationText: '${(distanceKm * 2).round()} min',
        trafficStatus: 'unknown',
      );
    }
    
    return route;
  }
}

enum RouteOptimization {
  fastest,    // Shortest time (default)
  shortest,   // Shortest distance
  avoidTolls, // Avoid tolls
  avoidHighways, // Avoid highways
}

class RouteInfo {
  final List<LatLng> points;
  final double distanceKm;
  final int durationMinutes;
  final int? durationInTrafficMinutes; // Duration with traffic
  final String distanceText;
  final String durationText;
  final String? trafficStatus; // 'light', 'moderate', 'heavy', 'unknown'
  final int? trafficDelayMinutes; // Additional minutes due to traffic

  RouteInfo({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
    this.durationInTrafficMinutes,
    required this.distanceText,
    required this.durationText,
    this.trafficStatus,
    this.trafficDelayMinutes,
  });

  // Get ETA text with traffic information
  String get etaText {
    if (durationInTrafficMinutes != null) {
      return '$durationInTrafficMinutes min (with traffic)';
    }
    return '$durationMinutes min';
  }

  // Get traffic status color
  Color get trafficColor {
    switch (trafficStatus) {
      case 'light':
        return Colors.green;
      case 'moderate':
        return Colors.orange;
      case 'heavy':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Get traffic icon
  IconData get trafficIcon {
    switch (trafficStatus) {
      case 'light':
        return Icons.traffic;
      case 'moderate':
        return Icons.traffic;
      case 'heavy':
        return Icons.traffic;
      default:
        return Icons.help_outline;
    }
  }

  // Check if route has traffic delays
  bool get hasTrafficDelay => trafficDelayMinutes != null && trafficDelayMinutes! > 0;
}
