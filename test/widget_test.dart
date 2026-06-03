import 'package:distance_tracker/utils/formatters.dart';
import 'package:distance_tracker/utils/haversine.dart';
import 'package:distance_tracker/utils/movement_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  group('distance formatting', () {
    test('uses meters below one kilometer', () {
      expect(formatDistance(42), '42 m');
      expect(distanceUnitForValue(42), 'm');
    });

    test('uses kilometers at one kilometer and above', () {
      expect(formatDistance(1250), '1.25 km');
      expect(distanceUnitForValue(1250), 'km');
    });
  });

  group('distance calculation', () {
    test('matches the expected Haversine distance for one equator degree', () {
      final meters = haversineDistance(0, 0, 0, 1);

      expect(meters, closeTo(111195.08, 1));
    });
  });

  group('movement filter', () {
    test('accepts the first accurate point even when speed is zero', () {
      final filter = MovementFilter();
      final point = _position(latitude: 0, longitude: 0, speed: 0);

      expect(filter.isValidMovement(point, null), isTrue);
      expect(filter.shouldAutoPause, isFalse);
    });

    test('ignores a single low-speed GPS jump', () {
      final filter = MovementFilter();
      final last = _position(latitude: 0, longitude: 0, speed: 0);
      final jumped = _position(
        latitude: 0,
        longitude: 0.00004,
        speed: 0,
        timestamp: DateTime(2026, 1, 1, 0, 0, 4),
      );

      expect(filter.isValidMovement(jumped, last), isFalse);
      expect(filter.shouldAutoPause, isFalse);
    });

    test('accepts sustained movement even when reported speed is low', () {
      final filter = MovementFilter();
      final last = _position(latitude: 0, longitude: 0, speed: 0);
      final firstMove = _position(
        latitude: 0,
        longitude: 0.00004,
        speed: 0.1,
        timestamp: DateTime(2026, 1, 1, 0, 0, 4),
      );
      final secondMove = _position(
        latitude: 0,
        longitude: 0.00008,
        speed: 0.1,
        timestamp: DateTime(2026, 1, 1, 0, 0, 8),
      );

      expect(filter.isValidMovement(firstMove, last), isFalse);
      expect(filter.isValidMovement(secondMove, last), isTrue);
      expect(filter.shouldAutoPause, isFalse);
    });

    test('calculates speed from position timestamps', () {
      final filter = MovementFilter();
      final last = _position(latitude: 0, longitude: 0, speed: 0);
      final moved = _position(
        latitude: 0,
        longitude: 0.00008,
        speed: 0,
        timestamp: DateTime(2026, 1, 1, 0, 0, 8),
      );

      final distance = haversineDistance(
        last.latitude,
        last.longitude,
        moved.latitude,
        moved.longitude,
      );

      expect(filter.speedBetween(moved, last, distance), closeTo(1.11, 0.02));
    });

    test(
      'does not auto-pause while speed suggests movement but distance waits',
      () {
        final filter = MovementFilter();
        final last = _position(latitude: 0, longitude: 0, speed: 1.4);
        final smallMove = _position(
          latitude: 0,
          longitude: 0.000005,
          speed: 1.4,
        );

        for (var i = 0; i < MovementFilter.autoPauseAfterCount + 2; i++) {
          expect(filter.isValidMovement(smallMove, last), isFalse);
        }

        expect(filter.shouldAutoPause, isFalse);
      },
    );

    test('auto-pauses after repeated stationary readings', () {
      final filter = MovementFilter();
      final last = _position(latitude: 0, longitude: 0, speed: 0);
      final stationary = _position(latitude: 0, longitude: 0.000001, speed: 0);

      for (var i = 0; i < MovementFilter.autoPauseAfterCount; i++) {
        expect(filter.isValidMovement(stationary, last), isFalse);
      }

      expect(filter.shouldAutoPause, isTrue);
    });

    test('auto-pauses after repeated jitter that is not sustained', () {
      final filter = MovementFilter();
      final last = _position(latitude: 0, longitude: 0, speed: 0);
      final jitter = _position(
        latitude: 0,
        longitude: 0.00004,
        speed: 0,
        timestamp: DateTime(2026, 1, 1, 0, 0, 8),
      );

      expect(filter.isValidMovement(jitter, last), isFalse);
      for (var i = 0; i < MovementFilter.autoPauseAfterCount; i++) {
        expect(filter.isValidMovement(jitter, last), isFalse);
      }

      expect(filter.shouldAutoPause, isTrue);
    });
  });
}

Position _position({
  required double latitude,
  required double longitude,
  required double speed,
  double accuracy = 5,
  DateTime? timestamp,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp ?? DateTime(2026),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
  );
}
