import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app/app_navigator.dart';
import '../background/background_location_permissions.dart';
import '../widgets/glass_action_dialog.dart';

enum PermissionSettingsPromptResult { skipped, dismissed, openedSettings }

class PermissionSettingsHelper {
  PermissionSettingsHelper._();

  static bool _dialogVisible = false;
  static final Map<String, DateTime> _lastPromptAtByKey = {};

  static const Duration _promptCooldown = Duration(minutes: 2);

  static bool shouldOpenSettings(PermissionStatus status) {
    return status.isPermanentlyDenied || status.isRestricted || status.isDenied;
  }

  static Future<void> launchAppSettings() async {
    await Geolocator.openAppSettings();
  }

  /// Opens the native location-permission flow when possible, then falls back to
  /// app settings only if the system dialog cannot be shown again.
  static Future<void> launchLocationPermissionSettings() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        return;
      }
    }

    if (Platform.isAndroid) {
      final foreground = await Permission.location.status;
      if (!foreground.isGranted) {
        final foregroundResult = await Permission.location.request();
        if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
          return;
        }
        if (shouldOpenSettings(foregroundResult)) {
          await launchAppSettings();
          return;
        }
      }

      final background = await Permission.locationAlways.status;
      if (!background.isGranted) {
        // Foreground already granted: shows Android "Allow all the time" sheet.
        final backgroundResult = await Permission.locationAlways.request();
        if (backgroundResult.isGranted) return;
        if (shouldOpenSettings(backgroundResult) || backgroundResult.isDenied) {
          await launchAppSettings();
        }
        return;
      }
      return;
    }

    if (Platform.isIOS) {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.always) return;
      }
      await Geolocator.openAppSettings();
      return;
    }

    await launchAppSettings();
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

    _dialogVisible = true;
    _lastPromptAtByKey[dialogKey] = DateTime.now();
    var openedSettings = false;

    try {
      final openSettings = await GlassActionDialog.show(
        context: context,
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
