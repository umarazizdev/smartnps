import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api/api_client.dart';
import '../auth/auth_repository.dart';
import '../background/background_location_permissions.dart';
import '../utilities/app_config.dart';
import '../utilities/app_version_info.dart';
import '../utilities/device_identity.dart';

/// Store-safe OS permission snapshot for the native-app permission-status API.
///
/// Read-only: never requests permissions, only reports current OS state.
class NativePermissionStatusService {
  NativePermissionStatusService._() {
    _settingsChannel.setMethodCallHandler(_handleSettingsMethodCall);
  }

  static final NativePermissionStatusService instance =
      NativePermissionStatusService._();

  static const MethodChannel _settingsChannel = MethodChannel(
    'com.smartnps360.app/settings',
  );
  static const Duration _appCycleDebounce = Duration(milliseconds: 350);
  static const Duration _batteryMonitorInterval = Duration(minutes: 5);

  String? _lastPayloadFingerprint;
  String? _lastAppCycle;
  String? _pendingAppCycle;
  Future<bool>? _appCycleUploadInFlight;
  Timer? _batteryMonitorTimer;
  int? _lastUploadedBatteryPercentage;
  bool _batteryUploadInFlight = false;
  bool _batteryMonitoringActive = false;
  bool _syncInFlight = false;
  bool _syncRequestedWhileInFlight = false;

  void resetSyncState() {
    stopBatteryMonitoring();
    _lastPayloadFingerprint = null;
    _lastAppCycle = null;
    _pendingAppCycle = null;
    _appCycleUploadInFlight = null;
    _lastUploadedBatteryPercentage = null;
    _syncRequestedWhileInFlight = false;
  }

  Future<Map<String, dynamic>> buildPayload() async {
    return {
      'platform': DeviceIdentity.platformName(),
      'deviceId': await DeviceIdentity.getDeviceId(),
      'appVersion': AppVersionInfo.version,
      'build': AppVersionInfo.buildNumber,
      'battery_percentage': await _batteryPercentage(),
      'low_power_mode': await _lowPowerModeStatus(),
      'permissions': await _readPermissions(),
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<dynamic> _handleSettingsMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'lowPowerModeChanged':
        if (kDebugMode) {
          debugPrint(
            '[NativePermissionStatus] low_power_mode changed ${call.arguments}',
          );
        }
        unawaited(syncIfChanged());
        return null;
      default:
        throw MissingPluginException('No handler for ${call.method}');
    }
  }

  /// Starts conservative live battery uploads while the app is active.
  void startBatteryMonitoring({bool uploadImmediately = true}) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _batteryMonitoringActive = true;
    if (_batteryMonitorTimer != null) return;

    if (uploadImmediately) {
      unawaited(_uploadBatteryIfChanged());
    }
    _batteryMonitorTimer = Timer.periodic(_batteryMonitorInterval, (_) {
      unawaited(_uploadBatteryIfChanged());
    });
  }

  void stopBatteryMonitoring() {
    _batteryMonitoringActive = false;
    _batteryMonitorTimer?.cancel();
    _batteryMonitorTimer = null;
  }

  /// Uploads only when the OS-state snapshot changed.
  ///
  /// Ignores volatile fields that should not trigger permission-status syncs.
  Future<void> syncIfChanged() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final accessToken = await AuthRepository.instance.ensureValidAccessToken();
    if (accessToken == null || accessToken.isEmpty) return;
    if (_syncInFlight) {
      _syncRequestedWhileInFlight = true;
      return;
    }

    _syncInFlight = true;
    try {
      do {
        _syncRequestedWhileInFlight = false;

        final payload = await buildPayload();
        final fingerprint = _fingerprint(payload);
        if (fingerprint == _lastPayloadFingerprint) {
          if (kDebugMode) {
            debugPrint(
              '[NativePermissionStatus] skip upload (unchanged permissions)',
            );
          }
          continue;
        }

        final uploaded = await _upload(payload);
        if (uploaded) _lastPayloadFingerprint = fingerprint;
      } while (_syncRequestedWhileInFlight);
    } finally {
      _syncInFlight = false;
    }
  }

  /// Posts in-app push toggle state to the permission-status API (always uploads).
  Future<bool> uploadPushToggle({required bool enabled}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    final accessToken = await AuthRepository.instance.ensureValidAccessToken();
    if (accessToken == null || accessToken.isEmpty) return false;

    final payload = await buildPayload();
    final permissions = Map<String, dynamic>.from(
      payload['permissions'] as Map<String, dynamic>,
    );
    permissions['push'] = enabled ? 'enabled' : 'disabled';
    payload['permissions'] = permissions;

    if (kDebugMode) {
      debugPrint(
        '[NativePermissionStatus] push state upload '
        'push=${permissions['push']}',
      );
    }
    final uploaded = await _upload(payload);
    if (uploaded) {
      _lastPayloadFingerprint = _fingerprint(payload);
    }
    return uploaded;
  }

  /// Posts app lifecycle state with the same snapshot used by permission sync.
  Future<bool> uploadAppCycle({required String appCycle}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    _pendingAppCycle = appCycle;
    final inFlight = _appCycleUploadInFlight;
    if (inFlight != null) {
      if (kDebugMode) {
        debugPrint('[NativePermissionStatus] queued app_cycle upload $appCycle');
      }
      return inFlight;
    }

    final task = _drainAppCycleUploads();
    _appCycleUploadInFlight = task;
    try {
      return await task;
    } finally {
      if (identical(_appCycleUploadInFlight, task)) {
        _appCycleUploadInFlight = null;
      }
    }
  }

  Future<bool> _drainAppCycleUploads() async {
    var ok = true;

    while (_pendingAppCycle != null) {
      await Future<void>.delayed(_appCycleDebounce);

      final appCycle = _pendingAppCycle;
      _pendingAppCycle = null;
      if (appCycle == null) continue;

      final uploaded = await _uploadAppCycleNow(appCycle);
      ok = ok && uploaded;
    }

    return ok;
  }

  Future<bool> _uploadAppCycleNow(String appCycle) async {
    final accessToken = await AuthRepository.instance.ensureValidAccessToken();
    if (accessToken == null || accessToken.isEmpty) return false;

    if (appCycle == _lastAppCycle) {
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] skip app_cycle upload (unchanged $appCycle)',
        );
      }
      return true;
    }

    final payload = await buildPayload();
    payload['app_cycle'] = appCycle;

    if (kDebugMode) {
      debugPrint('[NativePermissionStatus] app_cycle upload $appCycle');
    }
    final uploaded = await _upload(payload);
    if (uploaded) {
      _lastAppCycle = appCycle;
      _lastPayloadFingerprint = _fingerprint(payload);
    }
    return uploaded;
  }

  Future<void> _uploadBatteryIfChanged() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_batteryUploadInFlight) return;

    _batteryUploadInFlight = true;
    try {
      final accessToken = await AuthRepository.instance.ensureValidAccessToken();
      if (accessToken == null || accessToken.isEmpty) {
        stopBatteryMonitoring();
        return;
      }
      if (!_batteryMonitoringActive) return;

      final batteryPercentage = await _batteryPercentage();
      if (batteryPercentage == null ||
          batteryPercentage == _lastUploadedBatteryPercentage) {
        return;
      }
      if (!_batteryMonitoringActive) return;

      final payload = await buildPayload();
      payload['battery_percentage'] = batteryPercentage;
      if (!_batteryMonitoringActive) return;

      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] battery upload $batteryPercentage%',
        );
      }
      final uploaded = await _upload(payload);
      if (uploaded) {
        _lastPayloadFingerprint = _fingerprint(payload);
      }
    } finally {
      _batteryUploadInFlight = false;
    }
  }

  String _fingerprint(Map<String, dynamic> payload) {
    final copy = Map<String, dynamic>.from(payload)
      ..remove('app_cycle')
      ..remove('battery_percentage')
      ..remove('checkedAt');
    final permissions = copy['permissions'];
    if (permissions is Map) {
      copy['permissions'] = Map<String, dynamic>.from(permissions)
        ..remove('push');
    }
    return jsonEncode(copy);
  }

  Future<Map<String, String>> _readPermissions() async {
    if (Platform.isAndroid) {
      await BackgroundLocationPermissions.refreshPermissionStateFromOs();
    } else if (Platform.isIOS) {
      await BackgroundLocationPermissions.refreshPermissionStateFromOs();
    }

    return {
      'foregroundLocation': await _foregroundLocationStatus(),
      'backgroundLocation': await _backgroundLocationStatus(),
      'preciseLocation': await _preciseLocationStatus(),
      'notifications': await _notificationStatus(),
      'batteryOptimization': await _batteryOptimizationStatus(),
    };
  }

  Future<String> _foregroundLocationStatus() async {
    if (!Platform.isAndroid && !Platform.isIOS) return 'unknown';

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return 'denied';

    if (Platform.isAndroid) {
      return _mapPermissionStatus(await Permission.location.status);
    }

    return _mapGeolocatorPermission(
      await BackgroundLocationPermissions.readIosLocationPermission(),
      foreground: true,
    );
  }

  Future<String> _backgroundLocationStatus() async {
    if (!Platform.isAndroid && !Platform.isIOS) return 'unknown';

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return 'denied';

    if (Platform.isAndroid) {
      try {
        final nativeGranted = await _settingsChannel.invokeMethod<bool>(
          'hasBackgroundLocationPermission',
        );
        if (nativeGranted == true) return 'granted';
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
            '[NativePermissionStatus] android background check failed: $error',
          );
        }
      }
      return _mapPermissionStatus(await Permission.locationAlways.status);
    }

    return _mapGeolocatorPermission(
      await BackgroundLocationPermissions.readIosLocationPermission(),
      foreground: false,
    );
  }

  Future<String> _preciseLocationStatus() async {
    if (!Platform.isAndroid && !Platform.isIOS) return 'unknown';

    if (Platform.isAndroid) {
      final foreground = await Permission.location.status;
      if (foreground.isDenied || foreground.isPermanentlyDenied) {
        return 'denied';
      }
      if (!foreground.isGranted) return 'unknown';
      try {
        final precise = await _settingsChannel.invokeMethod<bool>(
          'hasPreciseLocationPermission',
        );
        return precise == true ? 'granted' : 'denied';
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
            '[NativePermissionStatus] android precise check failed: $error',
          );
        }
        return _mapPermissionStatus(foreground);
      }
    }

    final locationPermission =
        await BackgroundLocationPermissions.readIosLocationPermission();
    if (locationPermission == LocationPermission.denied ||
        locationPermission == LocationPermission.deniedForever) {
      return 'denied';
    }
    if (locationPermission == LocationPermission.unableToDetermine) {
      return 'unknown';
    }

    try {
      final accuracy = await Geolocator.getLocationAccuracy();
      return switch (accuracy) {
        LocationAccuracyStatus.precise => 'granted',
        LocationAccuracyStatus.reduced => 'denied',
        LocationAccuracyStatus.unknown => 'unknown',
      };
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[NativePermissionStatus] ios precise check failed: $error');
      }
      return 'unknown';
    }
  }

  Future<String> _notificationStatus() async {
    if (Platform.isAndroid) {
      return _mapPermissionStatus(await Permission.notification.status);
    }
    if (Platform.isIOS) {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return switch (settings.authorizationStatus) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => 'granted',
        AuthorizationStatus.denied => 'denied',
        AuthorizationStatus.notDetermined => 'unknown',
      };
    }
    return 'unknown';
  }

  Future<String> _batteryOptimizationStatus() async {
    if (!Platform.isAndroid) return 'unknown';

    try {
      final status = await _settingsChannel.invokeMethod<String>(
        'batteryOptimizationStatus',
      );
      if (status == 'granted' || status == 'denied') return status!;
      if (status != null) return 'unknown';
    } on MissingPluginException {
      // Fall through for older native builds that only expose the boolean API.
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] battery optimization status check failed: $error',
        );
      }
    }

    try {
      final ignoring = await _settingsChannel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      if (ignoring == null) return 'unknown';
      // Exempt from battery optimization = granted for background reliability.
      return ignoring ? 'granted' : 'denied';
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] battery optimization check failed: $error',
        );
      }
      return 'unknown';
    }
  }

  Future<String> _lowPowerModeStatus() async {
    if (!Platform.isAndroid && !Platform.isIOS) return 'unknown';

    try {
      final status = await _settingsChannel.invokeMethod<String>(
        'lowPowerModeStatus',
      );
      if (status == 'enabled' || status == 'disabled') return status!;
      return 'unknown';
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[NativePermissionStatus] low power mode check failed: $error');
      }
      return 'unknown';
    }
  }

  Future<int?> _batteryPercentage() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      final level = await Battery().batteryLevel;
      if (level < 0 || level > 100) return null;
      return level;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[NativePermissionStatus] battery level failed: $error');
      }
      return null;
    }
  }

  String _mapPermissionStatus(PermissionStatus status) {
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return 'granted';
    }
    if (status.isPermanentlyDenied || status.isRestricted || status.isDenied) {
      return 'denied';
    }
    return 'unknown';
  }

  String _mapGeolocatorPermission(
    LocationPermission permission, {
    required bool foreground,
  }) {
    return switch (permission) {
      LocationPermission.always => 'granted',
      LocationPermission.whileInUse => foreground ? 'granted' : 'denied',
      LocationPermission.denied || LocationPermission.deniedForever => 'denied',
      LocationPermission.unableToDetermine => 'unknown',
    };
  }

  Future<bool> _upload(Map<String, dynamic> payload) async {
    ApiClient.instance.ensureAuthInterceptorInstalled();
    final uri = Uri.parse(AppConfig.permissionStatusUrl);

    try {
      if (kDebugMode) {
        debugPrint('[NativePermissionStatus] POST $uri body=$payload');
      }
      final response = await ApiClient.instance.dio.postUri(
        uri,
        data: payload,
        options: Options(
          headers: const {'Accept': 'application/json'},
          contentType: Headers.jsonContentType,
          sendTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
        ),
      );
      final ok =
          response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] upload ${ok ? 'ok' : 'failed'} '
          'status=${response.statusCode}',
        );
      }
      if (ok) _rememberUploadedBattery(payload);
      return ok;
    } catch (error) {
      debugPrint('[NativePermissionStatus] upload failed: $error');
      return false;
    }
  }

  void _rememberUploadedBattery(Map<String, dynamic> payload) {
    final batteryPercentage = payload['battery_percentage'];
    if (batteryPercentage is int &&
        batteryPercentage >= 0 &&
        batteryPercentage <= 100) {
      _lastUploadedBatteryPercentage = batteryPercentage;
    }
  }
}
