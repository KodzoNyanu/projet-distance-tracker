import 'package:distance_tracker/utils/formatters.dart';
import 'package:distance_tracker/utils/haversine.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
