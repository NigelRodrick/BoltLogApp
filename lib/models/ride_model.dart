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
  final double? counterOffer; // Transporter's counter-offer
  final String? priceStatus; // 'pending', 'accepted', 'rejected'
  final String? lastCounterOfferBy; // 'sender' or 'transporter' - who sent the last counter-offer
  final String? senderLastViewedAt; // When sender last viewed the request (ISO8601)
  // Payment method for sender to pay transporter
  final String? senderPaymentMethod; // 'cash' or 'ecocash' - how sender will pay transporter

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
    this.senderLastViewedAt,
    this.senderPaymentMethod,
  });

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
    };
    if (driverId != null) map['driverId'] = driverId;
    if (lastCounterOfferBy != null) map['lastCounterOfferBy'] = lastCounterOfferBy;
    if (senderLastViewedAt != null) map['senderLastViewedAt'] = senderLastViewedAt;
    if (acceptedTransporterId != null) map['acceptedTransporterId'] = acceptedTransporterId;
    return map;
  }

  factory RideModel.fromMap(Map<String, dynamic> map, String id) {
    return RideModel(
      id: id,
      userId: map['userId'] ?? '',
      driverId: map['driverId'],
      acceptedTransporterId: map['acceptedTransporterId'],
      pickupLocation: map['pickupLocation'] ?? '',
      dropoffLocation: map['dropoffLocation'] ?? '',
      pickupLat: map['pickupLat']?.toDouble(),
      pickupLng: map['pickupLng']?.toDouble(),
      dropoffLat: map['dropoffLat']?.toDouble(),
      dropoffLng: map['dropoffLng']?.toDouble(),
      status: map['status'] ?? 'open',
      price: map['price']?.toDouble(),
      createdAt: DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
      completedAt: map['completedAt'] != null ? DateTime.parse(map['completedAt']) : null,
      notes: map['notes'],
      packageDescription: map['packageDescription'],
      weight: map['weight']?.toDouble(),
      dimensions: map['dimensions'],
      packageType: map['packageType'],
      transportType: map['transportType'],
      estimatedValue: map['estimatedValue']?.toDouble(),
      counterOffer: map['counterOffer']?.toDouble(),
      priceStatus: map['priceStatus'],
      lastCounterOfferBy: map['lastCounterOfferBy'],
      senderLastViewedAt: map['senderLastViewedAt'],
      senderPaymentMethod: map['senderPaymentMethod'],
    );
  }
}

