import 'dart:io';

import 'package:flutter/material.dart';

import '../app/app_navigator.dart';
import '../background/background_location_permissions.dart';
import '../permissions/required_permissions_gate.dart';
import '../utilities/overlay_prompt_guard.dart';
import '../utilities/permission_settings_helper.dart';
import 'glass_action_dialog.dart';

enum ClockInBlockedAction { cancelled, openSettings }

class ClockInBlockedDialog {
  ClockInBlockedDialog._();

  static bool _dialogVisible = false;
  static final Map<String, DateTime> _lastShownAtByReason = {};
  static const Duration _repeatCooldown = Duration(seconds: 8);

  static const String cancelClockInLabel = 'Cancel';

  static const String failureTitle = 'Unable to verify attendance';
  static const String gpsAccuracyLowReason = 'gps_accuracy_low';
  static const String gpsAccuracyFailureTitle = 'Weak GPS signal';
  static const String gpsAccuracyFailureMessage =
      'Make sure you turn on Wi-Fi and Bluetooth to improve accuracy, '
      'then try again later.';
  static const String cancelReason = 'clock_in_cancelled';
  static const String cancelMessage = 'Shift attendance was not completed.';

  static Future<void> showGpsAccuracyFailureForClockIn() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (RequiredPermissionsGate.shouldSuppressCompetingDialogs) return;
    if (_dialogVisible) return;
    if (PermissionSettingsHelper.settingsPromptVisible.value) return;
    if (_isInCooldown(gpsAccuracyLowReason)) return;

    final context = AppNavigator.key.currentContext;
    if (context == null || !context.mounted) return;

    await OverlayPromptGuard.waitUntilReady();

    final readyContext = AppNavigator.key.currentContext;
    if (readyContext == null || !readyContext.mounted) return;

    _dialogVisible = true;
    _lastShownAtByReason[gpsAccuracyLowReason] = DateTime.now();

    try {
      await GlassActionDialog.show(
        context: readyContext,
        icon: Icons.gps_not_fixed_rounded,
        title: gpsAccuracyFailureTitle,
        message: gpsAccuracyFailureMessage,
        primaryLabel: 'OK',
        variant: GlassActionDialogVariant.error,
      );
    } finally {
      _dialogVisible = false;
    }
  }

  static Future<ClockInBlockedAction?> showLocationSettingsPrompt(
    String? deniedReason,
  ) async {
    if (RequiredPermissionsGate.shouldSuppressCompetingDialogs) return null;
    if (_dialogVisible) return null;
    if (PermissionSettingsHelper.settingsPromptVisible.value) return null;

    final context = AppNavigator.key.currentContext;
    if (context == null || !context.mounted) return null;

    await OverlayPromptGuard.waitUntilReady();

    final readyContext = AppNavigator.key.currentContext;
    if (readyContext == null || !readyContext.mounted) return null;

    _dialogVisible = true;

    try {
      final bool? accepted;
      if (Platform.isAndroid) {

        OverlayPromptGuard.registerBlockingOverlay();
        try {
          accepted = await showGeneralDialog<bool>(
            context: readyContext,
            barrierDismissible: false,
            barrierLabel: 'Dismiss',
            barrierColor: Colors.black54,
            transitionDuration: Duration.zero,
            pageBuilder: (dialogContext, animation, secondaryAnimation) {
              return GlassActionDialog(
                icon: Icons.location_on_rounded,
                title: BackgroundLocationPermissions.clockInTitleFor(
                  deniedReason,
                ),
                message: BackgroundLocationPermissions.clockInSettingsMessageFor(
                  deniedReason,
                ),
                secondaryLabel: cancelClockInLabel,
                primaryLabel: 'Open Settings',
                destructiveSecondary: false,
              );
            },
          );
        } finally {
          OverlayPromptGuard.unregisterBlockingOverlay();
        }
      } else {
        accepted = await GlassActionDialog.show(
          context: readyContext,
          icon: Icons.location_on_rounded,
          title: BackgroundLocationPermissions.clockInTitleFor(deniedReason),
          message: BackgroundLocationPermissions.clockInSettingsMessageFor(
            deniedReason,
          ),
          secondaryLabel: cancelClockInLabel,
          primaryLabel: 'Open Settings',
          destructiveSecondary: false,
        );
      }
      if (accepted != true) return ClockInBlockedAction.cancelled;
      return ClockInBlockedAction.openSettings;
    } finally {
      _dialogVisible = false;
    }
  }

  static Future<ClockInBlockedAction?> showFailure({
    required String reason,
    required String title,
    required String message,
    bool bypassCooldown = false,
  }) async {

    if (RequiredPermissionsGate.shouldSuppressCompetingDialogs) return null;
    if (Platform.isAndroid &&
        PermissionSettingsHelper.isAwaitingSettingsReturn) {
      return null;
    }
    if (_dialogVisible) return null;
    if (PermissionSettingsHelper.settingsPromptVisible.value) return null;
    if (!bypassCooldown && _isInCooldown(reason)) return null;

    final context = AppNavigator.key.currentContext;
    if (context == null || !context.mounted) return null;

    await OverlayPromptGuard.waitUntilReady();

    if (Platform.isAndroid &&
        PermissionSettingsHelper.isAwaitingSettingsReturn) {
      return null;
    }

    final readyContext = AppNavigator.key.currentContext;
    if (readyContext == null || !readyContext.mounted) return null;

    final labels = _failureLabelsFor(reason);
    _dialogVisible = true;
    _lastShownAtByReason[reason] = DateTime.now();

    try {
      final accepted = await GlassActionDialog.show(
        context: readyContext,
        icon: labels.icon,
        title: title,
        message: message,
        secondaryLabel: cancelClockInLabel,
        primaryLabel: labels.primaryLabel,
        variant: GlassActionDialogVariant.error,
        destructiveSecondary: true,
      );
      if (accepted != true) return ClockInBlockedAction.cancelled;
      return labels.primaryAction;
    } finally {
      _dialogVisible = false;
    }
  }

  static bool _isInCooldown(String reason) {
    final last = _lastShownAtByReason[reason];
    if (last == null) return false;
    return DateTime.now().difference(last) < _repeatCooldown;
  }

  static void reconcileAfterAppResume() {
    if (!Platform.isAndroid) return;

    PermissionSettingsHelper.dismissStaleModalRouteIfPresent();
    if (!_dialogVisible) {
      return;
    }

    if (PermissionSettingsHelper.isAwaitingSettingsReturn) {
      _dialogVisible = false;
    }
  }

  static StoreSafeSettingsDestination settingsDestinationFor(String reason) {
    return BackgroundLocationPermissions.settingsDestinationFor(reason);
  }

  static String failureMessageFor(String? deniedReason) {
    final alwaysAccessLabel =
        BackgroundLocationPermissions.alwaysAccessLabel();

    switch (deniedReason) {
      case 'location_services_disabled':
        return 'Shift attendance was not completed. Location services are turned '
            'off on this device. Turn them on in Settings, then try again.';
      case 'location_foreground':
      case 'location_when_in_use':
        return 'Shift attendance was not completed. Background location '
            '($alwaysAccessLabel) is required. Open Settings and set location to '
            '$alwaysAccessLabel, then try again.';
      case 'location_background':
        return 'Shift attendance was not completed. Set location to '
            '$alwaysAccessLabel in Settings. Without background location, '
            'attendance cannot be verified from this app.';
      case 'location_always':
        if (Platform.isIOS) {
          return 'Shift attendance was not completed. Open Settings, tap '
              'SmartNPS360, choose Location, then select $alwaysAccessLabel. '
              'Attendance cannot be verified without $alwaysAccessLabel access.';
        }
        return 'Shift attendance was not completed. Open Settings and set '
            'location to $alwaysAccessLabel. Attendance cannot be verified without '
            'background location.';
      case 'location_precise':
        if (Platform.isIOS) {
          return 'Shift attendance was not completed. Open Settings, tap '
              'SmartNPS360, choose Location, then turn on Precise Location. '
              'Attendance cannot be verified without precise location.';
        }
        return 'Shift attendance was not completed. Open Settings and turn on '
            'Precise location for SmartNPS360. Attendance cannot be verified '
            'without precise location.';
      case 'gps_unavailable':
        return 'Shift attendance was not completed. Could not get your current '
            'location. Move outdoors or wait for GPS, then try again.';
      case 'mock_location':
        return 'Shift attendance was not completed. Disable mock or fake GPS '
            'location before verifying shift attendance from the mobile app.';
      default:
        return 'Shift attendance was not completed. Background location '
            '($alwaysAccessLabel) is required for shift attendance from the '
            'mobile app.';
    }
  }

  static _FailureDialogLabels _failureLabelsFor(String reason) {
    switch (reason) {
      case 'location_services_disabled':
      case 'location_foreground':
      case 'location_when_in_use':
      case 'location_background':
      case 'location_always':
      case 'location_precise':
      case 'background_location_required':
        return const _FailureDialogLabels(
          icon: Icons.error_outline_rounded,
          primaryLabel: 'Open Settings',
          primaryAction: ClockInBlockedAction.openSettings,
        );
      default:
        return const _FailureDialogLabels(
          icon: Icons.error_outline_rounded,
          primaryLabel: 'OK',
          primaryAction: ClockInBlockedAction.cancelled,
        );
    }
  }
}

class _FailureDialogLabels {
  const _FailureDialogLabels({
    required this.icon,
    required this.primaryLabel,
    required this.primaryAction,
  });

  final IconData icon;
  final String primaryLabel;
  final ClockInBlockedAction primaryAction;
}
