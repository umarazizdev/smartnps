import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_debug_logger.dart';

class ApiResponseDebugLogger extends ChangeNotifier {
  ApiResponseDebugLogger._();

  static final ApiResponseDebugLogger instance = ApiResponseDebugLogger._();

  static const int maxEntries = 80;
  static const int maxBodyChars = 6000;
  static const int maxAppendsPerSecond = 8;

  static const String _prefsEntriesKey = 'api_response_debug_entries_v1';
  static const String _prefsEndsAtKey = 'api_response_debug_ends_at_ms_v1';
  static const String _prefsTargetsKey = 'api_response_debug_targets_v1';

  final List<String> _entries = <String>[];
  final Set<SessionDebugApiSuccessTarget> _targets =
      <SessionDebugApiSuccessTarget>{SessionDebugApiSuccessTarget.all};
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

  Set<SessionDebugApiSuccessTarget> get targets =>
      Set<SessionDebugApiSuccessTarget>.unmodifiable(_targets);

  String get targetsLabel {
    if (_targets.isEmpty ||
        _targets.contains(SessionDebugApiSuccessTarget.all)) {
      return SessionDebugApiSuccessTarget.all.label;
    }
    return _targets.map((t) => t.label).join(', ');
  }

  List<String> get entries => List<String>.unmodifiable(_entries);

  bool shouldCapture(Uri uri) {
    _syncExpired();
    if (!isRunning) return false;
    if (_targets.isEmpty ||
        _targets.contains(SessionDebugApiSuccessTarget.all)) {
      return true;
    }
    for (final target in _targets) {
      if (target.matches(uri)) return true;
    }
    return false;
  }

  Future<void> ensureReady() async {
    if (_ready) {
      _syncExpired();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefsEntriesKey) ?? const <String>[];
    _entries
      ..clear()
      ..addAll(stored.take(maxEntries));

    final endsMs = prefs.getInt(_prefsEndsAtKey);
    if (endsMs != null && endsMs > 0) {
      _endsAt = DateTime.fromMillisecondsSinceEpoch(endsMs);
    }

    final targetIds =
        prefs.getStringList(_prefsTargetsKey) ?? const <String>[];
    _targets
      ..clear()
      ..addAll(_normalizeTargets(
        targetIds
            .map(SessionDebugApiSuccessTarget.tryParse)
            .whereType<SessionDebugApiSuccessTarget>(),
      ));

    _ready = true;
    _syncExpired();
    _armExpireTimer();
    _safeNotifyListeners();
  }

  Future<void> start({
    required Set<SessionDebugApiSuccessTarget> targets,
    required Duration duration,
  }) async {
    await ensureReady();
    if (duration <= Duration.zero) return;

    _targets
      ..clear()
      ..addAll(_normalizeTargets(targets));
    _endsAt = DateTime.now().add(duration);
    await _persistMeta();
    _armExpireTimer();
    unawaited(
      _appendEntry(
        _formatSessionLine(
          'started targets=${_targets.map((t) => t.id).join('+')} '
          'duration=${duration.inMinutes}m',
        ),
        persist: true,
      ),
    );
    _safeNotifyListeners();
  }

  Future<void> stop({String reason = 'stopped'}) async {
    await ensureReady();
    if (_endsAt == null && _targets.isEmpty) return;
    final wasRunning = isRunning;
    _endsAt = null;
    _expireTimer?.cancel();
    _expireTimer = null;
    await _persistMeta();
    if (wasRunning) {
      await _appendEntry(
        _formatSessionLine('session $reason'),
        persist: true,
      );
    }
    _safeNotifyListeners();
  }

  Future<void> clearEntries() async {
    await ensureReady();
    _entries.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsEntriesKey);
    _safeNotifyListeners();
  }

  void capture({
    required String method,
    required Uri uri,
    required int? statusCode,
    dynamic body,
    String? error,
  }) {
    if (!_ready) {
      unawaited(
        _ensureReadyThenCapture(
          method: method,
          uri: uri,
          statusCode: statusCode,
          body: body,
          error: error,
        ),
      );
      return;
    }
    if (!shouldCapture(uri)) return;
    if (!_allowAppend()) return;

    final path = uri.path.isEmpty ? '/' : uri.path;
    final code = statusCode ?? 0;
    final buffer = StringBuffer()
      ..writeln(
        '${DateTime.now().toUtc().toIso8601String()} '
        '${method.toUpperCase()} $path status=$code',
      );

    final errorText = error?.trim();
    if (errorText != null && errorText.isNotEmpty) {
      buffer.writeln('error=${_sanitize(errorText, maxChars: 400)}');
    }

    final rendered = _renderBody(body);
    if (rendered == null) {
      buffer.writeln('body=<empty>');
    } else {
      buffer.writeln('body:');
      buffer.writeln(rendered);
    }

    unawaited(_appendEntry(buffer.toString().trimRight(), persist: true));
  }

  String toCopyText() {
    final buffer = StringBuffer()
      ..writeln('running=$isRunning')
      ..writeln('remaining=${remaining.inSeconds}s')
      ..writeln('targets=${_targets.map((t) => t.id).join(',')}')
      ..writeln('--- responses (${_entries.length}) ---');
    for (var i = 0; i < _entries.length; i++) {
      if (i > 0) buffer.writeln('---');
      buffer.writeln(_entries[i]);
    }
    return buffer.toString();
  }

  Future<void> _ensureReadyThenCapture({
    required String method,
    required Uri uri,
    required int? statusCode,
    dynamic body,
    String? error,
  }) async {
    await ensureReady();
    capture(
      method: method,
      uri: uri,
      statusCode: statusCode,
      body: body,
      error: error,
    );
  }

  void _syncExpired() {
    final ends = _endsAt;
    if (ends == null) return;
    if (DateTime.now().isBefore(ends)) return;
    _endsAt = null;
    _expireTimer?.cancel();
    _expireTimer = null;
    unawaited(_persistMeta());
    unawaited(
      _appendEntry(
        _formatSessionLine('session auto-stopped (timer elapsed)'),
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
      _safeNotifyListeners();
      return;
    }
    _expireTimer = Timer(wait, () {
      _syncExpired();
      _safeNotifyListeners();
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

  Future<void> _appendEntry(String entry, {required bool persist}) async {
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    _safeNotifyListeners();
    if (!persist) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsEntriesKey, List<String>.from(_entries));
    } catch (_) {}
  }

  void _safeNotifyListeners() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString().toLowerCase();
      if (text.contains('lookup failed:') ||
          text.contains("is not a subtype of type 'state<") ||
          text.contains('is not a subtype of type \'state<') ||
          text.contains('ext.flutter.reassemble')) {
        return;
      }
      previous?.call(details);
    };
    try {
      notifyListeners();
    } finally {
      FlutterError.onError = previous;
    }
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
      await prefs.setStringList(
        _prefsTargetsKey,
        _targets.map((t) => t.id).toList(growable: false),
      );
    } catch (_) {}
  }

  static String _formatSessionLine(String message) {
    return '${DateTime.now().toUtc().toIso8601String()} [session] $message';
  }

  static Set<SessionDebugApiSuccessTarget> _normalizeTargets(
    Iterable<SessionDebugApiSuccessTarget> raw,
  ) {
    final targets = raw.toSet();
    if (targets.isEmpty ||
        targets.contains(SessionDebugApiSuccessTarget.all)) {
      return <SessionDebugApiSuccessTarget>{
        SessionDebugApiSuccessTarget.all,
      };
    }
    return targets;
  }

  static String? _renderBody(dynamic body) {
    if (body == null) return null;
    if (body is String) {
      final trimmed = body.trim();
      if (trimmed.isEmpty) return null;
      return _sanitize(trimmed);
    }
    if (body is List<int>) {
      return _sanitize('<binary ${body.length} bytes>');
    }
    try {
      final encoded = const JsonEncoder.withIndent('  ').convert(body);
      return _sanitize(encoded);
    } catch (_) {
      return _sanitize(body.toString());
    }
  }

  static String _sanitize(String raw, {int maxChars = maxBodyChars}) {
    var text = raw.replaceAll('\r\n', '\n');
    text = text.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9\-._~+/]+=*', caseSensitive: false),
      'Bearer ***',
    );
    text = text.replaceAll(
      RegExp(
        r'(access[_-]?token|refresh[_-]?token|password|authorization|'
        r'push[_-]?token)\s*[:=]\s*[^,\s}]+',
        caseSensitive: false,
      ),
      r'$1=***',
    );
    if (text.length > maxChars) {
      text = '${text.substring(0, maxChars)}…';
    }
    return text;
  }
}
