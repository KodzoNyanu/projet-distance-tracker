import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/session.dart';
import 'webhook_service.dart';

/// Exports session data as JSON or CSV and triggers the system share sheet.
class ExportService {
  ExportService._();

  // ── Multi-session exports ─────────────────────────────────────────────────

  /// Exports all [sessions] as a single pretty-printed JSON file.
  static Future<void> exportSessionsAsJson(List<Session> sessions) async {
    final data = {
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'session_count': sessions.length,
      'sessions': sessions.map(WebhookService.buildSessionEndPayload).toList(),
    };
    final json = const JsonEncoder.withIndent('  ').convert(data);
    await _share(json, 'kodzo_kilometrage_sessions.json', 'application/json');
  }

  /// Exports all [sessions] as a CSV summary (one row per session).
  static Future<void> exportSessionsAsCsv(List<Session> sessions) async {
    final buf = StringBuffer();
    buf.writeln(
      'session_id,start_time,end_time,total_distance_meters,total_distance_km,'
      'total_distance_miles,avg_speed_ms,avg_speed_kmh,max_speed_ms,'
      'max_speed_kmh,active_seconds,point_count',
    );
    for (final s in sessions) {
      buf.writeln(
        '${s.id},'
        '${s.startTime.toUtc().toIso8601String()},'
        '${s.endTime?.toUtc().toIso8601String() ?? ''},'
        '${s.totalDistanceMeters.toStringAsFixed(3)},'
        '${s.totalDistanceKm.toStringAsFixed(6)},'
        '${s.totalDistanceMiles.toStringAsFixed(6)},'
        '${s.avgSpeedMs.toStringAsFixed(3)},'
        '${(s.avgSpeedMs * 3.6).toStringAsFixed(3)},'
        '${s.maxSpeedMs.toStringAsFixed(3)},'
        '${(s.maxSpeedMs * 3.6).toStringAsFixed(3)},'
        '${s.activeSeconds},'
        '${s.locationPoints.length}',
      );
    }
    await _share(buf.toString(), 'kodzo_kilometrage_sessions.csv', 'text/csv');
  }

  // ── Single-session exports ────────────────────────────────────────────────

  /// Exports a single [session] as a JSON file with full GPS points.
  static Future<void> exportSessionAsJson(Session session) async {
    final payload = WebhookService.buildSessionEndPayload(session);
    payload['exported_at'] = DateTime.now().toUtc().toIso8601String();
    final json = const JsonEncoder.withIndent('  ').convert(payload);
    await _share(json, 'session_${session.id}.json', 'application/json');
  }

  /// Exports a single [session] as a CSV with one row per GPS point.
  static Future<void> exportSessionAsCsv(Session session) async {
    final buf = StringBuffer();
    buf.writeln(
      'latitude,longitude,timestamp,speed_ms,speed_kmh,accuracy_meters',
    );
    for (final p in session.locationPoints) {
      buf.writeln(
        '${p.latitude},'
        '${p.longitude},'
        '${p.timestamp.toUtc().toIso8601String()},'
        '${p.speed.toStringAsFixed(3)},'
        '${(p.speed * 3.6).toStringAsFixed(3)},'
        '${p.accuracy.toStringAsFixed(1)}',
      );
    }
    await _share(
      buf.toString(),
      'session_${session.id}_points.csv',
      'text/csv',
    );
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  static Future<void> _share(
    String content,
    String filename,
    String mimeType,
  ) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content, encoding: utf8);
    await Share.shareXFiles([XFile(file.path, mimeType: mimeType)]);
  }
}
