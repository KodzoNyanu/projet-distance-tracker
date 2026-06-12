import 'package:geolocator/geolocator.dart';
import 'filter_profiles.dart';
import 'kalman_filter.dart';
import 'movement_filter.dart';

/// Outcome of feeding one raw GPS fix through [DistancePipeline].
class PipelineResult {
  /// True when real movement distance is being credited on this fix.
  final bool accepted;

  /// Metres credited on this fix (see [MovementFilter] for the
  /// deferred-commit semantics).
  final double deltaMeters;

  /// Best estimate of the current speed in m/s; `null` when the previous
  /// value should be kept.
  final double? speedMs;

  /// True when the fix arrived after a signal gap.
  final bool gapDetected;

  /// The Kalman-smoothed fix the movement filter judged. Store this in the
  /// session track instead of the raw fix — it is the better path estimate.
  final Position smoothed;

  const PipelineResult({
    required this.accepted,
    required this.smoothed,
    this.deltaMeters = 0.0,
    this.speedMs,
    this.gapDetected = false,
  });
}

/// The full distance pipeline: sanitise → Kalman-smooth → movement-gate.
///
/// The Kalman layer runs first because it must see every plausible fix to
/// keep its velocity state current, and because shrinking jitter at the
/// source is what stops point-to-point summation from over-counting. The
/// movement filter then answers the semantic question — "is this travel?" —
/// on conditioned input, using the raw Doppler readings the smoothed fix
/// carries through.
class DistancePipeline {
  /// Above this raw accuracy the smoothed coordinates are not trusted for
  /// movement judgement: under multipath the Kalman turns chaotic jitter
  /// into clean-looking slow drift that fools the gates, while the raw
  /// chaos is exactly what the conservative gate machinery handles well.
  static const double smoothingTrustAccuracyMeters = 20.0;

  final MovementFilter _filter;
  final GpsKalmanFilter _kalman;
  FilterProfile _profile;
  DateTime? _lastRawTimestamp;

  DistancePipeline({
    double stationaryThresholdMs = 0.55,
    FilterProfile profile = FilterProfile.defaults,
  })  : _profile = profile,
        _filter = MovementFilter(
          stationaryThresholdMs: stationaryThresholdMs,
          profile: profile,
        ),
        _kalman = GpsKalmanFilter(sigmaA: profile.processNoiseSigmaA);

  double get stationaryThresholdMs => _filter.stationaryThresholdMs;
  FilterProfile get profile => _profile;
  bool get isMoving => _filter.isMoving;
  bool get shouldAutoPause => _filter.shouldAutoPause;

  /// Swaps tuning parameters without resetting filter state.
  void updateProfile(FilterProfile next) {
    _profile = next;
    _filter.updateProfile(next);
    _kalman.sigmaA = next.processNoiseSigmaA;
  }

  /// Feeds one raw GPS fix through the pipeline.
  PipelineResult process(Position raw) {
    final lastTs = _lastRawTimestamp;
    if (lastTs != null && !raw.timestamp.isAfter(lastTs)) {
      // Duplicate or out-of-order fix: no usable kinematics anywhere.
      return PipelineResult(accepted: false, smoothed: raw);
    }

    if (raw.accuracy > _profile.accuracyCeilingMeters) {
      // Garbage fix: not even worth a Kalman update. Deliberately does not
      // advance the raw timestamp — a long run of garbage becomes a gap,
      // which resets the Kalman when good signal returns.
      return PipelineResult(accepted: false, smoothed: raw);
    }
    _lastRawTimestamp = raw.timestamp;

    final estimate = _kalman.process(raw);
    final judged = raw.accuracy > smoothingTrustAccuracyMeters
        ? raw
        : estimate.smoothed;
    final result = _filter.process(judged);
    return PipelineResult(
      accepted: result.accepted,
      deltaMeters: result.deltaMeters,
      speedMs: result.speedMs,
      gapDetected: result.gapDetected || estimate.wasReset,
      smoothed: judged,
    );
  }

  /// Credits a still-pending delta; call when the session ends.
  double flush() => _filter.flush();

  /// Reset all state (session end).
  void reset() {
    _filter.reset();
    _kalman.reset();
    _lastRawTimestamp = null;
  }
}
