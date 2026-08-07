import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

class OsNotificationPermission {
  OsNotificationPermission._();

  static int? _androidSdkInt;

  static Future<bool> androidRequiresRuntimePermission() async {
    if (!Platform.isAndroid) return false;
    _androidSdkInt ??= (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    return _androidSdkInt! >= 33;
  }

  static Future<bool> isGranted() async {
    if (Platform.isAndroid) {
      if (!await androidRequiresRuntimePermission()) return true;
      return (await Permission.notification.status).isGranted;
    }
    if (Platform.isIOS) {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    }
    return true;
  }

  static Future<String> permissionApiStatus() async {
    if (Platform.isAndroid) {
      if (!await androidRequiresRuntimePermission()) return 'granted';
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

  static String _mapPermissionStatus(PermissionStatus status) {
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return 'granted';
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return 'denied';
    }
    return 'unknown';
  }
}
