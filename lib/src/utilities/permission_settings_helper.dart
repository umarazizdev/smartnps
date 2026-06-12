import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app/app_navigator.dart';
import '../background/background_location_permissions.dart';
import '../utilities/overlay_prompt_guard.dart';
import '../widgets/glass_action_dialog.dart';

enum PermissionSettingsPromptResult { skipped, dismissed, openedSettings }

enum LocationPermissionRequestResult {
  completed,
  promptShown,
  openedSettings,
}

class PermissionSettingsHelper {
  PermissionSettingsHelper._();

  static bool _dialogVisible = false;
  static final Map<String, DateTime> _lastPromptAtByKey = {};

  static const Duration _promptCooldown = Duration(minutes: 2);

  static bool shouldOpenSettings(PermissionStatus status) {
    return status.isPermanentlyDenied || status.isRestricted;
  }

  static Future<void> launchAppSettings() async {
    await Geolocator.openAppSettings();
  }

  /// Handles one location-permission step per call: OS prompt or Settings, never both.
  static Future<LocationPermissionRequestResult>
  requestNextLocationPermissionStep() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        return LocationPermissionRequestResult.openedSettings;
      }
    }

    if (Platform.isAndroid) {
      return _requestNextAndroidLocationStep();
    }

    if (Platform.isIOS) {
      return _requestNextIosLocationStep();
    }

    return LocationPermissionRequestResult.completed;
  }

  static Future<LocationPermissionRequestResult>
  _requestNextAndroidLocationStep() async {
    final foreground = await Permission.location.status;
    if (!foreground.isGranted) {
      if (shouldOpenSettings(foreground)) {
        await launchAppSettings();
        return LocationPermissionRequestResult.openedSettings;
      }
      await Permission.location.request();
      return LocationPermissionRequestResult.promptShown;
    }

    if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
      return LocationPermissionRequestResult.completed;
    }

    final background = await Permission.locationAlways.status;
    if (shouldOpenSettings(background)) {
      await launchAppSettings();
      return LocationPermissionRequestResult.openedSettings;
    }

    await Permission.locationAlways.request();
    if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
      return LocationPermissionRequestResult.completed;
    }

    final after = await Permission.locationAlways.status;
    if (shouldOpenSettings(after)) {
      await launchAppSettings();
      return LocationPermissionRequestResult.openedSettings;
    }

    return LocationPermissionRequestResult.promptShown;
  }

  static Future<LocationPermissionRequestResult> _requestNextIosLocationStep() async {
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.deniedForever) {
      await launchAppSettings();
      return LocationPermissionRequestResult.openedSettings;
    }

    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
      return LocationPermissionRequestResult.promptShown;
    }

    if (permission == LocationPermission.always) {
      return LocationPermissionRequestResult.completed;
    }

    await launchAppSettings();
    return LocationPermissionRequestResult.openedSettings;
  }

  /// One staged step per call. Prefer [requestNextLocationPermissionStep].
  static Future<void> launchLocationPermissionSettings() async {
    await requestNextLocationPermissionStep();
  }

  /// Shows an explanatory dialog first. Settings open only if the user taps
  /// [Open Settings]. Never auto-redirects without that tap.
  static Future<PermissionSettingsPromptResult> promptOpenSettings({
    required String title,
    required String message,
    String dialogKey = 'default',
    bool barrierDismissible = false,
    bool respectCooldown = true,
  }) async {
    if (_dialogVisible) {
      return PermissionSettingsPromptResult.skipped;
    }

    if (respectCooldown && _isInCooldown(dialogKey)) {
      if (kDebugMode) {
        debugPrint(
          '[PermissionSettings] skip dialog key=$dialogKey (cooldown)',
        );
      }
      return PermissionSettingsPromptResult.skipped;
    }

    final context = AppNavigator.key.currentContext;
    if (context == null || !context.mounted) {
      if (kDebugMode) {
        debugPrint(
          '[PermissionSettings] skip dialog key=$dialogKey (no context)',
        );
      }
      return PermissionSettingsPromptResult.skipped;
    }

    await OverlayPromptGuard.waitUntilReady();

    final readyContext = AppNavigator.key.currentContext;
    if (readyContext == null || !readyContext.mounted) {
      if (kDebugMode) {
        debugPrint(
          '[PermissionSettings] skip dialog key=$dialogKey (no context after wait)',
        );
      }
      return PermissionSettingsPromptResult.skipped;
    }

    _dialogVisible = true;
    _lastPromptAtByKey[dialogKey] = DateTime.now();
    var openedSettings = false;

    try {
      final openSettings = await GlassActionDialog.show(
        context: readyContext,
        barrierDismissible: barrierDismissible,
        icon: Icons.location_on_rounded,
        title: title,
        message: message,
        secondaryLabel: 'Not now',
        primaryLabel: 'Open Settings',
      );
      openedSettings = openSettings == true;

      if (openedSettings) {
        if (dialogKey == 'background_location') {
          await launchLocationPermissionSettings();
        } else {
          await launchAppSettings();
        }
        return PermissionSettingsPromptResult.openedSettings;
      }
      return PermissionSettingsPromptResult.dismissed;
    } finally {
      _dialogVisible = false;
    }
  }

  static void clearCooldown([String? dialogKey]) {
    if (dialogKey == null) {
      _lastPromptAtByKey.clear();
      return;
    }
    _lastPromptAtByKey.remove(dialogKey);
  }

  static bool _isInCooldown(String dialogKey) {
    final last = _lastPromptAtByKey[dialogKey];
    if (last == null) return false;
    return DateTime.now().difference(last) < _promptCooldown;
  }
}
