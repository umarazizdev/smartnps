import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/new_screens/Widgets/new_common_widgets.dart';
import 'package:smartnps360/src/screens/new_screens/Widgets/new_quick_actions_overlay.dart';
import '../new_main_controller.dart';
import '../new_models.dart';
import 'new_dashboard_controller.dart';
import 'new_dashboard_dial_controller.dart';

class NewDashboardScreen extends StatelessWidget {
  const NewDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(NewDashboardController(), permanent: true);
    return _DashboardBackground(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Greeting(controller: controller),
                  const SizedBox(height: 12),
                  _HeroClock(controller: controller),
                  const SizedBox(height: 10),
                  _ShiftActions(controller: controller),
                  const SizedBox(height: 12),
                  _Stats(controller: controller),
                  const SizedBox(height: 14),
                  _Shortcuts(controller: controller),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardBackground extends StatelessWidget {
  const _DashboardBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = _DashStyle.dark(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF0E1726), Color(0xFF111B2B)]
              : const [Color(0xFFF8FAFC), Color(0xFFF2F5F9)],
        ),
      ),
      child: child,
    );
  }
}

class _DashStyle {
  static bool dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color text(BuildContext context) =>
      dark(context) ? const Color(0xFFF5F7FA) : const Color(0xFF172033);

  static Color secondary(BuildContext context) =>
      dark(context) ? const Color(0xFFAAB6C7) : const Color(0xFF667085);

  static Color surface(BuildContext context) =>
      dark(context) ? const Color(0xFF182335) : const Color(0xFFFFFFFF);

  static Color line(BuildContext context) =>
      dark(context) ? const Color(0xFF2B3A4E) : const Color(0xFFE4E9F0);

  // Semantic attention red: deeper on light surfaces for small-text contrast,
  // brighter in dark mode so alerts remain immediately visible.
  static Color attention(BuildContext context) =>
      dark(context) ? const Color(0xFFFF7582) : const Color(0xFFC92F42);

  static WidgetStateProperty<Color?> interactionOverlay(Color color) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) return color.withAlpha(30);
      if (states.contains(WidgetState.focused)) return color.withAlpha(24);
      if (states.contains(WidgetState.hovered)) return color.withAlpha(16);
      return null;
    });
  }

  static BoxDecoration card(BuildContext context, {double radius = 22}) =>
      BoxDecoration(
        color: surface(context),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: line(context)),
        boxShadow: dark(context)
            ? const []
            : [
                BoxShadow(
                  color: const Color(0xFF101828).withAlpha(10),
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                ),
              ],
      );
}

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: _DashStyle.card(context),
    padding: padding,
    child: child,
  );
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.controller});
  final NewDashboardController controller;

  Color _statusColor(NewLiveStatusMode mode) {
    switch (mode) {
      case NewLiveStatusMode.active:
        return NewUi.accent;
      case NewLiveStatusMode.breakMode:
        return NewUi.warning;
      case NewLiveStatusMode.standby:
        return const Color(0xFFB57818);
      case NewLiveStatusMode.idle:
        return NewUi.success;
    }
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    final color = _statusColor(controller.liveStatusMode.value);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 18,
                    height: 1.27,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.5,
                    color: _DashStyle.secondary(context),
                  ),
                  children: [
                    TextSpan(text: '${controller.greetingPrefix} '),
                    TextSpan(
                      text: controller.firstName,
                      style: TextStyle(
                        color: NewUi.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _DashStyle.dark(context)
                      ? Colors.white.withAlpha(9)
                      : const Color(0xFFF1F4F8),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: _DashStyle.line(context)),
                ),
                child: Text(
                  controller.officerRole.value.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .7,
                    color: _DashStyle.secondary(context),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: _LiveStatusPill(
            text: controller.liveStatusText.value,
            color: color,
          ),
        ),
      ],
    );
  });
}

class _LiveStatusPill extends StatelessWidget {
  const _LiveStatusPill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 220),
    constraints: const BoxConstraints(minHeight: 32),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withAlpha(_DashStyle.dark(context) ? 32 : 18),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: color.withAlpha(60)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NewPulseDot(color: color, size: 6),
        const SizedBox(width: 7),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              height: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _HeroClock extends StatefulWidget {
  const _HeroClock({required this.controller});
  final NewDashboardController controller;

  @override
  State<_HeroClock> createState() => _HeroClockState();
}

class _HeroClockState extends State<_HeroClock> with TickerProviderStateMixin {
  late final AnimationController _ringPulse;
  late final AnimationController _blinkPulse;
  late final NewDashboardDialController dialController;
  Worker? _blinkWorker;
  NewTimerBlinkTier _lastTier = NewTimerBlinkTier.none;

  @override
  void initState() {
    super.initState();
    dialController = Get.isRegistered<NewDashboardDialController>()
        ? Get.find<NewDashboardDialController>()
        : Get.put(NewDashboardDialController());
    _ringPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2300),
    )..repeat(reverse: true);
    _blinkPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _blinkWorker = ever<NewTimerBlinkTier>(
      widget.controller.blinkTier,
      _syncBlink,
    );
    _syncBlink(widget.controller.blinkTier.value);
  }

  @override
  void dispose() {
    _blinkWorker?.dispose();
    _ringPulse.dispose();
    _blinkPulse.dispose();
    super.dispose();
  }

  void _syncBlink(NewTimerBlinkTier tier) {
    if (tier == _lastTier) return;
    _lastTier = tier;
    if (tier == NewTimerBlinkTier.none) {
      _blinkPulse.stop();
      _blinkPulse.value = 0;
      return;
    }
    _blinkPulse.duration = Duration(
      milliseconds: tier == NewTimerBlinkTier.red
          ? 700
          : tier == NewTimerBlinkTier.orange
          ? 900
          : 1100,
    );
    if (!_blinkPulse.isAnimating) _blinkPulse.repeat(reverse: true);
  }

  Color _arrivalColor(NewArrivalStatus status, BuildContext context) {
    switch (status) {
      case NewArrivalStatus.pending:
        return _DashStyle.secondary(context);
      case NewArrivalStatus.early:
        return NewUi.accent;
      case NewArrivalStatus.onTime:
        return NewUi.success;
      case NewArrivalStatus.slight:
        return NewUi.warning;
      case NewArrivalStatus.late:
        return NewUi.danger;
    }
  }

  Color _blinkColor(NewTimerBlinkTier tier, double t, bool dark) {
    switch (tier) {
      case NewTimerBlinkTier.yellow:
        return Color.lerp(
          dark ? const Color(0xFFFBBF24) : const Color(0xFF985A00),
          dark ? const Color(0xFFFFE08A) : const Color(0xFFA76200),
          t,
        )!;
      case NewTimerBlinkTier.orange:
        return Color.lerp(
          dark ? const Color(0xFFFF964F) : const Color(0xFFA94708),
          dark ? const Color(0xFFFFC07C) : const Color(0xFFB84A08),
          t,
        )!;
      case NewTimerBlinkTier.red:
        return Color.lerp(
          dark ? const Color(0xFFFF7582) : const Color(0xFFC92F42),
          dark ? const Color(0xFFFFA5AD) : const Color(0xFFD63849),
          t,
        )!;
      case NewTimerBlinkTier.none:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Obx(() {
      final isBreak = controller.isOnBreak;
      final hasDuty = controller.hasActiveDuty;
      final tier = controller.blinkTier.value;
      final timerLabel = controller.timerLabel.value;
      final timerText = controller.timerText.value;
      final compact =
          controller.timerCompact.value || controller.lateStartedStyle.value;
      final isDark = _DashStyle.dark(context);

      return _DashboardPanel(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth - 8;
            final size = math.min(252.0, available).toDouble();
            return SizedBox(
              height: size + 2,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_ringPulse, _blinkPulse]),
                      builder: (_, _) => CustomPaint(
                        size: Size.square(size),
                        painter: _DialPainter(
                          lateEnd: controller.dialLateEnd.value,
                          work1End: controller.dialWork1End.value,
                          breakEnd: controller.dialBreakEnd.value,
                          liveEnd: controller.dialLiveEnd.value,
                          activeDots: controller.dialActiveDots.value,
                          dark: isDark,
                          pulse: _ringPulse.value,
                          blink: tier == NewTimerBlinkTier.none
                              ? 0
                              : _blinkPulse.value,
                          blinkTier: tier,
                        ),
                      ),
                    ),
                  ),
                  MediaQuery.withClampedTextScaling(
                    // A circular dial has a fixed safe text area. Keep system
                    // scaling useful without allowing labels to cross the ring.
                    maxScaleFactor: 1.15,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: size * .68),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: _blinkPulse,
                            builder: (_, _) {
                              final t = tier == NewTimerBlinkTier.none
                                  ? 0.0
                                  : _blinkPulse.value;
                              return Text(
                                timerLabel.toUpperCase(),
                                key: ValueKey(timerLabel),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: tier == NewTimerBlinkTier.none
                                      ? _DashStyle.secondary(context)
                                      : _blinkColor(tier, t, isDark),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.35,
                                  height: 1.15,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 6),
                          AnimatedBuilder(
                            animation: _blinkPulse,
                            builder: (_, _) {
                              final t = tier == NewTimerBlinkTier.none
                                  ? 0.0
                                  : _blinkPulse.value;
                              return FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  timerText,
                                  key: ValueKey(timerText),
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w800,
                                    fontSize: compact ? 18 : 27,
                                    height: 1.05,
                                    letterSpacing: -.8,
                                    color: tier == NewTimerBlinkTier.none
                                        ? (isBreak
                                              ? NewUi.warning
                                              : _DashStyle.text(context))
                                        : _blinkColor(tier, t, isDark),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 9),
                          if (!isBreak)
                            _RotatingRingFields(dialController: dialController),
                          if (isBreak) ...[
                            Text(
                              'BREAK ACTIVE',
                              style: TextStyle(
                                color: _DashStyle.secondary(context),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .9,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              controller.selectedSite.value,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _DashStyle.text(context),
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          if (!isBreak)
                            _DialPill(
                              text: controller.arrivalText.value,
                              icon: Icons.schedule_rounded,
                              color: _arrivalColor(
                                controller.arrivalStatus.value,
                                context,
                              ),
                            ),
                          if (isBreak)
                            _DialPill(
                              text: 'Break Active',
                              icon: Icons.hourglass_bottom_rounded,
                              color: NewUi.warning,
                            ),
                          if (hasDuty &&
                              controller.status.value !=
                                  NewOfficerStatus.standby) ...[
                            const SizedBox(height: 5),
                            _DialPill(
                              text: controller.breakBadgeText.value,
                              icon: Icons.coffee_rounded,
                              color: NewUi.warning,
                              strike:
                                  controller.breakBadgeText.value == 'Taken',
                              onTap: controller.toggleBreak,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    });
  }
}

class _RotatingRingFields extends StatelessWidget {
  const _RotatingRingFields({required this.dialController});
  final NewDashboardDialController dialController;

  @override
  Widget build(BuildContext context) => Obx(
    () => AnimatedOpacity(
      opacity: dialController.fading.value ? 0 : 1,
      duration: const Duration(milliseconds: 600),
      child: AnimatedSlide(
        offset: dialController.fading.value
            ? const Offset(0, .08)
            : Offset.zero,
        duration: const Duration(milliseconds: 600),
        child: Column(
          children: [
            Text(
              dialController.title.value.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                color: _DashStyle.secondary(context),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .85,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              dialController.subtitle.value,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _DashStyle.text(context),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DialPill extends StatelessWidget {
  const _DialPill({
    required this.text,
    required this.icon,
    required this.color,
    this.strike = false,
    this.onTap,
  });
  final String text;
  final IconData icon;
  final Color color;
  final bool strike;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withAlpha(_DashStyle.dark(context) ? 31 : 17),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12.5, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  text,
                  key: ValueKey(text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    decoration: strike ? TextDecoration.lineThrough : null,
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

class _DialPainter extends CustomPainter {
  const _DialPainter({
    required this.lateEnd,
    required this.work1End,
    required this.breakEnd,
    required this.liveEnd,
    required this.activeDots,
    required this.dark,
    required this.pulse,
    required this.blink,
    required this.blinkTier,
  });

  final double lateEnd;
  final double work1End;
  final double breakEnd;
  final double liveEnd;
  final int activeDots;
  final bool dark;
  final double pulse;
  final double blink;
  final NewTimerBlinkTier blinkTier;

  Color get _urgencyBase {
    switch (blinkTier) {
      case NewTimerBlinkTier.red:
        return dark ? const Color(0xFFFF5261) : const Color(0xFFD92535);
      case NewTimerBlinkTier.orange:
        return const Color(0xFFEA580C);
      case NewTimerBlinkTier.yellow:
        return const Color(0xFF10B981);
      case NewTimerBlinkTier.none:
        return Colors.transparent;
    }
  }

  Color get _urgencyBright {
    switch (blinkTier) {
      case NewTimerBlinkTier.red:
        return dark ? const Color(0xFFFFA3AB) : const Color(0xFFFF8A94);
      case NewTimerBlinkTier.orange:
        return const Color(0xFFFDBA74);
      case NewTimerBlinkTier.yellow:
        return const Color(0xFF6EE7B7);
      case NewTimerBlinkTier.none:
        return Colors.transparent;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 15;
    final start = math.pi * .74;
    final sweep = math.pi * 1.52;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final blinking = blinkTier != NewTimerBlinkTier.none;
    final idleTrack = dark
        ? Colors.white.withAlpha(17)
        : const Color(0xFFE8EDF5);

    if (blinking) {
      final trackColor = Color.lerp(_urgencyBase, _urgencyBright, blink)!;
      final trackGlow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18 + blink * 6
        ..strokeCap = StrokeCap.round
        ..color = trackColor.withAlpha(
          (55 + (blink * 120).round()).clamp(0, 175),
        );
      final track = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..color = trackColor;
      canvas.drawArc(rect, start, sweep, false, trackGlow);
      canvas.drawArc(rect, start, sweep, false, track);
    } else {
      final track = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..color = idleTrack;
      canvas.drawArc(rect, start, sweep, false, track);
    }

    void drawSeg(double from, double to, Color color) {
      final a0 = from.clamp(0.0, 1.0);
      final a1 = to.clamp(0.0, 1.0);
      if (a1 <= a0) return;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..shader = NewUi.accentGradient(color).createShader(rect);
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 17 + pulse * 2
        ..strokeCap = StrokeCap.round
        ..color = color.withAlpha(28 + (pulse * 24).round());
      canvas.drawArc(rect, start + sweep * a0, sweep * (a1 - a0), false, glow);
      canvas.drawArc(rect, start + sweep * a0, sweep * (a1 - a0), false, paint);
    }

    drawSeg(0, lateEnd, NewUi.danger);
    drawSeg(lateEnd, work1End, NewUi.success);
    drawSeg(work1End, breakEnd, NewUi.warning);
    drawSeg(breakEnd, liveEnd, NewUi.success);

    final dotTrack = Paint()
      ..color = dark ? Colors.white.withAlpha(22) : const Color(0xFFCBD5E1);
    final dotActive = Paint()..color = NewUi.accent2.withAlpha(180);
    final dotRadius = radius - 25;
    final lit = activeDots.clamp(0, 60);
    for (int i = 0; i < 60; i++) {
      final point = i / 59;
      final a = start + sweep * point;
      final p = Offset(
        center.dx + math.cos(a) * dotRadius,
        center.dy + math.sin(a) * dotRadius,
      );
      final on = i < lit;
      canvas.drawCircle(p, on ? 2.05 : 1.65, on ? dotActive : dotTrack);
    }

    final headFrac = liveEnd > 0 ? liveEnd : (lateEnd > 0 ? lateEnd : 0.0);
    if (headFrac > 0) {
      final headColor = lateEnd >= liveEnd && lateEnd > 0
          ? NewUi.danger
          : (breakEnd > work1End && liveEnd <= breakEnd + 0.001
                ? NewUi.warning
                : NewUi.success);
      final head = Offset(
        center.dx + math.cos(start + sweep * headFrac) * radius,
        center.dy + math.sin(start + sweep * headFrac) * radius,
      );
      canvas.drawCircle(
        head,
        7 + pulse * 4,
        Paint()..color = headColor.withAlpha(((1 - pulse) * 68).round()),
      );
      canvas.drawCircle(head, 5.1, Paint()..color = headColor);
    }
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) =>
      oldDelegate.lateEnd != lateEnd ||
      oldDelegate.work1End != work1End ||
      oldDelegate.breakEnd != breakEnd ||
      oldDelegate.liveEnd != liveEnd ||
      oldDelegate.activeDots != activeDots ||
      oldDelegate.dark != dark ||
      oldDelegate.pulse != pulse ||
      oldDelegate.blink != blink ||
      oldDelegate.blinkTier != blinkTier;
}

class _Stats extends StatelessWidget {
  const _Stats({required this.controller});
  final NewDashboardController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
    final warnings = int.tryParse(controller.warningCountValue.value) ?? 0;
    final historyMode = controller.monthStatOffset.value != 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 300;
        final warningCard = _StatCard(
          data: controller.warningStat,
          icon: Icons.warning_amber_rounded,
          danger: warnings > 0,
          pulse: controller.warningHasUnread.value,
          onTap: controller.openWarnings,
        );
        final onTimeCard = _StatCard(
          data: controller.onTimeStat,
          icon: Icons.event_available_rounded,
          danger: false,
          historyMode: historyMode,
          onTap: controller.handleOnTimeStatTap,
          onDoubleTap: controller.resetOnTimeStat,
        );
        if (compact) {
          return Column(
            children: [warningCard, const SizedBox(height: 10), onTimeCard],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: warningCard),
            const SizedBox(width: 12),
            Expanded(child: onTimeCard),
          ],
        );
      },
    );
  });
}

class _StatCard extends StatefulWidget {
  const _StatCard({
    required this.data,
    required this.icon,
    required this.danger,
    required this.onTap,
    this.onDoubleTap,
    this.pulse = false,
    this.historyMode = false,
  });
  final NewDashboardStatData data;
  final IconData icon;
  final bool danger;
  final bool pulse;
  final bool historyMode;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );
    if (widget.pulse) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _StatCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!widget.pulse && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.danger
        ? _DashStyle.attention(context)
        : widget.historyMode
        ? NewUi.purple
        : NewUi.accent;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep the cards dense on compact iPhones, while allowing their
        // controls and type to grow slightly on wider devices.
        final cardWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 180.0;
        final scale = (cardWidth / 180).clamp(.88, 1.08);
        final horizontalPadding = 10.0 * scale;
        final iconSize = 24.0 * scale;
        return AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final base = _DashStyle.card(context, radius: 18);
            final pulse = _pulse.value;
            return Container(
              constraints: BoxConstraints(minHeight: 88 * scale),
              decoration: base.copyWith(
                border: Border.all(
                  width: widget.pulse ? 1.35 : 1,
                  color: widget.pulse
                      ? accent.withAlpha((120 + pulse * 70).round())
                      : _DashStyle.line(context),
                ),
                boxShadow: widget.pulse
                    ? [
                        ...?base.boxShadow,
                        BoxShadow(
                          color: accent.withAlpha((18 + pulse * 24).round()),
                          blurRadius: 10 + (pulse * 5),
                          spreadRadius: .4 + (pulse * .8),
                        ),
                      ]
                    : base.boxShadow,
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onTap,
                  onDoubleTap: widget.onDoubleTap,
                  overlayColor: _DashStyle.interactionOverlay(accent),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      8 * scale,
                      horizontalPadding,
                      7 * scale,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: iconSize,
                              height: iconSize,
                              decoration: BoxDecoration(
                                color: accent.withAlpha(
                                  _DashStyle.dark(context) ? 36 : 19,
                                ),
                                borderRadius: BorderRadius.circular(7 * scale),
                              ),
                              child: Icon(
                                widget.icon,
                                size: 14.5 * scale,
                                color: accent,
                              ),
                            ),
                            SizedBox(width: 6 * scale),
                            Expanded(
                              child: Text(
                                widget.data.title.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5 * scale,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .45,
                                  color: _DashStyle.secondary(context),
                                ),
                              ),
                            ),
                            if (widget.data.tag != null)
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 5.5 * scale,
                                  vertical: 3 * scale,
                                ),
                                decoration: BoxDecoration(
                                  color: NewUi.purple.withAlpha(21),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  widget.data.tag!,
                                  style: TextStyle(
                                    color: NewUi.purple,
                                    fontSize: 10.5 * scale,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: 5 * scale),
                        Text(
                          widget.data.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 21 * scale,
                            height: 1.05,
                            letterSpacing: -.7,
                            fontWeight: FontWeight.w800,
                            color: widget.danger
                                ? accent
                                : _DashStyle.text(context),
                          ),
                        ),
                        SizedBox(height: 1.5 * scale),
                        Text(
                          widget.data.meta,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5 * scale,
                            height: 1.15,
                            fontWeight: FontWeight.w500,
                            color: widget.danger
                                ? accent
                                : _DashStyle.secondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.controller});
  final NewDashboardController controller;

  Widget _editableTile(NewShortcutItem item, bool editing) {
    final tile = _ShortcutTile(
      item: item,
      editing: editing,
      onTap: () => controller.handleShortcut(item.id),
    );
    if (!editing) return tile;
    return DragTarget<NewShortcutItem>(
      onWillAcceptWithDetails: (details) => details.data.id != item.id,
      onAcceptWithDetails: (details) =>
          controller.reorderShortcut(details.data, item),
      builder: (context, candidate, rejected) => AnimatedScale(
        scale: candidate.isEmpty ? 1 : .96,
        duration: const Duration(milliseconds: 150),
        child: LongPressDraggable<NewShortcutItem>(
          data: item,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: 108,
              height: 120,
              child: _ShortcutTile(item: item, editing: true, onTap: () {}),
            ),
          ),
          childWhenDragging: Opacity(opacity: .26, child: tile),
          child: tile,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _DashboardPanel(
    padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Shortcuts',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _DashStyle.text(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: -.25,
                  height: 1.15,
                ),
              ),
            ),
            Obx(
              () => _HeaderTextButton(
                text: controller.shortcutEditing.value ? 'Done' : 'Edit',
                icon: controller.shortcutEditing.value
                    ? Icons.check_rounded
                    : Icons.edit_outlined,
                selected: controller.shortcutEditing.value,
                onTap: controller.toggleShortcutEdit,
              ),
            ),
            const SizedBox(width: 6),
            _HeaderTextButton(
              text: 'All',
              icon: Icons.grid_view_rounded,
              onTap: () {
                if (Get.isRegistered<NewMainController>()) {
                  Get.find<NewMainController>().toggleQuickActions();
                } else {
                  NewQuickActionsDialog.show();
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Obx(() {
          final editing = controller.shortcutEditing.value;
          final narrow = MediaQuery.sizeOf(context).width < 365;
          final crossSpacing = narrow ? 2.0 : 4.0;
          final mainSpacing = narrow ? 4.0 : 6.0;
          final extent = narrow ? 90.0 : 96.0;
          final delegate = SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: crossSpacing,
            mainAxisSpacing: mainSpacing,
            mainAxisExtent: extent,
          );

          if (!editing) {
            final items = controller.visibleShortcuts();
            return GridView.builder(
              primary: false,
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: delegate,
              itemCount: items.length,
              itemBuilder: (context, index) =>
                  _editableTile(items[index], false),
            );
          }

          final items = controller.shortcutEditItems();
          final pinnedCount = NewDashboardController.pinnedShortcutCount.clamp(
            0,
            items.length,
          );
          final pinned = items.take(pinnedCount).toList();
          final rest = items.skip(pinnedCount).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GridView.builder(
                primary: false,
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: delegate,
                itemCount: pinned.length,
                itemBuilder: (context, index) =>
                    _editableTile(pinned[index], true),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 14, 2, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: _DashStyle.line(context),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'Items above are visible',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .2,
                          color: _DashStyle.secondary(context),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: _DashStyle.line(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (rest.isNotEmpty)
                GridView.builder(
                  primary: false,
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: delegate,
                  itemCount: rest.length,
                  itemBuilder: (context, index) =>
                      _editableTile(rest[index], true),
                ),
            ],
          );
        }),
      ],
    ),
  );
}

class _HeaderTextButton extends StatelessWidget {
  const _HeaderTextButton({
    required this.text,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Material(
    color: NewUi.accent.withAlpha(
      selected
          ? (_DashStyle.dark(context) ? 38 : 20)
          : (_DashStyle.dark(context) ? 18 : 8),
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color: NewUi.accent.withAlpha(
          selected
              ? (_DashStyle.dark(context) ? 75 : 55)
              : (_DashStyle.dark(context) ? 38 : 28),
        ),
      ),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: NewUi.accent),
            const SizedBox(width: 5),
            Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -.1,
                color: NewUi.accent,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
    required this.item,
    required this.editing,
    required this.onTap,
  });
  final NewShortcutItem item;
  final bool editing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = newColor(item.colorKey);
    final dark = _DashStyle.dark(context);
    final hasBadge = item.badge != null && item.badge!.isNotEmpty;
    const iconBox = 44.0;
    return Opacity(
      opacity: item.enabled ? 1 : .47,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: item.enabled && !editing ? onTap : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: iconBox,
              height: iconBox,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color.withAlpha(dark ? 35 : 18),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: color.withAlpha(dark ? 95 : 70),
                        ),
                      ),
                      child: Icon(
                        newIcon(item.iconKey),
                        color: dark
                            ? Color.lerp(color, Colors.white, .18)
                            : color,
                        size: 22,
                      ),
                    ),
                  ),
                  if (hasBadge)
                    Positioned(
                      top: -5,
                      right: -5,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: cRed,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: _DashStyle.surface(context),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: cRed.withAlpha(70),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          item.badge!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  if (editing)
                    Positioned(
                      left: -3,
                      top: -3,
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        color: _DashStyle.secondary(context),
                        size: 16,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -.1,
                height: 1.15,
                color: _DashStyle.secondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftActions extends StatelessWidget {
  const _ShiftActions({required this.controller});
  final NewDashboardController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
    final standby = controller.isStandbyMode;
    final onShift = controller.isOnActiveShift;
    final onBreak = controller.isOnBreak;
    final breakEnabled =
        controller.breakActionEnabled && !controller.breakTaken;
    final shiftColor = standby
        ? NewUi.warning
        : onShift
        ? NewUi.danger
        : NewUi.accent;
    final shiftButton = _NativeShiftButton(
      mainLabel: controller.shiftActionMainLabel,
      icon: onShift ? Icons.stop_rounded : Icons.play_arrow_rounded,
      color: shiftColor,
      onTap: controller.startShiftFlow,
    );
    final breakButton = _NativeBreakButton(
      label: controller.breakActionLabel,
      enabled: breakEnabled,
      onBreak: onBreak,
      onTap: controller.toggleBreak,
    );
    return Row(
      children: [
        Expanded(child: shiftButton),
        const SizedBox(width: 8),
        Expanded(child: breakButton),
      ],
    );
  });
}

class _NativeShiftButton extends StatelessWidget {
  const _NativeShiftButton({
    required this.mainLabel,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String mainLabel;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    height: 54,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color, Color.lerp(color, Colors.black, .10)!],
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withAlpha(24)),
      boxShadow: [
        BoxShadow(
          color: color.withAlpha(18),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        overlayColor: _DashStyle.interactionOverlay(Colors.white),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 29,
                width: 29,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(28),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  mainLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _NativeBreakButton extends StatelessWidget {
  const _NativeBreakButton({
    required this.label,
    required this.enabled,
    required this.onBreak,
    required this.onTap,
  });
  final String label;
  final bool enabled;
  final bool onBreak;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = NewUi.warning;
    final dark = _DashStyle.dark(context);
    final foreground = onBreak
        ? (dark ? const Color(0xFFFFD66B) : const Color(0xFF9A6500))
        : (dark ? const Color(0xFFD4BD83) : const Color(0xFF735B22));
    return Opacity(
      opacity: enabled ? 1 : .76,
      child: Container(
        height: 54,
        decoration: _DashStyle.card(context, radius: 14).copyWith(
          color: onBreak
              ? color.withAlpha(dark ? 30 : 17)
              : color.withAlpha(dark ? 12 : 7),
          boxShadow: const [],
          border: Border.all(
            color: onBreak
                ? color.withAlpha(90)
                : color.withAlpha(dark ? 55 : 45),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            overlayColor: enabled
                ? _DashStyle.interactionOverlay(color)
                : const WidgetStatePropertyAll(Colors.transparent),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 29,
                    width: 29,
                    decoration: BoxDecoration(
                      color: color.withAlpha(dark ? 35 : 18),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.coffee_rounded,
                      size: 17,
                      color: onBreak ? foreground : color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
