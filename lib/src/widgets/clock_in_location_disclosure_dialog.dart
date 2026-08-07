import 'dart:io';

import 'package:flutter/material.dart';

import '../background/background_location_permissions.dart';
import '../background/location_disclosure_consent.dart';
import '../permissions/required_permissions_gate.dart';
import 'clock_in_blocked_dialog.dart';
import 'glass_action_dialog.dart';

class ClockInLocationDisclosureDialog extends StatelessWidget {
  const ClockInLocationDisclosureDialog({super.key});

  static const String cancelLabel = 'Cancel';
  static const String title = 'Location required for shift attendance';
  static const double _messageMaxHeightFactor = 0.48;

  static String _alwaysAccessLabel() =>
      BackgroundLocationPermissions.alwaysAccessLabel();

  static String _foregroundStepLabel() =>
      BackgroundLocationPermissions.foregroundAccessLabel();

  static String _messageForPhase({
    required bool compact,
    LocationPermissionPhase phase = LocationPermissionPhase.none,
  }) {
    final alwaysAccessLabel = _alwaysAccessLabel();
    final foregroundStepLabel = _foregroundStepLabel();
    final core = compact
        ? 'SmartNPS360 uses your location only during an active shift to verify '
            'attendance and field activity. Sent to your employer; stops when your '
            'shift ends.'
        : 'SmartNPS360 uses your location only during an active shift to verify '
            'attendance, breaks, visits, and field activity. Your live location may '
            'be collected in the background and is sent to your employer. Tracking '
            'stops when your shift ends.';
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

  static Future<bool> show(
    BuildContext context, {
    LocationPermissionPhase phase = LocationPermissionPhase.none,
    bool compact = false,
  }) async {
    if (RequiredPermissionsGate.shouldSuppressCompetingDialogs) {
      return false;
    }
    if (!await LocationDisclosureConsent.shouldShowLocationDisclosure()) {
      return true;
    }

    final result = await GlassActionDialog.show(
      context: context,
      icon: Icons.location_on_rounded,
      title: title,
      message: _messageForPhase(compact: compact, phase: phase),
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
