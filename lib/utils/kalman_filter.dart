import 'dart:math' as math;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';

/// Outcome of feeding one raw fix through [GpsKalmanFilter].
class KalmanEstimate {
  /// The fix with smoothed latitude/longitude. Accuracy, Doppler speed,
  /// speed accuracy, heading, and timestamp are passed through untouched —
  /// downstream movement gating scales with the raw accuracy radius
  /// (multipath announces itself there) and relies on raw chip Doppler.
  final Position smoothed;

  /// Smoothed ground speed in m/s from the filter's velocity state.
  final double speedMs;

  /// 1σ radial position uncertainty of the estimate in metres.
  final double effectiveAccuracy;

  /// The measurement failed the innovation gate; [smoothed] is a
  /// prediction-only coast.
  final bool wasOutlier;

  /// The filter re-initialised on this fix (first fix, long gap, or
  /// persistent outliers — e.g. tunnel exit).
  final bool wasReset;

  const KalmanEstimate({
    required this.smoothed,
    required this.speedMs,
    required this.effectiveAccuracy,
    this.wasOutlier = false,
    this.wasReset = false,
  });
}

/// Constant-velocity Kalman filter over GPS fixes.
///
/// Raw point-to-point summation systematically overestimates distance:
/// unbiased position noise adds phantom zigzag to every segment. Smoothing
/// the trajectory first removes that bias at the source.
///
/// Design:
///  - 2-D local tangent plane (equirectangular) anchored at the first fix;
///    sub-centimetre projection error at session scales.
///  - Two independent 2-state filters `[position, velocity]` for the east
///    and north axes — equivalent to the block-diagonal 4-state filter under
///    isotropic noise and much simpler.
///  - Process noise from the white-noise-acceleration model, with σₐ
///    supplied by the active profile (walking brakes gently, vehicles hard).
///  - Measurement noise from the reported accuracy, floored because phones
///    love to claim optimistic radii.
///  - Innovation gating: a measurement whose Mahalanobis distance exceeds
///    the χ²(2 dof, 99%) bound is ignored (prediction-only coast). After
///    [maxConsecutiveOutliers] rejections the filter hard-resets to the
///    measurement — that is a real relocation, not noise.
class GpsKalmanFilter {
  static const double chiSquareGate = 9.21; // χ²(2 dof, 99%)
  static const int maxConsecutiveOutliers = 3;
  static const double minMeasurementSigma = 3.0;
  static const int maxGapSeconds = 15;
  static const double _earthRadius = 6371008.8;

  /// Expected acceleration noise in m/s²; see FilterProfile.processNoiseSigmaA.
  double sigmaA;

  double? _lat0;
  double? _lon0;
  double _cosLat0 = 1.0;
  _AxisFilter? _east;
  _AxisFilter? _north;
  DateTime? _lastTimestamp;
  int _consecutiveOutliers = 0;

  GpsKalmanFilter({this.sigmaA = 1.5});

  /// Feeds one raw fix; returns the smoothed estimate.
  KalmanEstimate process(Position position) {
    final east = _east;
    final north = _north;
    final lastTs = _lastTimestamp;

    if (east == null || north == null || lastTs == null) {
      return _initialize(position, wasReset: false);
    }

    final dt =
        position.timestamp.difference(lastTs).inMilliseconds / 1000.0;
    if (dt <= 0) {
      // Stale fix — keep the current estimate.
      return _estimate(position);
    }
    if (dt > maxGapSeconds) {
      debugPrint('[KALMAN] ${dt.toStringAsFixed(0)}s gap — re-initialising');
      return _initialize(position, wasReset: true);
    }

    final sigma = math.max(position.accuracy, minMeasurementSigma);
    final rVar = sigma * sigma;
    final (e, n) = _project(position.latitude, position.longitude);

    east.predict(dt, sigmaA);
    north.predict(dt, sigmaA);
    _lastTimestamp = position.timestamp;

    // Innovation gate: Mahalanobis distance of the measurement against the
    // predicted state. With independent axes, S is diagonal.
    final yE = e - east.p;
    final yN = n - north.p;
    final sE = east.p00 + rVar;
    final sN = north.p00 + rVar;
    final mahalanobis = (yE * yE) / sE + (yN * yN) / sN;

    if (mahalanobis > chiSquareGate) {
      _consecutiveOutliers++;
      if (_consecutiveOutliers >= maxConsecutiveOutliers) {
        debugPrint(
          '[KALMAN] $_consecutiveOutliers consecutive outliers — '
          'accepting relocation',
        );
        return _initialize(position, wasReset: true);
      }
      debugPrint(
        '[KALMAN] OUTLIER d²=${mahalanobis.toStringAsFixed(1)} — coasting',
      );
      return _estimate(position, wasOutlier: true);
    }

    _consecutiveOutliers = 0;
    east.update(yE, rVar);
    north.update(yN, rVar);
    return _estimate(position);
  }

  /// Clear all state (session end).
  void reset() {
    _lat0 = null;
    _lon0 = null;
    _east = null;
    _north = null;
    _lastTimestamp = null;
    _consecutiveOutliers = 0;
  }

  KalmanEstimate _initialize(Position position, {required bool wasReset}) {
    _lat0 = position.latitude;
    _lon0 = position.longitude;
    _cosLat0 = math.cos(position.latitude * math.pi / 180.0);
    final sigma = math.max(position.accuracy, minMeasurementSigma);
    // Velocity is unknown at init: a generous prior lets the first few
    // measurements establish it quickly.
    _east = _AxisFilter(p: 0, v: 0, p00: sigma * sigma, p11: 100.0);
    _north = _AxisFilter(p: 0, v: 0, p00: sigma * sigma, p11: 100.0);
    _lastTimestamp = position.timestamp;
    _consecutiveOutliers = 0;
    return KalmanEstimate(
      smoothed: position,
      speedMs: 0.0,
      effectiveAccuracy: sigma,
      wasReset: wasReset,
    );
  }

  KalmanEstimate _estimate(Position position, {bool wasOutlier = false}) {
    final east = _east!;
    final north = _north!;
    final (lat, lon) = _unproject(east.p, north.p);
    final effective = math.sqrt(east.p00 + north.p00);
    final speed = math.sqrt(east.v * east.v + north.v * north.v);
    return KalmanEstimate(
      smoothed: Position(
        latitude: lat,
        longitude: lon,
        timestamp: position.timestamp,
        accuracy: position.accuracy,
        altitude: position.altitude,
        altitudeAccuracy: position.altitudeAccuracy,
        heading: position.heading,
        headingAccuracy: position.headingAccuracy,
        speed: position.speed,
        speedAccuracy: position.speedAccuracy,
      ),
      speedMs: speed,
      effectiveAccuracy: effective,
      wasOutlier: wasOutlier,
    );
  }

  (double, double) _project(double lat, double lon) {
    final e =
        (lon - _lon0!) * _cosLat0 * _earthRadius * math.pi / 180.0;
    final n = (lat - _lat0!) * _earthRadius * math.pi / 180.0;
    return (e, n);
  }

  (double, double) _unproject(double e, double n) {
    final lat = _lat0! + n / _earthRadius * 180.0 / math.pi;
    final lon = _lon0! + e / (_earthRadius * _cosLat0) * 180.0 / math.pi;
    return (lat, lon);
  }
}

/// One-axis `[position, velocity]` Kalman filter.
class _AxisFilter {
  double p; // position (m)
  double v; // velocity (m/s)
  // Covariance (symmetric 2×2; p01 == p10).
  double p00;
  double p01 = 0;
  double p11;

  _AxisFilter({
    required this.p,
    required this.v,
    required this.p00,
    required this.p11,
  });

  void predict(double dt, double sigmaA) {
    p += v * dt;

    final q = sigmaA * sigmaA;
    final dt2 = dt * dt;
    final dt3 = dt2 * dt;
    final dt4 = dt3 * dt;

    // P = F P Fᵀ + Q with F = [[1, dt], [0, 1]].
    final newP00 = p00 + 2 * dt * p01 + dt2 * p11 + q * dt4 / 4;
    final newP01 = p01 + dt * p11 + q * dt3 / 2;
    final newP11 = p11 + q * dt2;
    p00 = newP00;
    p01 = newP01;
    p11 = newP11;
  }

  /// Measurement update given precomputed innovation `y = z - p`.
  void update(double y, double rVar) {
    final s = p00 + rVar;
    final k0 = p00 / s;
    final k1 = p01 / s;

    p += k0 * y;
    v += k1 * y;

    // P = (I - K H) P with H = [1, 0].
    final newP00 = (1 - k0) * p00;
    final newP01 = (1 - k0) * p01;
    final newP11 = p11 - k1 * p01;
    p00 = newP00;
    p01 = newP01;
    p11 = newP11;
  }
}
