import 'dart:io';

import 'package:flutter/material.dart';

import '../../background/location/background_location_permissions.dart';
import '../../background/duty/location_disclosure_consent.dart';
import '../../permissions/required_permissions_gate.dart';
import 'clock_in_blocked_dialog.dart';
import 'glass_action_dialog.dart';

class ClockInLocationDisclosureDialog extends StatelessWidget {
  const ClockInLocationDisclosureDialog({super.key});

  static const String cancelLabel = 'Cancel';
  static const String title = 'SmartNPS360 Location Notice';
  static const double _messageMaxHeightFactor = 0.48;

  static String _alwaysAccessLabel() =>
      BackgroundLocationPermissions.alwaysAccessLabel();

  static String _foregroundStepLabel() =>
      BackgroundLocationPermissions.foregroundAccessLabel();

  static String _privacyNoticeCore({required bool compact}) {
    if (compact) {
      return 'Location is used only while you are clocked in on an active shift. '
          'It supports safety, patrol verification, and attendance. '
          'SmartNPS360 may collect and use your location, including in the '
          'background. Tracking stops when your shift ends and you clock out.';
    }
    return 'Location is used only while you are clocked in on an active shift.\n'
        'It supports safety, patrol verification, and attendance.\n\n'
        'While you are on duty:\n'
        'SmartNPS360 may collect and use your location, including in the '
        'background.\n\n'
        'When you clock out:\n'
        'Tracking stops when your shift ends and you clock out.\n\n'
        'Leaving the site (if enabled):\n'
        'If enabled, leaving the site can clock you out and stop tracking.';
  }

  static String _messageForPhase({
    required bool compact,
    LocationPermissionPhase phase = LocationPermissionPhase.none,
  }) {
    final alwaysAccessLabel = _alwaysAccessLabel();
    final foregroundStepLabel = _foregroundStepLabel();
    final core = _privacyNoticeCore(compact: compact);
    final requirement = compact
        ? '$alwaysAccessLabel is required for shift attendance from this app.'
        : '$alwaysAccessLabel is required when the app is not on screen. '
              'Without it, shift attendance cannot be verified from this app.';
    final steps = switch (phase) {
      LocationPermissionPhase.foregroundOnly =>
        compact
            ? 'Open Settings and set location to $alwaysAccessLabel.'
            : 'You allowed $foregroundStepLabel. Open Settings and set '
                  'location to $alwaysAccessLabel.',
      LocationPermissionPhase.backgroundReady =>
        compact
            ? '$alwaysAccessLabel is enabled. Location is ready for shift attendance.'
            : '$alwaysAccessLabel is enabled. Location is ready for shift attendance.',
      LocationPermissionPhase.none =>
        compact
            ? 'Allow $foregroundStepLabel, then $alwaysAccessLabel.'
            : 'You will be asked in two steps:\n'
                  '1. Allow location ($foregroundStepLabel)\n'
                  '2. Then allow $alwaysAccessLabel access so tracking works when the '
                  'app is in the background or not on screen.',
    };
    final iosNote = !compact && Platform.isIOS
        ? '\n\nIf you force-close SmartNPS360 from the app switcher, location '
              'updates may pause until you open the app again.'
        : '';
    if (phase == LocationPermissionPhase.backgroundReady) {
      return '$core\n\n$steps$iosNote';
    }
    return '$core\n\n$steps\n\n$requirement$iosNote';
  }

  static String _titleForPermission(String permissionId) {
    return switch (permissionId) {
      'locationServices' => 'Location Services required',
      'preciseLocation' => 'Precise location required',
      'backgroundLocation' => 'Background location required',
      'motionActivity' =>
        Platform.isAndroid
            ? 'Physical activity required'
            : 'Motion & Fitness required',
      'backgroundAppRefresh' =>
        Platform.isAndroid
            ? 'Background activity required'
            : 'Background App Refresh required',
      'foregroundLocation' => title,
      _ => title,
    };
  }

  static IconData _iconForPermission(String permissionId) {
    return switch (permissionId) {
      'locationServices' => Icons.location_off_rounded,
      'preciseLocation' => Icons.gps_fixed_rounded,
      'backgroundLocation' => Icons.share_location_rounded,
      'motionActivity' => Icons.directions_walk_rounded,
      'backgroundAppRefresh' => Icons.sync_rounded,
      _ => Icons.location_on_rounded,
    };
  }

  static String _alwaysLocationDisclosureMessage() {
    final alwaysLabel = _alwaysAccessLabel();
    return 'Background location ("$alwaysLabel") is required for live location '
        'while you are on duty—including when the app is in the background.\n\n'
        'Tracking stops when you clock out. You are not tracked off duty.';
  }

  static String _messageForPermission(
    String permissionId, {
    required LocationPermissionPhase phase,
  }) {
    return switch (permissionId) {
      'locationServices' =>
        '${_privacyNoticeCore(compact: true)}\n\n'
            'Device Location Services must be turned on to continue.',
      'preciseLocation' =>
        '${_privacyNoticeCore(compact: true)}\n\n'
            'Precise location is required for check-ins and attendance '
            'verification.',
      'backgroundLocation' => _alwaysLocationDisclosureMessage(),
      'motionActivity' =>
        'SmartNPS360 uses motion activity while you are on duty to detect '
            'walking, driving, or stationary movement so background location pings '
            'and route polylines stay accurate. Used only during your shift.',
      'backgroundAppRefresh' =>
        Platform.isAndroid
            ? 'Background activity must be allowed so SmartNPS360 can keep verifying '
                  'attendance while you are on duty and the app is not on screen. '
                  'Tracking may be unreliable until this is fixed.'
            : 'Background App Refresh must be enabled so SmartNPS360 can keep verifying '
                  'attendance while you are on duty and the app is not on screen. '
                  'Tracking may be unreliable until this is fixed.\n\n'
                  'Tap Continue to open Settings → Apps → SmartNPS360, then turn on '
                  'Background App Refresh.',
      _ => _messageForPhase(compact: false, phase: phase),
    };
  }

  static Future<bool> show(
    BuildContext context, {
    LocationPermissionPhase phase = LocationPermissionPhase.none,
    bool compact = false,
  }) async {
    if (Platform.isAndroid) {
      return true;
    }
    if (RequiredPermissionsGate.isPrivacyNoticeVisible) {
      return false;
    }
    if (!await LocationDisclosureConsent.shouldShowLocationDisclosure()) {
      return true;
    }

    return _present(
      context: context,
      icon: Icons.location_on_rounded,
      title: title,
      message: _messageForPhase(compact: compact, phase: phase),
    );
  }

  static Future<bool> showForPermission(
    BuildContext context, {
    required String permissionId,
  }) async {
    if (RequiredPermissionsGate.isPrivacyNoticeVisible) {
      return false;
    }

    if (Platform.isAndroid && permissionId != 'backgroundLocation') {
      return true;
    }

    final forceAlwaysDisclosure = permissionId == 'backgroundLocation';

    final isLocationPermission =
        permissionId != 'motionActivity' &&
        permissionId != 'backgroundAppRefresh';
    if (!forceAlwaysDisclosure &&
        isLocationPermission &&
        !await LocationDisclosureConsent.shouldShowLocationDisclosure()) {
      return true;
    }

    final phase = await BackgroundLocationPermissions.currentPermissionPhase();
    if (!context.mounted) return false;

    final allowed = await _present(
      context: context,
      icon: _iconForPermission(permissionId),
      title: _titleForPermission(permissionId),
      message: _messageForPermission(permissionId, phase: phase),
    );

    if (allowed && isLocationPermission) {
      await LocationDisclosureConsent.markAcceptedForAll();
    }
    return allowed;
  }

  static Future<bool> _present({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String message,
  }) async {
    final result = await GlassActionDialog.show(
      context: context,
      icon: icon,
      title: title,
      message: message,
      secondaryLabel: ClockInBlockedDialog.cancelClockInLabel,
      primaryLabel: 'Continue',
      destructiveSecondary: true,
      messageMaxHeightFactor: _messageMaxHeightFactor,
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
