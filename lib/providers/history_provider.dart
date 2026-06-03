import 'package:flutter/foundation.dart';
import '../models/session.dart';
import '../services/storage_service.dart';

class HistoryProvider extends ChangeNotifier {
  List<Session> _sessions = [];

  List<Session> get sessions => _sessions;

  void load() {
    _sessions = StorageService.getAllSessions();
    notifyListeners();
  }

  Future<void> deleteSession(String id) async {
    await StorageService.deleteSession(id);
    load();
  }
}
