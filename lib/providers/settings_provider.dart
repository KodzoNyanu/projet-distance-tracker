import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SettingsProvider extends ChangeNotifier {
  static const _boxName = 'settings';
  static const _keyImperial = 'use_imperial';
  static const _keyAutoPauseEnabled = 'auto_pause_enabled';
  static const _keyPauseThreshold = 'pause_threshold_kmh';
  static const _keyWebhookUrl = 'webhook_url';
  static const _keyRealtimeWebhook = 'realtime_webhook_enabled';
  static const _keyWebhookInterval = 'webhook_interval_seconds';
  static const _keyPostOnComplete = 'post_session_on_complete';
  static const _keyLanguage = 'language_code';

  bool _useImperial = false;
  bool _autoPauseEnabled = false;
  String _languageCode = 'fr';
  double _autoPauseThresholdKmh = 2.0;

  // ── Webhook / API settings ─────────────────────────────────────────────
  String _webhookUrl = '';
  bool _realtimeWebhookEnabled = false;
  int _webhookIntervalSeconds = 5;
  bool _postSessionOnComplete = true;

  bool get useImperial => _useImperial;
  bool get autoPauseEnabled => _autoPauseEnabled;
  String get languageCode => _languageCode;
  double get autoPauseThresholdKmh => _autoPauseThresholdKmh;
  double get autoPauseThresholdMs => _autoPauseThresholdKmh / 3.6;

  String get webhookUrl => _webhookUrl;
  bool get realtimeWebhookEnabled => _realtimeWebhookEnabled;
  int get webhookIntervalSeconds => _webhookIntervalSeconds;
  bool get postSessionOnComplete => _postSessionOnComplete;

  static Future<void> openBox() async {
    await Hive.openBox(_boxName);
  }

  void load() {
    final box = Hive.box(_boxName);
    _useImperial = box.get(_keyImperial, defaultValue: false) as bool;
    _autoPauseEnabled =
        box.get(_keyAutoPauseEnabled, defaultValue: false) as bool;
    _autoPauseThresholdKmh =
        box.get(_keyPauseThreshold, defaultValue: 2.0) as double;
    _webhookUrl = box.get(_keyWebhookUrl, defaultValue: '') as String;
    _realtimeWebhookEnabled =
        box.get(_keyRealtimeWebhook, defaultValue: false) as bool;
    _webhookIntervalSeconds =
        box.get(_keyWebhookInterval, defaultValue: 5) as int;
    _postSessionOnComplete =
        box.get(_keyPostOnComplete, defaultValue: true) as bool;
    _languageCode = box.get(_keyLanguage, defaultValue: 'fr') as String;
    notifyListeners();
  }

  Future<void> setUseImperial(bool value) async {
    _useImperial = value;
    await Hive.box(_boxName).put(_keyImperial, value);
    notifyListeners();
  }

  Future<void> setAutoPauseEnabled(bool value) async {
    _autoPauseEnabled = value;
    await Hive.box(_boxName).put(_keyAutoPauseEnabled, value);
    notifyListeners();
  }

  Future<void> setAutoPauseThresholdKmh(double value) async {
    _autoPauseThresholdKmh = value;
    await Hive.box(_boxName).put(_keyPauseThreshold, value);
    notifyListeners();
  }

  Future<void> setWebhookUrl(String value) async {
    _webhookUrl = value.trim();
    await Hive.box(_boxName).put(_keyWebhookUrl, _webhookUrl);
    notifyListeners();
  }

  Future<void> setRealtimeWebhookEnabled(bool value) async {
    _realtimeWebhookEnabled = value;
    await Hive.box(_boxName).put(_keyRealtimeWebhook, value);
    notifyListeners();
  }

  Future<void> setWebhookIntervalSeconds(int value) async {
    _webhookIntervalSeconds = value.clamp(1, 300);
    await Hive.box(_boxName).put(_keyWebhookInterval, _webhookIntervalSeconds);
    notifyListeners();
  }

  Future<void> setPostSessionOnComplete(bool value) async {
    _postSessionOnComplete = value;
    await Hive.box(_boxName).put(_keyPostOnComplete, value);
    notifyListeners();
  }

  Future<void> setLanguageCode(String value) async {
    if (value != 'fr' && value != 'en') return;
    _languageCode = value;
    await Hive.box(_boxName).put(_keyLanguage, value);
    notifyListeners();
  }
}
