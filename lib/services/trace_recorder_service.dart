import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Records every raw GPS fix of a session to a JSONL trace file, before any
/// filtering, so real-world sessions can be replayed through filter changes
/// in unit tests (see test/support/trace_loader.dart).
///
/// File format (`traces/[sessionId].jsonl` in the app documents directory):
///
///   line 1: {"schema":"kk-trace-v1","sessionId":"…","startTime":"ISO-8601",
///            "groundTruthMeters":null}
///   line n: {"ts":epoch ms,"lat":…,"lon":…,"acc":…,"speed":…,
///            "speedAcc":…,"heading":…,"headingAcc":…}
///
/// `groundTruthMeters` is null when recorded; fill it in by hand (odometer
/// reading, measured route) before committing a trace as a test fixture.
class TraceRecorderService {
  static const String schemaVersion = 'kk-trace-v1';

  /// Traces beyond the newest [maxTraces] are deleted when a recording starts.
  static const int maxTraces = 20;

  IOSink? _sink;
  int _unflushedLines = 0;

  bool get isRecording => _sink != null;

  static Future<Directory> _tracesDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/traces');
    await dir.create(recursive: true);
    return dir;
  }

  /// Opens a new trace file for [sessionId] and writes the header line.
  Future<void> start(String sessionId, DateTime startTime) async {
    if (_sink != null) await stop();
    try {
      final dir = await _tracesDir();
      await _pruneOldTraces(dir, keep: maxTraces - 1);
      final file = File('${dir.path}/$sessionId.jsonl');
      _sink = file.openWrite(mode: FileMode.append);
      _writeLine({
        'schema': schemaVersion,
        'sessionId': sessionId,
        'startTime': startTime.toUtc().toIso8601String(),
        'groundTruthMeters': null,
      });
      await _sink?.flush();
    } catch (e) {
      // Trace recording is diagnostics — never let it break tracking.
      debugPrint('[TRACE] failed to start recorder: $e');
      _sink = null;
    }
  }

  /// Appends one raw fix. No-op when not recording.
  void record(Position position) {
    if (_sink == null) return;
    _writeLine({
      'ts': position.timestamp.millisecondsSinceEpoch,
      'lat': position.latitude,
      'lon': position.longitude,
      'acc': position.accuracy,
      'speed': position.speed,
      'speedAcc': position.speedAccuracy,
      'heading': position.heading,
      'headingAcc': position.headingAccuracy,
    });
    _unflushedLines++;
    if (_unflushedLines >= 15) {
      _unflushedLines = 0;
      _sink?.flush().catchError((Object e) {
        debugPrint('[TRACE] flush failed: $e');
      });
    }
  }

  /// Flushes and closes the current trace file.
  Future<void> stop() async {
    final sink = _sink;
    _sink = null;
    _unflushedLines = 0;
    if (sink == null) return;
    try {
      await sink.flush();
      await sink.close();
    } catch (e) {
      debugPrint('[TRACE] failed to close recorder: $e');
    }
  }

  void _writeLine(Map<String, Object?> json) {
    try {
      _sink?.writeln(jsonEncode(json));
    } catch (e) {
      debugPrint('[TRACE] write failed: $e');
    }
  }

  // ── Trace management ──────────────────────────────────────────────────────

  /// All recorded trace files, newest first.
  static Future<List<File>> listTraces() async {
    final dir = await _tracesDir();
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.jsonl'))
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path)); // ids are timestamps
    return files;
  }

  /// Shares every recorded trace through the system share sheet.
  /// Returns false when there is nothing to share.
  static Future<bool> exportAll() async {
    final files = await listTraces();
    if (files.isEmpty) return false;
    await Share.shareXFiles(
      files.map((f) => XFile(f.path, mimeType: 'application/jsonl')).toList(),
    );
    return true;
  }

  static Future<void> _pruneOldTraces(Directory dir, {required int keep}) async {
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.jsonl'))
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));
    for (final stale in files.skip(keep)) {
      try {
        await stale.delete();
      } catch (e) {
        debugPrint('[TRACE] failed to prune ${stale.path}: $e');
      }
    }
  }
}
