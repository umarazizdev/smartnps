import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utilities/permission_settings_helper.dart';

class BackgroundPermissionOutcome {
  const BackgroundPermissionOutcome({
    required this.granted,
    this.openSettings = false,
    this.deniedReason,
  });

  final bool granted;
  final bool openSettings;
  final String? deniedReason;
}

class BackgroundLocationPermissions {
  static Future<Map<String, dynamic>> statusSnapshot() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    final geolocatorPermission = await readIosLocationPermission();

    return {
      'serviceEnabled': serviceEnabled,
      'geolocatorPermission': geolocatorPermission.name,
      if (Platform.isAndroid) ...{
        'foreground': (await Permission.location.status).toString(),
        'background': (await Permission.locationAlways.status).toString(),
        'notification': (await Permission.notification.status).toString(),
      },
      if (Platform.isIOS) ...{
        'notification': (await Permission.notification.status).toString(),
      },
    };
  }

  /// Reads the current iOS authorization from Geolocator only (Settings-safe).
  static Future<LocationPermission> readIosLocationPermission() async {
    if (!Platform.isIOS) return LocationPermission.always;
    return Geolocator.checkPermission();
  }

  static Future<BackgroundPermissionOutcome> ensureGranted() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const BackgroundPermissionOutcome(
        granted: false,
        openSettings: true,
        deniedReason: 'location_services_disabled',
      );
    }

    if (Platform.isAndroid) {
      return _ensureAndroidGranted();
    }

    if (Platform.isIOS) {
      return _ensureIosGranted();
    }

    return const BackgroundPermissionOutcome(granted: true);
  }

  static Future<BackgroundPermissionOutcome> _ensureAndroidGranted() async {
    final fgBefore = await Permission.location.status;
    if (kDebugMode) {
      // ignore: avoid_print
      print('[BackgroundLocationPermissions] android fg(before)=$fgBefore');
    }
    final fg = fgBefore.isGranted
        ? fgBefore
        : await Permission.location.request();
    if (!fg.isGranted) {
      return BackgroundPermissionOutcome(
        granted: false,
        openSettings: PermissionSettingsHelper.shouldOpenSettings(fg),
        deniedReason: 'location_foreground',
      );
    }
    if (!fgBefore.isGranted) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }

    final notificationBefore = await Permission.notification.status;
    if (kDebugMode) {
      // ignore: avoid_print
      print(
        '[BackgroundLocationPermissions] android notification(before)=$notificationBefore',
      );
    }
    if (!notificationBefore.isGranted) {
      final notification = await Permission.notification.request();
      if (kDebugMode) {
        // ignore: avoid_print
        print(
          '[BackgroundLocationPermissions] android notification(after)=$notification',
        );
      }
      if (!notification.isGranted &&
          PermissionSettingsHelper.shouldOpenSettings(notification)) {
        return const BackgroundPermissionOutcome(
          granted: false,
          openSettings: true,
          deniedReason: 'notification',
        );
      }
    }

    final bgBefore = await Permission.locationAlways.status;
    if (kDebugMode) {
      // ignore: avoid_print
      print('[BackgroundLocationPermissions] android bg(before)=$bgBefore');
    }
    final bg = bgBefore.isGranted
        ? bgBefore
        : await Permission.locationAlways.request();
    if (kDebugMode) {
      // ignore: avoid_print
      print('[BackgroundLocationPermissions] android bg(after)=$bg');
    }
    if (bg.isGranted) {
      return const BackgroundPermissionOutcome(granted: true);
    }

    // Foreground location is enough to start; user can upgrade in settings.
    return const BackgroundPermissionOutcome(
      granted: true,
      openSettings: true,
      deniedReason: 'location_background',
    );
  }

  /// Re-reads iOS authorization without showing the system prompt.
  ///
  /// After the user changes location to Always in Settings, only
  /// [Geolocator.checkPermission] reflects the new value. Calling
  /// [Geolocator.requestPermission] here would re-show the dialog and can
  /// leave the app stuck on whileInUse.
  static Future<LocationPermission> refreshIosLocationPermission() async {
    final permission = await readIosLocationPermission();
    if (kDebugMode && Platform.isIOS) {
      // ignore: avoid_print
      print('[BackgroundLocationPermissions] ios geolocator(check)=$permission');
    }
    return permission;
  }

  static Future<BackgroundPermissionOutcome> _ensureIosGranted() async {
    // On iOS, permission_handler often reports "denied" after the user grants
    // "Always" in Settings while Geolocator reflects the real authorization.
    var geoPermission = await refreshIosLocationPermission();
    if (kDebugMode) {
      // ignore: avoid_print
      print(
        '[BackgroundLocationPermissions] ios geolocator(before)=$geoPermission',
      );
    }

    if (geoPermission == LocationPermission.denied) {
      geoPermission = await Geolocator.requestPermission();
      if (kDebugMode) {
        // ignore: avoid_print
        print(
          '[BackgroundLocationPermissions] ios geolocator(after request)=$geoPermission',
        );
      }
    }

    if (geoPermission == LocationPermission.denied ||
        geoPermission == LocationPermission.deniedForever) {
      return const BackgroundPermissionOutcome(
        granted: false,
        openSettings: true,
        deniedReason: 'location_when_in_use',
      );
    }

    if (geoPermission == LocationPermission.always) {
      return const BackgroundPermissionOutcome(granted: true);
    }

    // whileInUse: tracking can start, but background updates need "Always".
    return const BackgroundPermissionOutcome(
      granted: true,
      openSettings: true,
      deniedReason: 'location_always',
    );
  }

  static Future<bool> iosHasSufficientLocation() async {
    if (!Platform.isIOS) return true;
    final permission = await readIosLocationPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  static Future<bool> iosHasBackgroundLocation() async {
    if (!Platform.isIOS) return true;
    final permission = await readIosLocationPermission();
    return permission == LocationPermission.always;
  }

  static Future<String?> settingsDeniedReasonIfAny() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return 'location_services_disabled';

    if (Platform.isIOS) {
      final permission = await readIosLocationPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return 'location_when_in_use';
      }
      if (permission == LocationPermission.whileInUse) {
        return 'location_always';
      }
      return null;
    }

    if (Platform.isAndroid) {
      final foreground = await Permission.location.status;
      if (!foreground.isGranted) return 'location_foreground';
      final background = await Permission.locationAlways.status;
      if (!background.isGranted) return 'location_background';
      return null;
    }

    return null;
  }

  static Future<bool> hasSufficientBackgroundAccess() async {
    if (Platform.isIOS) {
      return iosHasBackgroundLocation();
    }
    if (Platform.isAndroid) {
      final bg = await Permission.locationAlways.status;
      if (bg.isGranted) return true;
      final fg = await Permission.location.status;
      return fg.isGranted;
    }
    return true;
  }

  static String settingsTitleFor(String? deniedReason) {
    switch (deniedReason) {
      case 'location_services_disabled':
        return 'Turn on location services';
      case 'location_foreground':
      case 'location_when_in_use':
        return 'Enable location access';
      case 'location_background':
      case 'location_always':
        if (Platform.isIOS) return 'Enable Always location';
        if (Platform.isAndroid) return 'Enable all-the-time location';
        return 'Enable always-on location';
      case 'notification':
        return 'Enable notifications';
      default:
        return 'Permission needed';
    }
  }

  static String settingsMessageFor(String? deniedReason) {
    switch (deniedReason) {
      case 'location_services_disabled':
        return 'Location services are turned off on this device. Turn them on '
            'to continue duty tracking.';
      case 'location_foreground':
      case 'location_when_in_use':
        return 'Location access is required while you are on duty. Please '
            'enable location for SmartNPS360.';
      case 'location_background':
      case 'location_always':
        if (Platform.isIOS) {
          return 'Background location is required while you are on duty. '
              'Please set location to Always.\n\n'
              'Open ${PermissionSettingsHelper.iosBackgroundLocationSettingsSteps}.';
        }
        if (Platform.isAndroid) {
          return 'Background location is required while you are on duty. '
              'Please set location to Allow all the time.\n\n'
              'Open ${PermissionSettingsHelper.androidBackgroundLocationSettingsSteps}.';
        }
        return 'Please enable always-on location access for duty tracking.';
      case 'notification':
        return 'Notifications are required for shift alerts. Please enable '
            'notifications for SmartNPS360.';
      default:
        return 'A required permission is missing. Please enable it to '
            'continue duty tracking.';
    }
  }
}
