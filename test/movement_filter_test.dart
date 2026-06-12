import 'package:distance_tracker/utils/filter_profiles.dart';
import 'package:distance_tracker/utils/movement_filter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/positions.dart';

void main() {
  group('movement filter', () {
    test('anchors on the first accurate fix without counting distance', () {
      final filter = MovementFilter();

      final result = filter.process(testPosition(longitude: 0, speed: 0));

      expect(result.accepted, isFalse);
      expect(result.deltaMeters, 0);
      expect(filter.isMoving, isFalse);
      expect(filter.shouldAutoPause, isFalse);
    });

    test('phone on a table: jitter never accumulates distance or speed', () {
      final filter = MovementFilter();
      filter.process(testPosition(longitude: 0, speed: 0, second: 0));

      var totalMeters = 0.0;
      // Two minutes of coordinates wobbling ~2.2 m around the true position
      // while the GPS chip reports speed 0.
      for (var i = 1; i <= 120; i++) {
        final jitter = i.isEven ? 0.0 : 0.00002;
        final result = filter.process(
          testPosition(longitude: jitter, speed: 0, accuracy: 10, second: i),
        );
        totalMeters += result.deltaMeters;
        expect(result.accepted, isFalse);
        expect(result.speedMs, 0);
      }

      expect(totalMeters, 0);
      expect(filter.isMoving, isFalse);
    });

    test(
      'multipath wander with fake Doppler speed never accumulates distance',
      () {
        // Regression for the field logs: stationary phone, accuracy degrading
        // from ~13 m to ~45 m while the chip reports speeds ramping up to
        // 2.5 m/s and coordinates wander ~8 m away from the true position.
        final filter = MovementFilter();
        filter.process(testPosition(longitude: 0, speed: 0, second: 0));

        var totalMeters = 0.0;
        for (var i = 1; i <= 20; i++) {
          final result = filter.process(
            testPosition(
              longitude: (i.clamp(0, 12)) * 0.000006, // drifts out to ~8 m
              speed: 0.5 + i * 0.1, // fake Doppler ramping to 2.5 m/s
              accuracy: 13.0 + i * 1.6, // degrading to ~45 m
              second: i,
            ),
          );
          totalMeters += result.deltaMeters;
          expect(result.accepted, isFalse, reason: 'fix $i must be rejected');
        }

        expect(totalMeters, 0);
        expect(filter.isMoving, isFalse);
      },
    );

    test('jitter is rejected even when Doppler speed is unavailable', () {
      final filter = MovementFilter();
      filter.process(testPosition(longitude: 0, speed: -1, second: 0));

      for (var i = 1; i <= 30; i++) {
        final jitter = i.isEven ? 0.0 : 0.00003; // ~3.3 m wobble
        final result = filter.process(
          testPosition(longitude: jitter, speed: -1, accuracy: 10, second: i),
        );
        expect(result.accepted, isFalse);
      }

      expect(filter.isMoving, isFalse);
    });

    test('walking is counted once displacement outgrows the accuracy gate', () {
      final filter = MovementFilter();
      filter.process(testPosition(longitude: 0, speed: 0, second: 0));

      // 10 s of walking at 1.4 m/s with good accuracy and healthy Doppler.
      var totalMeters = 0.0;
      for (var i = 1; i <= 10; i++) {
        final result = filter.process(
          testPosition(
            longitude: i * 0.0000126, // ≈1.4 m per second
            speed: 1.4,
            speedAccuracy: 0.5,
            second: i,
          ),
        );
        totalMeters += result.deltaMeters;
      }

      expect(filter.isMoving, isTrue);
      // 14 m walked; everything except the chunk still building is counted.
      expect(totalMeters, greaterThan(11.5));
      expect(totalMeters, lessThanOrEqualTo(14.1));
    });

    test('vehicle travel is counted in full from a standing start', () {
      final filter = MovementFilter();
      filter.process(testPosition(longitude: 0, speed: 0, second: 0));

      // 6 s of driving at ~15 m/s with mediocre urban accuracy.
      var totalMeters = 0.0;
      for (var i = 1; i <= 6; i++) {
        final result = filter.process(
          testPosition(
            longitude: i * 0.000135, // ≈15 m per second
            speed: 15,
            speedAccuracy: 1,
            accuracy: 20,
            second: i,
          ),
        );
        totalMeters += result.deltaMeters;
      }
      // The last accepted delta sits in the one-fix confirmation window
      // until the session ends.
      totalMeters += filter.flush();

      expect(filter.isMoving, isTrue);
      expect(totalMeters, closeTo(90.0, 1.0));
    });

    test('a single Doppler spike does not start movement', () {
      final filter = MovementFilter();
      filter.process(testPosition(longitude: 0, speed: 0, second: 0));

      final spike = filter.process(
        testPosition(longitude: 0.00005, speed: 5, second: 1),
      );
      final calm = filter.process(
        testPosition(longitude: 0.00005, speed: 0, second: 2),
      );

      expect(spike.accepted, isFalse);
      expect(calm.accepted, isFalse);
      expect(filter.isMoving, isFalse);
    });

    test('a coordinate jump with Doppler at zero is a correction, not travel', () {
      final filter = MovementFilter();
      filter.process(testPosition(longitude: 0, speed: 0, second: 0));
      filter.process(testPosition(longitude: 0, speed: 0, second: 1));

      // GPS relocates ~33 m (e.g. cached fix replaced by a satellite fix)
      // while the chip still reports the user as stationary.
      var totalMeters = 0.0;
      for (var i = 2; i <= 10; i++) {
        final result = filter.process(
          testPosition(longitude: 0.0003, speed: 0, second: i),
        );
        totalMeters += result.deltaMeters;
      }

      expect(totalMeters, 0);
      expect(filter.isMoving, isFalse);
    });

    test('stops after consecutive fixes without movement evidence', () {
      final filter = MovementFilter();
      filter.process(testPosition(longitude: 0, speed: 0, second: 0));
      // Get into the moving state.
      for (var i = 1; i <= 4; i++) {
        filter.process(
          testPosition(
            longitude: i * 0.0000126,
            speed: 1.4,
            speedAccuracy: 0.5,
            second: i,
          ),
        );
      }
      expect(filter.isMoving, isTrue);

      // User stops: coordinates hold still, Doppler drops to 0.
      for (var i = 5;
          i < 5 + FilterProfile.defaults.exitMovingEvidence;
          i++) {
        final result = filter.process(
          testPosition(longitude: 4 * 0.0000126, speed: 0, second: i),
        );
        expect(result.accepted, isFalse);
        expect(result.speedMs, 0);
      }

      expect(filter.isMoving, isFalse);
    });

    test('auto-pauses after repeated stationary readings', () {
      final filter = MovementFilter();
      filter.process(testPosition(longitude: 0, speed: 0, second: 0));

      for (var i = 1; i <= FilterProfile.defaults.autoPauseAfterCount; i++) {
        filter.process(testPosition(longitude: 0, speed: 0, second: i));
      }

      expect(filter.shouldAutoPause, isTrue);
    });
  });

  group('movement filter hardening', () {
    test('snap-back: an A→B→A multipath round trip credits nothing', () {
      final filter = MovementFilter();
      filter.process(testPosition(longitude: 0, speed: 0, second: 0));

      // Walk east to establish the moving state and some real distance.
      var realMeters = 0.0;
      for (var i = 1; i <= 8; i++) {
        realMeters += filter
            .process(
              testPosition(
                longitude: i * 0.0000126,
                speed: 1.4,
                speedAccuracy: 0.5,
                second: i,
              ),
            )
            .deltaMeters;
      }
      expect(filter.isMoving, isTrue);

      // Multipath spike: position teleports ~33 m ahead for one fix with no
      // usable Doppler, then returns exactly where the user was.
      var spikeMeters = 0.0;
      spikeMeters += filter
          .process(
            testPosition(
              longitude: 8 * 0.0000126 + 0.0003,
              speed: -1,
              second: 9,
            ),
          )
          .deltaMeters;
      spikeMeters += filter
          .process(
            testPosition(longitude: 8 * 0.0000126, speed: -1, second: 10),
          )
          .deltaMeters;
      spikeMeters += filter.flush();

      // Whatever was still pending from the real walk may commit here, but
      // the ~66 m phantom round trip must not.
      expect(realMeters + spikeMeters, lessThan(15.0));
    });

    test('bearing reversal without Doppler support is held back', () {
      final filter = MovementFilter();
      filter.process(testPosition(longitude: 0, speed: 0, second: 0));

      // Drive east so deltas commit with an eastward bearing. True path
      // length: 75 m (fix 1 builds toward the start gate, fixes 2–5 credit).
      var totalMeters = 0.0;
      for (var i = 1; i <= 5; i++) {
        totalMeters += filter
            .process(
              testPosition(
                longitude: i * 0.000135,
                speed: 15,
                speedAccuracy: 1,
                accuracy: 10,
                second: i,
              ),
            )
            .deltaMeters;
      }
      expect(filter.isMoving, isTrue);

      // Position bounces ~40 m backwards along the path one second after a
      // committed delta, with no Doppler corroboration. The fix may commit
      // the pending eastward delta, but its own reversal must be held.
      totalMeters += filter
          .process(
            testPosition(
              longitude: 5 * 0.000135 - 0.00036,
              speed: -1,
              accuracy: 10,
              second: 6,
            ),
          )
          .deltaMeters;
      totalMeters += filter.flush();

      expect(totalMeters, closeTo(75.0, 1.0));
    });

    test('duplicate and out-of-order timestamps are dropped', () {
      final filter = MovementFilter();
      filter.process(testPosition(longitude: 0, speed: 0, second: 5));

      final duplicate = filter.process(
        testPosition(longitude: 0.0003, speed: 5, second: 5),
      );
      final outOfOrder = filter.process(
        testPosition(longitude: 0.0003, speed: 5, second: 3),
      );

      expect(duplicate.accepted, isFalse);
      expect(duplicate.deltaMeters, 0);
      expect(outOfOrder.accepted, isFalse);
      expect(filter.isMoving, isFalse);
    });

    test('a long gap re-anchors without crediting the jump', () {
      final filter = MovementFilter();
      filter.process(testPosition(longitude: 0, speed: 0, second: 0));
      filter.process(testPosition(longitude: 0, speed: 0, second: 1));

      // 60 s signal outage, reappearing 500 m away.
      final reappear = filter.process(
        testPosition(longitude: 0.0045, speed: 0, second: 61),
      );

      expect(reappear.deltaMeters, 0);
      expect(reappear.gapDetected, isTrue);

      // Staying put afterwards must not credit anything either.
      var totalMeters = reappear.deltaMeters;
      for (var i = 62; i <= 70; i++) {
        totalMeters += filter
            .process(testPosition(longitude: 0.0045, speed: 0, second: i))
            .deltaMeters;
      }
      expect(totalMeters, 0);
    });

    test('accuracy outliers are rejected below the hard ceiling', () {
      final filter = MovementFilter();

      // 30 s of clean 5 m fixes teaches the filter what "normal" is.
      for (var i = 0; i <= 30; i++) {
        filter.process(testPosition(longitude: 0, speed: 0, second: i));
      }

      // A 40 m-accuracy fix (legal under the 50 m ceiling) jumps 30 m with
      // fake Doppler — exactly the multipath shape. Must be rejected
      // outright because the recent norm is ~5 m.
      var totalMeters = 0.0;
      for (var i = 31; i <= 36; i++) {
        final result = filter.process(
          testPosition(
            longitude: 0.0003,
            speed: 2,
            accuracy: 40,
            second: i,
          ),
        );
        totalMeters += result.deltaMeters;
        expect(result.accepted, isFalse, reason: 'fix $i must be rejected');
      }

      expect(totalMeters, 0);
      expect(filter.isMoving, isFalse);
    });

    test('flush credits the delta still pending at session end', () {
      final filter = MovementFilter();
      filter.process(testPosition(longitude: 0, speed: 0, second: 0));

      var totalMeters = 0.0;
      for (var i = 1; i <= 4; i++) {
        totalMeters += filter
            .process(
              testPosition(
                longitude: i * 0.000135,
                speed: 15,
                speedAccuracy: 1,
                accuracy: 20,
                second: i,
              ),
            )
            .deltaMeters;
      }

      final flushed = filter.flush();
      expect(flushed, greaterThan(0));
      expect(totalMeters + flushed, closeTo(60.0, 1.0));
      // A second flush must not double-credit.
      expect(filter.flush(), 0);
    });

    test('accepted speed is EMA-smoothed', () {
      final filter = MovementFilter();
      filter.process(testPosition(longitude: 0, speed: 0, second: 0));

      double? lastSpeed;
      for (var i = 1; i <= 6; i++) {
        final result = filter.process(
          testPosition(
            longitude: i * 0.000135, // steady 15 m/s
            speed: 15,
            speedAccuracy: 1,
            accuracy: 20,
            second: i,
          ),
        );
        if (result.accepted && result.speedMs != null) {
          lastSpeed = result.speedMs;
        }
      }

      // Steady input converges on the true speed.
      expect(lastSpeed, isNotNull);
      expect(lastSpeed, closeTo(15.0, 1.0));
    });
  });
}
