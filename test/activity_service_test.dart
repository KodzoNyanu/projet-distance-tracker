import 'package:distance_tracker/services/activity_service.dart';
import 'package:distance_tracker/utils/filter_profiles.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveActiveProfile', () {
    test('falls back to the mixed-use default when nothing is known', () {
      expect(
        resolveActiveProfile(forcingVehicle: false),
        same(FilterProfile.defaults),
      );
    });

    test('recognized mode picks its profile in Auto', () {
      expect(
        resolveActiveProfile(
          forcingVehicle: false,
          recognizedMode: ActivityMode.walking,
        ),
        same(FilterProfile.walking),
      );
    });

    test('a manual lock outranks the recognized mode', () {
      expect(
        resolveActiveProfile(
          forcingVehicle: false,
          manualMode: ActivityMode.walking,
          recognizedMode: ActivityMode.vehicle,
        ),
        same(FilterProfile.walking),
      );
    });

    test('the speed safety net forces vehicle over a manual walking lock', () {
      expect(
        resolveActiveProfile(
          forcingVehicle: true,
          manualMode: ActivityMode.walking,
        ),
        same(FilterProfile.vehicle),
      );
    });
  });

  group('DisplacementMode', () {
    test('auto maps to no pinned activity mode', () {
      expect(DisplacementMode.auto.activityMode, isNull);
    });

    test('manual modes map to their activity mode', () {
      expect(DisplacementMode.walking.activityMode, ActivityMode.walking);
      expect(DisplacementMode.cycling.activityMode, ActivityMode.cycling);
      expect(DisplacementMode.vehicle.activityMode, ActivityMode.vehicle);
    });

    test('parse round-trips known names and defaults unknown to auto', () {
      expect(DisplacementModeX.parse('vehicle'), DisplacementMode.vehicle);
      expect(DisplacementModeX.parse(null), DisplacementMode.auto);
      expect(DisplacementModeX.parse('garbage'), DisplacementMode.auto);
    });
  });

  group('ActivityService debounce', () {
    test('two confident reports switch the mode', () async {
      final service = ActivityService(source: const Stream.empty());
      final emitted = <ActivityMode>[];
      service.modeStream.listen(emitted.add);

      service.ingest(
        const Activity(ActivityType.IN_VEHICLE, ActivityConfidence.HIGH),
      );
      expect(service.currentMode, isNull, reason: 'one report is not enough');
      service.ingest(
        const Activity(ActivityType.IN_VEHICLE, ActivityConfidence.MEDIUM),
      );

      await Future<void>.delayed(Duration.zero);
      expect(service.currentMode, ActivityMode.vehicle);
      expect(emitted, [ActivityMode.vehicle]);
    });

    test('low-confidence reports never confirm a switch', () {
      final service = ActivityService(source: const Stream.empty());

      for (var i = 0; i < 5; i++) {
        service.ingest(
          const Activity(ActivityType.WALKING, ActivityConfidence.LOW),
        );
      }

      expect(service.currentMode, isNull);
    });

    test('UNKNOWN holds the current mode', () {
      final service = ActivityService(source: const Stream.empty());
      service.ingest(
        const Activity(ActivityType.WALKING, ActivityConfidence.HIGH),
      );
      service.ingest(
        const Activity(ActivityType.WALKING, ActivityConfidence.HIGH),
      );
      expect(service.currentMode, ActivityMode.walking);

      for (var i = 0; i < 5; i++) {
        service.ingest(
          const Activity(ActivityType.UNKNOWN, ActivityConfidence.HIGH),
        );
      }

      expect(service.currentMode, ActivityMode.walking);
    });

    test('a flapping classification does not switch the mode', () {
      final service = ActivityService(source: const Stream.empty());
      service.ingest(
        const Activity(ActivityType.IN_VEHICLE, ActivityConfidence.HIGH),
      );
      service.ingest(
        const Activity(ActivityType.IN_VEHICLE, ActivityConfidence.HIGH),
      );
      expect(service.currentMode, ActivityMode.vehicle);

      // One stray WALKING at a red light, then back to vehicle.
      service.ingest(
        const Activity(ActivityType.WALKING, ActivityConfidence.MEDIUM),
      );
      service.ingest(
        const Activity(ActivityType.IN_VEHICLE, ActivityConfidence.HIGH),
      );

      expect(service.currentMode, ActivityMode.vehicle);
    });

    test('RUNNING maps to the walking profile', () {
      final service = ActivityService(source: const Stream.empty());
      service.ingest(
        const Activity(ActivityType.RUNNING, ActivityConfidence.HIGH),
      );
      service.ingest(
        const Activity(ActivityType.RUNNING, ActivityConfidence.HIGH),
      );

      expect(service.currentMode, ActivityMode.walking);
    });
  });

  group('SpeedModeHeuristic', () {
    final t0 = DateTime(2026, 1, 1);

    test('sustained high speed forces vehicle mode', () {
      final heuristic = SpeedModeHeuristic();

      var changed = false;
      for (var s = 0; s <= 5; s++) {
        changed = heuristic.update(15.0, t0.add(Duration(seconds: s)));
      }

      expect(changed, isTrue);
      expect(heuristic.forcingVehicle, isTrue);
    });

    test('a brief spike does not force vehicle mode', () {
      final heuristic = SpeedModeHeuristic();

      heuristic.update(15.0, t0);
      heuristic.update(15.0, t0.add(const Duration(seconds: 2)));
      heuristic.update(1.0, t0.add(const Duration(seconds: 3)));
      heuristic.update(15.0, t0.add(const Duration(seconds: 4)));

      expect(heuristic.forcingVehicle, isFalse);
    });

    test('sustained low speed releases the vehicle override', () {
      final heuristic = SpeedModeHeuristic();
      for (var s = 0; s <= 5; s++) {
        heuristic.update(15.0, t0.add(Duration(seconds: s)));
      }
      expect(heuristic.forcingVehicle, isTrue);

      // Red light: 20 s at 0 m/s must NOT release (could be traffic).
      var changed = false;
      for (var s = 6; s <= 26; s++) {
        changed = heuristic.update(0.0, t0.add(Duration(seconds: s)));
      }
      expect(changed, isFalse);
      expect(heuristic.forcingVehicle, isTrue);

      // But 30+ s of low speed does release it.
      var released = false;
      for (var s = 27; s <= 40; s++) {
        released =
            released || heuristic.update(0.0, t0.add(Duration(seconds: s)));
      }
      expect(released, isTrue);
      expect(heuristic.forcingVehicle, isFalse);
    });
  });
}
