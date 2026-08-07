import 'dart:io';

import 'package:flutter/material.dart';

import '../utilities/overlay_prompt_guard.dart';
import '../utilities/permission_settings_helper.dart';
import 'glass_action_dialog.dart';

/// Guides the user to enable Motion & Fitness / Physical activity after they
/// deny the OS permission prompt.
class MotionActivitySettingsDialog {
  MotionActivitySettingsDialog._();

  static const String dialogKey = 'motion_activity';

  static String get permissionName =>
      Platform.isAndroid ? 'Physical activity' : 'Motion & Fitness';

  static String get title => '$permissionName is off';

  static List<String> get appSettingsSteps {
    if (Platform.isAndroid) {
      return const [
        'Open Settings',
        'Tap Apps, then SmartNPS360',
        'Tap Permissions',
        'Tap Physical activity',
        'Choose Allow',
      ];
    }
    return const [
      'Open Settings',
      'Tap SmartNPS360',
      'Turn on Motion & Fitness',
    ];
  }

  static List<String> get phoneSettingsSteps {
    if (Platform.isAndroid) {
      return const [
        'Open Settings',
        'Search for "Physical activity" or "Permission manager"',
        'Find SmartNPS360',
        'Set Physical activity to Allow',
      ];
    }
    return const [
      'Open Settings',
      'Tap Privacy & Security',
      'Tap Motion & Fitness',
      'Turn on SmartNPS360',
    ];
  }

  /// Shows the guidance dialog. Returns `true` if the user chose Open Settings.
  static Future<bool> show({BuildContext? context}) async {
    if (PermissionSettingsHelper.resolveDialogContext(context) == null) {
      return false;
    }

    await OverlayPromptGuard.waitUntilReady();

    // Prefer the root navigator after the await so we never reuse a stale
    // caller BuildContext across the async gap.
    final readyContext = PermissionSettingsHelper.resolveDialogContext();
    if (readyContext == null || !readyContext.mounted) return false;

    PermissionSettingsHelper.settingsPromptVisible.value = true;
    try {
      final openSettings = await GlassActionDialog.show(
        context: readyContext,
        barrierDismissible: false,
        icon: Icons.directions_walk_rounded,
        title: title,
        content: _MotionActivitySettingsContent(
          permissionName: permissionName,
          appSettingsSteps: appSettingsSteps,
          phoneSettingsSteps: phoneSettingsSteps,
        ),
        secondaryLabel: 'Not now',
        primaryLabel: 'Open Settings',
        messageMaxHeightFactor: 0.55,
      );
      return openSettings == true;
    } finally {
      PermissionSettingsHelper.settingsPromptVisible.value = false;
    }
  }

  /// Shows guidance, then opens app settings when the user confirms.
  static Future<bool> showAndMaybeOpenSettings({BuildContext? context}) async {
    final open = await show(context: context);
    if (!open) return false;
    await PermissionSettingsHelper.openSettingsForUserTap(
      destination: StoreSafeSettingsDestination.app,
      waitForReturn: true,
    );
    return true;
  }
}

class _MotionActivitySettingsContent extends StatelessWidget {
  const _MotionActivitySettingsContent({
    required this.permissionName,
    required this.appSettingsSteps,
    required this.phoneSettingsSteps,
  });

  final String permissionName;
  final List<String> appSettingsSteps;
  final List<String> phoneSettingsSteps;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.72)
        : const Color(0xFF5D6168);
    final titleColor = isDark ? Colors.white : const Color(0xFF171717);
    final stepBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFF3F4F6);
    final stepNumberBg = isDark
        ? const Color(0xFF1E3A5F)
        : const Color(0xFFEEF2FF);
    final stepNumberFg = isDark
        ? const Color(0xFF93C5FD)
        : const Color(0xFF3B82F6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'SmartNPS360 needs $permissionName to detect walking, driving, and '
          'other activity while you are on duty.\n\n'
          'You can turn it back on using either path below.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: bodyColor,
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 16),
        _StepSection(
          heading: 'From app settings',
          steps: appSettingsSteps,
          titleColor: titleColor,
          bodyColor: bodyColor,
          stepBg: stepBg,
          stepNumberBg: stepNumberBg,
          stepNumberFg: stepNumberFg,
        ),
        const SizedBox(height: 14),
        _StepSection(
          heading: 'From phone settings',
          steps: phoneSettingsSteps,
          titleColor: titleColor,
          bodyColor: bodyColor,
          stepBg: stepBg,
          stepNumberBg: stepNumberBg,
          stepNumberFg: stepNumberFg,
        ),
      ],
    );
  }
}

class _StepSection extends StatelessWidget {
  const _StepSection({
    required this.heading,
    required this.steps,
    required this.titleColor,
    required this.bodyColor,
    required this.stepBg,
    required this.stepNumberBg,
    required this.stepNumberFg,
  });

  final String heading;
  final List<String> steps;
  final Color titleColor;
  final Color bodyColor;
  final Color stepBg;
  final Color stepNumberBg;
  final Color stepNumberFg;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: stepBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              heading,
              style: TextStyle(
                color: titleColor,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: stepNumberBg,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: stepNumberFg,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        steps[i],
                        style: TextStyle(
                          color: bodyColor,
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
