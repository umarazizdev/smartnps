import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utilities/permission_settings_helper.dart';

enum LocationPermissionPhase {
  none,
  foregroundOnly,
  backgroundReady,
}

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
  static const MethodChannel _nativeSettingsChannel = MethodChannel(
    'com.smartnps360.app/settings',
  );

  /// True when background location is already granted — skip all disclosure and
  /// permission dialogs (Android Allow all the time / iOS Always).
  static Future<bool> isBackgroundLocationFullyEnabled() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    await refreshPermissionStateFromOs();
    return hasSufficientBackgroundAccess();
  }

  /// Re-reads the current OS permission state (Settings-safe on iOS).
  static Future<void> refreshPermissionStateFromOs() async {
    if (Platform.isIOS) {
      await refreshIosLocationPermission();
      return;
    }
    if (Platform.isAndroid) {
      await androidHasBackgroundLocationAccess();
    }
  }

  /// Strict clock-in check: reads background permission from the OS only.
  /// Foreground / "While using the app" is never treated as clock-in ready.
  static Future<bool> isClockInBackgroundReady() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    await refreshPermissionStateFromOs();
    if (Platform.isIOS) {
      final permission = await readIosLocationPermission();
      return permission == LocationPermission.always;
    }
    if (Platform.isAndroid) {
      try {
        final nativeGranted = await _nativeSettingsChannel.invokeMethod<bool>(
          'hasBackgroundLocationPermission',
        );
        return nativeGranted == true;
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
            '[BackgroundLocationPermissions] clock-in bg check failed: $error',
          );
        }
        return false;
      }
    }
    return false;
  }
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
      granted: false,
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
      print(
        '[BackgroundLocationPermissions] ios geolocator(check)=$permission',
      );
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
      granted: false,
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
    final permission = await refreshIosLocationPermission();
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
      if (await androidHasBackgroundLocationAccess()) return null;
      final foreground = await Permission.location.status;
      if (!foreground.isGranted) return 'location_foreground';
      return 'location_background';
    }

    return null;
  }

  static Future<LocationPermissionPhase> currentPermissionPhase() async {
    if (await hasSufficientBackgroundAccess()) {
      return LocationPermissionPhase.backgroundReady;
    }
    if (await hasForegroundLocationAccess()) {
      return LocationPermissionPhase.foregroundOnly;
    }
    return LocationPermissionPhase.none;
  }

  static Future<bool> hasForegroundLocationAccess() async {
    if (Platform.isIOS) {
      final permission = await readIosLocationPermission();
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    }
    if (Platform.isAndroid) {
      return (await Permission.location.status).isGranted;
    }
    return true;
  }

  static Future<bool> hasSufficientBackgroundAccess() async {
    if (Platform.isIOS) {
      return iosHasBackgroundLocation();
    }
    if (Platform.isAndroid) {
      return androidHasBackgroundLocationAccess();
    }
    return true;
  }

  /// Android "Allow all the time" — native OS check first, then plugin fallbacks.
  static Future<bool> androidHasBackgroundLocationAccess() async {
    try {
      final nativeGranted = await _nativeSettingsChannel.invokeMethod<bool>(
        'hasBackgroundLocationPermission',
      );
      if (nativeGranted == true) return true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[BackgroundLocationPermissions] native bg check failed: $error',
        );
      }
    }

    final bg = await Permission.locationAlways.status;
    if (bg.isGranted) return true;

    final geo = await Geolocator.checkPermission();
    return geo == LocationPermission.always;
  }

  /// Read-only check used before starting duty background tracking.
  static Future<BackgroundPermissionOutcome> readinessOutcome() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const BackgroundPermissionOutcome(
        granted: false,
        openSettings: true,
        deniedReason: 'location_services_disabled',
      );
    }

    if (!await hasSufficientBackgroundAccess()) {
      final deniedReason = await settingsDeniedReasonIfAny();
      final reason =
          deniedReason ??
          (Platform.isIOS ? 'location_always' : 'location_background');
      final openSettings =
          reason != 'location_foreground' && reason != 'location_when_in_use';
      return BackgroundPermissionOutcome(
        granted: false,
        openSettings: openSettings,
        deniedReason: reason,
      );
    }

    return const BackgroundPermissionOutcome(granted: true);
  }

  /// Requests notification permission once before Android foreground service start.
  static Future<void> ensureAndroidNotificationForService() async {
    if (!Platform.isAndroid) return;
    final status = await Permission.notification.status;
    if (status.isGranted) return;
    await Permission.notification.request();
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

  static String bannerTitleFor(String? deniedReason) {
    switch (deniedReason) {
      case 'location_services_disabled':
        return 'Turn on location services';
      case 'location_foreground':
      case 'location_when_in_use':
        return 'Location permission needed';
      case 'location_background':
      case 'location_always':
        return 'Background location required';
      default:
        return 'Location permission needed';
    }
  }

  static String clockInTitleFor(String? deniedReason) {
    switch (deniedReason) {
      case 'location_services_disabled':
        return 'Turn on location services';
      case 'location_foreground':
      case 'location_when_in_use':
        return 'Location permission needed';
      case 'location_background':
      case 'location_always':
        return 'Background location required to clock in';
      default:
        return 'Location required to clock in';
    }
  }

  static String clockInMessageFor(String? deniedReason) {
    switch (deniedReason) {
      case 'location_services_disabled':
        return 'Location services are turned off. Turn them on to clock in '
            'from the mobile app.';
      case 'location_foreground':
        return 'Allow location access to clock in. Background location '
            '(Allow all the time) is required to complete clock-in.';
      case 'location_when_in_use':
        return 'Allow location access to clock in. Background location '
            '(Always) is required to complete clock-in.';
      case 'location_background':
        return 'Set location to Allow all the time to clock in from this app. '
            'Without background location, clock-in is not available.';
      case 'location_always':
        if (Platform.isIOS) {
          return 'Open Settings, tap SmartNPS360, choose Location, then select '
              'Always. Without Always access, you cannot clock in from this app.';
        }
        return 'Open Settings and set location to Always. Without background '
            'location, you cannot clock in from this app.';
      default:
        return 'Background location is required to clock in from the mobile app.';
    }
  }

  static String clockInSettingsMessageFor(String? deniedReason) {
    switch (deniedReason) {
      case 'location_background':
        return 'Clock-in requires location set to Allow all the time. Open '
            'Settings and choose Allow all the time for SmartNPS360.';
      case 'location_always':
        if (Platform.isIOS) {
          return 'Clock-in requires Location set to Always. Open Settings, tap '
              'SmartNPS360, choose Location, then select Always.';
        }
        return clockInMessageFor(deniedReason);
      default:
        return clockInMessageFor(deniedReason);
    }
  }

  static String bannerMessageFor(String? deniedReason) {
    switch (deniedReason) {
      case 'location_services_disabled':
        return 'Location services are turned off. Turn them on to continue '
            'duty tracking while you are on duty.';
      case 'location_foreground':
        return 'Tap Allow Location to grant access. Your location is used only '
            'while you are on duty.';
      case 'location_when_in_use':
        return 'Tap Allow Location to grant access. Your location is used only '
            'while you are on duty.';
      case 'location_background':
        return 'Tap Allow all the time on the next screen, or open Settings to '
            'enable background location for duty tracking.';
      case 'location_always':
        if (Platform.isIOS) {
          return 'Open Settings, tap SmartNPS360, choose Location, then '
              'select Always. Your location is used only while you are on duty.';
        }
        return 'Open Settings and set location to Always. Your location is used '
            'only while you are on duty.';
      default:
        return 'Location access is required while you are on duty.';
    }
  }

  static String bannerButtonLabelFor(String? deniedReason) {
    switch (deniedReason) {
      case 'location_services_disabled':
      case 'location_background':
      case 'location_always':
        return 'Open Settings';
      case 'location_foreground':
      case 'location_when_in_use':
        return 'Allow Location';
      default:
        return 'Enable Location';
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
          return 'Open Settings, tap SmartNPS360, choose Location, then '
              'select Always. Your location is used only while you are on duty.';
        }
        if (Platform.isAndroid) {
          return 'Background location is required while you are on duty. '
              'Please set location to Allow all the time.';
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

  static String locationServicesDisabledSettingsMessage() {
    if (Platform.isIOS) {
      return 'Location Services are turned off. Open Settings, go to Privacy & '
          'Security, tap Location Services, and turn them on. Then return here.';
    }
    return 'Location services are turned off on this device. Turn them on '
        'to continue duty tracking.';
  }

  /// Where Open Settings should navigate after the user confirms in-app.
  static StoreSafeSettingsDestination settingsDestinationFor(String? deniedReason) {
    if (deniedReason == 'location_services_disabled') {
      if (Platform.isAndroid) {
        return StoreSafeSettingsDestination.systemLocationServices;
      }
      return StoreSafeSettingsDestination.app;
    }
    return StoreSafeSettingsDestination.locationPermission;
  }

  static String settingsDialogKeyFor(String? deniedReason) {
    return deniedReason == 'location_services_disabled'
        ? 'location_services'
        : 'background_location';
  }

  static String settingsDialogMessageFor(String? deniedReason) {
    if (deniedReason == 'location_services_disabled') {
      return locationServicesDisabledSettingsMessage();
    }
    return settingsMessageFor(deniedReason);
  }
}
