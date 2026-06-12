import 'package:geolocator/geolocator.dart';

/// Builds a geolocator [Position] for filter tests.
///
/// Timestamps are derived from [second] so traces can be expressed as a
/// simple sequence of per-second fixes, matching the app's 1 Hz stream.
Position testPosition({
  required double longitude,
  required double speed,
  double latitude = 0,
  double accuracy = 5,
  double speedAccuracy = 0,
  double heading = 0,
  double headingAccuracy = 0,
  int second = 0,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime(2026, 1, 1).add(Duration(seconds: second)),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: heading,
    headingAccuracy: headingAccuracy,
    speed: speed,
    speedAccuracy: speedAccuracy,
  );
}
