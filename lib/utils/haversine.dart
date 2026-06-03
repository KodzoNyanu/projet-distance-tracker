import 'dart:math' as math;

/// Calculates the distance between two GPS coordinates using the
/// Haversine formula. Returns distance in metres.
double haversineDistance(double lat1, double lon1, double lat2, double lon2) {
  const double earthRadiusMeters = 6371008.8;

  final double dLat = _toRad(lat2 - lat1);
  final double dLon = _toRad(lon2 - lon1);

  final double a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);

  final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusMeters * c;
}

double _toRad(double degrees) => degrees * math.pi / 180.0;
