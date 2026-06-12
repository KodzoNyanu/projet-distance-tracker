import 'dart:math' as math;

import 'package:distance_tracker/utils/haversine.dart';
import 'package:distance_tracker/utils/kalman_filter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/positions.dart';

// ~1 m of longitude at the equator, in degrees.
const _degPerMeter = 1 / 111195.08;

void main() {
  group('GpsKalmanFilter', () {
    test('converges on a noisy straight line and beats the raw noise', () {
      final rng = math.Random(7);
      // Walking-grade process noise: constant velocity fits the model, so
      // the filter can smooth hard.
      final kalman = GpsKalmanFilter(sigmaA: 0.8);

      // 120 s drive east at 15 m/s with σ=5 m white noise.
      var rawErrorSum = 0.0;
      var smoothedErrorSum = 0.0;
      var samples = 0;
      for (var t = 0; t <= 120; t++) {
        final truthMeters = 15.0 * t;
        final noise = _gauss(rng) * 5.0;
        final estimate = kalman.process(
          testPosition(
            longitude: (truthMeters + noise) * _degPerMeter,
            speed: 15,
            speedAccuracy: 1,
            accuracy: 5,
            second: t,
          ),
        );
        if (t >= 20) {
          // Judge only after convergence.
          final smoothedMeters =
              estimate.smoothed.longitude / _degPerMeter;
          rawErrorSum += noise.abs();
          smoothedErrorSum += (smoothedMeters - truthMeters).abs();
          samples++;
        }
      }

      final rawMae = rawErrorSum / samples;
      final smoothedMae = smoothedErrorSum / samples;
      // Measured ratio 0.60 with walking-grade σₐ.
      expect(smoothedMae, lessThan(rawMae * 0.65),
          reason: 'smoothing must substantially cut the position error '
              '(raw MAE ${rawMae.toStringAsFixed(2)}m, '
              'smoothed MAE ${smoothedMae.toStringAsFixed(2)}m)');
    });

    test('shrinks the phantom path length of stationary jitter', () {
      final rng = math.Random(8);
      final kalman = GpsKalmanFilter(sigmaA: 1.5);

      double rawPath = 0.0;
      double smoothedPath = 0.0;
      double? prevRawLon;
      double? prevSmoothLon;
      double? prevSmoothLat;
      for (var t = 0; t <= 300; t++) {
        final noiseLon = _gauss(rng) * 4.0 * _degPerMeter;
        final estimate = kalman.process(
          testPosition(
            longitude: noiseLon,
            speed: 0,
            accuracy: 8,
            second: t,
          ),
        );
        if (prevRawLon != null) {
          rawPath += haversineDistance(0, prevRawLon, 0, noiseLon);
          smoothedPath += haversineDistance(
            prevSmoothLat!,
            prevSmoothLon!,
            estimate.smoothed.latitude,
            estimate.smoothed.longitude,
          );
        }
        prevRawLon = noiseLon;
        prevSmoothLon = estimate.smoothed.longitude;
        prevSmoothLat = estimate.smoothed.latitude;
      }

      // Measured 0.36 with the default mixed-use σₐ=1.5; per-activity
      // profiles (still/walking) will smooth harder.
      expect(smoothedPath, lessThan(rawPath * 0.45),
          reason: 'stationary zigzag must shrink by at least 55% '
              '(raw ${rawPath.toStringAsFixed(0)}m, '
              'smoothed ${smoothedPath.toStringAsFixed(0)}m)');
    });

    test('a single teleport fix is gated out and coasted over', () {
      final kalman = GpsKalmanFilter(sigmaA: 1.5);

      // Steady walk east at 1.4 m/s.
      KalmanEstimate? last;
      for (var t = 0; t <= 30; t++) {
        last = kalman.process(
          testPosition(
            longitude: 1.4 * t * _degPerMeter,
            speed: 1.4,
            speedAccuracy: 0.5,
            second: t,
          ),
        );
      }

      // 100 m sideways teleport for one fix.
      final spike = kalman.process(
        testPosition(
          longitude: 1.4 * 31 * _degPerMeter,
          latitude: 100 * _degPerMeter,
          speed: 1.4,
          speedAccuracy: 0.5,
          second: 31,
        ),
      );

      expect(spike.wasOutlier, isTrue);
      // The estimate must stay near the path, not jump to the spike.
      final latOffsetMeters = spike.smoothed.latitude / _degPerMeter;
      expect(latOffsetMeters.abs(), lessThan(10));
      expect(last, isNotNull);
    });

    test('persistent relocation is accepted after three outliers', () {
      final kalman = GpsKalmanFilter(sigmaA: 1.5);
      for (var t = 0; t <= 20; t++) {
        kalman.process(testPosition(longitude: 0, speed: 0, second: t));
      }

      // The position genuinely moved 200 m (e.g. tunnel exit).
      KalmanEstimate? estimate;
      for (var t = 21; t <= 23; t++) {
        estimate = kalman.process(
          testPosition(
            longitude: 200 * _degPerMeter,
            speed: 0,
            second: t,
          ),
        );
      }

      expect(estimate!.wasReset, isTrue);
      final lonMeters = estimate.smoothed.longitude / _degPerMeter;
      expect(lonMeters, closeTo(200, 1));
    });

    test('re-initialises after a long gap', () {
      final kalman = GpsKalmanFilter(sigmaA: 1.5);
      for (var t = 0; t <= 10; t++) {
        kalman.process(testPosition(longitude: 0, speed: 0, second: t));
      }

      final afterGap = kalman.process(
        testPosition(
          longitude: 500 * _degPerMeter,
          speed: 0,
          second: 120,
        ),
      );

      expect(afterGap.wasReset, isTrue);
      final lonMeters = afterGap.smoothed.longitude / _degPerMeter;
      expect(lonMeters, closeTo(500, 1));
    });

    test('passes raw Doppler readings through untouched', () {
      final kalman = GpsKalmanFilter();
      kalman.process(testPosition(longitude: 0, speed: 0, second: 0));
      final estimate = kalman.process(
        testPosition(
          longitude: 1.4 * _degPerMeter,
          speed: 1.37,
          speedAccuracy: 0.42,
          second: 1,
        ),
      );

      expect(estimate.smoothed.speed, 1.37);
      expect(estimate.smoothed.speedAccuracy, 0.42);
    });
  });
}

double _gauss(math.Random rng) {
  final u1 = rng.nextDouble().clamp(1e-12, 1.0);
  final u2 = rng.nextDouble();
  return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
}
