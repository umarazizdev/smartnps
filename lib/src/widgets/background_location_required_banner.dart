import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../app/native_theme_controller.dart';
import '../background/background_location_permissions.dart';
import '../background/duty_heartbeat_service.dart';
import '../utilities/app_lifecycle_resume_gate.dart';
import '../utilities/app_config.dart';

class BackgroundLocationRequiredBanner extends StatefulWidget {
  const BackgroundLocationRequiredBanner({super.key});

  @override
  State<BackgroundLocationRequiredBanner> createState() =>
      _BackgroundLocationRequiredBannerState();
}

class _BackgroundLocationRequiredBannerState
    extends State<BackgroundLocationRequiredBanner>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  String? _deniedReason;
  bool _loading = true;
  bool _requestInFlight = false;
  late final AnimationController _highlightController;
  late final Animation<double> _highlightPulse;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _highlightPulse = CurvedAnimation(
      parent: _highlightController,
      curve: Curves.easeInOut,
    );
    unawaited(_refreshBannerContent());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncHighlightAnimation();
  }

  void _syncHighlightAnimation() {
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;
    if (reduceMotion) {
      _highlightController.stop();
      _highlightController.value = 1;
      return;
    }
    if (!_highlightController.isAnimating) {
      _highlightController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _highlightController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppLifecycleResumeGate.notifyResumed();
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
      await DutyHeartbeatService.instance.handleBannerEnableLocationAction(
        context,
      );
      await _refreshBannerContent();
    } finally {
      if (mounted) setState(() => _requestInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isDark = NativeThemeController.instance.isDark;
      return _buildBanner(isDark);
    });
  }

  Widget _buildBanner(bool isDark) {
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

    // Light: warm cream warning strip. Dark: slate bar matching web cards.
    final background = isDark
        ? const Color(0xFF1A2332)
        : const Color(0xFFFFF4E6);
    final backgroundPeak = isDark
        ? const Color(0xFF243044)
        : const Color(0xFFFFE3C2);
    final accent = isDark ? const Color(0xFFFBBF24) : const Color(0xFFC2410C);
    final accentBright = isDark
        ? const Color(0xFFFDE68A)
        : const Color(0xFFEA580C);
    final titleColor = isDark ? Colors.white : const Color(0xFF111827);
    final messageColor = isDark
        ? Colors.white.withValues(alpha: 0.86)
        : const Color(0xFF374151);
    final buttonBackground =
        isDark ? const Color(0xFFFBBF24) : const Color(AppConfig.cPrimary);
    final buttonForeground =
        isDark ? const Color(0xFF111827) : Colors.white;

    return AnimatedBuilder(
      animation: _highlightPulse,
      builder: (context, child) {
        final pulse = _highlightPulse.value;
        final borderAlpha = isDark
            ? lerpDouble(0.55, 1.0, pulse)!
            : lerpDouble(0.72, 1.0, pulse)!;
        final accentBarWidth = lerpDouble(isDark ? 4 : 5, isDark ? 6 : 7, pulse)!;
        final animatedBackground = Color.lerp(background, backgroundPeak, pulse)!;
        final glowAlpha = isDark
            ? lerpDouble(0.16, 0.42, pulse)!
            : lerpDouble(0.22, 0.5, pulse)!;

        return Material(
          color: animatedBackground,
          elevation: isDark ? 0 : lerpDouble(0, 2.5, pulse)!,
          shadowColor: accent.withValues(alpha: glowAlpha),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: accentBright.withValues(alpha: borderAlpha),
                  width: isDark ? 1.5 : 2,
                ),
                left: BorderSide(
                  color: accentBright.withValues(alpha: borderAlpha),
                  width: accentBarWidth,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: glowAlpha),
                  blurRadius: lerpDouble(isDark ? 8 : 6, isDark ? 20 : 16, pulse)!,
                  spreadRadius: lerpDouble(0, isDark ? 1.2 : 1, pulse)!,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedBuilder(
                  animation: _highlightPulse,
                  builder: (context, iconChild) {
                    final pulse = _highlightPulse.value;
                    final iconScale = lerpDouble(1.0, 1.1, pulse)!;
                    return Transform.scale(
                      scale: iconScale,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: isDark
                              ? accent.withValues(
                                  alpha: lerpDouble(0.14, 0.28, pulse)!,
                                )
                              : Colors.white.withValues(
                                  alpha: lerpDouble(0.72, 1.0, pulse)!,
                                ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: accentBright.withValues(
                              alpha: isDark
                                  ? lerpDouble(0.45, 0.9, pulse)!
                                  : lerpDouble(0.55, 1.0, pulse)!,
                            ),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(
                                alpha: isDark
                                    ? lerpDouble(0.18, 0.45, pulse)!
                                    : lerpDouble(0.24, 0.55, pulse)!,
                              ),
                              blurRadius: lerpDouble(4, 12, pulse)!,
                              spreadRadius: lerpDouble(0, 1, pulse)!,
                            ),
                          ],
                        ),
                        child: iconChild,
                      ),
                    );
                  },
                  child: Icon(
                    Icons.location_on_rounded,
                    color: accentBright,
                    size: 19,
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
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
                        style: TextStyle(
                          color: messageColor,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedBuilder(
                animation: _highlightPulse,
                builder: (context, child) {
                  final pulse = _highlightPulse.value;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: buttonBackground.withValues(
                            alpha: isDark
                                ? lerpDouble(0.12, 0.35, pulse)!
                                : lerpDouble(0.18, 0.42, pulse)!,
                          ),
                          blurRadius: lerpDouble(2, 10, pulse)!,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: child,
                  );
                },
                child: FilledButton(
                  onPressed:
                      _loading || _requestInFlight ? null : _onEnableLocation,
                  style: FilledButton.styleFrom(
                    backgroundColor: buttonBackground,
                    foregroundColor: buttonForeground,
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
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
