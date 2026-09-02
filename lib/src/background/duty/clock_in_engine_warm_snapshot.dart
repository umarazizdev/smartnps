import 'package:shared_preferences/shared_preferences.dart';

import '../../utilities/app_debug_log.dart';

class ClockInEngineWarmSnapshot {
  ClockInEngineWarmSnapshot._();

  static const String _prefsKeyMs = 'duty.android.clockin_warm_pending_ms';
  static const Duration ttl = Duration(minutes: 4);

  static Future<void> markPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKeyMs, DateTime.now().millisecondsSinceEpoch);
      locationDebugLog('[DutyLocation] clock-in FGS warm pending marked');
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKeyMs);
    } catch (_) {}
  }

  static Future<bool> isValidPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final ms = prefs.getInt(_prefsKeyMs);
      if (ms == null || ms <= 0) return false;
      final markedAt = DateTime.fromMillisecondsSinceEpoch(ms);
      if (DateTime.now().difference(markedAt) > ttl) {
        await clear();
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
