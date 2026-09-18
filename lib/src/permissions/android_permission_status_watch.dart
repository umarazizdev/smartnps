import 'dart:io';

import 'package:flutter/services.dart';

import '../api/api_urls.dart';
import '../auth/auth_repository.dart';
import '../push/notifications/push_notification_preferences.dart';
import '../utilities/app_debug_log.dart';
import '../utilities/app_version_info.dart';
import '../utilities/device_identity.dart';

/// Arms a lightweight Android AlarmManager watch that, after process death,
/// re-reads OS permissions and POSTs `/native-app/permission-status` only when
/// the snapshot changed. Never starts location FGS.
class AndroidPermissionStatusWatch {
  AndroidPermissionStatusWatch._();

  static const MethodChannel _channel = MethodChannel(
    'com.smartnps360.app/android_permission_status',
  );

  static Future<void>? _armInFlight;

  static Future<void> arm({bool markSynced = false}) async {
    if (!Platform.isAndroid) return;
    final inFlight = _armInFlight;
    if (inFlight != null) return inFlight;

    final future = _armImpl(markSynced: markSynced);
    _armInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_armInFlight, future)) {
        _armInFlight = null;
      }
    }
  }

  static Future<void> _armImpl({required bool markSynced}) async {
    if (!await AuthRepository.instance.isOfficerLoggedIn()) return;
    final access = await AuthRepository.instance.getAccessToken();
    if (access == null || access.isEmpty) return;
    final refresh = await AuthRepository.instance.getRefreshToken();
    final pushEnabled = await PushNotificationPreferences.readEnabled();

    try {
      await _channel.invokeMethod<void>('arm', {
        'accessToken': access,
        'refreshToken': refresh,
        'apiBaseUrl': ApiUrls.baseUrl,
        'deviceId': await DeviceIdentity.getDeviceId(),
        'deviceName': await DeviceIdentity.getDeviceName(),
        'appVersion': AppVersionInfo.version,
        'build': AppVersionInfo.buildNumber,
        'pushStatus': pushEnabled ? 'enabled' : 'disabled',
        'markSynced': markSynced,
      });
    } on MissingPluginException {
      locationDebugLog(
        '[AndroidPermStatus] arm skipped; native plugin missing',
      );
    } catch (e) {
      locationDebugLog('[AndroidPermStatus] arm failed: $e');
    }
  }

  static Future<void> syncSession({bool markSynced = false}) async {
    if (!Platform.isAndroid) return;
    if (!await AuthRepository.instance.isOfficerLoggedIn()) {
      await disarm();
      return;
    }
    final access = await AuthRepository.instance.getAccessToken();
    if (access == null || access.isEmpty) {
      await disarm();
      return;
    }
    final refresh = await AuthRepository.instance.getRefreshToken();
    final pushEnabled = await PushNotificationPreferences.readEnabled();
    try {
      await _channel.invokeMethod<void>('syncSession', {
        'accessToken': access,
        'refreshToken': refresh,
        'apiBaseUrl': ApiUrls.baseUrl,
        'pushStatus': pushEnabled ? 'enabled' : 'disabled',
        'markSynced': markSynced,
      });
    } on MissingPluginException {
    } catch (e) {
      locationDebugLog('[AndroidPermStatus] syncSession failed: $e');
    }
  }

  static Future<void> noteCurrentSynced() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('noteCurrentSynced');
    } on MissingPluginException {
    } catch (e) {
      locationDebugLog('[AndroidPermStatus] noteCurrentSynced failed: $e');
    }
  }

  static Future<void> disarm() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('disarm');
    } on MissingPluginException {
    } catch (e) {
      locationDebugLog('[AndroidPermStatus] disarm failed: $e');
    }
  }
}
