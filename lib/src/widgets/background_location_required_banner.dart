import 'dart:async';

import 'package:flutter/material.dart';

import '../background/background_location_permissions.dart';
import '../background/duty_heartbeat_service.dart';
import '../utilities/app_config.dart';
import '../utilities/permission_settings_helper.dart';

class BackgroundLocationRequiredBanner extends StatefulWidget {
  const BackgroundLocationRequiredBanner({super.key});

  @override
  State<BackgroundLocationRequiredBanner> createState() =>
      _BackgroundLocationRequiredBannerState();
}

class _BackgroundLocationRequiredBannerState
    extends State<BackgroundLocationRequiredBanner> with WidgetsBindingObserver {
  String? _deniedReason;
  bool _loading = true;
  bool _requestInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshBannerContent());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshBannerContent());
    }
  }

  Future<void> _refreshBannerContent() async {
    final reason =
        await BackgroundLocationPermissions.settingsDeniedReasonIfAny();
    if (!mounted) return;
    setState(() {
      _deniedReason = reason;
      _loading = false;
    });
  }

  Future<void> _onEnableLocation() async {
    if (_requestInFlight) return;
    setState(() => _requestInFlight = true);
    try {
      await PermissionSettingsHelper.requestNextLocationPermissionStep();
      await _refreshBannerContent();
      await DutyHeartbeatService.instance
          .refreshBackgroundLocationPermissionBannerState();
    } finally {
      if (mounted) setState(() => _requestInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final deniedReason = _deniedReason;
    final title = _loading
        ? 'Location permission needed'
        : BackgroundLocationPermissions.bannerTitleFor(deniedReason);
    final message = _loading
        ? 'Checking location access...'
        : BackgroundLocationPermissions.bannerMessageFor(deniedReason);
    final buttonLabel = _loading
        ? 'Enable Location'
        : BackgroundLocationPermissions.bannerButtonLabelFor(deniedReason);

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
                          title,
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          message,
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
                  onPressed: _loading || _requestInFlight ? null : _onEnableLocation,
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
                  child: Text(
                    buttonLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
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
