import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import '../utils/filter_profiles.dart';

/// Bridges the platform activity-recognition APIs (Android Activity
/// Recognition, iOS CMMotionActivityManager) to debounced [ActivityMode]
/// changes the distance pipeline can act on.
///
/// Debounce: a new mode is emitted only after it is reported twice in a row
/// with at least medium confidence, or after it persists for
/// [persistSeconds] regardless of confidence — traffic lights must not flap
/// the profile, but a long consistent signal should win eventually.
/// UNKNOWN and low-confidence one-offs hold the current mode.
///
/// This service is an enhancer, never a dependency: when the plugin is
/// unavailable or permission is denied, tracking continues on the default
/// profile and the speed heuristic ([SpeedModeHeuristic]) still catches the
/// vehicle case.
class ActivityService {
  static const int persistSeconds = 10;
  static const int confirmCount = 2;

  final Stream<Activity>? _source;
  final StreamController<ActivityMode> _modes =
      StreamController<ActivityMode>.broadcast();
  StreamSubscription<Activity>? _subscription;

  ActivityMode? _current;
  ActivityMode? _candidate;
  int _candidateCount = 0;
  DateTime? _candidateSince;

  /// [source] overrides the platform stream (tests).
  ActivityService({Stream<Activity>? source}) : _source = source;

  /// Debounced activity-mode changes.
  Stream<ActivityMode> get modeStream => _modes.stream;

  /// The last emitted mode, if any.
  ActivityMode? get currentMode => _current;

  /// Requests permission and subscribes to the platform stream. Returns
  /// false (and stays inert) when recognition is unavailable — never throws.
  Future<bool> start() async {
    try {
      if (_source == null) {
        final recognition = FlutterActivityRecognition.instance;
        var permission = await recognition.checkPermission();
        if (permission == ActivityPermission.PERMANENTLY_DENIED) {
          debugPrint('[ACTIVITY] permission permanently denied');
          return false;
        }
        if (permission == ActivityPermission.DENIED) {
          permission = await recognition.requestPermission();
          if (permission != ActivityPermission.GRANTED) {
            debugPrint('[ACTIVITY] permission not granted');
            return false;
          }
        }
        _subscription = recognition.activityStream
            .handleError((Object e) => debugPrint('[ACTIVITY] error: $e'))
            .listen(ingest);
      } else {
        _subscription = _source.listen(ingest);
      }
      return true;
    } catch (e) {
      debugPrint('[ACTIVITY] unavailable: $e');
      return false;
    }
  }

  /// Feeds one platform activity event through the debounce. Public for
  /// tests; production events arrive via [start].
  void ingest(Activity activity) {
    final mode = _mapType(activity.type);
    if (mode == null) return; // UNKNOWN holds the current mode.

    final now = DateTime.now();
    if (mode == _current) {
      _candidate = null;
      _candidateCount = 0;
      _candidateSince = null;
      return;
    }

    if (mode != _candidate) {
      _candidate = mode;
      _candidateCount = 0;
      _candidateSince = now;
    }
    final confident = activity.confidence != ActivityConfidence.LOW;
    if (confident) _candidateCount++;

    final persisted = _candidateSince != null &&
        now.difference(_candidateSince!).inSeconds >= persistSeconds;
    if (_candidateCount >= confirmCount || persisted) {
      _current = mode;
      _candidate = null;
      _candidateCount = 0;
      _candidateSince = null;
      debugPrint('[ACTIVITY] mode → $mode');
      _modes.add(mode);
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _current = null;
    _candidate = null;
    _candidateCount = 0;
    _candidateSince = null;
  }

  void dispose() {
    stop();
    _modes.close();
  }

  static ActivityMode? _mapType(ActivityType type) {
    switch (type) {
      case ActivityType.STILL:
        return ActivityMode.still;
      case ActivityType.WALKING:
      case ActivityType.RUNNING:
        return ActivityMode.walking;
      case ActivityType.ON_BICYCLE:
        return ActivityMode.cycling;
      case ActivityType.IN_VEHICLE:
        return ActivityMode.vehicle;
      case ActivityType.UNKNOWN:
        return null;
    }
  }
}

/// Always-on safety net under the activity stream: sustained high speed
/// forces the vehicle profile even when recognition is absent, lagging, or
/// wrong, and sustained low speed releases it again.
class SpeedModeHeuristic {
  static const double fastSpeedMs = 12.0; // ~43 km/h: nothing on foot
  static const int fastHoldSeconds = 5;
  static const double slowSpeedMs = 2.5;
  static const int slowHoldSeconds = 30;

  DateTime? _fastSince;
  DateTime? _slowSince;
  bool _forcingVehicle = false;

  /// Whether the heuristic currently overrides the mode to vehicle.
  bool get forcingVehicle => _forcingVehicle;

  /// Feeds one smoothed speed sample; returns true when the forcing state
  /// changed.
  bool update(double speedMs, DateTime timestamp) {
    if (speedMs >= fastSpeedMs) {
      _slowSince = null;
      _fastSince ??= timestamp;
      if (!_forcingVehicle &&
          timestamp.difference(_fastSince!).inSeconds >= fastHoldSeconds) {
        _forcingVehicle = true;
        return true;
      }
      return false;
    }

    _fastSince = null;
    if (_forcingVehicle && speedMs < slowSpeedMs) {
      _slowSince ??= timestamp;
      if (timestamp.difference(_slowSince!).inSeconds >= slowHoldSeconds) {
        _forcingVehicle = false;
        _slowSince = null;
        return true;
      }
    } else {
      _slowSince = null;
    }
    return false;
  }

  void reset() {
    _fastSince = null;
    _slowSince = null;
    _forcingVehicle = false;
  }
}
