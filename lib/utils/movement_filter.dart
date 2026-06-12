import 'dart:math' as math;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';
import 'filter_profiles.dart';
import 'haversine.dart';

/// Outcome of feeding one GPS fix through [MovementFilter].
class FilterResult {
  /// True when real movement distance is being credited on this fix —
  /// either the fix itself is movement or it confirmed a pending delta.
  final bool accepted;

  /// Metres credited on this fix (0 unless [accepted]). Because accepted
  /// deltas are held pending for one fix (see [MovementFilter]), the delta
  /// credited here usually belongs to the previous accepted fix.
  final double deltaMeters;

  /// Best estimate of the current speed in m/s. 0 when stationary,
  /// `null` when there is no new estimate and the previous value should be
  /// kept (e.g. movement is building up below the distance gate).
  final double? speedMs;

  /// True when the fix arrived after a long gap (signal outage, OS
  /// buffering). Downstream smoothing filters should reset on this.
  final bool gapDetected;

  const FilterResult({
    required this.accepted,
    this.deltaMeters = 0.0,
    this.speedMs,
    this.gapDetected = false,
  });
}

/// An accepted displacement awaiting confirmation by the next fix.
class _PendingDelta {
  final double meters;
  final Position prevAnchor;
  final double bearingDegrees;
  final DateTime timestamp;

  _PendingDelta({
    required this.meters,
    required this.prevAnchor,
    required this.bearingDegrees,
    required this.timestamp,
  });
}

/// Stationary/moving state machine that turns raw GPS fixes into distance.
///
/// Two hostile realities of consumer GPS drive this design:
///
///  1. Coordinates never sit still. Even on a table the reported position
///     wanders metres (jitter/drift), so any filter that judges fixes in
///     isolation eventually counts that drift as movement.
///  2. Doppler speed cannot be trusted on cheap GNSS chips. Under multipath
///     (indoors, near walls) they report 1–2.5 m/s while the phone is
///     perfectly still — always together with a degrading accuracy radius.
///
/// Consequences:
///
///  - Distance only accumulates in the MOVING state, and a displacement only
///    counts as movement evidence when it is larger than what the accuracy
///    radius could fake: the gates scale with `position.accuracy`.
///  - Doppler speed is never sufficient evidence by itself. A reliable
///    near-zero reading vetoes displacement evidence (a coordinate jump
///    while the chip says "not moving" is a position correction, not
///    travel); a high reading merely corroborates, shrinking the start gate.
///  - The anchor only advances when distance is credited, so real movement
///    below a gate keeps accumulating until it crosses it — poor signal
///    makes updates chunkier, never wrong. While stationary the anchor is
///    refreshed periodically so drift can never pile up into a fake
///    displacement.
///  - An accepted displacement is held *pending* for one fix before it is
///    credited. If the next fix lands back at the previous anchor, the
///    displacement was a multipath spike (A→B→A) and is discarded; the cost
///    is one second of display latency. Call [flush] when the session ends
///    to credit a still-pending delta.
///  - A displacement that reverses the bearing of the previous credited
///    delta within a few seconds needs Doppler corroboration — satellite
///    handovers love to bounce positions back along the path.
///  - Fixes with an accuracy radius far worse than the recent norm are
///    rejected even below the hard ceiling, and fixes after a long gap
///    re-anchor without crediting the jump.
class MovementFilter {
  /// Adaptive accuracy rejection: a fix is rejected when its accuracy is
  /// worse than `max(floor, scale × EWMA of recent accepted accuracies)`,
  /// capped by the profile ceiling.
  static const double adaptiveAccuracyFloorMeters = 35.0;
  static const double adaptiveAccuracyScale = 2.5;
  static const double accuracyEwmaAlpha = 0.1;

  /// Fixes separated by more than this re-anchor without crediting distance
  /// (OS-buffered fixes after throttling would otherwise create one giant
  /// fake delta).
  static const int maxGapSeconds = 15;

  /// A pending delta reversing more than this against the previous credited
  /// bearing within [bounceWindowSeconds] needs Doppler corroboration.
  static const double bounceBearingDegrees = 150.0;
  static const int bounceWindowSeconds = 3;

  /// User-configured speed threshold in m/s below which the user is
  /// considered stationary. Default: 0.55 m/s ≈ 2 km/h. The active profile
  /// can raise the effective threshold (vehicle mode), never lower it.
  final double stationaryThresholdMs;

  FilterProfile profile;

  double get _effectiveStationaryThreshold =>
      math.max(stationaryThresholdMs, profile.stationaryThresholdMs);

  bool _isMoving = false;
  Position? _anchor;
  DateTime? _lastFixTimestamp;
  double? _accuracyEwma;
  double? _emaSpeed;
  _PendingDelta? _pending;
  _PendingDelta? _lastCommitted;
  int _movingEvidence = 0;
  int _stationaryEvidence = 0;
  int _stationaryReadings = 0;

  MovementFilter({
    this.stationaryThresholdMs = 0.55,
    this.profile = FilterProfile.defaults,
  });

  /// Whether the filter currently considers the user to be moving.
  bool get isMoving => _isMoving;

  /// Returns `true` if enough consecutive stationary readings have
  /// accumulated to trigger auto-pause.
  bool get shouldAutoPause => _stationaryReadings >= profile.autoPauseAfterCount;

  /// Swaps tuning parameters without resetting movement state, so an
  /// activity-mode change mid-session never drops distance.
  void updateProfile(FilterProfile next) {
    profile = next;
  }

  /// Feeds one GPS fix through the filter.
  FilterResult process(Position position) {
    final lastTs = _lastFixTimestamp;
    if (lastTs != null && !position.timestamp.isAfter(lastTs)) {
      // Duplicate or out-of-order timestamp: no usable kinematics.
      debugPrint('[GPS] REJECT stale timestamp ${position.timestamp}');
      return const FilterResult(accepted: false);
    }

    // Accuracy gate, adapted to how good the signal has recently been: a
    // phone that normally reports 5 m must not feed 40 m outliers into the
    // state machine just because they clear the hard ceiling.
    final ewma = _accuracyEwma;
    final maxAccuracy = ewma == null
        ? profile.accuracyCeilingMeters
        : math.min(
            profile.accuracyCeilingMeters,
            math.max(adaptiveAccuracyFloorMeters, adaptiveAccuracyScale * ewma),
          );
    if (position.accuracy > maxAccuracy) {
      debugPrint(
        '[GPS] REJECT poor accuracy: ${position.accuracy.toStringAsFixed(1)}m '
        '> max ${maxAccuracy.toStringAsFixed(1)}m',
      );
      // No information either way — keep the previous speed estimate.
      return const FilterResult(accepted: false);
    }
    _accuracyEwma = ewma == null
        ? position.accuracy
        : accuracyEwmaAlpha * position.accuracy +
            (1 - accuracyEwmaAlpha) * ewma;

    final anchor = _anchor;
    if (anchor == null) {
      _anchor = position;
      _lastFixTimestamp = position.timestamp;
      debugPrint(
        '[GPS] FIRST FIX — anchor set '
        '(acc=${position.accuracy.toStringAsFixed(1)}m, '
        'speed=${position.speed.toStringAsFixed(2)}m/s)',
      );
      return const FilterResult(accepted: false, speedMs: 0.0);
    }

    if (lastTs != null &&
        position.timestamp.difference(lastTs).inSeconds > maxGapSeconds) {
      // Signal outage or OS buffering: the displacement across the gap is
      // unknowable, so re-anchor without crediting it. Movement that was
      // already gated before the gap still counts.
      final flushed = _commitPending();
      _anchor = position;
      _lastFixTimestamp = position.timestamp;
      _movingEvidence = 0;
      _stationaryEvidence = 0;
      debugPrint(
        '[GPS] GAP ${position.timestamp.difference(lastTs).inSeconds}s — '
        're-anchored without crediting the jump',
      );
      return FilterResult(
        accepted: flushed > 0,
        deltaMeters: flushed,
        gapDetected: true,
      );
    }
    _lastFixTimestamp = position.timestamp;

    // Resolve the delta accepted on the previous fix: discard it if this fix
    // snapped back to the previous anchor (multipath spike), credit it
    // otherwise.
    var committed = 0.0;
    final pending = _pending;
    if (pending != null) {
      _pending = null;
      final toPrevAnchor = haversineDistance(
        pending.prevAnchor.latitude,
        pending.prevAnchor.longitude,
        position.latitude,
        position.longitude,
      );
      final toPendingAnchor = haversineDistance(
        anchor.latitude,
        anchor.longitude,
        position.latitude,
        position.longitude,
      );
      final snapRadius = math.max(
        profile.minDistanceMeters,
        position.accuracy * profile.movingGateScale,
      );
      if (toPrevAnchor <= snapRadius && toPrevAnchor < toPendingAnchor) {
        _anchor = pending.prevAnchor;
        debugPrint(
          '[GPS] SNAP-BACK — discarded phantom '
          '${pending.meters.toStringAsFixed(1)}m round trip',
        );
      } else {
        committed = pending.meters;
        _lastCommitted = pending;
      }
    }

    final current = _anchor!;
    final distance = haversineDistance(
      current.latitude,
      current.longitude,
      position.latitude,
      position.longitude,
    );
    final elapsedSeconds =
        position.timestamp.difference(current.timestamp).inMilliseconds /
        1000.0;
    final calculatedSpeed = elapsedSeconds > 0
        ? distance / elapsedSeconds
        : 0.0;

    // Doppler speed straight from the chip. Reliable-low readings veto
    // displacement evidence; high readings only corroborate (cheap chips
    // report 1–2.5 m/s while stationary under multipath, so a high reading
    // is never proof of movement on its own).
    final reported = position.speed;
    final speedReliable =
        reported >= 0 &&
        (position.speedAccuracy <= 0 || reported >= position.speedAccuracy);
    // Corroboration (shrinking gates, overriding the bounce check) demands
    // more than the veto does: a real confidence estimate must accompany the
    // reading. Multipath wander loves to report 1–2.5 m/s with
    // speedAccuracy 0, and that must never weaken the gates.
    final dopplerMoving =
        speedReliable &&
        position.speedAccuracy > 0 &&
        reported >= _effectiveStationaryThreshold;
    final dopplerStationary =
        speedReliable && reported < _effectiveStationaryThreshold;
    final plausible = calculatedSpeed <= profile.maxPlausibleSpeedMs;

    return _isMoving
        ? _whileMoving(
            position,
            distance,
            calculatedSpeed,
            plausible,
            dopplerStationary,
            dopplerMoving,
            committed,
          )
        : _whileStationary(
            position,
            distance,
            elapsedSeconds,
            calculatedSpeed,
            plausible,
            dopplerMoving,
            dopplerStationary,
            committed,
          );
  }

  FilterResult _whileMoving(
    Position position,
    double distance,
    double calculatedSpeed,
    bool plausible,
    bool dopplerStationary,
    bool dopplerMoving,
    double committed,
  ) {
    final gate = math.max(
      profile.minDistanceMeters,
      position.accuracy * profile.movingGateScale,
    );
    final motion =
        plausible &&
        !dopplerStationary &&
        calculatedSpeed >= _effectiveStationaryThreshold;

    if (motion && distance >= gate) {
      final bearing = bearingBetween(
        _anchor!.latitude,
        _anchor!.longitude,
        position.latitude,
        position.longitude,
      );
      if (!dopplerMoving && _isSuspectedBounce(position, distance, bearing)) {
        // Sharp reversal right after a credited delta with no Doppler
        // support: most likely the position bouncing back along the path.
        debugPrint(
          '[GPS] BOUNCE SUSPECT — ${distance.toStringAsFixed(1)}m reversal '
          'held back for lack of Doppler corroboration',
        );
        return FilterResult(accepted: committed > 0, deltaMeters: committed);
      }
      _stationaryEvidence = 0;
      _stationaryReadings = 0;
      _pending = _PendingDelta(
        meters: distance,
        prevAnchor: _anchor!,
        bearingDegrees: bearing,
        timestamp: position.timestamp,
      );
      _anchor = position;
      _updateSpeedEma(calculatedSpeed);
      debugPrint(
        '[GPS] ACCEPT dist=${distance.toStringAsFixed(1)}m (pending) '
        'commit=${committed.toStringAsFixed(1)}m '
        'speed=${calculatedSpeed.toStringAsFixed(2)}m/s '
        'acc=${position.accuracy.toStringAsFixed(1)}m',
      );
      return FilterResult(
        accepted: true,
        deltaMeters: committed,
        speedMs: _emaSpeed,
      );
    }

    if (motion) {
      // Looks like movement but the displacement hasn't outgrown the
      // accuracy gate yet — keep the anchor so it can keep accumulating.
      debugPrint(
        '[GPS] BUILDING dist=${distance.toStringAsFixed(1)}m < '
        'gate ${gate.toStringAsFixed(1)}m '
        '(acc=${position.accuracy.toStringAsFixed(1)}m)',
      );
      return FilterResult(accepted: committed > 0, deltaMeters: committed);
    }

    // No movement evidence on this fix.
    _stationaryEvidence++;
    _stationaryReadings++;
    if (_stationaryEvidence >= profile.exitMovingEvidence) {
      _isMoving = false;
      _movingEvidence = 0;
      _emaSpeed = null;
      debugPrint('[GPS] STOPPED — entering stationary state');
    } else {
      debugPrint(
        '[GPS] STOP CANDIDATE $_stationaryEvidence/'
        '${profile.exitMovingEvidence} '
        '(dist=${distance.toStringAsFixed(1)}m, '
        'speed=${position.speed.toStringAsFixed(2)}m/s)',
      );
    }
    return FilterResult(
      accepted: committed > 0,
      deltaMeters: committed,
      speedMs: 0.0,
    );
  }

  FilterResult _whileStationary(
    Position position,
    double distance,
    double elapsedSeconds,
    double calculatedSpeed,
    bool plausible,
    bool dopplerMoving,
    bool dopplerStationary,
    double committed,
  ) {
    final scale = dopplerMoving
        ? profile.corroboratedStartGateScale
        : profile.startGateScale;
    final gate = math.max(profile.minDistanceMeters, position.accuracy * scale);
    final evidence =
        plausible &&
        !dopplerStationary &&
        distance >= gate &&
        calculatedSpeed >= _effectiveStationaryThreshold;

    if (evidence) {
      _movingEvidence++;
      _stationaryReadings = 0;
      if (_movingEvidence >= profile.enterMovingEvidence) {
        _isMoving = true;
        _movingEvidence = 0;
        _stationaryEvidence = 0;
        _pending = _PendingDelta(
          meters: distance,
          prevAnchor: _anchor!,
          bearingDegrees: bearingBetween(
            _anchor!.latitude,
            _anchor!.longitude,
            position.latitude,
            position.longitude,
          ),
          timestamp: position.timestamp,
        );
        _anchor = position;
        _updateSpeedEma(calculatedSpeed);
        debugPrint(
          '[GPS] ACCEPT (movement started) '
          'dist=${distance.toStringAsFixed(1)}m (pending) '
          'speed=${calculatedSpeed.toStringAsFixed(2)}m/s',
        );
        return FilterResult(
          accepted: true,
          deltaMeters: committed,
          speedMs: _emaSpeed,
        );
      }
      debugPrint(
        '[GPS] MOVEMENT CANDIDATE $_movingEvidence/'
        '${profile.enterMovingEvidence} '
        '(dist=${distance.toStringAsFixed(1)}m > '
        'gate ${gate.toStringAsFixed(1)}m, '
        'speed=${position.speed.toStringAsFixed(2)}m/s)',
      );
      return FilterResult(
        accepted: committed > 0,
        deltaMeters: committed,
        speedMs: 0.0,
      );
    }

    // Still stationary.
    _movingEvidence = 0;
    _stationaryReadings++;
    if (elapsedSeconds >= profile.anchorRefreshSeconds &&
        calculatedSpeed < _effectiveStationaryThreshold) {
      // Only flush when the displacement is too slow to be travel —
      // a slow walk building toward the gate must keep its anchor.
      _anchor = position;
      debugPrint(
        '[GPS] STATIONARY — anchor refreshed, '
        '${distance.toStringAsFixed(1)}m of drift flushed',
      );
    } else {
      debugPrint(
        '[GPS] STATIONARY dist=${distance.toStringAsFixed(1)}m '
        'speed=${position.speed.toStringAsFixed(2)}m/s '
        'acc=${position.accuracy.toStringAsFixed(1)}m',
      );
    }
    return FilterResult(
      accepted: committed > 0,
      deltaMeters: committed,
      speedMs: 0.0,
    );
  }

  bool _isSuspectedBounce(
    Position position,
    double distance,
    double bearing,
  ) {
    // A genuine U-turn is unaffected by a hold: the anchor stays put, so the
    // displacement keeps accumulating and commits as soon as Doppler
    // corroborates or the bounce window expires — only seconds of latency.
    final last = _lastCommitted;
    if (last == null) return false;
    if (position.timestamp.difference(last.timestamp).inSeconds >
        bounceWindowSeconds) {
      return false;
    }
    return bearingDifference(bearing, last.bearingDegrees) >
        bounceBearingDegrees;
  }

  void _updateSpeedEma(double speed) {
    final previous = _emaSpeed;
    _emaSpeed = previous == null
        ? speed
        : profile.speedEmaAlpha * speed +
            (1 - profile.speedEmaAlpha) * previous;
  }

  double _commitPending() {
    final pending = _pending;
    _pending = null;
    if (pending == null) return 0.0;
    _lastCommitted = pending;
    return pending.meters;
  }

  /// Credits a still-pending delta. Call when the session ends so the last
  /// second of movement isn't lost to the deferred-commit window.
  double flush() => _commitPending();

  /// Reset all state (e.g. when a session stops). Discards any pending
  /// delta — call [flush] first to credit it.
  void reset() {
    _isMoving = false;
    _anchor = null;
    _lastFixTimestamp = null;
    _accuracyEwma = null;
    _emaSpeed = null;
    _pending = null;
    _lastCommitted = null;
    _movingEvidence = 0;
    _stationaryEvidence = 0;
    _stationaryReadings = 0;
  }
}
