import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AndroidDutyLocationHealth {
  AndroidDutyLocationHealth._();

  static const Duration staleThreshold = Duration(minutes: 2);
  static const int maxSoftRecoverBeforeHardRestart = 2;
  static const String uploadEvent = 'duty_location_upload';
  static const String startedEvent = 'duty_location_started';

  static const String _prefsLastUploadMs = 'duty.android.last_upload_ms';
  static const String _prefsStartedMs = 'duty.android.started_ms';

  static DateTime? _startedAt;
  static DateTime? _lastUploadAt;
  static int _softRecoverAttempts = 0;
  static StreamSubscription<Map<String, dynamic>?>? _uploadSub;
  static StreamSubscription<Map<String, dynamic>?>? _startedSub;

  static DateTime? get startedAt => _startedAt;
  static DateTime? get lastUploadAt => _lastUploadAt;
  static int get softRecoverAttempts => _softRecoverAttempts;
  static bool get shouldHardRestart =>
      _softRecoverAttempts >= maxSoftRecoverBeforeHardRestart;

  static void noteSoftRecoverAttempted() {
    _softRecoverAttempts++;
  }

  static void resetRecoverAttempts() {
    _softRecoverAttempts = 0;
  }

  static void ensureListenerInstalled() {
    if (!Platform.isAndroid) return;

    _startedSub ??= FlutterBackgroundService().on(startedEvent).listen((event) {
      final at = _parseAt(event) ?? DateTime.now();
      markStarted(at: at);
      unawaited(persistStarted(at));
      if (kDebugMode) {
        debugPrint('[DutyLocation] Android FGS started event received');
      }
    });

    _uploadSub ??= FlutterBackgroundService().on(uploadEvent).listen((event) {
      final at = _parseAt(event) ?? DateTime.now();
      markUpload(at: at);
    });
  }

  static DateTime? _parseAt(Map<String, dynamic>? event) {
    final raw = event?['at']?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static void markStarted({DateTime? at}) {
    _startedAt = at ?? DateTime.now();
    _lastUploadAt = null;
    resetRecoverAttempts();
  }

  static void markUpload({DateTime? at}) {
    _lastUploadAt = at ?? DateTime.now();
    resetRecoverAttempts();
  }

  static void markStopped() {
    _startedAt = null;
    _lastUploadAt = null;
    resetRecoverAttempts();
    unawaited(clearPersisted());
  }

  static Future<void> persistStarted(DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsStartedMs, at.millisecondsSinceEpoch);
      await prefs.remove(_prefsLastUploadMs);
    } catch (_) {}
  }

  static Future<void> persistUpload(DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsLastUploadMs, at.millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<void> clearPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsLastUploadMs);
      await prefs.remove(_prefsStartedMs);
    } catch (_) {}
  }

  static Future<void> hydrateFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final uploadMs = prefs.getInt(_prefsLastUploadMs);
      final startedMs = prefs.getInt(_prefsStartedMs);
      if (uploadMs != null && uploadMs > 0) {
        final uploadAt = DateTime.fromMillisecondsSinceEpoch(uploadMs);
        if (_lastUploadAt == null || uploadAt.isAfter(_lastUploadAt!)) {
          _lastUploadAt = uploadAt;
        }
      }
      if (startedMs != null && startedMs > 0) {
        final startedAt = DateTime.fromMillisecondsSinceEpoch(startedMs);
        if (_startedAt == null || startedAt.isAfter(_startedAt!)) {
          _startedAt = startedAt;
        }
      }
    } catch (_) {}
  }

  static Future<bool> computeNeedsRecovery() async {
    if (!Platform.isAndroid) return false;
    await hydrateFromPrefs();

    final last = _lastUploadAt;
    if (last != null) {
      return DateTime.now().difference(last) > staleThreshold;
    }

    final started = _startedAt;
    if (started != null) {
      return DateTime.now().difference(started) > staleThreshold;
    }

    return false;
  }
}
