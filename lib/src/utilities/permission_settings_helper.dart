import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app/app_navigator.dart';
import '../utilities/app_config.dart';
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

  /// Background (Always) location only — not for foreground / while-in-use.
  static String get iosBackgroundLocationSettingsSteps =>
      'Settings → Apps → ${AppConfig.appName} → Location → Always';

  static String get androidBackgroundLocationSettingsSteps =>
      'Settings → Apps → ${AppConfig.appName} → Permissions → Location → '
      'Allow all the time';

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
        await launchAppSettings();
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
