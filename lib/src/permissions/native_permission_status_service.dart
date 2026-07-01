import 'dart:convert';
import 'dart:io';

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
  NativePermissionStatusService._();

  static final NativePermissionStatusService instance =
      NativePermissionStatusService._();

  static const MethodChannel _settingsChannel = MethodChannel(
    'com.smartnps360.app/settings',
  );

  String? _lastPayloadFingerprint;
  bool _syncInFlight = false;

  void resetSyncState() {
    _lastPayloadFingerprint = null;
  }

  Future<Map<String, dynamic>> buildPayload() async {
    return {
      'platform': DeviceIdentity.platformName(),
      'deviceId': await DeviceIdentity.getDeviceId(),
      'appVersion': AppVersionInfo.version,
      'permissions': await _readPermissions(),
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Uploads only when the permission snapshot changed (ignores [checkedAt]).
  Future<void> syncIfChanged() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final accessToken = await AuthRepository.instance.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) return;
    if (_syncInFlight) return;

    _syncInFlight = true;
    try {
      final payload = await buildPayload();
      final fingerprint = _fingerprint(payload);
      if (fingerprint == _lastPayloadFingerprint) {
        if (kDebugMode) {
          debugPrint(
            '[NativePermissionStatus] skip upload (unchanged permissions)',
          );
        }
        return;
      }

      final uploaded = await _upload(payload);
      if (uploaded) {
        _lastPayloadFingerprint = fingerprint;
      }
    } finally {
      _syncInFlight = false;
    }
  }

  /// Posts in-app push toggle state to the permission-status API (always uploads).
  Future<bool> uploadPushToggle({required bool enabled}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    final accessToken = await AuthRepository.instance.getAccessToken();
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
    return _upload(payload);
  }

  String _fingerprint(Map<String, dynamic> payload) {
    final copy = Map<String, dynamic>.from(payload)..remove('checkedAt');
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
      'motionActivity': await _motionActivityStatus(),
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

  Future<String> _motionActivityStatus() async {
    // Motion/activity permission is not declared in app manifests (store-safe).
    return 'unknown';
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
      return ok;
    } catch (error) {
      debugPrint('[NativePermissionStatus] upload failed: $error');
      return false;
    }
  }
}
