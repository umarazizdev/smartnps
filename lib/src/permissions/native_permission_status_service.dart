import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api/api_client.dart';
import '../auth/auth_repository.dart';
import '../background/background_location_permissions.dart';
import '../push/push_notification_preferences.dart';
import 'os_notification_permission.dart';
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
  Future<void> _uploadSerial = Future<void>.value();
  bool _syncCoalescePending = false;
  bool _syncForceNext = false;
  Future<void>? _syncInFlight;

  void resetSyncState() {
    stopBatteryMonitoring();
    _lastPayloadFingerprint = null;
    _lastAppCycle = null;
    _pendingAppCycle = null;
    _appCycleUploadInFlight = null;
    _lastUploadedBatteryPercentage = null;
    _syncCoalescePending = false;
    _syncForceNext = false;
    _syncInFlight = null;
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
    unawaited(
      _startBatteryMonitoringImpl(uploadImmediately: uploadImmediately),
    );
  }

  Future<void> _startBatteryMonitoringImpl({
    required bool uploadImmediately,
  }) async {
    if (!await AuthRepository.instance.isOfficerLoggedIn()) {
      stopBatteryMonitoring();
      return;
    }

    _batteryMonitoringActive = true;
    if (_batteryMonitorTimer != null) return;

    if (uploadImmediately) {
      await _uploadBatteryIfChanged();
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

  /// Uploads when the permission snapshot changed (includes in-app push toggle).
  Future<bool> syncIfChanged({bool force = false}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    final accessToken = await _accessTokenForLoggedInOfficer();
    if (accessToken == null || accessToken.isEmpty) return false;

    if (force) _syncForceNext = true;

    final inFlight = _syncInFlight;
    if (inFlight != null) {
      _syncCoalescePending = true;
      if (force) _syncForceNext = true;
      return inFlight.then((_) => true);
    }

    final task = _runSyncIfChanged();
    _syncInFlight = task;
    try {
      await task;
      return true;
    } finally {
      if (identical(_syncInFlight, task)) {
        _syncInFlight = null;
      }
    }
  }

  Future<void> _runSyncIfChanged() async {
    await _serialized(() async {
      do {
        _syncCoalescePending = false;
        final force = _syncForceNext;
        _syncForceNext = false;

        final payload = await buildPayload();
        final fingerprint = _fingerprint(payload);
        if (!force && fingerprint == _lastPayloadFingerprint) {
          if (kDebugMode) {
            debugPrint(
              '[NativePermissionStatus] skip upload (unchanged permissions)',
            );
          }
          continue;
        }

        final uploaded = await _upload(payload);
        if (uploaded) _lastPayloadFingerprint = fingerprint;
      } while (_syncCoalescePending);
    });
  }

  /// Posts in-app push toggle state to the permission-status API.
  Future<bool> uploadPushToggle({required bool enabled}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    final accessToken = await _accessTokenForLoggedInOfficer();
    if (accessToken == null || accessToken.isEmpty) return false;

    if (kDebugMode) {
      debugPrint(
        '[NativePermissionStatus] push state upload push=${enabled ? 'enabled' : 'disabled'}',
      );
    }
    return syncIfChanged(force: true);
  }

  /// Posts app lifecycle state with the same snapshot used by permission sync.
  Future<bool> uploadAppCycle({required String appCycle}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    if (!await AuthRepository.instance.isOfficerLoggedIn()) return false;

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
    final accessToken = await _accessTokenForLoggedInOfficer();
    if (accessToken == null || accessToken.isEmpty) return false;

    if (appCycle == _lastAppCycle) {
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] skip app_cycle upload (unchanged $appCycle)',
        );
      }
      return true;
    }

    var uploaded = false;
    await _serialized(() async {
      final payload = await buildPayload();
      payload['app_cycle'] = appCycle;

      if (kDebugMode) {
        debugPrint('[NativePermissionStatus] app_cycle upload $appCycle');
      }
      uploaded = await _upload(payload);
      if (uploaded) {
        _lastAppCycle = appCycle;
        _lastPayloadFingerprint = _fingerprint(payload);
      }
    });
    return uploaded;
  }

  Future<void> _uploadBatteryIfChanged() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_batteryUploadInFlight) return;

    _batteryUploadInFlight = true;
    try {
      final accessToken = await _accessTokenForLoggedInOfficer();
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

      await _serialized(() async {
        if (!_batteryMonitoringActive) return;

        final payload = await buildPayload();
        payload['battery_percentage'] = batteryPercentage;

        if (kDebugMode) {
          debugPrint(
            '[NativePermissionStatus] battery upload $batteryPercentage%',
          );
        }
        final uploaded = await _upload(payload);
        if (uploaded) {
          _lastPayloadFingerprint = _fingerprint(payload);
        }
      });
    } finally {
      _batteryUploadInFlight = false;
    }
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _uploadSerial = _uploadSerial.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });
    return completer.future;
  }

  Future<String?> _accessTokenForLoggedInOfficer() async {
    if (!await AuthRepository.instance.isOfficerLoggedIn()) return null;
    return AuthRepository.instance.ensureValidAccessToken();
  }

  String _fingerprint(Map<String, dynamic> payload) {
    final copy = Map<String, dynamic>.from(payload)
      ..remove('app_cycle')
      ..remove('battery_percentage')
      ..remove('checkedAt');
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
      'push': await _pushToggleStatus(),
    };
  }

  Future<String> _pushToggleStatus() async {
    if (!Platform.isAndroid && !Platform.isIOS) return 'disabled';
    final enabled = await PushNotificationPreferences.readEnabled();
    return enabled ? 'enabled' : 'disabled';
  }

  Future<String> _foregroundLocationStatus() async {
    if (!Platform.isAndroid && !Platform.isIOS) return 'unknown';

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return 'unknown';

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
    if (!serviceEnabled) return 'unknown';

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
      if (!foreground.isGranted) {
        return _mapPermissionStatus(foreground);
      }
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
    if (locationPermission == LocationPermission.deniedForever) {
      return 'denied';
    }
    if (locationPermission == LocationPermission.denied ||
        locationPermission == LocationPermission.unableToDetermine) {
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
    return OsNotificationPermission.permissionApiStatus();
  }

  Future<String> _batteryOptimizationStatus() async {
    if (!Platform.isAndroid) return 'unknown';

    try {
      final status = await _settingsChannel.invokeMethod<String>(
        'batteryOptimizationStatus',
      );
      if (status == 'granted') return 'granted';
      if (status == 'unknown') return 'unknown';
      // Legacy native builds reported "denied" for the default optimized state.
      if (status == 'denied') return 'unknown';
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
      // Default OS state is not exempt; that is not an explicit officer denial.
      return ignoring ? 'granted' : 'unknown';
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
    // permanentlyDenied/restricted = officer explicitly blocked access.
    // denied alone often means "not granted yet" before the first OS prompt.
    if (status.isPermanentlyDenied || status.isRestricted) {
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
      LocationPermission.whileInUse =>
        foreground ? 'granted' : 'unknown',
      LocationPermission.deniedForever => 'denied',
      LocationPermission.denied || LocationPermission.unableToDetermine =>
        'unknown',
    };
  }

  Future<bool> _upload(Map<String, dynamic> payload) async {
    ApiClient.instance.ensureAuthInterceptorInstalled();
    final uri = Uri.parse(AppConfig.permissionStatusUrl);

    try {
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] POST ${uri.path} body=$payload',
        );
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
      if (ok) _rememberUploadedBattery(payload);
      return ok;
    } catch (_) {
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
