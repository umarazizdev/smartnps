import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../../utilities/app_debug_log.dart';

class IosSignificantLocationChangeService {
  IosSignificantLocationChangeService._();

  static const MethodChannel _channel = MethodChannel(
    'com.smartnps360.app/ios_slc',
  );
  static const EventChannel _events = EventChannel(
    'com.smartnps360.app/ios_slc_events',
  );

  static StreamSubscription<dynamic>? _subscription;
  static Future<void> Function(Position position, String source)? _onLocation;
  static Future<void> Function()? _onLocationWake;
  static bool _nativeCallHandlerInstalled = false;
  static bool _nativeMonitoring = false;

  static bool get isMonitoring => _nativeMonitoring;

  static Future<void> claimWake() async {
    if (!Platform.isIOS) return;
    if (!await _ensureNativeChannelsReady()) return;
    try {
      await _channel.invokeMethod<dynamic>('claimWakeUpload');
    } on MissingPluginException catch (e) {
      locationDebugLog('[IosSLC] claimWake skipped: $e');
    }
  }

  static Future<void> syncNativeAuth({
    String? accessToken,
    String? refreshToken,
    String? deviceId,
    bool clear = false,
  }) async {
    if (!Platform.isIOS) return;
    if (!await _ensureNativeChannelsReady()) return;
    try {
      await _channel.invokeMethod<dynamic>('syncAuthSession', {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'deviceId': deviceId,
        'clear': clear,
      });
    } on MissingPluginException catch (e) {
      locationDebugLog('[IosSLC] syncAuthSession skipped: $e');
    }
  }

  static void setOnLocationWake(Future<void> Function() handler) {
    _onLocationWake = handler;
    _installNativeCallHandler();
  }

  static void _installNativeCallHandler() {
    if (_nativeCallHandlerInstalled) return;
    _nativeCallHandlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLocationWake') {
        unawaited(_onLocationWake?.call() ?? Future<void>.value());
        return true;
      }
    });
  }

  static Future<bool> ensureNativeReady({int maxAttempts = 20}) {
    return _ensureNativeChannelsReady(maxAttempts: maxAttempts);
  }

  static Future<void> setOnDuty(bool onDuty) async {
    if (!Platform.isIOS) return;
    if (!await _ensureNativeChannelsReady()) return;
    try {
      await _channel.invokeMethod<dynamic>('setOnDuty', {'onDuty': onDuty});
      if (!onDuty) {
        await setUnpaidBreak(false);
      }
    } on MissingPluginException catch (e) {
      locationDebugLog(
        '[IosSLC] setOnDuty skipped; native channel unavailable: $e',
      );
    }
  }

  static Future<void> setUnpaidBreak(bool unpaid) async {
    if (!Platform.isIOS) return;
    if (!await _ensureNativeChannelsReady()) return;
    try {
      await _channel.invokeMethod<dynamic>('setUnpaidBreak', {
        'unpaid': unpaid,
      });
    } on MissingPluginException catch (e) {
      locationDebugLog(
        '[IosSLC] setUnpaidBreak skipped; native channel unavailable: $e',
      );
    }
  }

  static Future<void> armForUnpaidBreak() async {
    if (!Platform.isIOS) return;
    if (!await _ensureNativeChannelsReady()) return;
    await setOnDuty(true);
    await setUnpaidBreak(true);
    await _ensureEventSubscription();
    try {
      final result = await _invokeMap('startMonitoring');
      _nativeMonitoring = result['running'] == true;
      locationDebugLog(
        '[IosSLC] armForUnpaidBreak running=$_nativeMonitoring '
        'unpaid=${result['unpaidBreak'] == true}',
      );
    } catch (e) {
      locationDebugLog('[IosSLC] armForUnpaidBreak failed: $e');
    }
  }

  static Future<Map<String, dynamic>> start({
    required Future<void> Function(Position position, String source) onLocation,
  }) async {
    if (!Platform.isIOS) return {'ok': true, 'running': false};

    _onLocation = onLocation;

    if (!await _ensureNativeChannelsReady()) {
      return {
        'ok': false,
        'running': false,
        'error': {
          'code': 'missing_plugin',
          'message': 'iOS SLC native channel is unavailable',
        },
      };
    }

    await setOnDuty(true);
    await _ensureEventSubscription();

    final result = await _invokeMap('startMonitoring');
    _nativeMonitoring = result['running'] == true;

    await drainPendingLocations();
    return result;
  }

  static Future<void> drainPendingLocations() async {
    if (!Platform.isIOS) return;
    final List<dynamic>? pending;
    try {
      pending = await _channel.invokeMethod<List<dynamic>>(
        'drainPendingLocations',
      );
    } on MissingPluginException catch (e) {
      locationDebugLog(
        '[IosSLC] drain skipped; native channel unavailable: $e',
      );
      return;
    }
    if (pending == null || pending.isEmpty) return;

    for (final payload in pending) {
      await _handlePayload(payload);
    }
  }

  static Future<Map<String, dynamic>> status() async {
    if (!Platform.isIOS) return {'ok': true, 'running': false};
    final result = await _invokeMap('isMonitoring');
    _nativeMonitoring = result['running'] == true;
    return result;
  }

  static Future<void> stop({
    bool drainPending = false,
    bool clearOnDuty = true,
  }) async {
    if (!Platform.isIOS) return;

    if (drainPending) {
      await drainPendingLocations();
    }

    try {
      await _channel.invokeMethod<dynamic>('stopMonitoring');
    } catch (e) {
      locationDebugLog('[IosSLC] stop failed: $e');
    }

    if (clearOnDuty) {
      await setOnDuty(false);
    }

    await _subscription?.cancel();
    _subscription = null;
    _onLocation = null;
    _nativeMonitoring = false;
  }

  static Future<bool> _ensureNativeChannelsReady({int maxAttempts = 15}) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await _channel.invokeMethod<dynamic>('isMonitoring');
        return true;
      } on MissingPluginException {
        if (attempt == maxAttempts - 1) break;
        await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
      }
    }
    return false;
  }

  static Future<void> _ensureEventSubscription() async {
    if (_subscription != null) return;

    try {
      _subscription = _events.receiveBroadcastStream().listen(
        (event) {
          unawaited(_handlePayload(event));
        },
        onError: (Object error) {
          locationDebugLog('[IosSLC] event stream error: $error');
        },
      );
    } on MissingPluginException catch (e) {
      locationDebugLog('[IosSLC] event stream unavailable: $e');
    }
  }

  static Future<Map<String, dynamic>> _invokeMap(String method) async {
    final dynamic value;
    try {
      value = await _channel.invokeMethod<dynamic>(method);
    } on MissingPluginException catch (e) {
      locationDebugLog(
        '[IosSLC] $method skipped; native channel unavailable: $e',
      );
      return {
        'ok': false,
        'running': false,
        'error': {
          'code': 'missing_plugin',
          'message': 'iOS SLC native channel is unavailable',
        },
      };
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return {'ok': false, 'error': 'Unexpected response from $method'};
  }

  static Future<void> _handlePayload(Object? event) async {
    final callback = _onLocation;
    if (callback == null) return;

    if (event is! Map) return;
    final map = Map<Object?, Object?>.from(event);
    final source = map['source']?.toString() ?? 'ios_slc';
    final position = _positionFromMap(map);
    if (position == null) return;

    locationDebugLog('[IosSLC] event source=$source acc=${position.accuracy}');

    await callback(position, source);
  }

  static Position? _positionFromMap(Map<Object?, Object?> map) {
    final latitude = _doubleOrNull(map['latitude']);
    final longitude = _doubleOrNull(map['longitude']);
    if (latitude == null || longitude == null) return null;

    return Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: _timestampFromPayload(map['timestampMs']),
      accuracy: _doubleOrDefault(map['accuracy']),
      altitude: _doubleOrDefault(map['altitude']),
      altitudeAccuracy: _doubleOrDefault(map['altitudeAccuracy']),
      heading: _doubleOrDefault(map['heading']),
      headingAccuracy: _doubleOrDefault(map['headingAccuracy']),
      speed: _doubleOrDefault(map['speed']),
      speedAccuracy: _doubleOrDefault(map['speedAccuracy']),
      isMocked: false,
    );
  }

  static DateTime _timestampFromPayload(Object? value) {
    final timestampMs = _intOrNull(value);
    if (timestampMs == null || timestampMs <= 0) {
      return DateTime.now().toUtc();
    }
    return DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true);
  }

  static double? _doubleOrNull(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static double _doubleOrDefault(Object? value, [double fallback = 0]) {
    final parsed = _doubleOrNull(value);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) return fallback;
    return parsed;
  }

  static int? _intOrNull(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
