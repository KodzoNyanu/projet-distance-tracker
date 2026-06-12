// Generates synthetic GPS trace fixtures (kk-trace-v1 JSONL) with known
// ground truth for test/trace_replay_test.dart.
//
//   dart run tool/generate_fixtures.dart
//
// The noise model is first-order Gauss-Markov (autocorrelated), which mimics
// real GNSS wander far better than white noise: consecutive fixes drift
// around the true position instead of teleporting. Seeded RNG keeps the
// fixtures reproducible. Real recorded traces (Settings → record raw GPS
// traces, then export) should be added alongside these as they are collected.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const earthRadius = 6371008.8;
const baseLat = 4.0511; // Douala
const baseLon = 9.7679;

void main() {
  final dir = Directory('test/fixtures');
  dir.createSync(recursive: true);

  _write(dir, 'stationary_multipath', _stationaryMultipath());
  _write(dir, 'walking_loop', _walkingLoop());
  _write(dir, 'drive_with_stops', _driveWithStops());
  _write(dir, 'mixed_walk_drive', _mixedWalkDrive());
}

class Fix {
  final int second;
  final double east; // metres east of origin (true position + noise)
  final double north;
  final double accuracy;
  final double speed; // Doppler, -1 when unavailable
  final double speedAccuracy;

  Fix(this.second, this.east, this.north, this.accuracy, this.speed,
      this.speedAccuracy);
}

class Trace {
  final List<Fix> fixes;
  final double groundTruthMeters;

  Trace(this.fixes, this.groundTruthMeters);
}

/// One-hour stationary phone near a wall: wandering noise, degrading
/// accuracy episodes, and bursts of fake Doppler speed. Truth: 0 m.
Trace _stationaryMultipath() {
  final rng = math.Random(11);
  final noise = _GaussMarkov(rng, sigma: 4.0);
  final fixes = <Fix>[];
  for (var t = 0; t < 3600; t++) {
    // Multipath episode every ~10 min: noise and accuracy blow up and the
    // chip invents speed.
    final episode = (t % 600) > 480;
    final n = noise.next(scale: episode ? 3.0 : 1.0);
    final accuracy = episode ? 25.0 + rng.nextDouble() * 25 : 8.0 + rng.nextDouble() * 6;
    final speed = episode ? 0.4 + rng.nextDouble() * 2.0 : rng.nextDouble() * 0.2;
    fixes.add(Fix(t, n.$1, n.$2, accuracy, speed, episode ? 0.0 : 0.5));
  }
  return Trace(fixes, 0);
}

/// 2 km out-and-back walk at 1.4 m/s with a 60 s pause at the turnaround.
Trace _walkingLoop() {
  final rng = math.Random(22);
  final noise = _GaussMarkov(rng, sigma: 3.0);
  final fixes = <Fix>[];
  var east = 0.0;
  var truth = 0.0;
  const speed = 1.4;
  final outSeconds = (1000 / speed).round(); // 1 km out

  var t = 0;
  void walk(int seconds, double direction) {
    for (var i = 0; i < seconds; i++, t++) {
      east += speed * direction;
      truth += speed;
      final n = noise.next();
      // Doppler is healthy while walking, with occasional dropouts.
      final dropout = rng.nextDouble() < 0.05;
      fixes.add(Fix(
        t,
        east + n.$1,
        n.$2,
        4.0 + rng.nextDouble() * 4,
        dropout ? -1.0 : speed + (rng.nextDouble() - 0.5) * 0.4,
        dropout ? 0.0 : 0.5,
      ));
    }
  }

  void pause(int seconds) {
    for (var i = 0; i < seconds; i++, t++) {
      final n = noise.next();
      fixes.add(Fix(t, east + n.$1, n.$2, 5.0 + rng.nextDouble() * 5,
          rng.nextDouble() * 0.2, 0.5));
    }
  }

  walk(outSeconds, 1);
  pause(60);
  walk(outSeconds, -1);
  return Trace(fixes, truth);
}

/// ~10 km urban drive: accelerate to 14 m/s, two 45 s red lights, worse
/// accuracy than open-sky walking.
Trace _driveWithStops() {
  final rng = math.Random(33);
  final noise = _GaussMarkov(rng, sigma: 6.0);
  final fixes = <Fix>[];
  var east = 0.0;
  var speed = 0.0;
  var truth = 0.0;
  var t = 0;

  void drive(int seconds, double targetSpeed) {
    for (var i = 0; i < seconds; i++, t++) {
      // Ease toward the target speed at ~1.5 m/s².
      final diff = targetSpeed - speed;
      speed += diff.clamp(-1.5, 1.5);
      east += speed;
      truth += speed;
      final n = noise.next();
      fixes.add(Fix(
        t,
        east + n.$1,
        n.$2,
        8.0 + rng.nextDouble() * 10,
        math.max(0, speed + (rng.nextDouble() - 0.5) * 1.0),
        1.0,
      ));
    }
  }

  drive(240, 14); // ~3.3 km
  drive(45, 0); // braking + red light
  drive(300, 14); // ~4.1 km
  drive(45, 0);
  drive(200, 14); // ~2.7 km
  drive(20, 0);
  return Trace(fixes, truth);
}

/// 500 m walk → 3 km drive → 300 m walk, the mixed-mode shape the app
/// struggles with.
Trace _mixedWalkDrive() {
  final rng = math.Random(44);
  final noise = _GaussMarkov(rng, sigma: 4.0);
  final fixes = <Fix>[];
  var east = 0.0;
  var speed = 0.0;
  var truth = 0.0;
  var t = 0;

  void move(int seconds, double targetSpeed, double accel, double accBase) {
    for (var i = 0; i < seconds; i++, t++) {
      final diff = targetSpeed - speed;
      speed += diff.clamp(-accel, accel);
      east += speed;
      truth += speed;
      final n = noise.next();
      fixes.add(Fix(
        t,
        east + n.$1,
        n.$2,
        accBase + rng.nextDouble() * 8,
        math.max(0, speed + (rng.nextDouble() - 0.5) * 0.6),
        0.8,
      ));
    }
  }

  move(360, 1.4, 0.5, 4); // ~500 m walk
  move(60, 0, 0.5, 5); // waiting for the car
  move(260, 12, 1.5, 9); // ~3 km drive
  move(30, 0, 1.5, 9); // parking
  move(220, 1.4, 0.5, 4); // ~300 m walk
  return Trace(fixes, truth);
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/// First-order Gauss-Markov 2-D noise: x_t = ρ·x_{t-1} + √(1−ρ²)·σ·w_t.
class _GaussMarkov {
  final math.Random rng;
  final double sigma;
  final double rho = 0.95;
  double _e = 0;
  double _n = 0;

  _GaussMarkov(this.rng, {required this.sigma});

  (double, double) next({double scale = 1.0}) {
    final k = math.sqrt(1 - rho * rho) * sigma * scale;
    _e = rho * _e + k * _gauss();
    _n = rho * _n + k * _gauss();
    return (_e, _n);
  }

  double _gauss() {
    final u1 = rng.nextDouble().clamp(1e-12, 1.0);
    final u2 = rng.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
}

void _write(Directory dir, String name, Trace trace) {
  final start = DateTime.utc(2026, 1, 1, 8);
  final buf = StringBuffer();
  buf.writeln(jsonEncode({
    'schema': 'kk-trace-v1',
    'sessionId': name,
    'startTime': start.toIso8601String(),
    'groundTruthMeters': double.parse(trace.groundTruthMeters.toStringAsFixed(1)),
  }));
  final cosLat = math.cos(baseLat * math.pi / 180);
  for (final f in trace.fixes) {
    final lat = baseLat + f.north / earthRadius * 180 / math.pi;
    final lon = baseLon + f.east / (earthRadius * cosLat) * 180 / math.pi;
    buf.writeln(jsonEncode({
      'ts': start.add(Duration(seconds: f.second)).millisecondsSinceEpoch,
      'lat': double.parse(lat.toStringAsFixed(8)),
      'lon': double.parse(lon.toStringAsFixed(8)),
      'acc': double.parse(f.accuracy.toStringAsFixed(1)),
      'speed': double.parse(f.speed.toStringAsFixed(2)),
      'speedAcc': double.parse(f.speedAccuracy.toStringAsFixed(2)),
      'heading': 0,
      'headingAcc': 0,
    }));
  }
  File('${dir.path}/$name.jsonl').writeAsStringSync(buf.toString());
  // ignore: avoid_print
  print('wrote $name.jsonl: ${trace.fixes.length} fixes, '
      'truth ${trace.groundTruthMeters.toStringAsFixed(1)} m');
}
