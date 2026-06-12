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

/// Initial bearing in degrees (0–360, clockwise from north) of the great
/// circle from point 1 to point 2.
double bearingBetween(double lat1, double lon1, double lat2, double lon2) {
  final double dLon = _toRad(lon2 - lon1);
  final double y = math.sin(dLon) * math.cos(_toRad(lat2));
  final double x =
      math.cos(_toRad(lat1)) * math.sin(_toRad(lat2)) -
      math.sin(_toRad(lat1)) * math.cos(_toRad(lat2)) * math.cos(dLon);
  final double degrees = math.atan2(y, x) * 180.0 / math.pi;
  return (degrees + 360.0) % 360.0;
}

/// Smallest absolute angle in degrees (0–180) between two bearings.
double bearingDifference(double a, double b) {
  final double diff = (a - b).abs() % 360.0;
  return diff > 180.0 ? 360.0 - diff : diff;
}

double _toRad(double degrees) => degrees * math.pi / 180.0;
