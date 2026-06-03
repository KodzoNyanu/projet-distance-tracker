import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/session.dart';
import '../models/location_point.dart';

/// Builds structured JSON payloads and sends them to a user-configured HTTP endpoint.
class WebhookService {
  WebhookService._();

  // ── Payload builders ──────────────────────────────────────────────────────

  /// Fired once when a session begins.
  static Map<String, dynamic> buildSessionStartPayload({
    required String sessionId,
    required DateTime startTime,
  }) {
    return {
      'event': 'session_start',
      'session_id': sessionId,
      'timestamp': startTime.toUtc().toIso8601String(),
    };
  }

  /// Fired at each real-time distance update while tracking.
  static Map<String, dynamic> buildDistanceUpdatePayload({
    required String sessionId,
    required double distanceMeters,
    required double speedMs,
    required int activeSeconds,
    LocationPoint? location,
  }) {
    return {
      'event': 'distance_update',
      'session_id': sessionId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'distance_meters': _round(distanceMeters, 3),
      'distance_km': _round(distanceMeters / 1000.0, 6),
      'distance_miles': _round(distanceMeters / 1609.344, 6),
      'speed_ms': _round(speedMs, 3),
      'speed_kmh': _round(speedMs * 3.6, 3),
      'speed_mph': _round(speedMs * 2.23694, 3),
      'active_seconds': activeSeconds,
      if (location != null)
        'location': {
          'latitude': location.latitude,
          'longitude': location.longitude,
          'accuracy_meters': _round(location.accuracy, 1),
        },
    };
  }

  /// Fired once when a session ends; includes the full session summary and all GPS points.
  static Map<String, dynamic> buildSessionEndPayload(Session session) {
    return {
      'event': 'session_end',
      'session_id': session.id,
      'start_time': session.startTime.toUtc().toIso8601String(),
      'end_time': session.endTime?.toUtc().toIso8601String(),
      'total_distance_meters': _round(session.totalDistanceMeters, 3),
      'total_distance_km': _round(session.totalDistanceKm, 6),
      'total_distance_miles': _round(session.totalDistanceMiles, 6),
      'avg_speed_ms': _round(session.avgSpeedMs, 3),
      'avg_speed_kmh': _round(session.avgSpeedMs * 3.6, 3),
      'avg_speed_mph': _round(session.avgSpeedMs * 2.23694, 3),
      'max_speed_ms': _round(session.maxSpeedMs, 3),
      'max_speed_kmh': _round(session.maxSpeedMs * 3.6, 3),
      'max_speed_mph': _round(session.maxSpeedMs * 2.23694, 3),
      'active_seconds': session.activeSeconds,
      'location_points': session.locationPoints
          .map(
            (p) => {
              'latitude': p.latitude,
              'longitude': p.longitude,
              'timestamp': p.timestamp.toUtc().toIso8601String(),
              'speed_ms': _round(p.speed, 3),
              'speed_kmh': _round(p.speed * 3.6, 3),
              'accuracy_meters': _round(p.accuracy, 1),
            },
          )
          .toList(),
    };
  }

  // ── HTTP sender ───────────────────────────────────────────────────────────

  /// Posts [payload] as JSON to [url].
  /// Returns `true` on a 2xx response; never throws so tracking is unaffected by errors.
  static Future<bool> post(String url, Map<String, dynamic> payload) async {
    if (url.trim().isEmpty) return false;
    try {
      final uri = Uri.parse(url.trim());
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static double _round(double value, int decimals) {
    double factor = 1.0;
    for (int i = 0; i < decimals; i++) {
      factor *= 10;
    }
    return (value * factor).roundToDouble() / factor;
  }
}
