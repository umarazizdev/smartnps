import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'motion_activity_service.dart';
import 'vehicle_session_fusion.dart';

class MotionActivityFusionController {
  MotionActivityFusionController._();

  static final MotionActivityFusionController instance =
      MotionActivityFusionController._();

  static const _prefsActivityKey = 'motion_fusion_native_activity';
  static const _prefsConfidenceKey = 'motion_fusion_native_confidence';
  static const _prefsTimestampKey = 'motion_fusion_native_ts_ms';

  static const _nativePrefsTtlMs = 25000;

  final VehicleSessionFusion fusion = VehicleSessionFusion();

  StreamSubscription<MotionActivityUpdate>? _motionSub;
  MotionActivityUpdate? _lastNative;
  VehicleSessionSnapshot? lastSnapshot;
  bool _started = false;
  bool _starting = false;
  int _refCount = 0;

  MotionActivityUpdate? get lastNative => _lastNative;

  Future<void> acquire() async {
    _refCount++;
    await ensureStarted();
  }

  Future<void> release() async {
    if (_refCount > 0) _refCount--;
    if (_refCount == 0) {
      await stop();
    }
  }

  Future<void> ensureStarted() async {
    if (_started || _starting) return;
    _starting = true;
    try {
      final available = await MotionActivityService.isAvailable();
      if (!available) {
        if (kDebugMode) {
          debugPrint(
            '[MotionFusion] native motion unavailable — GPS-only fusion',
          );
        }
        _started = true;
        return;
      }

      await _motionSub?.cancel();
      _motionSub = MotionActivityService.stream.listen(_onNativeUpdate);

      final start = await MotionActivityService.start();
      if (start['ok'] == true) {
        if (kDebugMode) {
          debugPrint('[MotionFusion] native motion started');
        }

        await MotionActivityService.queryLatest();
      } else if (kDebugMode) {
        debugPrint('[MotionFusion] native start failed: $start');
      }
      _started = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MotionFusion] ensureStarted error: $e');
      }
      _started = true;
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    await _motionSub?.cancel();
    _motionSub = null;
    try {
      await MotionActivityService.stop();
    } catch (_) {}
    fusion.reset();
    lastSnapshot = null;
    _lastNative = null;
    _started = false;
    _starting = false;
  }

  void _onNativeUpdate(MotionActivityUpdate update) {
    _lastNative = update;
    unawaited(_persistNative(update));
    lastSnapshot = fusion.evaluate(
      nativeActivity: update.activity,
      nativeConfidence: update.confidence,
      gpsSpeedKmh: lastSnapshot?.gpsSpeedKmh ?? lastSnapshot?.smoothedSpeedKmh,
    );
  }

  Future<void> _persistNative(MotionActivityUpdate update) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = update.timestampMs > 0
          ? update.timestampMs
          : DateTime.now().millisecondsSinceEpoch;
      await prefs.setString(_prefsActivityKey, update.activity);
      await prefs.setInt(_prefsConfidenceKey, update.confidence);
      await prefs.setInt(_prefsTimestampKey, ts);
    } catch (_) {}
  }

  Future<({String activity, int confidence})> _readPersistedNative() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final activity = prefs.getString(_prefsActivityKey) ?? 'unknown';
      final confidence = prefs.getInt(_prefsConfidenceKey) ?? 0;
      final ts = prefs.getInt(_prefsTimestampKey) ?? 0;
      if (ts > 0) {
        final ageMs = DateTime.now().millisecondsSinceEpoch - ts;
        if (ageMs > _nativePrefsTtlMs) {
          return (activity: 'unknown', confidence: 0);
        }
      }
      return (activity: activity, confidence: confidence);
    } catch (_) {
      return (activity: 'unknown', confidence: 0);
    }
  }

  Future<VehicleSessionSnapshot> evaluatePosition(Position position) async {
    await ensureStarted();

    var activity = _lastNative?.activity ?? 'unknown';
    var confidence = _lastNative?.confidence ?? 0;

    if (activity == 'unknown' || _lastNative == null) {
      final persisted = await _readPersistedNative();
      if (persisted.activity != 'unknown') {
        activity = persisted.activity;
        confidence = persisted.confidence;
      }
    }

    final speedMps = position.speed;
    final speedKmh = (speedMps.isFinite && speedMps >= 0)
        ? speedMps * 3.6
        : null;

    final snapshot = fusion.evaluate(
      nativeActivity: activity,
      nativeConfidence: confidence,
      gpsSpeedKmh: speedKmh,
    );
    lastSnapshot = snapshot;
    return snapshot;
  }

  VehicleSessionSnapshot evaluateRaw({
    required String nativeActivity,
    required int nativeConfidence,
    double? gpsSpeedKmh,
  }) {
    final snapshot = fusion.evaluate(
      nativeActivity: nativeActivity,
      nativeConfidence: nativeConfidence,
      gpsSpeedKmh: gpsSpeedKmh,
    );
    lastSnapshot = snapshot;
    return snapshot;
  }
}
