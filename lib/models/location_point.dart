import 'package:hive/hive.dart';

part 'location_point.g.dart';

@HiveType(typeId: 0)
class LocationPoint extends HiveObject {
  @HiveField(0)
  final double latitude;

  @HiveField(1)
  final double longitude;

  @HiveField(2)
  final DateTime timestamp;

  /// Speed in metres per second (from GPS, may be -1 if unavailable)
  @HiveField(3)
  final double speed;

  /// Estimated accuracy radius in metres
  @HiveField(4)
  final double accuracy;

  LocationPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.speed,
    required this.accuracy,
  });
}
