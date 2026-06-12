import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../background/duty_heartbeat_service.dart';
import '../utilities/app_config.dart';
import '../utilities/permission_settings_helper.dart';

class BackgroundLocationRequiredBanner extends StatelessWidget {
  const BackgroundLocationRequiredBanner({super.key});

  Future<void> _onEnableLocation() async {
    await PermissionSettingsHelper.launchLocationPermissionSettings();
  }

  String _permissionHint() {
    if (Platform.isIOS) return 'Always';
    if (Platform.isAndroid) return 'Allow all the time';
    return 'Always';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final permissionHint = _permissionHint();

    final background = isDark
        ? const Color(0xFF1A2332)
        : const Color(0xFFFFF8E7);
    final accent = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    final titleColor = isDark ? Colors.white : const Color(0xFF1F2937);
    final messageColor = isDark
        ? Colors.white.withValues(alpha: 0.72)
        : const Color(0xFF4B5563);
    final borderColor = isDark
        ? accent.withValues(alpha: 0.45)
        : accent.withValues(alpha: 0.35);

    return Material(
      color: background,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: borderColor, width: 1)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isDark ? 0.16 : 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.location_on_rounded,
                      color: accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Background location required',
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Enable $permissionHint location to continue duty tracking. '
                          'Your location is used only while you are on duty.',
                          style: TextStyle(
                            color: messageColor,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    unawaited(() async {
                      await _onEnableLocation();
                      await DutyHeartbeatService.instance
                          .refreshBackgroundLocationPermissionBannerState();
                    }());
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark
                        ? accent
                        : const Color(AppConfig.cPrimary),
                    foregroundColor: isDark
                        ? const Color(0xFF111827)
                        : Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Enable Location',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
