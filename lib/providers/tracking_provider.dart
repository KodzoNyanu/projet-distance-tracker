import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/session.dart';
import '../models/location_point.dart';
import '../services/location_service.dart';
import '../services/background_service.dart';
import '../services/storage_service.dart';
import '../services/webhook_service.dart';
import '../providers/settings_provider.dart';
import '../utils/haversine.dart';
import '../utils/movement_filter.dart';
import '../utils/formatters.dart';

enum TrackingState { idle, tracking, autoPaused, stopped }

class TrackingProvider extends ChangeNotifier {
  final LocationService _locationService = LocationService();
  late MovementFilter _filter;

  TrackingState _state = TrackingState.idle;
  double _distanceMeters = 0.0;
  double _currentSpeedMs = 0.0;
  double _maxSpeedMs = 0.0;
  double _totalSpeedSum = 0.0;
  int _speedReadings = 0;
  int _activeSeconds = 0;
  Position? _lastPosition;
  Session? _currentSession;
  Timer? _elapsedTimer;
  StreamSubscription<Position>? _positionSub;
  String? _errorMessage;

  // User-configurable auto-pause threshold in m/s
  double _autoPauseThresholdMs = 0.55; // ≈ 2 km/h
  bool _autoPauseEnabled = false;

  // Unit preference (injected by SettingsProvider or Settings screen)
  bool useImperial = false;

  // ── Webhook / real-time API config ────────────────────────────────────────
  String _webhookUrl = '';
  bool _realtimeWebhookEnabled = false;
  int _webhookIntervalSeconds = 5;
  bool _postSessionOnComplete = true;
  DateTime? _lastWebhookPost;
  DateTime? _lastSessionPersist;

  // ── Getters ──────────────────────────────────────────────────────────────

  TrackingState get state => _state;
  double get distanceMeters => _distanceMeters;
  double get currentSpeedMs => _currentSpeedMs;
  double get maxSpeedMs => _maxSpeedMs;
  int get activeSeconds => _activeSeconds;
  Duration get activeDuration => Duration(seconds: _activeSeconds);
  Session? get currentSession => _currentSession;
  String? get errorMessage => _errorMessage;
  double get autoPauseThresholdMs => _autoPauseThresholdMs;
  bool get autoPauseEnabled => _autoPauseEnabled;

  bool get isIdle => _state == TrackingState.idle;
  bool get isTracking => _state == TrackingState.tracking;
  bool get isAutoPaused => _state == TrackingState.autoPaused;
  bool get isStopped => _state == TrackingState.stopped;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Called by ProxyProvider whenever SettingsProvider changes.
  void applySettings(SettingsProvider settings) {
    useImperial = settings.useImperial;
    _autoPauseEnabled = settings.autoPauseEnabled;
    _autoPauseThresholdMs = settings.autoPauseThresholdMs;
    _webhookUrl = settings.webhookUrl;
    _realtimeWebhookEnabled = settings.realtimeWebhookEnabled;
    _webhookIntervalSeconds = settings.webhookIntervalSeconds;
    _postSessionOnComplete = settings.postSessionOnComplete;
    // Rebuild filter in case threshold changed
    _filter = MovementFilter(stationaryThresholdMs: _autoPauseThresholdMs);
  }

  /// Updates auto-pause speed threshold (in m/s).
  void setAutoPauseThreshold(double thresholdMs) {
    _autoPauseThresholdMs = thresholdMs;
    _filter = MovementFilter(stationaryThresholdMs: _autoPauseThresholdMs);
    notifyListeners();
  }

  /// Starts a new session. Throws if location permission is unavailable.
  Future<void> startSession() async {
    _clearError();
    _resetState();
    _filter = MovementFilter(stationaryThresholdMs: _autoPauseThresholdMs);

    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _currentSession = Session(id: sessionId, startTime: DateTime.now());

    try {
      await _locationService.startTracking();
    } on LocationServiceException catch (e) {
      _setError(e.message);
      return;
    }

    _state = TrackingState.tracking;
    _startElapsedTimer();
    _lastWebhookPost = null;
    _persistCurrentSession(force: true);

    BackgroundService.init();
    await BackgroundService.start(distanceText: _notificationText());

    // Fire session_start webhook event
    if (_webhookUrl.isNotEmpty) {
      WebhookService.post(
        _webhookUrl,
        WebhookService.buildSessionStartPayload(
          sessionId: sessionId,
          startTime: _currentSession!.startTime,
        ),
      );
    }

    _positionSub = _locationService.positionStream.listen(
      _onPosition,
      onError: (Object e) {
        _setError(e.toString());
        stopSession();
      },
    );

    notifyListeners();
  }

  /// Stops the current session and saves it to Hive.
  Future<Session?> stopSession() async {
    if (_state == TrackingState.idle) return null;

    _state = TrackingState.stopped;
    _stopElapsedTimer();
    await _positionSub?.cancel();
    await _locationService.stopTracking();
    await BackgroundService.stop();
    _filter.reset();

    if (_currentSession != null) {
      _currentSession!.endTime = DateTime.now();
      _currentSession!.totalDistanceMeters = _distanceMeters;
      _currentSession!.maxSpeedMs = _maxSpeedMs;
      _currentSession!.avgSpeedMs = _speedReadings > 0
          ? _totalSpeedSum / _speedReadings
          : 0.0;
      _currentSession!.activeSeconds = _activeSeconds;
      await StorageService.saveSession(_currentSession!);

      // Fire session_end webhook with full session data
      if (_webhookUrl.isNotEmpty && _postSessionOnComplete) {
        WebhookService.post(
          _webhookUrl,
          WebhookService.buildSessionEndPayload(_currentSession!),
        );
      }
    }

    notifyListeners();
    return _currentSession;
  }

  /// Resets to idle so a new session can be started.
  void resetToIdle() {
    _resetState();
    _state = TrackingState.idle;
    notifyListeners();
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  void _onPosition(Position position) {
    final valid = _filter.isValidMovement(position, _lastPosition);

    if (valid) {
      if (_state == TrackingState.autoPaused) {
        // Resume
        _state = TrackingState.tracking;
        _startElapsedTimer();
        _filter.reset();
      }

      var delta = 0.0;
      if (_lastPosition != null) {
        delta = haversineDistance(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        _distanceMeters += delta;
      }

      final reportedSpeedMs = position.speed >= 0 ? position.speed : 0.0;
      final calculatedSpeedMs = _filter.speedBetween(
        position,
        _lastPosition,
        delta,
      );
      _currentSpeedMs = calculatedSpeedMs > reportedSpeedMs
          ? calculatedSpeedMs
          : reportedSpeedMs;
      if (_currentSpeedMs > _maxSpeedMs) _maxSpeedMs = _currentSpeedMs;
      if (_currentSpeedMs > 0) {
        _totalSpeedSum += _currentSpeedMs;
        _speedReadings++;
      }

      _currentSession?.locationPoints.add(
        LocationPoint(
          latitude: position.latitude,
          longitude: position.longitude,
          timestamp: DateTime.now(),
          speed: _currentSpeedMs,
          accuracy: position.accuracy,
        ),
      );

      _lastPosition = position;

      // Real-time webhook: throttled by webhookIntervalSeconds
      if (_realtimeWebhookEnabled &&
          _webhookUrl.isNotEmpty &&
          _currentSession != null) {
        final now = DateTime.now();
        final elapsed = _lastWebhookPost == null
            ? _webhookIntervalSeconds + 1
            : now.difference(_lastWebhookPost!).inSeconds;
        if (elapsed >= _webhookIntervalSeconds) {
          _lastWebhookPost = now;
          final loc = _currentSession!.locationPoints.isNotEmpty
              ? _currentSession!.locationPoints.last
              : null;
          WebhookService.post(
            _webhookUrl,
            WebhookService.buildDistanceUpdatePayload(
              sessionId: _currentSession!.id,
              distanceMeters: _distanceMeters,
              speedMs: _currentSpeedMs,
              activeSeconds: _activeSeconds,
              location: loc,
            ),
          );
        }
      }

      // Update foreground notification every accepted point
      BackgroundService.update(distanceText: _notificationText());
      _persistCurrentSession();
    } else {
      if (position.speed >= 0) {
        _currentSpeedMs = position.speed;
      }

      if (_autoPauseEnabled &&
          _filter.shouldAutoPause &&
          _state == TrackingState.tracking) {
        _state = TrackingState.autoPaused;
        _currentSpeedMs = 0.0;
        _stopElapsedTimer();
      }
    }

    notifyListeners();
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state == TrackingState.tracking) {
        _activeSeconds++;
        notifyListeners();
      }
    });
  }

  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  void _resetState() {
    _stopElapsedTimer();
    _distanceMeters = 0.0;
    _currentSpeedMs = 0.0;
    _maxSpeedMs = 0.0;
    _totalSpeedSum = 0.0;
    _speedReadings = 0;
    _activeSeconds = 0;
    _lastPosition = null;
    _currentSession = null;
    _errorMessage = null;
    _lastSessionPersist = null;
  }

  void _persistCurrentSession({bool force = false}) {
    final session = _currentSession;
    if (session == null) return;

    final now = DateTime.now();
    if (!force &&
        _lastSessionPersist != null &&
        now.difference(_lastSessionPersist!).inSeconds < 15) {
      return;
    }

    session.totalDistanceMeters = _distanceMeters;
    session.maxSpeedMs = _maxSpeedMs;
    session.avgSpeedMs = _speedReadings > 0
        ? _totalSpeedSum / _speedReadings
        : 0.0;
    session.activeSeconds = _activeSeconds;
    _lastSessionPersist = now;
    unawaited(StorageService.saveSession(session));
  }

  void _setError(String msg) {
    _errorMessage = msg;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }

  String _notificationText() {
    return formatDistance(_distanceMeters, useImperial: useImperial);
  }

  @override
  void dispose() {
    _stopElapsedTimer();
    _positionSub?.cancel();
    _locationService.dispose();
    super.dispose();
  }
}
