import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MotionActivityUpdate {
  const MotionActivityUpdate({
    required this.activity,
    required this.confidence,
    required this.timestampMs,
    required this.source,
    this.raw,
  });

  final String activity;
  final int confidence;
  final int timestampMs;
  final String source;
  final Map<String, dynamic>? raw;

  factory MotionActivityUpdate.fromMap(Map<dynamic, dynamic> map) {
    return MotionActivityUpdate(
      activity: (map['activity'] ?? 'unknown').toString(),
      confidence: _asInt(map['confidence']),
      timestampMs: _asInt(map['timestampMs']),
      source: (map['source'] ?? 'unknown').toString(),
      raw: map['raw'] is Map
          ? Map<String, dynamic>.from(map['raw'] as Map)
          : null,
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class MotionActivityService {
  MotionActivityService._();

  static const MethodChannel _methods = MethodChannel(
    'com.smartnps360.app/motion_activity',
  );
  static const EventChannel _events = EventChannel(
    'com.smartnps360.app/motion_activity_events',
  );

  static StreamSubscription<dynamic>? _subscription;
  static final StreamController<MotionActivityUpdate> _controller =
      StreamController<MotionActivityUpdate>.broadcast();

  static bool _listening = false;
  static MotionActivityUpdate? _lastUpdate;

  static MotionActivityUpdate? get lastUpdate => _lastUpdate;

  static Stream<MotionActivityUpdate> get stream => _controller.stream;

  static Future<bool> isAvailable() async {
    try {
      final result = await _methods.invokeMethod<dynamic>('isAvailable');
      return result == true;
    } on MissingPluginException {
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MotionActivity] isAvailable failed: $e');
      }
      return false;
    }
  }

  static Future<String> checkPermission() async {
    try {
      final result = await _methods.invokeMethod<dynamic>('checkPermission');
      return result?.toString() ?? 'unknown';
    } on MissingPluginException {
      return 'unavailable';
    } catch (_) {
      return 'unknown';
    }
  }

  static Future<String> requestPermission() async {
    try {
      final result = await _methods.invokeMethod<dynamic>('requestPermission');
      return result?.toString() ?? 'unknown';
    } on MissingPluginException {
      return 'unavailable';
    } catch (_) {
      return 'unknown';
    }
  }

  static Future<Map<String, dynamic>> start() async {
    await _ensureEventSubscription();
    try {
      final result = await _methods.invokeMethod<dynamic>('start');
      return _asMap(result);
    } on MissingPluginException {
      return {
        'ok': false,
        'running': false,
        'error': {
          'code': 'missing_plugin',
          'message': 'Motion activity native channel is unavailable',
        },
      };
    } catch (e) {
      return {
        'ok': false,
        'running': false,
        'error': {'code': 'start_failed', 'message': e.toString()},
      };
    }
  }

  static Future<void> stop() async {
    try {
      await _methods.invokeMethod<dynamic>('stop');
    } on MissingPluginException {
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MotionActivity] stop failed: $e');
      }
    }
    await _cancelEventSubscription();
  }

  static Future<bool> isRunning() async {
    try {
      final result = await _methods.invokeMethod<dynamic>('isRunning');
      final map = _asMap(result);
      return map['running'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<MotionActivityUpdate?> queryLatest() async {
    try {
      final result = await _methods.invokeMethod<dynamic>('queryLatest');
      final map = _asMap(result);
      final updateRaw = map['update'];
      if (updateRaw is Map) {
        final update = MotionActivityUpdate.fromMap(updateRaw);
        _publish(update);
        return update;
      }
      return _lastUpdate;
    } on MissingPluginException {
      return _lastUpdate;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MotionActivity] queryLatest failed: $e');
      }
      return _lastUpdate;
    }
  }

  static void _publish(MotionActivityUpdate update) {
    _lastUpdate = update;
    if (!_controller.isClosed) {
      _controller.add(update);
    }
  }

  static Future<void> _ensureEventSubscription() async {
    if (_listening) return;
    _listening = true;
    _subscription = _events.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          _publish(MotionActivityUpdate.fromMap(event));
        }
      },
      onError: (Object error) {
        if (kDebugMode) {
          debugPrint('[MotionActivity] stream error: $error');
        }
      },
      cancelOnError: false,
    );
  }

  static Future<void> _cancelEventSubscription() async {
    await _subscription?.cancel();
    _subscription = null;
    _listening = false;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }
}
