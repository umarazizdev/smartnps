import 'dart:io';

import 'package:flutter/material.dart';

import '../background/background_location_permissions.dart';
import '../background/location_disclosure_consent.dart';
import 'clock_in_blocked_dialog.dart';
import 'glass_action_dialog.dart';

/// Store-safe disclosure shown only before clock-in location permission prompts.
class ClockInLocationDisclosureDialog extends StatelessWidget {
  const ClockInLocationDisclosureDialog({super.key});

  static String _alwaysAccessLabel() {
    if (Platform.isIOS) return 'Always';
    if (Platform.isAndroid) return 'Allow all the time';
    return 'always-on';
  }

  static String _foregroundStepLabel() {
    if (Platform.isIOS) return 'While Using the App';
    if (Platform.isAndroid) return 'While using the app';
    return 'while using the app';
  }

  static String _messageForPhase({
    required bool compact,
    LocationPermissionPhase phase = LocationPermissionPhase.none,
  }) {
    final alwaysAccessLabel = _alwaysAccessLabel();
    final foregroundStepLabel = _foregroundStepLabel();
    final core = compact
        ? 'Location verifies clock-in and your shift. Sent to your employer; '
            'stops when you clock out.'
        : 'Your location verifies clock-in and is used during your shift for '
            'attendance and field work. Data is sent to your employer and '
            'stops when you clock out.';
    final requirement = compact
        ? '$alwaysAccessLabel is required to clock in from this app.'
        : '$alwaysAccessLabel is required when the app is not on screen. '
            'Without it, you cannot clock in from this app.';
    final steps = switch (phase) {
      LocationPermissionPhase.foregroundOnly =>
        compact
            ? 'Open Settings and set location to $alwaysAccessLabel.'
            : 'You allowed $foregroundStepLabel. Open Settings and set '
                'location to $alwaysAccessLabel.',
      LocationPermissionPhase.backgroundReady =>
        compact
            ? '$alwaysAccessLabel is enabled. You can clock in now.'
            : '$alwaysAccessLabel is enabled. You can clock in at your work '
                'location.',
      LocationPermissionPhase.none =>
        compact
            ? 'Allow $foregroundStepLabel, then $alwaysAccessLabel.'
            : 'Next: allow $foregroundStepLabel, then $alwaysAccessLabel.',
    };
    if (phase == LocationPermissionPhase.backgroundReady) {
      return '$core\n\n$steps';
    }
    return '$core\n\n$steps\n\n$requirement';
  }

  static Future<bool> show(
    BuildContext context, {
    LocationPermissionPhase phase = LocationPermissionPhase.none,
    bool compact = false,
  }) async {
    if (!await LocationDisclosureConsent.shouldShowLocationDisclosure()) {
      return true;
    }

    final result = await GlassActionDialog.show(
      context: context,
      icon: Icons.login_rounded,
      title: 'Location required to clock in',
      message: _messageForPhase(compact: compact, phase: phase),
      secondaryLabel: ClockInBlockedDialog.cancelClockInLabel,
      primaryLabel: 'Continue',
      destructiveSecondary: true,
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
