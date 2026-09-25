import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Temporary, button-gated debug capture for the Debug Env screen.
///
/// Default OFF. Writes only while [isRunning], only for selected categories,
/// with a hard line cap and rate limit so it stays light.
class SessionDebugLogger extends ChangeNotifier {
  SessionDebugLogger._();

  static final SessionDebugLogger instance = SessionDebugLogger._();

  static const int maxLogs = 150;
  static const int maxMessageChars = 280;
  static const int maxAppendsPerSecond = 5;

  static const String _prefsLogsKey = 'session_debug_logs_v1';
  static const String _prefsEndsAtKey = 'session_debug_ends_at_ms_v1';
  static const String _prefsCategoriesKey = 'session_debug_categories_v1';

  /// Read by Flutter prefs; native gate uses MethodChannel sync instead.
  static const String killCapturePrefsKey = 'session_debug_kill_capture_v1';

  static const MethodChannel _settingsChannel = MethodChannel(
    'com.smartnps360.app/settings',
  );

  final List<String> _logs = <String>[];
  final Set<SessionDebugCategory> _categories = <SessionDebugCategory>{};
  DateTime? _endsAt;
  bool _ready = false;
  int _appendsThisSecond = 0;
  int _rateWindowSecond = 0;
  Timer? _expireTimer;

  bool get isReady => _ready;
  bool get isRunning {
    final ends = _endsAt;
    if (ends == null) return false;
    return DateTime.now().isBefore(ends);
  }

  DateTime? get endsAt => _endsAt;

  Duration get remaining {
    final ends = _endsAt;
    if (ends == null) return Duration.zero;
    final left = ends.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  Set<SessionDebugCategory> get categories =>
      Set<SessionDebugCategory>.unmodifiable(_categories);

  List<String> get logs => List<String>.unmodifiable(_logs);

  /// True only while Run is active and [category] is selected.
  bool isCategoryActive(SessionDebugCategory category) {
    _syncExpired();
    return isRunning && _categories.contains(category);
  }

  Future<void> ensureReady() async {
    if (_ready) {
      _syncExpired();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefsLogsKey) ?? const <String>[];
    _logs
      ..clear()
      ..addAll(stored.take(maxLogs));

    final endsMs = prefs.getInt(_prefsEndsAtKey);
    if (endsMs != null && endsMs > 0) {
      _endsAt = DateTime.fromMillisecondsSinceEpoch(endsMs);
    }
    final cats = prefs.getStringList(_prefsCategoriesKey) ?? const <String>[];
    _categories
      ..clear()
      ..addAll(
        cats
            .map(SessionDebugCategory.tryParse)
            .whereType<SessionDebugCategory>(),
      );

    _ready = true;
    _syncExpired();
    _armExpireTimer();
    notifyListeners();
  }

  Future<void> start({
    required Set<SessionDebugCategory> categories,
    required Duration duration,
  }) async {
    await ensureReady();
    if (categories.isEmpty || duration <= Duration.zero) return;

    _categories
      ..clear()
      ..addAll(categories);
    _endsAt = DateTime.now().add(duration);
    await _persistMeta();
    _armExpireTimer();
    unawaited(
      _appendLine(
        _formatLine(
          'session',
          'started categories=${categories.map((c) => c.id).join(',')} '
          'duration=${duration.inMinutes}m',
        ),
        persist: true,
      ),
    );
    notifyListeners();
  }

  Future<void> stop({String reason = 'stopped'}) async {
    await ensureReady();
    if (_endsAt == null && _categories.isEmpty) return;
    final wasRunning = isRunning;
    _endsAt = null;
    _categories.clear();
    _expireTimer?.cancel();
    _expireTimer = null;
    await _persistMeta();
    if (wasRunning) {
      await _appendLine(
        _formatLine('session', 'session $reason'),
        persist: true,
      );
    }
    notifyListeners();
  }

  Future<void> clearLogs() async {
    await ensureReady();
    _logs.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsLogsKey);
    notifyListeners();
  }

  /// No-op unless a session is running and [category] is selected.
  void log(SessionDebugCategory category, String message) {
    if (!_ready) {
      unawaited(_ensureReadyThenLog(category, message));
      return;
    }
    _syncExpired();
    if (!isRunning || !_categories.contains(category)) return;

    final cleaned = _sanitize(message);
    if (cleaned.isEmpty) return;
    if (!_allowAppend()) return;

    final line = _formatLine(category.id, cleaned);
    unawaited(_appendLine(line, persist: true));
  }

  /// Forwards noisy helpers only when the message looks like a failure.
  void logIfErrorLike(SessionDebugCategory category, String message) {
    if (!_looksLikeError(message)) return;
    log(category, message);
  }

  String toCopyText() {
    final buffer = StringBuffer()
      ..writeln('running=$isRunning')
      ..writeln('remaining=${remaining.inSeconds}s')
      ..writeln(
        'categories=${_categories.map((c) => c.id).join(',')}',
      )
      ..writeln('--- logs (${_logs.length}) ---');
    for (final line in _logs) {
      buffer.writeln(line);
    }
    return buffer.toString();
  }

  Future<void> _ensureReadyThenLog(
    SessionDebugCategory category,
    String message,
  ) async {
    await ensureReady();
    log(category, message);
  }

  void _syncExpired() {
    final ends = _endsAt;
    if (ends == null) return;
    if (DateTime.now().isBefore(ends)) return;
    _endsAt = null;
    _categories.clear();
    _expireTimer?.cancel();
    _expireTimer = null;
    unawaited(_persistMeta());
    unawaited(
      _appendLine(
        _formatLine('session', 'session auto-stopped (timer elapsed)'),
        persist: true,
      ),
    );
  }

  void _armExpireTimer() {
    _expireTimer?.cancel();
    _expireTimer = null;
    final ends = _endsAt;
    if (ends == null) return;
    final wait = ends.difference(DateTime.now());
    if (wait.isNegative) {
      _syncExpired();
      notifyListeners();
      return;
    }
    _expireTimer = Timer(wait, () {
      _syncExpired();
      notifyListeners();
    });
  }

  bool _allowAppend() {
    final second = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (second != _rateWindowSecond) {
      _rateWindowSecond = second;
      _appendsThisSecond = 0;
    }
    if (_appendsThisSecond >= maxAppendsPerSecond) return false;
    _appendsThisSecond += 1;
    return true;
  }

  Future<void> _appendLine(String line, {required bool persist}) async {
    _logs.add(line);
    if (_logs.length > maxLogs) {
      _logs.removeRange(0, _logs.length - maxLogs);
    }
    notifyListeners();
    if (!persist) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsLogsKey, List<String>.from(_logs));
    } catch (_) {}
  }

  Future<void> _persistMeta() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ends = _endsAt;
      if (ends == null) {
        await prefs.remove(_prefsEndsAtKey);
      } else {
        await prefs.setInt(_prefsEndsAtKey, ends.millisecondsSinceEpoch);
      }
      if (_categories.isEmpty) {
        await prefs.remove(_prefsCategoriesKey);
      } else {
        await prefs.setStringList(
          _prefsCategoriesKey,
          _categories.map((c) => c.id).toList(growable: false),
        );
      }
      final killCapture =
          ends != null &&
          DateTime.now().isBefore(ends) &&
          _categories.contains(SessionDebugCategory.kill);
      await prefs.setBool(killCapturePrefsKey, killCapture);
      try {
        await _settingsChannel.invokeMethod<dynamic>(
          'setKillDebugCaptureEnabled',
          {'enabled': killCapture},
        );
      } catch (_) {}
    } catch (_) {}
  }

  static String _formatLine(String category, String message) {
    final stamp = DateTime.now().toUtc().toIso8601String();
    return '$stamp [$category] $message';
  }

  static String _sanitize(String raw) {
    var text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return '';
    text = text.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9\-._~+/]+=*', caseSensitive: false),
      'Bearer ***',
    );
    text = text.replaceAll(
      RegExp(
        r'(access[_-]?token|refresh[_-]?token|password|authorization)\s*[:=]\s*[^,\s}]+',
        caseSensitive: false,
      ),
      r'$1=***',
    );
    if (text.length > maxMessageChars) {
      text = '${text.substring(0, maxMessageChars)}…';
    }
    return text;
  }

  static bool _looksLikeError(String message) {
    final lower = message.toLowerCase();
    const needles = <String>[
      'error',
      'fail',
      'exception',
      'denied',
      'timeout',
      'unable',
      'missing',
      'reject',
      'crash',
      'invalid',
    ];
    for (final n in needles) {
      if (lower.contains(n)) return true;
    }
    return false;
  }
}

enum SessionDebugCategory {
  apiErrors('api'),
  uploads('uploads'),
  duty('duty'),
  permissions('permissions'),
  kill('kill');

  const SessionDebugCategory(this.id);

  final String id;

  String get label => switch (this) {
        SessionDebugCategory.apiErrors => 'API errors',
        SessionDebugCategory.uploads => 'Uploads',
        SessionDebugCategory.duty => 'Duty',
        SessionDebugCategory.permissions => 'Permissions',
        SessionDebugCategory.kill => 'Kill cycle',
      };

  static SessionDebugCategory? tryParse(String raw) {
    final id = raw.trim().toLowerCase();
    for (final value in SessionDebugCategory.values) {
      if (value.id == id) return value;
    }
    return null;
  }
}

/// Preset run durations for the Debug Env screen.
enum SessionDebugDuration {
  oneMinute(Duration(minutes: 1), '1 min'),
  fiveMinutes(Duration(minutes: 5), '5 min'),
  fifteenMinutes(Duration(minutes: 15), '15 min');

  const SessionDebugDuration(this.duration, this.label);

  final Duration duration;
  final String label;
}
