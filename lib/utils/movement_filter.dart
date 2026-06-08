import 'package:geolocator/geolocator.dart';
import 'haversine.dart';

/// Guards against bad GPS readings and detects whether the user is moving.
class MovementFilter {
  /// Maximum acceptable accuracy radius in metres.
  /// Points with worse accuracy are discarded.
  static const double maxAccuracyMeters = 50.0;

  /// Speed threshold in m/s below which the user is considered stationary.
  /// Default: 0.55 m/s ≈ 2 km/h
  final double stationaryThresholdMs;

  /// Absolute minimum distance between consecutive accepted points.
  /// The effective minimum is max(minDistanceMeters, accuracy * accuracyScale)
  /// so that noisier fixes require proportionally larger movement before
  /// contributing to the total, preventing GPS jitter inflation.
  static const double minDistanceMeters = 2.0;
  static const double accuracyScale = 0.5;

  /// Minimum elapsed time before low reported speed can be overridden by
  /// coordinate movement. This rejects one-off GPS jumps while stationary.
  static const int minCalculatedSpeedSeconds = 1;

  /// Number of consecutive stationary readings before auto-pause is triggered.
  static const int autoPauseAfterCount = 6;

  int _consecutiveStationaryReadings = 0;

  MovementFilter({this.stationaryThresholdMs = 0.55});

  /// Returns `true` if [position] should be accepted as a real movement point.
  ///
  /// Rejects if:
  ///  - accuracy is worse than [maxAccuracyMeters]
  ///  - both GPS speed and distance indicate the user is stationary
  ///  - distance from [lastPosition] has not yet reached [minDistanceMeters]
  bool isValidMovement(Position position, Position? lastPosition) {
    if (position.accuracy > maxAccuracyMeters) {
      return false;
    }

    if (lastPosition == null) {
      _consecutiveStationaryReadings = 0;
      return true;
    }

    final distance = haversineDistance(
      lastPosition.latitude,
      lastPosition.longitude,
      position.latitude,
      position.longitude,
    );

    final effectiveMin = position.accuracy * accuracyScale > minDistanceMeters
        ? position.accuracy * accuracyScale
        : minDistanceMeters;

    if (distance < effectiveMin) {
      if (position.speed >= 0 && position.speed < stationaryThresholdMs) {
        _consecutiveStationaryReadings++;
      }
      return false;
    }

    // GPS speed < 0 means the platform didn't report speed; don't block on it.
    final speedUnavailable = position.speed < 0;
    final hasMovingSpeed = position.speed >= stationaryThresholdMs;
    final calculatedSpeed = speedBetween(position, lastPosition, distance);

    if (hasMovingSpeed || speedUnavailable) {
      _consecutiveStationaryReadings = 0;
      return true;
    }

    // GPS speed is low — fall back to coordinate-derived speed.
    if (calculatedSpeed >= stationaryThresholdMs) {
      _consecutiveStationaryReadings = 0;
      return true;
    }

    // Both GPS speed and coordinate movement indicate stationary.
    _consecutiveStationaryReadings++;
    return false;
  }

  /// Calculates speed from two GPS points. Returns 0 when timestamps are too
  /// close together to distinguish real movement from GPS jitter.
  double speedBetween(
    Position position,
    Position? lastPosition,
    double distance,
  ) {
    if (lastPosition == null) return 0;

    final elapsedSeconds =
        position.timestamp.difference(lastPosition.timestamp).inMilliseconds /
        1000;
    if (elapsedSeconds < minCalculatedSpeedSeconds) return 0;

    return distance / elapsedSeconds;
  }

  /// Returns `true` if enough consecutive bad readings have accumulated
  /// to trigger auto-pause.
  bool get shouldAutoPause =>
      _consecutiveStationaryReadings >= autoPauseAfterCount;

  /// Reset the counter (e.g. when user resumes or stops).
  void reset() {
    _consecutiveStationaryReadings = 0;
  }
}
