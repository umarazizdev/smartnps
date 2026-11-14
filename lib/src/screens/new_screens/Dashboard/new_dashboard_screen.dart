import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/new_screens/Widgets/new_common_widgets.dart';
import '../new_models.dart';
import 'new_dashboard_controller.dart';
import 'new_dashboard_dial_controller.dart';

class NewDashboardScreen extends StatelessWidget {
  const NewDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(NewDashboardController(), permanent: true);
    return NewAnimatedShell(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
        children: [
          _Greeting(controller: controller),
          const SizedBox(height: 8),
          _HeroClock(controller: controller),
          const SizedBox(height: 10),
          _Stats(controller: controller),
          const SizedBox(height: 14),
          _Shortcuts(controller: controller),
          const SizedBox(height: 14),
          _ShiftActions(controller: controller),
        ],
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.controller});

  final NewDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final status = controller.status.value;
      final statusText = status == NewOfficerStatus.onShift ? 'On Shift' : status == NewOfficerStatus.onBreak ? 'On Break' : 'On Standby';
      final statusColor = status == NewOfficerStatus.onBreak ? NewUi.warning : status == NewOfficerStatus.onShift ? NewUi.accent : NewUi.success;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TUESDAY, MAY 19', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _muted(context), fontWeight: FontWeight.w900, letterSpacing: .8)),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.9, height: 1.05),
                    children: [
                      TextSpan(text: 'Good morning, ', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                      TextSpan(text: controller.firstName, style: const TextStyle(color: NewUi.accent2)),
                    ],
                  ),
                ),
                Text(controller.officerRole.value.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _muted(context), fontWeight: FontWeight.w900, letterSpacing: .8)),
              ],
            ),
          ),
          NewPill(text: statusText, pulse: true, color: statusColor),
        ],
      );
    });
  }
}

class _HeroClock extends StatefulWidget {
  const _HeroClock({required this.controller});

  final NewDashboardController controller;

  @override
  State<_HeroClock> createState() => _HeroClockState();
}

class _HeroClockState extends State<_HeroClock> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final NewDashboardDialController dialController;

  @override
  void initState() {
    super.initState();
    dialController = Get.isRegistered<NewDashboardDialController>() ? Get.find<NewDashboardDialController>() : Get.put(NewDashboardDialController());
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Obx(() {
      final status = controller.status.value;
      final isStandby = status == NewOfficerStatus.standby;
      final isBreak = status == NewOfficerStatus.onBreak;
      final statusColor = isBreak ? NewUi.warning : status == NewOfficerStatus.onShift ? NewUi.accent : NewUi.success;
      final workColor = controller.arrivalText.value.toLowerCase().contains('late') ? NewUi.danger : NewUi.success;
      final progress = isStandby ? 0.0 : isBreak ? .30 : .44;
      final breakProgress = isStandby ? 0.0 : isBreak ? .20 : controller.breakBadgeText.value == 'Taken' ? .13 : 0.0;
      final timerLabel = isStandby ? 'Off Duty' : isBreak ? 'Break Timer' : controller.timerLabel.value;
      final timerText = isStandby ? '0:00:00' : controller.timerText.value;

      return NewGlassCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 15),
        highlightColor: statusColor,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = math.min(math.max(constraints.maxWidth - 8, 258), 292).toDouble();
            return SizedBox(
              height: size + 2,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, _) => CustomPaint(
                      size: Size.square(size),
                      painter: _DialPainter(progress: progress, breakProgress: breakProgress, color: workColor, dark: Theme.of(context).brightness == Brightness.dark, pulse: _pulse.value),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 600),
                        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: Transform.translate(offset: Offset(0, 4 * (1 - animation.value)), child: child)),
                        child: Text(timerLabel.toUpperCase(), key: ValueKey(timerLabel), style: TextStyle(color: _muted(context), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.62, height: 1)),
                      ),
                      const SizedBox(height: 5),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(timerText, key: ValueKey(timerText), style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'monospace', fontSize: 28, letterSpacing: -1.12, height: 1, color: isBreak ? NewUi.warning : Theme.of(context).textTheme.bodyLarge?.color)),
                      ),
                      const SizedBox(height: 10),
                      if (!isBreak) _RotatingRingFields(dialController: dialController),
                      if (isBreak) ...[
                        Text('BREAK ACTIVE', style: TextStyle(color: _muted(context), fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: .95, height: 1)),
                        const SizedBox(height: 3),
                        Text(controller.selectedSite.value, style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: -.13, height: 1.1)),
                      ],
                      const SizedBox(height: 7),
                      if (!isBreak) _DialPill(text: controller.arrivalText.value, icon: Icons.schedule_rounded, color: controller.arrivalText.value == 'Pending' ? _muted(context) : NewUi.success),
                      if (isBreak) _DialPill(text: 'Break Active', icon: Icons.hourglass_bottom_rounded, color: NewUi.warning),
                      if (!isStandby) ...[
                        const SizedBox(height: 6),
                        _DialPill(text: controller.breakBadgeText.value, icon: Icons.coffee_rounded, color: NewUi.warning, strike: controller.breakBadgeText.value == 'Taken', onTap: controller.toggleBreak),
                      ],
                    ],
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
  Widget build(BuildContext context) {
    return Obx(
      () => AnimatedOpacity(
        opacity: dialController.fading.value ? 0 : 1,
        duration: const Duration(milliseconds: 600),
        curve: Curves.ease,
        child: AnimatedSlide(
          offset: dialController.fading.value ? const Offset(0, .08) : Offset.zero,
          duration: const Duration(milliseconds: 600),
          curve: Curves.ease,
          child: Column(
            children: [
              Text(dialController.title.value.toUpperCase(), style: TextStyle(color: _muted(context), fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: .95, height: 1)),
              const SizedBox(height: 3),
              Text(dialController.subtitle.value, style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: -.13, height: 1.1)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialPill extends StatelessWidget {
  const _DialPill({required this.text, required this.icon, required this.color, this.strike = false, this.onTap});

  final String text;
  final IconData icon;
  final Color color;
  final bool strike;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withAlpha(23), borderRadius: BorderRadius.circular(99), border: Border.all(color: color.withAlpha(70))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 5),
          AnimatedSwitcher(duration: const Duration(milliseconds: 550), child: Text(text, key: ValueKey(text), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .2, decoration: strike ? TextDecoration.lineThrough : null, decorationThickness: 1.5))),
        ]),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  const _DialPainter({required this.progress, required this.breakProgress, required this.color, required this.dark, required this.pulse});

  final double progress;
  final double breakProgress;
  final Color color;
  final bool dark;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 15;
    final start = math.pi * .74;
    final sweep = math.pi * 1.52;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()..style = PaintingStyle.stroke..strokeWidth = 14..strokeCap = StrokeCap.round..color = dark ? Colors.white.withAlpha(17) : const Color(0xFFE8EDF5);
    final glow = Paint()..style = PaintingStyle.stroke..strokeWidth = 17 + pulse * 3..strokeCap = StrokeCap.round..color = color.withAlpha(30 + (pulse * 30).round());
    final active = Paint()..style = PaintingStyle.stroke..strokeWidth = 14..strokeCap = StrokeCap.round..shader = NewUi.accentGradient(color).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawArc(rect, start, sweep, false, track);
    final clampedProgress = progress.clamp(0.0, 1.0);
    final activeSweep = sweep * clampedProgress;
    if (clampedProgress > 0) {
      canvas.drawArc(rect, start, activeSweep, false, glow);
      canvas.drawArc(rect, start, activeSweep, false, active);
    }
    if (breakProgress > 0) {
      final breakPaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 14..strokeCap = StrokeCap.round..shader = NewUi.accentGradient(NewUi.warning).createShader(rect);
      canvas.drawArc(rect, start + activeSweep + math.pi * .08, sweep * breakProgress.clamp(0, .28), false, breakPaint);
    }
    final dotTrack = Paint()..color = dark ? Colors.white.withAlpha(22) : const Color(0xFFCBD5E1);
    final dotActive = Paint()..color = NewUi.accent2.withAlpha(160);
    final dotRadius = radius - 25;
    for (int i = 0; i < 60; i++) {
      final point = i / 59;
      final a = start + sweep * point;
      final p = Offset(center.dx + math.cos(a) * dotRadius, center.dy + math.sin(a) * dotRadius);
      final activeDot = clampedProgress > 0 && point <= clampedProgress;
      canvas.drawCircle(p, activeDot ? 2.05 : 1.65, activeDot ? dotActive : dotTrack);
    }
    if (clampedProgress > 0) {
      final head = Offset(center.dx + math.cos(start + activeSweep) * radius, center.dy + math.sin(start + activeSweep) * radius);
      canvas.drawCircle(head, 7 + pulse * 4, Paint()..color = color.withAlpha(((1 - pulse) * 68).round()));
      canvas.drawCircle(head, 5.1, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) => oldDelegate.progress != progress || oldDelegate.breakProgress != breakProgress || oldDelegate.color != color || oldDelegate.dark != dark || oldDelegate.pulse != pulse;
}

class _Stats extends StatelessWidget {
  const _Stats({required this.controller});

  final NewDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Row(
        children: [
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _StatCard(data: controller.warningStat, icon: Icons.warning_amber_rounded, color: NewUi.danger, onTap: controller.nextWarningStat, onDoubleTap: controller.resetWarningStat))),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _StatCard(data: controller.weekStat, icon: Icons.calendar_today_rounded, color: NewUi.accent, onTap: controller.nextWeekStat, onDoubleTap: controller.resetWeekStat))),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _StatCard(data: controller.onTimeStat, icon: Icons.check_circle_rounded, color: NewUi.accent, onTap: controller.nextOnTimeStat, onDoubleTap: controller.resetOnTimeStat))),
        ],
      ),
    );
  }
}

class _StatCard extends StatefulWidget {
  const _StatCard({required this.data, required this.icon, required this.color, required this.onTap, required this.onDoubleTap});

  final NewDashboardStatData data;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  bool get _danger => widget.color == NewUi.danger;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    if (_danger) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant _StatCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_danger && !_pulse.isAnimating) _pulse.repeat();
    if (!_danger && _pulse.isAnimating) {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final pulse = _danger ? math.sin(_pulse.value * math.pi) : 0.0;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: _danger ? [BoxShadow(color: NewUi.danger.withAlpha((28 * pulse).round()), blurRadius: 6 + (6 * pulse), spreadRadius: 0)] : null,
            ),
            child: child,
          );
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: Container(
            key: ValueKey('${widget.data.title}_${widget.data.value}_${widget.data.meta}'),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 6),
            decoration: BoxDecoration(
              color: _danger
                  ? NewUi.danger.withAlpha(isDark ? 13 : 10)
                  : isDark
                      ? Colors.white.withAlpha(10)
                      : Colors.white.withAlpha(238),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _danger ? NewUi.danger.withAlpha(isDark ? 82 : 78) : isDark ? Colors.white.withAlpha(18) : const Color(0xFFE5EAF1)),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(isDark ? 40 : 12), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: SizedBox(
              height: 76,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(padding: const EdgeInsets.only(top: 1), child: Icon(widget.icon, size: 13, color: widget.color)),
                      const SizedBox(width: 4),
                      Expanded(child: Text(widget.data.title, maxLines: 2, softWrap: true, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10.2, height: 1.05, fontWeight: FontWeight.w900, color: _danger ? NewUi.danger : _muted(context)))),
                      if (widget.data.tag != null) ...[
                        const SizedBox(width: 3),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: NewUi.purple.withAlpha(30), borderRadius: BorderRadius.circular(5), border: Border.all(color: NewUi.purple.withAlpha(80))), child: Text(widget.data.tag!, style: const TextStyle(color: NewUi.purple, fontSize: 8, height: 1, fontWeight: FontWeight.w900))),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(widget.data.value, maxLines: 1, softWrap: false, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 19, height: 1, fontWeight: FontWeight.w900, color: _danger ? NewUi.danger : null)),
                  const SizedBox(height: 4),
                  Expanded(child: Text(widget.data.meta, maxLines: 2, softWrap: true, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 9.4, height: 1.15, color: _danger ? NewUi.danger : _muted(context), fontWeight: FontWeight.w700))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Shortcuts extends StatefulWidget {
  const _Shortcuts({required this.controller});

  final NewDashboardController controller;

  @override
  State<_Shortcuts> createState() => _ShortcutsState();
}

class _ShortcutsState extends State<_Shortcuts> {
  bool showAll = false;

  void _reorder(NewDashboardController controller, NewShortcutItem from, NewShortcutItem to) {
    if (from.id == to.id) return;
    final target = showAll ? controller.allQuickActions : controller.shortcuts;
    final fromIndex = target.indexWhere((e) => e.id == from.id);
    final toIndex = target.indexWhere((e) => e.id == to.id);
    if (fromIndex == -1 || toIndex == -1) return;
    final item = target.removeAt(fromIndex);
    target.insert(toIndex, item);
    target.refresh();
  }

  Widget _editableTile(NewDashboardController controller, NewShortcutItem item) {
    final tile = _ShortcutTile(item: item, editing: controller.shortcutEditing.value, onTap: () => controller.handleShortcut(item.id));
    if (!controller.shortcutEditing.value) return tile;
    return DragTarget<NewShortcutItem>(
      onWillAcceptWithDetails: (details) => details.data.id != item.id,
      onAcceptWithDetails: (details) => _reorder(controller, details.data, item),
      builder: (context, candidate, rejected) {
        return AnimatedScale(
          scale: candidate.isEmpty ? 1 : .95,
          duration: const Duration(milliseconds: 140),
          child: LongPressDraggable<NewShortcutItem>(
            data: item,
            feedback: Material(color: Colors.transparent, child: SizedBox(width: 104, height: 112, child: _ShortcutTile(item: item, editing: true, onTap: () {}))),
            childWhenDragging: Opacity(opacity: .28, child: tile),
            child: tile,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return NewGlassCard(
      child: Column(
        children: [
          NewSectionTitle(
            title: 'Quick Shortcuts',
            icon: Icons.bolt_rounded,
            action: Row(mainAxisSize: MainAxisSize.min, children: [
              Obx(() => _HeaderTextButton(text: controller.shortcutEditing.value ? 'Done' : 'Edit', onTap: controller.toggleShortcutEdit)),
              _HeaderTextButton(text: showAll ? 'Less' : 'All', onTap: () => setState(() => showAll = !showAll)),
            ]),
          ),
          Obx(() {
            final items = showAll ? controller.allQuickActions.where((e) => !e.hidden).toList() : controller.shortcuts;
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: GridView.builder(
                key: ValueKey('${showAll}_${controller.shortcutEditing.value}_${items.map((e) => e.id).join()}'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 9, mainAxisSpacing: 9, childAspectRatio: .96),
                itemCount: items.length,
                itemBuilder: (context, index) => _editableTile(controller, items[index]),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _HeaderTextButton extends StatelessWidget {
  const _HeaderTextButton({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
      child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF163B7A))),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({required this.item, required this.editing, required this.onTap});

  final NewShortcutItem item;
  final bool editing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = newColor(item.colorKey);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Opacity(
      opacity: item.enabled ? 1 : .42,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: item.enabled && !editing ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 210),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: isDark ? Colors.white.withAlpha(editing ? 18 : 10) : const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(18), border: Border.all(color: editing ? color.withAlpha(115) : isDark ? Colors.white.withAlpha(18) : const Color(0xFFE5EAF1)), boxShadow: editing ? [BoxShadow(color: color.withAlpha(30), blurRadius: 18)] : null),
          child: Stack(children: [
            Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(gradient: NewUi.accentGradient(color), borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: color.withAlpha(60), blurRadius: 12)]), child: Icon(newIcon(item.iconKey), color: Colors.white, size: 21)),
              const SizedBox(height: 8),
              Text(item.title, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.1, height: 1.12)),
            ])),
            if (item.badge != null) Positioned(left: 0, top: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: cRed, borderRadius: BorderRadius.circular(99)), child: Text(item.badge!, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)))),
            if (editing) Positioned(right: 0, top: 0, child: Container(width: 24, height: 24, decoration: BoxDecoration(color: color.withAlpha(22), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withAlpha(55))), child: Icon(Icons.drag_indicator_rounded, size: 15, color: color))),
          ]),
        ),
      ),
    );
  }
}

class _ShiftActions extends StatelessWidget {
  const _ShiftActions({required this.controller});

  final NewDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return NewGlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const NewSectionTitle(title: 'Shift Actions', icon: Icons.play_circle_fill_rounded),
        Obx(() => Row(children: [
          Expanded(child: NewActionButton(text: controller.status.value == NewOfficerStatus.standby ? 'Start Shift' : 'End Shift', icon: controller.status.value == NewOfficerStatus.standby ? Icons.play_arrow_rounded : Icons.stop_rounded, color: controller.status.value == NewOfficerStatus.standby ? NewUi.accent : NewUi.danger, onTap: controller.startShiftFlow)),
          const SizedBox(width: 10),
          Expanded(child: _BreakActionButton(text: controller.status.value == NewOfficerStatus.onBreak ? 'End Break' : 'Start Break', enabled: controller.status.value != NewOfficerStatus.standby, onTap: controller.toggleBreak)),
        ])),
      ]),
    );
  }
}

class _BreakActionButton extends StatelessWidget {
  const _BreakActionButton({required this.text, required this.enabled, required this.onTap});

  final String text;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 190),
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: enabled ? NewUi.warning.withAlpha(isDark ? 22 : 18) : NewUi.warning.withAlpha(isDark ? 16 : 13), borderRadius: BorderRadius.circular(15), border: Border.all(color: NewUi.warning.withAlpha(enabled ? 85 : 62))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.coffee_rounded, size: 17, color: NewUi.warning.withAlpha(enabled ? 255 : 205)), const SizedBox(width: 8), Text(text, style: TextStyle(color: NewUi.warning.withAlpha(enabled ? 255 : 205), fontSize: 13, fontWeight: FontWeight.w900))]),
      ),
    );
  }
}

Color _muted(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight;
