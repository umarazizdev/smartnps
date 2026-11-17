import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:smartnps360/src/utilities/app_config.dart';
import '../new_models.dart';
import 'new_dashboard_controller.dart';

/// SmartNPS360 shift hero (no raster assets required).
///
/// The ring reads the controller's *existing* shift/late/break segments; it
/// never calculates or changes shift time, geofencing or clock-in state.
class NewDashboardHero extends StatefulWidget {
  const NewDashboardHero({super.key, required this.controller});

  final NewDashboardController controller;

  @override
  State<NewDashboardHero> createState() => _NewDashboardHeroState();
}

enum _DialCase { upcoming, overdue, working, workingLate, breakTime }

enum _DayPeriod { morning, afternoon, evening, night }

class _NewDashboardHeroState extends State<NewDashboardHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    // A restrained indicator animation, rather than blinking the whole dial.
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  _DialCase _resolveCase(NewDashboardController c) {
    if (c.isOnBreak) return _DialCase.breakTime;
    if (c.status.value == NewOfficerStatus.onShift) {
      return c.arrivalStatus.value == NewArrivalStatus.late ||
              c.arrivalStatus.value == NewArrivalStatus.slight
          ? _DialCase.workingLate
          : _DialCase.working;
    }
    if (c.lateStartedStyle.value) return _DialCase.overdue;
    return _DialCase.upcoming;
  }

  static _DayPeriod periodFor(String? demo) {
    if (demo != null) {
      switch (demo) {
        case 'morning':
          return _DayPeriod.morning;
        case 'afternoon':
          return _DayPeriod.afternoon;
        case 'evening':
          return _DayPeriod.evening;
        case 'night':
          return _DayPeriod.night;
      }
    }
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 11) return _DayPeriod.morning;
    if (hour >= 11 && hour < 17) return _DayPeriod.afternoon;
    if (hour >= 17 && hour < 21) return _DayPeriod.evening;
    return _DayPeriod.night;
  }

  String _timer(String raw) {
    if (!RegExp(r'^\d+:\d{2}:\d{2}$').hasMatch(raw)) return raw;
    final parts = raw.split(':');
    parts[0] = parts[0].padLeft(2, '0');
    return parts.join(':');
  }

  Color _accent(_DialCase mode, bool dark) {
    switch (mode) {
      case _DialCase.upcoming:
        return dark ? const Color(0xFF82B4FF) : const Color(0xFF2866D5);
      case _DialCase.overdue:
        return dark ? const Color(0xFFFF858C) : const Color(0xFFD43F50);
      case _DialCase.working:
      case _DialCase.workingLate:
        return dark ? const Color(0xFF5ED6AE) : const Color(0xFF128A69);
      case _DialCase.breakTime:
        return dark ? const Color(0xFFFFCE77) : const Color(0xFFAA710F);
    }
  }

  IconData _caseIcon(_DialCase mode) {
    switch (mode) {
      case _DialCase.upcoming:
        return Icons.schedule_rounded;
      case _DialCase.overdue:
        return Icons.error_outline_rounded;
      case _DialCase.working:
      case _DialCase.workingLate:
        return Icons.verified_outlined;
      case _DialCase.breakTime:
        return Icons.coffee_outlined;
    }
  }

  Color _arrivalAccent(NewArrivalStatus arrival, bool dark) {
    switch (arrival) {
      case NewArrivalStatus.late:
      case NewArrivalStatus.slight:
        return dark ? const Color(0xFFFF959B) : const Color(0xFFCA4051);
      case NewArrivalStatus.onTime:
      case NewArrivalStatus.early:
        return dark ? const Color(0xFF5ED6AE) : const Color(0xFF128A69);
      case NewArrivalStatus.pending:
        return dark ? const Color(0xFF82B4FF) : const Color(0xFF2866D5);
    }
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    final c = widget.controller;
    final mode = _resolveCase(c);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accent(mode, dark);
    final primary = dark ? const Color(0xFFF3F7FF) : const Color(0xFF15223A);
    final secondary = dark ? const Color(0xFFABBAD0) : const Color(0xFF69778D);
    final border = dark ? const Color(0xFF2B3A50) : const Color(0xFFE1E8F1);
    final label = c.timerLabel.value;
    final timer = _timer(c.timerText.value);
    final arrival = c.arrivalStatus.value;
    final lateOnDuty = mode == _DialCase.workingLate;
    final urgency =
        mode == _DialCase.upcoming &&
        c.blinkTier.value != NewTimerBlinkTier.none;
    final noShift = c.showNoAssignedShift;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF182536) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border),
        boxShadow: dark
            ? const []
            : [
                BoxShadow(
                  color: const Color(0xFF182D51).withAlpha(12),
                  blurRadius: 22,
                  offset: const Offset(0, 7),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 5,
                  height: 17,
                  decoration: BoxDecoration(
                    color: noShift ? secondary : accent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'SHIFT OVERVIEW',
                    style: TextStyle(
                      color: secondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.05,
                    ),
                  ),
                ),
                if (!noShift)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accent.withAlpha(50)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          c.liveStatusText.value,
                          style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (noShift)
              _NoShiftContent(
                primary: primary,
                secondary: secondary,
                dark: dark,
              )
            else ...[
              const SizedBox(height: 2),
              LayoutBuilder(
                builder: (context, constraints) {
                  final diameter = math.min(208.0, constraints.maxWidth - 6.0);
                  return Center(
                    child: SizedBox(
                      height: diameter,
                      width: diameter,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          RepaintBoundary(
                            child: AnimatedBuilder(
                              animation: _pulse,
                              builder: (context, child) => CustomPaint(
                                size: Size.square(diameter),
                                painter: _ShiftDialPainter(
                                  accent: accent,
                                  dark: dark,
                                  mode: mode,
                                  progressLate: c.dialLateEnd.value,
                                  progressWork: c.dialWork1End.value,
                                  progressBreak: c.dialBreakEnd.value,
                                  progressLive: c.dialLiveEnd.value,
                                  activeDots: c.dialActiveDots.value,
                                  pulse: _pulse.value,
                                  urgency: urgency,
                                ),
                              ),
                            ),
                          ),
                          MediaQuery.withClampedTextScaling(
                            maxScaleFactor: 1.20,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 26,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _caseIcon(mode),
                                        size: 13,
                                        color: accent,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          label.toUpperCase(),
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: accent,
                                            fontSize: 10.5,
                                            letterSpacing: .6,
                                            height: 1.15,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      timer,
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: mode == _DialCase.overdue
                                            ? accent
                                            : primary,
                                        fontFamily: 'monospace',
                                        fontSize: timer.contains(' ') ? 17 : 27,
                                        fontWeight: FontWeight.w800,
                                        height: 1.02,
                                        letterSpacing: -1,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  // Only unique, actionable secondary information
                                  // belongs inside the dial. The current duty status
                                  // already appears in the greeting above.
                                  if (lateOnDuty) ...[
                                    const SizedBox(height: 9),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.error_outline_rounded,
                                          size: 12,
                                          color: _arrivalAccent(arrival, dark),
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            c.arrivalText.value,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: _arrivalAccent(
                                                arrival,
                                                dark,
                                              ),
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Container(height: 1, color: border.withAlpha(dark ? 190 : 170)),
              const SizedBox(height: 10),
              // The location appears only in this footer, never in the greeting.
              Row(
                children: [
                  Icon(Icons.event_outlined, size: 16, color: secondary),
                  const SizedBox(width: 7),
                  Expanded(
                    flex: 3,
                    child: Text(
                      c.selectedShift.value,
                      style: TextStyle(
                        color: primary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (c.selectedSite.value.trim().isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Flexible(
                      flex: 2,
                      child: Tooltip(
                        message: c.selectedSite.value,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: secondary,
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                c.selectedSite.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: primary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  });
}

class _NoShiftContent extends StatelessWidget {
  const _NoShiftContent({
    required this.primary,
    required this.secondary,
    required this.dark,
  });

  final Color primary;
  final Color secondary;
  final bool dark;

  static const _dispatchNumber = '+14158004372';
  static const _displayNumber = '+1 (415) 800-4372';

  Future<void> _contactDispatch(
    BuildContext context, {
    required bool whatsapp,
  }) async {
    final uri = whatsapp
        ? Uri.https('wa.me', '/${_dispatchNumber.substring(1)}')
        : Uri(scheme: 'tel', path: _dispatchNumber);
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (!context.mounted) return;
    final action = whatsapp ? 'open WhatsApp' : 'open the phone dialer';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Unable to $action. Contact Dispatch at $_displayNumber.',
        ),
      ),
    );
  }

  Widget _contactButton(BuildContext context, {required bool whatsapp}) {
    final color = whatsapp
        ? (dark ? const Color(0xFF6DDBA8) : const Color(0xFF087B4F))
        : (dark ? const Color(0xFF9CBFFF) : const Color(0xFF2866D5));
    final surface = whatsapp
        ? (dark ? const Color(0xFF203B35) : const Color(0xFFEDF9F2))
        : (dark ? const Color(0xFF202F45) : const Color(0xFFF3F7FD));
    final border = whatsapp
        ? (dark ? const Color(0xFF355D4D) : const Color(0xFFCFEBDD))
        : (dark ? const Color(0xFF344864) : const Color(0xFFDFE8F5));
    return Semantics(
      hint: whatsapp
          ? 'Opens WhatsApp to contact Dispatch'
          : 'Opens the phone dialer to call Dispatch',
      child: OutlinedButton(
        onPressed: () => _contactDispatch(context, whatsapp: whatsapp),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          backgroundColor: surface,
          side: BorderSide(color: border),
          minimumSize: const Size(0, 56),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ExcludeSemantics(
              child: whatsapp
                  ? Image.asset(
                      'assets/Icons/whatsapp.png',
                      color: color,
                      width: 21,
                      height: 21,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Icon(
                        whatsapp
                            ? Icons.chat_bubble_outline_rounded
                            : Icons.call_outlined,
                        size: 18,
                        color: color,
                      ),
                    )
                  : Icon(Icons.call_outlined, size: 21, color: color),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    whatsapp ? 'WhatsApp' : 'Call Dispatch',
                    style: TextStyle(
                      color: color,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    whatsapp ? 'Message Dispatch' : 'Open phone dialer',
                    style: TextStyle(
                      color: color.withAlpha(190),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 5, 4, 3),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: SvgPicture.asset(
                  dark
                      ? 'assets/images/no_shift_dark.svg'
                      : 'assets/images/no_shift_light.svg',
                  width: 160,
                  height: 128,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                  placeholderBuilder: (context) => SizedBox(
                    width: 160,
                    height: 128,
                    child: Icon(
                      Icons.calendar_month_outlined,
                      size: 52,
                      color: dark
                          ? const Color(0xFF9CBFFF)
                          : const Color(0xFF4D83D5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'No shift scheduled',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  letterSpacing: -.55,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Expecting a shift? Please contact Dispatch.',
                textAlign: TextAlign.center,
                style: TextStyle(color: secondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 17),
              LayoutBuilder(
                builder: (context, constraints) {
                  final whatsapp = _contactButton(context, whatsapp: true);
                  final call = _contactButton(context, whatsapp: false);
                  if (constraints.maxWidth < 276 ||
                      MediaQuery.textScalerOf(context).scale(12.5) > 15) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [whatsapp, const SizedBox(height: 8), call],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: whatsapp),
                      const SizedBox(width: 10),
                      Expanded(child: call),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Day-period icon keeps the four visual variants without repeating the
/// greeting's day-part label. It is decorative for sighted users, and labeled
/// for screen readers/long press.
class NewDashboardPeriodIcon extends StatelessWidget {
  const NewDashboardPeriodIcon({super.key, required this.controller});
  final NewDashboardController controller;
  @override
  Widget build(BuildContext context) => Obx(
    () => _PeriodChip(
      period: _NewDashboardHeroState.periodFor(
        AppConfig.enableDialVisualStateDemo
            ? controller.demoDialPeriod.value
            : controller.greetingPrefix.value.toLowerCase().contains('morning')
            ? 'morning'
            : controller.greetingPrefix.value.toLowerCase().contains(
                'afternoon',
              )
            ? 'afternoon'
            : null,
      ),
      dark: Theme.of(context).brightness == Brightness.dark,
    ),
  );
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.period, required this.dark});
  final _DayPeriod period;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color color;
    switch (period) {
      case _DayPeriod.morning:
        label = 'Morning';
        color = const Color(0xFFD18B22);
        break;
      case _DayPeriod.afternoon:
        label = 'Afternoon';
        color = const Color(0xFFE5A522);
        break;
      case _DayPeriod.evening:
        label = 'Evening';
        color = const Color(0xFFA477C7);
        break;
      case _DayPeriod.night:
        label = 'Night';
        color = const Color(0xFF7D91CD);
        break;
    }
    return Tooltip(
      message: label,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color.withAlpha(dark ? 29 : 16),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: SvgPicture.asset(
          'assets/images/dial_${period.name}.svg',
          width: 25,
          height: 25,
        ),
      ),
    );
  }
}

class _ShiftDialPainter extends CustomPainter {
  const _ShiftDialPainter({
    required this.accent,
    required this.dark,
    required this.mode,
    required this.progressLate,
    required this.progressWork,
    required this.progressBreak,
    required this.progressLive,
    required this.activeDots,
    required this.pulse,
    required this.urgency,
  });

  final Color accent;
  final bool dark;
  final _DialCase mode;
  final double progressLate;
  final double progressWork;
  final double progressBreak;
  final double progressLive;
  final int activeDots;
  final double pulse;
  final bool urgency;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 12;
    final arc = Rect.fromCircle(center: center, radius: radius);
    // Open bottom, intentionally less dominant than the original thick gauge.
    final start = math.pi * .76;
    final sweep = math.pi * 1.48;
    final neutral = dark ? const Color(0xFF3A4A60) : const Color(0xFFE4EBF3);

    canvas.drawArc(
      arc,
      start,
      sweep,
      false,
      Paint()
        ..color = Color.lerp(neutral, accent, dark ? .12 : .09)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );

    // Subtle clock ticks; no heavy 60-dot rim or decorative wave assets.
    for (var i = 0; i <= 36; i++) {
      final a = start + sweep * (i / 36);
      final outer = radius - 12;
      final inner = outer - (i % 6 == 0 ? 5 : 3);
      final paint = Paint()
        ..color = (dark ? const Color(0xFF51657E) : const Color(0xFFC9D4E3))
            .withAlpha(i % 6 == 0 ? 160 : 108)
        ..strokeWidth = i % 6 == 0 ? 1.5 : 1.1
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        center + Offset(math.cos(a) * inner, math.sin(a) * inner),
        center + Offset(math.cos(a) * outer, math.sin(a) * outer),
        paint,
      );
    }

    void segment(double from, double to, Color color) {
      final left = from.clamp(0.0, 1.0);
      final right = to.clamp(0.0, 1.0);
      if (right - left < .001) return;
      canvas.drawArc(
        arc,
        start + sweep * left,
        sweep * (right - left),
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round,
      );
    }

    final success = dark ? const Color(0xFF46CAA0) : const Color(0xFF1AA783);
    final danger = dark ? const Color(0xFFFF777E) : const Color(0xFFDF5463);
    final warning = dark ? const Color(0xFFFFCC74) : const Color(0xFFD99A36);
    segment(0, progressLate, danger);
    segment(progressLate, progressWork, success);
    segment(progressWork, progressBreak, warning);
    segment(progressBreak, progressLive, success);

    final isActive =
        mode == _DialCase.working ||
        mode == _DialCase.workingLate ||
        mode == _DialCase.breakTime;
    final fraction = progressLive.clamp(0.0, 1.0);
    final markerAngle = start + sweep * (isActive ? fraction : 0);
    final markerColor =
        mode == _DialCase.workingLate && progressLive <= progressLate + .001
        ? danger
        : mode == _DialCase.breakTime
        ? warning
        : accent;
    final marker =
        center +
        Offset(math.cos(markerAngle) * radius, math.sin(markerAngle) * radius);
    canvas.drawCircle(
      marker,
      isActive ? 5.0 + pulse * .65 : 4.5,
      Paint()..color = markerColor,
    );
    if (isActive || urgency) {
      canvas.drawCircle(
        marker,
        7.5 + pulse * 2.5,
        Paint()..color = markerColor.withAlpha((36 * (1 - pulse)).round()),
      );
    }
    // Preserve the controller's second-hand signal in a discreet little mark.
    if (isActive && activeDots > 0) {
      final a = start + sweep * (activeDots.clamp(0, 60) / 60);
      final small =
          center +
          Offset(math.cos(a) * (radius - 19), math.sin(a) * (radius - 19));
      canvas.drawCircle(small, 1.8, Paint()..color = accent.withAlpha(165));
    }
  }

  @override
  bool shouldRepaint(covariant _ShiftDialPainter old) =>
      old.accent != accent ||
      old.dark != dark ||
      old.mode != mode ||
      old.progressLate != progressLate ||
      old.progressWork != progressWork ||
      old.progressBreak != progressBreak ||
      old.progressLive != progressLive ||
      old.activeDots != activeDots ||
      old.pulse != pulse ||
      old.urgency != urgency;
}
