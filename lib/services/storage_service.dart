import 'package:hive_flutter/hive_flutter.dart';
import '../models/session.dart';
import '../models/location_point.dart';

class StorageService {
  static const _sessionBoxName = 'sessions';

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(LocationPointAdapter());
    Hive.registerAdapter(SessionAdapter());
    await Hive.openBox<Session>(_sessionBoxName);
    await Hive.openBox('settings');
  }

  static Box<Session> get _box => Hive.box<Session>(_sessionBoxName);

  static Future<void> saveSession(Session session) async {
    await _box.put(session.id, session);
  }

  static List<Session> getAllSessions() {
    final sessions = _box.values.toList();
    sessions.sort((a, b) => b.startTime.compareTo(a.startTime));
    return sessions;
  }

  static Future<void> deleteSession(String id) async {
    await _box.delete(id);
  }

  static Session? getSession(String id) {
    return _box.get(id);
  }
}
