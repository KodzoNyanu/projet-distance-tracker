import 'dart:convert';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

/// A recorded GPS trace (see lib/services/trace_recorder_service.dart for the
/// JSONL format) plus its reference distance when one was measured.
class GpsTrace {
  final String sessionId;
  final DateTime startTime;

  /// Reference distance in metres (odometer, measured route), null when the
  /// trace was recorded without one.
  final double? groundTruthMeters;

  final List<Position> fixes;

  const GpsTrace({
    required this.sessionId,
    required this.startTime,
    required this.groundTruthMeters,
    required this.fixes,
  });
}

/// Parses a kk-trace-v1 JSONL file into a [GpsTrace].
GpsTrace loadTrace(String path) {
  final lines = File(path)
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    throw FormatException('empty trace file: $path');
  }

  final header = jsonDecode(lines.first) as Map<String, dynamic>;
  if (header['schema'] != 'kk-trace-v1') {
    throw FormatException('unknown trace schema in $path: ${header['schema']}');
  }

  final fixes = lines.skip(1).map((line) {
    final j = jsonDecode(line) as Map<String, dynamic>;
    return Position(
      latitude: (j['lat'] as num).toDouble(),
      longitude: (j['lon'] as num).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(j['ts'] as int),
      accuracy: (j['acc'] as num).toDouble(),
      altitude: 0,
      altitudeAccuracy: 0,
      heading: (j['heading'] as num? ?? 0).toDouble(),
      headingAccuracy: (j['headingAcc'] as num? ?? 0).toDouble(),
      speed: (j['speed'] as num? ?? -1).toDouble(),
      speedAccuracy: (j['speedAcc'] as num? ?? 0).toDouble(),
    );
  }).toList();

  return GpsTrace(
    sessionId: header['sessionId'] as String,
    startTime: DateTime.parse(header['startTime'] as String),
    groundTruthMeters: (header['groundTruthMeters'] as num?)?.toDouble(),
    fixes: fixes,
  );
}

/// All committed fixture traces under test/fixtures.
List<GpsTrace> loadFixtureTraces() {
  final dir = Directory('test/fixtures');
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.jsonl'))
      .map((f) => loadTrace(f.path))
      .toList();
}
