import 'package:flutter/material.dart';

import '../../background/location/background_location_permissions.dart';
import 'clock_in_location_disclosure_dialog.dart';

class LocationTrackingDisclosureDialog extends StatelessWidget {
  const LocationTrackingDisclosureDialog({super.key});

  static const String cancelDutyLabel = ClockInLocationDisclosureDialog.cancelLabel;

  static Future<bool> show(
    BuildContext context, {
    LocationPermissionPhase phase = LocationPermissionPhase.none,
  }) {
    return ClockInLocationDisclosureDialog.show(
      context,
      phase: phase,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
