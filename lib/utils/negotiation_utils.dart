import '../models/ride_model.dart';

/// Returns true when there is an active negotiation on this ride.
/// A negotiation is considered active while:
/// - status is 'pending' (negotiation stage)
/// - priceStatus is 'pending' (no final decision)
/// - a specific transporter is in play (acceptedTransporterId set)
bool negotiationInProgress(RideModel ride) {
  return ride.status == 'pending' &&
      ride.priceStatus == 'pending' &&
      ride.acceptedTransporterId != null;
}

