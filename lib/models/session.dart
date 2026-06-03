import 'package:hive/hive.dart';
import 'location_point.dart';

part 'session.g.dart';

@HiveType(typeId: 1)
class Session extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final DateTime startTime;

  @HiveField(2)
  DateTime? endTime;

  /// Total distance in metres (GPS Haversine sum)
  @HiveField(3)
  double totalDistanceMeters;

  /// Average speed in m/s (over active moving time)
  @HiveField(4)
  double avgSpeedMs;

  /// Peak speed in m/s
  @HiveField(5)
  double maxSpeedMs;

  /// Recorded GPS points during the session
  @HiveField(6)
  List<LocationPoint> locationPoints;

  /// Total active (moving) time in seconds
  @HiveField(7)
  int activeSeconds;

  Session({
    required this.id,
    required this.startTime,
    this.endTime,
    this.totalDistanceMeters = 0.0,
    this.avgSpeedMs = 0.0,
    this.maxSpeedMs = 0.0,
    List<LocationPoint>? locationPoints,
    this.activeSeconds = 0,
  }) : locationPoints = locationPoints ?? [];

  bool get isCompleted => endTime != null;

  Duration get activeDuration => Duration(seconds: activeSeconds);

  double get totalDistanceKm => totalDistanceMeters / 1000.0;

  double get totalDistanceMiles => totalDistanceMeters / 1609.344;
}
