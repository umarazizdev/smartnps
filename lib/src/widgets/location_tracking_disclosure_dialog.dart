import 'dart:io';

import 'package:flutter/material.dart';

import '../background/background_location_permissions.dart';
import '../background/location_disclosure_consent.dart';
import 'glass_action_dialog.dart';

class LocationTrackingDisclosureDialog extends StatelessWidget {
  const LocationTrackingDisclosureDialog({super.key});

  static const String cancelDutyLabel = 'Cancel duty tracking';

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

  static String _dutyDisclosureMessage({
    required bool compact,
    LocationPermissionPhase phase = LocationPermissionPhase.none,
  }) {
    final alwaysAccessLabel = _alwaysAccessLabel();
    final foregroundStepLabel = _foregroundStepLabel();
    final intro =
        'SmartNPS360 uses your location only during an active shift to verify '
        'attendance, breaks, visits, and field activity.';
    final steps = switch (phase) {
      LocationPermissionPhase.foregroundOnly =>
        compact
            ? 'On the next screen, tap Open Settings and set location to '
                '$alwaysAccessLabel.'
            : 'After you tap Continue, you will see an Open Settings prompt. '
                'Set location to $alwaysAccessLabel for on-duty tracking.',
      LocationPermissionPhase.backgroundReady =>
        'Background location ($alwaysAccessLabel) is already enabled for on-duty '
        'tracking.',
      LocationPermissionPhase.none =>
        compact
            ? 'You will be asked to allow location access, then $alwaysAccessLabel '
                'access for on-duty background tracking.'
            : 'You will be asked in two steps:\n'
                '1. Allow location ($foregroundStepLabel)\n'
                '2. Then allow $alwaysAccessLabel access so tracking works when the '
                'app is in the background or not on screen.',
    };
    final dutyOnly =
        'Your live location is collected and uploaded only while you are on duty. '
        'Tracking stops when you clock out or end your shift.';
    final iosNote = Platform.isIOS
        ? '\n\nIf you force-close SmartNPS360 from the app switcher, location '
            'updates may pause until you open the app again.'
        : '';
    return '$intro\n\n$steps\n\n$dutyOnly$iosNote';
  }

  static String _titleForPhase(LocationPermissionPhase phase) {
    return switch (phase) {
      LocationPermissionPhase.foregroundOnly => 'Background location for duty',
      LocationPermissionPhase.backgroundReady => 'Location tracking during duty',
      LocationPermissionPhase.none => 'Location tracking during duty',
    };
  }

  static Future<bool> show(
    BuildContext context, {
    LocationPermissionPhase phase = LocationPermissionPhase.none,
  }) async {
    if (!await LocationDisclosureConsent.shouldShowLocationDisclosure()) {
      return true;
    }

    final result = await GlassActionDialog.show(
      context: context,
      icon: Icons.location_on_rounded,
      title: _titleForPhase(phase),
      message: _dutyDisclosureMessage(compact: false, phase: phase),
      secondaryLabel: cancelDutyLabel,
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
