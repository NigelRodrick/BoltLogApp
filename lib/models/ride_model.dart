class RideModel {
  final String? id;
  final String userId; // Sender/Customer
  final String? driverId; // Transporter (set when they accept the ride)
  final String? acceptedTransporterId; // Transporter in negotiation (set when sender accepts their offer)
  final String pickupLocation;
  final String dropoffLocation;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
      final String status; // 'open', 'pending' (negotiation), 'in_progress', 'parcel_collected', 'completed', 'cancelled'
  final double? price;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? notes;
  // Goods/package details
  final String? packageDescription;
  final double? weight; // in kg (optional)
  final String? dimensions; // e.g., "30x20x15 cm" (optional)
  final String? packageType; // 'small', 'medium', 'large', 'fragile', 'bulk'
  final String? transportType; // 'bike', 'sedan', 'pickup', 'closed_pickup', 'lorry'
  final double? estimatedValue;
  // Price negotiation
  final double? counterOffer; // Latest negotiated amount
  final String? priceStatus; // 'pending', 'accepted', 'rejected'
  final String? lastCounterOfferBy; // 'sender' or 'transporter' - who sent the last counter-offer
  /// Transporter currently in negotiation (who last sent or received a counter). Ensures correct sender/transporter see the right amounts when multiple transporters have offers.
  final String? negotiatingTransporterId;
  final String? senderLastViewedAt; // When sender last viewed the request (ISO8601)
  // Payment method for sender to pay transporter
  final String? senderPaymentMethod; // 'cash' or 'ecocash' - how sender will pay transporter
  // Final agreed amount for this delivery (used for fee calculation)
  final double? finalPrice;
  // inDrive-style cancellation
  final DateTime? cancelledAt;
  final String? cancelledBy; // 'sender' or 'transporter' or 'system'
  final String? cancellationReason;
  /// Last known transporter GPS (written by transporter during active delivery).
  final double? driverLiveLat;
  final double? driverLiveLng;
  final String? driverLocationUpdatedAt;
  /// Why the ride was last set back to [status] `open`: `transporter_declined` | `sender_declined` (for client UX).
  final String? lastReopenReason;
  /// Transporter tapped "parcel collected" (ISO8601).
  final String? pickupMarkedByDriverAt;
  /// Sender acknowledged pickup in-app (ISO8601).
  final String? pickupConfirmedBySenderAt;
  /// Transporter tapped "delivered" — [status] stays `parcel_collected` until sender confirms.
  final String? deliveryMarkedByDriverAt;
  /// Sender confirmed receipt; aligns with [completedAt] when [status] is `completed`.
  final String? deliveryConfirmedBySenderAt;

  RideModel({
    this.id,
    required this.userId,
    this.driverId,
    this.acceptedTransporterId,
    required this.pickupLocation,
    required this.dropoffLocation,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    this.status = 'open',
    this.price,
    required this.createdAt,
    this.completedAt,
    this.notes,
    this.packageDescription,
    this.weight,
    this.dimensions,
    this.packageType,
    this.transportType,
    this.estimatedValue,
    this.counterOffer,
    this.priceStatus,
    this.lastCounterOfferBy,
    this.negotiatingTransporterId,
    this.senderLastViewedAt,
    this.senderPaymentMethod,
    this.finalPrice,
    this.cancelledAt,
    this.cancelledBy,
    this.cancellationReason,
    this.driverLiveLat,
    this.driverLiveLng,
    this.driverLocationUpdatedAt,
    this.lastReopenReason,
    this.pickupMarkedByDriverAt,
    this.pickupConfirmedBySenderAt,
    this.deliveryMarkedByDriverAt,
    this.deliveryConfirmedBySenderAt,
  });

  /// Driver said parcel collected; sender has not confirmed yet.
  bool get awaitingSenderPickupConfirm =>
      (pickupMarkedByDriverAt != null && pickupMarkedByDriverAt!.isNotEmpty) &&
      (pickupConfirmedBySenderAt == null || pickupConfirmedBySenderAt!.isEmpty);

  /// Driver said delivered; sender must confirm before [status] becomes `completed`.
  bool get awaitingSenderDeliveryConfirm =>
      (deliveryMarkedByDriverAt != null && deliveryMarkedByDriverAt!.isNotEmpty) &&
      status != 'completed';

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'userId': userId,
      'pickupLocation': pickupLocation,
      'dropoffLocation': dropoffLocation,
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'dropoffLat': dropoffLat,
      'dropoffLng': dropoffLng,
      'status': status,
      'price': price,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'notes': notes,
      'packageDescription': packageDescription,
      'weight': weight,
      'dimensions': dimensions,
      'packageType': packageType,
      'transportType': transportType,
      'estimatedValue': estimatedValue,
      'counterOffer': counterOffer,
      'priceStatus': priceStatus,
      'senderPaymentMethod': senderPaymentMethod,
      'finalPrice': finalPrice,
    };
    if (driverId != null) map['driverId'] = driverId;
    if (lastCounterOfferBy != null) map['lastCounterOfferBy'] = lastCounterOfferBy;
    if (negotiatingTransporterId != null) map['negotiatingTransporterId'] = negotiatingTransporterId;
    if (senderLastViewedAt != null) map['senderLastViewedAt'] = senderLastViewedAt;
    if (acceptedTransporterId != null) map['acceptedTransporterId'] = acceptedTransporterId;
    if (cancelledAt != null) map['cancelledAt'] = cancelledAt!.toIso8601String();
    if (cancelledBy != null) map['cancelledBy'] = cancelledBy;
    if (cancellationReason != null) map['cancellationReason'] = cancellationReason;
    if (driverLiveLat != null) map['driverLiveLat'] = driverLiveLat;
    if (driverLiveLng != null) map['driverLiveLng'] = driverLiveLng;
    if (driverLocationUpdatedAt != null) {
      map['driverLocationUpdatedAt'] = driverLocationUpdatedAt;
    }
    if (lastReopenReason != null) map['lastReopenReason'] = lastReopenReason;
    if (pickupMarkedByDriverAt != null) {
      map['pickupMarkedByDriverAt'] = pickupMarkedByDriverAt;
    }
    if (pickupConfirmedBySenderAt != null) {
      map['pickupConfirmedBySenderAt'] = pickupConfirmedBySenderAt;
    }
    if (deliveryMarkedByDriverAt != null) {
      map['deliveryMarkedByDriverAt'] = deliveryMarkedByDriverAt;
    }
    if (deliveryConfirmedBySenderAt != null) {
      map['deliveryConfirmedBySenderAt'] = deliveryConfirmedBySenderAt;
    }
    return map;
  }

  /// Matches server fields set by [RideService.respondToCounterOffer] when the sender
  /// accepts the transporter's counter-offer. Use for instant navigation without a
  /// second [getRideById] round-trip.
  RideModel afterSenderAcceptedCounterOffer() {
    final agreed = counterOffer ?? price;
    final tid = negotiatingTransporterId;
    return RideModel(
      id: id,
      userId: userId,
      driverId: driverId,
      acceptedTransporterId: tid,
      pickupLocation: pickupLocation,
      dropoffLocation: dropoffLocation,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
      status: 'pending',
      price: agreed,
      createdAt: createdAt,
      completedAt: completedAt,
      notes: notes,
      packageDescription: packageDescription,
      weight: weight,
      dimensions: dimensions,
      packageType: packageType,
      transportType: transportType,
      estimatedValue: estimatedValue,
      counterOffer: null,
      priceStatus: 'accepted',
      lastCounterOfferBy: lastCounterOfferBy,
      negotiatingTransporterId: tid,
      senderLastViewedAt: senderLastViewedAt,
      senderPaymentMethod: senderPaymentMethod,
      finalPrice: agreed,
      cancelledAt: cancelledAt,
      cancelledBy: cancelledBy,
      cancellationReason: cancellationReason,
      driverLiveLat: driverLiveLat,
      driverLiveLng: driverLiveLng,
      driverLocationUpdatedAt: driverLocationUpdatedAt,
      lastReopenReason: null,
      pickupMarkedByDriverAt: null,
      pickupConfirmedBySenderAt: null,
      deliveryMarkedByDriverAt: null,
      deliveryConfirmedBySenderAt: null,
    );
  }

  factory RideModel.fromMap(Map<String, dynamic> map, String id) {
    return RideModel(
      id: id,
      userId: map['userId'] ?? '',
      driverId: map['driverId'],
      acceptedTransporterId: map['acceptedTransporterId'],
      pickupLocation: map['pickupLocation'] ?? '',
      dropoffLocation: map['dropoffLocation'] ?? '',
      pickupLat: (map['pickupLat'] as num?)?.toDouble(),
      pickupLng: (map['pickupLng'] as num?)?.toDouble(),
      dropoffLat: (map['dropoffLat'] as num?)?.toDouble(),
      dropoffLng: (map['dropoffLng'] as num?)?.toDouble(),
      status: map['status'] ?? 'open',
      price: (map['price'] as num?)?.toDouble(),
      createdAt: DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
      completedAt: map['completedAt'] != null ? DateTime.parse(map['completedAt']) : null,
      notes: map['notes'],
      packageDescription: map['packageDescription'],
      weight: (map['weight'] as num?)?.toDouble(),
      dimensions: map['dimensions'],
      packageType: map['packageType'],
      transportType: map['transportType'],
      estimatedValue: (map['estimatedValue'] as num?)?.toDouble(),
      counterOffer: (map['counterOffer'] as num?)?.toDouble(),
      priceStatus: map['priceStatus'],
      lastCounterOfferBy: map['lastCounterOfferBy'],
      negotiatingTransporterId: map['negotiatingTransporterId'],
      senderLastViewedAt: map['senderLastViewedAt'],
      senderPaymentMethod: map['senderPaymentMethod'],
      finalPrice: (map['finalPrice'] as num?)?.toDouble(),
      cancelledAt: map['cancelledAt'] != null ? DateTime.parse(map['cancelledAt']) : null,
      cancelledBy: map['cancelledBy'],
      cancellationReason: map['cancellationReason'],
      driverLiveLat: (map['driverLiveLat'] as num?)?.toDouble(),
      driverLiveLng: (map['driverLiveLng'] as num?)?.toDouble(),
      driverLocationUpdatedAt: map['driverLocationUpdatedAt'] as String?,
      lastReopenReason: map['lastReopenReason'] as String?,
      pickupMarkedByDriverAt: map['pickupMarkedByDriverAt'] as String?,
      pickupConfirmedBySenderAt: map['pickupConfirmedBySenderAt'] as String?,
      deliveryMarkedByDriverAt: map['deliveryMarkedByDriverAt'] as String?,
      deliveryConfirmedBySenderAt: map['deliveryConfirmedBySenderAt'] as String?,
    );
  }
}

