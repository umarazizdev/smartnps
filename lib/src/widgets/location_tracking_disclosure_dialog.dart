import 'dart:io';

import 'package:flutter/material.dart';

import 'glass_action_dialog.dart';

class LocationTrackingDisclosureDialog extends StatelessWidget {
  const LocationTrackingDisclosureDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final alwaysAccessLabel = Platform.isIOS
        ? 'Always'
        : Platform.isAndroid
        ? 'Allow all the time'
        : 'always-on';
    final result = await GlassActionDialog.show(
      context: context,
      icon: Icons.location_on_rounded,
      title: 'Location tracking during duty',
      message:
          'SmartNPS360 uses your location only during an active shift to verify attendance, breaks, visits, and field activity.\n\n'
          'Please enable $alwaysAccessLabel location access to continue your shift, even when the app is closed or not on screen.\n\n'
          'Your live location is collected and uploaded only while you are on duty. Tracking stops when you clock out or end your shift.',
      secondaryLabel: 'Not now',
      primaryLabel: 'Continue',
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
