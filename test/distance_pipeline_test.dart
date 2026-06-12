import 'dart:math' as math;

import 'package:distance_tracker/utils/distance_pipeline.dart';
import 'package:distance_tracker/utils/filter_profiles.dart';
import 'package:distance_tracker/utils/movement_filter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/positions.dart';

const _degPerMeter = 1 / 111195.08;

void main() {
  group('DistancePipeline', () {
    test('reduces jitter overestimation versus the bare movement filter', () {
      final rng = math.Random(99);
      // 20 min walk east at 1.4 m/s with autocorrelated σ=3.5 m noise —
      // the scenario where raw point-to-point summation overestimates.
      const trueSpeed = 1.4;
      const seconds = 1200;
      final fixes = List.generate(seconds + 1, (t) {
        final noise = _gaussMarkov(rng, t);
        return testPosition(
          longitude: (trueSpeed * t + noise.$1) * _degPerMeter,
          latitude: noise.$2 * _degPerMeter,
          speed: trueSpeed,
          speedAccuracy: 0.5,
          accuracy: 6,
          second: t,
        );
      });
      const truth = trueSpeed * seconds;

      final legacy = MovementFilter();
      var legacyMeters = 0.0;
      for (final fix in fixes) {
        legacyMeters += legacy.process(fix).deltaMeters;
      }
      legacyMeters += legacy.flush();

      final pipeline = DistancePipeline();
      var pipelineMeters = 0.0;
      for (final fix in fixes) {
        pipelineMeters += pipeline.process(fix).deltaMeters;
      }
      pipelineMeters += pipeline.flush();

      final legacyError = (legacyMeters - truth).abs() / truth;
      final pipelineError = (pipelineMeters - truth).abs() / truth;
      // ignore: avoid_print
      print(
        '[pipeline] truth ${truth.toStringAsFixed(0)}m, '
        'legacy ${legacyMeters.toStringAsFixed(0)}m '
        '(${(legacyError * 100).toStringAsFixed(1)}%), '
        'pipeline ${pipelineMeters.toStringAsFixed(0)}m '
        '(${(pipelineError * 100).toStringAsFixed(1)}%)',
      );

      expect(pipelineError, lessThan(legacyError));
      // With the mixed-use default profile (σₐ=1.5) the pipeline roughly
      // halves the legacy error; the walking profile (σₐ=0.8, Phase 3)
      // must bring this under 5%.
      expect(pipelineError, lessThan(0.10));
    });

    test('credits no distance for stationary jitter', () {
      final rng = math.Random(123);
      final pipeline = DistancePipeline();

      var totalMeters = 0.0;
      for (var t = 0; t <= 600; t++) {
        final noise = _gaussMarkov(rng, t);
        totalMeters += pipeline
            .process(
              testPosition(
                longitude: noise.$1 * _degPerMeter,
                latitude: noise.$2 * _degPerMeter,
                speed: 0,
                accuracy: 10,
                second: t,
              ),
            )
            .deltaMeters;
      }
      totalMeters += pipeline.flush();

      expect(totalMeters, 0);
    });

    test('rejects garbage-accuracy fixes before they touch any state', () {
      final pipeline = DistancePipeline();
      pipeline.process(testPosition(longitude: 0, speed: 0, second: 0));

      final garbage = pipeline.process(
        testPosition(
          longitude: 0.001,
          speed: 5,
          accuracy: 120,
          second: 1,
        ),
      );

      expect(garbage.accepted, isFalse);
      expect(garbage.deltaMeters, 0);
    });

    test('duplicate timestamps are dropped at the pipeline mouth', () {
      final pipeline = DistancePipeline();
      pipeline.process(testPosition(longitude: 0, speed: 0, second: 0));

      final duplicate = pipeline.process(
        testPosition(longitude: 0.0003, speed: 5, second: 0),
      );

      expect(duplicate.accepted, isFalse);
      expect(duplicate.deltaMeters, 0);
    });

    test('vehicle travel still counts in full through the pipeline', () {
      final pipeline = DistancePipeline();
      pipeline.process(testPosition(longitude: 0, speed: 0, second: 0));

      var totalMeters = 0.0;
      for (var i = 1; i <= 60; i++) {
        totalMeters += pipeline
            .process(
              testPosition(
                longitude: i * 15.0 * _degPerMeter,
                speed: 15,
                speedAccuracy: 1,
                accuracy: 10,
                second: i,
              ),
            )
            .deltaMeters;
      }
      totalMeters += pipeline.flush();

      // 900 m driven; the Kalman needs a few fixes to spin up its velocity
      // estimate, so allow a small convergence deficit but no overshoot.
      expect(totalMeters, greaterThan(870));
      expect(totalMeters, lessThanOrEqualTo(905));
    });

    test('a profile switch mid-session keeps movement state and distance', () {
      final pipeline = DistancePipeline();
      pipeline.process(testPosition(longitude: 0, speed: 0, second: 0));

      // Walking on the default profile…
      var totalMeters = 0.0;
      for (var i = 1; i <= 10; i++) {
        totalMeters += pipeline
            .process(
              testPosition(
                longitude: i * 1.4 * _degPerMeter,
                speed: 1.4,
                speedAccuracy: 0.5,
                second: i,
              ),
            )
            .deltaMeters;
      }
      expect(pipeline.isMoving, isTrue);

      // …activity recognition flips to vehicle and the user accelerates.
      pipeline.updateProfile(FilterProfile.vehicle);
      expect(pipeline.isMoving, isTrue,
          reason: 'profile swap must not reset movement state');

      final base = 10 * 1.4;
      for (var i = 11; i <= 40; i++) {
        totalMeters += pipeline
            .process(
              testPosition(
                longitude: (base + (i - 10) * 12.0) * _degPerMeter,
                speed: 12,
                speedAccuracy: 1,
                accuracy: 10,
                second: i,
              ),
            )
            .deltaMeters;
      }
      totalMeters += pipeline.flush();

      // 14 m walked + 360 m driven, minus Kalman spin-up at the transition.
      expect(totalMeters, greaterThan(350));
      expect(totalMeters, lessThanOrEqualTo(376));
    });
  });
}

// Stateful Gauss-Markov noise (ρ=0.95) shared across the test file.
double _gmE = 0;
double _gmN = 0;
(double, double) _gaussMarkov(math.Random rng, int t) {
  if (t == 0) {
    _gmE = 0;
    _gmN = 0;
  }
  const rho = 0.95;
  const sigma = 3.5;
  final k = math.sqrt(1 - rho * rho) * sigma;
  _gmE = rho * _gmE + k * _gauss(rng);
  _gmN = rho * _gmN + k * _gauss(rng);
  return (_gmE, _gmN);
}

double _gauss(math.Random rng) {
  final u1 = rng.nextDouble().clamp(1e-12, 1.0);
  final u2 = rng.nextDouble();
  return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
}
