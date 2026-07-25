import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Snapshot of the most recent native motion activity update.
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

/// Dart bridge for native Core Motion / Activity Recognition channels.
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

  /// Broadcast stream of activity updates. Subscribe after [start].
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

  /// iOS: triggers the Motion & Fitness system prompt when needed.
  /// Android: returns current status (runtime prompt via permission_handler).
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

  static Future<void> _ensureEventSubscription() async {
    if (_listening) return;
    _listening = true;
    _subscription = _events.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          _controller.add(MotionActivityUpdate.fromMap(event));
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
