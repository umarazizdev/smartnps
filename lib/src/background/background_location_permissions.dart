import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utilities/overlay_prompt_guard.dart';
import '../utilities/permission_settings_helper.dart';

enum LocationPermissionPhase { none, foregroundOnly, backgroundReady }

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
  ///
  /// Android uses the native OS check with plugin fallbacks so Play updates
  /// and cold-start (before MethodChannel is ready) still resolve correctly.
  static Future<bool> isClockInBackgroundReady() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    await refreshPermissionStateFromOs();
    if (Platform.isIOS) {
      final permission = await readIosLocationPermission();
      return permission == LocationPermission.always;
    }
    if (Platform.isAndroid) {
      return androidHasBackgroundLocationAccess();
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
        : await OverlayPromptGuard.runDuringOsPermissionPrompt(
            Permission.location.request,
          );
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
      final notification = await OverlayPromptGuard.runDuringOsPermissionPrompt(
        Permission.notification.request,
      );
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
        : await OverlayPromptGuard.runDuringOsPermissionPrompt(
            Permission.locationAlways.request,
          );
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
      geoPermission = await OverlayPromptGuard.runDuringOsPermissionPrompt(
        Geolocator.requestPermission,
      );
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
      if (!await hasPreciseLocationAccess()) {
        return 'location_precise';
      }
      return null;
    }

    if (Platform.isAndroid) {
      if (!await androidHasBackgroundLocationAccess()) {
        final foreground = await Permission.location.status;
        if (!foreground.isGranted) return 'location_foreground';
        return 'location_background';
      }
      if (!await hasPreciseLocationAccess()) {
        return 'location_precise';
      }
      return null;
    }

    return null;
  }

  /// True when the OS grants precise / fine location (not Approximate / Reduced).
  ///
  /// Uses the native Settings channel (same pattern as background location OS
  /// checks): Android ACCESS_FINE, iOS CLAccuracyAuthorization.fullAccuracy.
  static Future<bool> hasPreciseLocationAccess() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    if (Platform.isAndroid) {
      return _androidHasFineLocationPermission();
    }

    return _iosHasPreciseLocationPermission();
  }

  static Future<bool> _iosHasPreciseLocationPermission() async {
    try {
      final precise = await _nativeSettingsChannel.invokeMethod<bool>(
        'hasPreciseLocationPermission',
      );
      if (precise != null) {
        if (kDebugMode) {
          debugPrint(
            '[BackgroundLocationPermissions] ios native precise=$precise',
          );
        }
        return precise;
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[BackgroundLocationPermissions] ios native precise check failed: '
          '$error',
        );
      }
    }

    // Fallback if native channel is not ready yet (cold start).
    try {
      final accuracy = await Geolocator.getLocationAccuracy();
      final granted = accuracy == LocationAccuracyStatus.precise;
      if (kDebugMode) {
        debugPrint(
          '[BackgroundLocationPermissions] ios geolocator precise=$granted '
          '($accuracy)',
        );
      }
      return granted;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[BackgroundLocationPermissions] ios geolocator precise failed: '
          '$error',
        );
      }
      // Authorized but unreadable → treat as missing so banner can recover.
      return !(await hasForegroundLocationAccess());
    }
  }

  static Future<bool> _androidHasFineLocationPermission() async {
    try {
      final precise = await _nativeSettingsChannel.invokeMethod<bool>(
        'hasPreciseLocationPermission',
      );
      if (precise != null) return precise;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[BackgroundLocationPermissions] android precise check failed: '
          '$error',
        );
      }
    }
    // Do not use Permission.location here — it is granted for Approximate-only.
    try {
      final accuracy = await Geolocator.getLocationAccuracy();
      return accuracy == LocationAccuracyStatus.precise;
    } catch (_) {
      return false;
    }
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

  /// iOS: "Always". Android: "Allow all the time".
  static String alwaysAccessLabel() {
    if (Platform.isIOS) return 'Always';
    if (Platform.isAndroid) return 'Allow all the time';
    return 'always-on';
  }

  /// iOS: "While Using the App". Android: "While using the app".
  static String foregroundAccessLabel() {
    if (Platform.isIOS) return 'While Using the App';
    if (Platform.isAndroid) return 'While using the app';
    return 'while using the app';
  }

  static String _backgroundAccessSettingsStepsMessage({
    required String trailingClause,
  }) {
    if (Platform.isIOS) {
      return 'Open Settings, tap SmartNPS360, choose Location, then select '
          '${alwaysAccessLabel()}. $trailingClause';
    }
    return 'Open Settings and set location to ${alwaysAccessLabel()}. '
        '$trailingClause';
  }

  static String settingsTitleFor(String? deniedReason) {
    switch (deniedReason) {
      case 'location_services_disabled':
        return 'Turn on location services';
      case 'location_foreground':
      case 'location_when_in_use':
        if (Platform.isAndroid) return 'Location access required';
        return 'Enable location access';
      case 'location_background':
      case 'location_always':
        if (Platform.isIOS) return 'Enable Always location';
        if (Platform.isAndroid) {
          return '${alwaysAccessLabel()} required';
        }
        return 'Enable ${alwaysAccessLabel()} location';
      case 'location_precise':
        if (Platform.isAndroid) return 'Precise location required';
        return 'Enable Precise location';
      case 'notification':
        if (Platform.isAndroid) return 'Notifications required';
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
        if (Platform.isAndroid) {
          return 'Allow all-the-time location';
        }
        return 'Background location required';
      case 'location_precise':
        return 'Precise location required';
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
        return 'Background location required for shift attendance';
      case 'location_precise':
        return 'Precise location required for shift attendance';
      default:
        return 'Location required for shift attendance';
    }
  }

  static String clockInMessageFor(String? deniedReason) {
    final alwaysLabel = alwaysAccessLabel();
    switch (deniedReason) {
      case 'location_services_disabled':
        return 'Location services are turned off. Turn them on to verify shift '
            'attendance from the mobile app.';
      case 'location_foreground':
      case 'location_when_in_use':
        return 'Allow location access for shift attendance. Background location '
            '($alwaysLabel) is required to complete attendance verification.';
      case 'location_background':
      case 'location_always':
        if (Platform.isIOS) {
          return _backgroundAccessSettingsStepsMessage(
            trailingClause:
                'Without ${alwaysLabel} access, shift attendance cannot be '
                'verified from this app.',
          );
        }
        return 'Set location to $alwaysLabel to verify shift attendance '
            'from this app. Without background location, attendance verification '
            'is not available.';
      case 'location_precise':
        if (Platform.isIOS) {
          return 'Shift attendance requires Precise Location. Open Settings, '
              'tap SmartNPS360, choose Location, then turn on Precise Location.';
        }
        return 'Shift attendance requires Precise location. Open Settings and '
            'turn on Precise location for SmartNPS360.';
      default:
        return 'Background location is required for shift attendance from the '
            'mobile app.';
    }
  }

  static String clockInSettingsMessageFor(String? deniedReason) {
    final alwaysLabel = alwaysAccessLabel();
    switch (deniedReason) {
      case 'location_background':
      case 'location_always':
        if (Platform.isIOS) {
          return 'Shift attendance requires Location set to $alwaysLabel. Open '
              'Settings, tap SmartNPS360, choose Location, then select '
              '$alwaysLabel.';
        }
        return 'Shift attendance requires location set to $alwaysLabel. Open '
            'Settings and choose $alwaysLabel for SmartNPS360.';
      case 'location_precise':
        return clockInMessageFor(deniedReason);
      default:
        return clockInMessageFor(deniedReason);
    }
  }

  static String bannerMessageFor(String? deniedReason) {
    final alwaysLabel = alwaysAccessLabel();
    switch (deniedReason) {
      case 'location_services_disabled':
        if (Platform.isAndroid) {
          return 'Device location is off. Turn it on to continue duty tracking.';
        }
        return 'Location services are turned off. Turn them on to continue '
            'duty tracking while you are on duty.';
      case 'location_foreground':
      case 'location_when_in_use':
        if (Platform.isAndroid) {
          return 'Allow location, then set it to $alwaysLabel for duty tracking.';
        }
        return 'Tap Allow Location to grant access. Your location is used only '
            'while you are on duty.';
      case 'location_background':
      case 'location_always':
        if (Platform.isIOS) {
          return _backgroundAccessSettingsStepsMessage(
            trailingClause: 'Your location is used only while you are on duty.',
          );
        }
        return 'Set Location to $alwaysLabel so duty tracking works in background.';
      case 'location_precise':
        if (Platform.isIOS) {
          return 'Open Settings, tap SmartNPS360, choose Location, then turn on '
              'Precise Location. Your location is used only while you are on duty.';
        }
        return 'Turn on Precise location for accurate duty tracking.';
      default:
        if (Platform.isAndroid) {
          return 'Enable location for SmartNPS360 to continue duty tracking.';
        }
        return 'Location access is required while you are on duty.';
    }
  }

  static String bannerButtonLabelFor(String? deniedReason) {
    switch (deniedReason) {
      case 'location_services_disabled':
      case 'location_background':
      case 'location_always':
      case 'location_precise':
        return 'Open Settings';
      case 'location_foreground':
      case 'location_when_in_use':
        return 'Allow Location';
      default:
        return 'Enable Location';
    }
  }

  static String settingsMessageFor(String? deniedReason) {
    final alwaysLabel = alwaysAccessLabel();
    switch (deniedReason) {
      case 'location_services_disabled':
        if (Platform.isAndroid) {
          return 'Device location is turned off. Please enable Location in Settings to continue.';
        }
        return 'Location services are turned off on this device. Turn them on '
            'to continue duty tracking.';
      case 'location_foreground':
      case 'location_when_in_use':
        if (Platform.isAndroid) {
          return 'Location access is not enabled. Please allow Location for SmartNPS360 in Settings.';
        }
        return 'Location access is required while you are on duty. Please '
            'enable location for SmartNPS360.';
      case 'location_background':
      case 'location_always':
        if (Platform.isIOS) {
          return _backgroundAccessSettingsStepsMessage(
            trailingClause: 'Your location is used only while you are on duty.',
          );
        }
        return 'Background location is not enabled. Please set Location to $alwaysLabel in Settings.';
      case 'location_precise':
        if (Platform.isIOS) {
          return 'Open Settings, tap SmartNPS360, choose Location, then turn on '
              'Precise Location. Your location is used only while you are on duty.';
        }
        return 'Precise location is not enabled. Please turn on Precise location in Settings.';
      case 'notification':
        if (Platform.isAndroid) {
          return 'Notifications are not enabled. Please allow notifications for SmartNPS360 in Settings.';
        }
        return 'Notifications are required for shift alerts. Please enable '
            'notifications for SmartNPS360.';
      default:
        if (Platform.isAndroid) {
          return 'A required location permission is not enabled. Please update it in Settings.';
        }
        return 'A required permission is missing. Please enable it to '
            'continue duty tracking.';
    }
  }

  static String locationServicesDisabledSettingsMessage() {
    if (Platform.isIOS) {
      return 'Location Services are turned off. Open Settings, go to Privacy & '
          'Security, tap Location Services, and turn them on. Then return here.';
    }
    return 'Device location is turned off. Please enable Location in Settings to continue.';
  }

  /// Where Open Settings should navigate after the user confirms in-app.
  static StoreSafeSettingsDestination settingsDestinationFor(
    String? deniedReason,
  ) {
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
