import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/new_screens/Widgets/new_common_widgets.dart';
import '../new_models.dart';
import 'new_calendar_controller.dart';
import 'new_year_calendar_view.dart';

class NewCalendarScreen extends StatelessWidget {
  const NewCalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(NewCalendarController());
    final media = MediaQuery.of(context);
    final scale = (media.size.width / 390).clamp(0.85, 1.2);
    final sidePad = 14.0 * scale;
    final bottomPad = media.padding.bottom + 108;
    return NewAnimatedShell(
      child: ListView(
        padding: EdgeInsets.fromLTRB(sidePad, 10 * scale, sidePad, bottomPad),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 580 * scale.clamp(1.0, 1.05)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Obx(
                    () => Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Calendar',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontSize: 22 * scale,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.6,
                                ),
                          ),
                        ),
                        NewPill(
                          text:
                              controller.selectedView.value ==
                                  NewCalendarView.year
                              ? '${controller.selectedYear.value}'
                              : controller.monthTitle,
                          icon: Icons.calendar_month_rounded,
                          color: NewUi.purple,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 10 * scale),
                  _CalendarViewSelector(controller: controller),
                  SizedBox(height: 10 * scale),
                  Obx(
                    () => AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: _Body(
                        controller: controller,
                        key: ValueKey(
                          '${controller.selectedView.value}${controller.selectedMonth.value}${controller.selectedYear.value}${controller.selectedDay.value}',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarViewSelector extends StatelessWidget {
  const _CalendarViewSelector({required this.controller});

  final NewCalendarController controller;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Obx(
      () => Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: dark ? Colors.white.withAlpha(8) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: dark ? Colors.white.withAlpha(18) : const Color(0xFFE4E9F1),
          ),
          boxShadow: dark
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(10),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Row(
          children: NewCalendarView.values.map((view) {
            final active = controller.selectedView.value == view;
            return Expanded(
              child: Semantics(
                button: true,
                selected: active,
                child: InkWell(
                  onTap: () => controller.changeView(view),
                  borderRadius: BorderRadius.circular(11),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: active
                          ? NewUi.accentGradient(NewUi.accent)
                          : null,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: NewUi.accent.withAlpha(46),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _calendarViewLabel(view),
                        maxLines: 1,
                        style: TextStyle(
                          color: active
                              ? Colors.white
                              : Theme.of(context).textTheme.bodyMedium?.color,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _calendarViewLabel(NewCalendarView view) {
    switch (view) {
      case NewCalendarView.today:
        return 'Today';
      case NewCalendarView.tomorrow:
        return 'Tomorrow';
      case NewCalendarView.week:
        return 'Week';
      case NewCalendarView.month:
        return 'Month';
      case NewCalendarView.year:
        return 'Year';
    }
  }
}

class _Body extends StatelessWidget {
  const _Body({super.key, required this.controller});

  final NewCalendarController controller;

  @override
  Widget build(BuildContext context) {
    switch (controller.selectedView.value) {
      case NewCalendarView.month:
        return _MonthCalendar(controller: controller);
      case NewCalendarView.year:
        return NewYearCalendarView(controller: controller);
      case NewCalendarView.today:
      case NewCalendarView.tomorrow:
      case NewCalendarView.week:
        return _ShiftList(shifts: controller.filteredShifts);
    }
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({required this.controller});

  final NewCalendarController controller;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final scale = (width / 390).clamp(0.85, 1.2);
    final gap = (4.0 * scale).clamp(3.0, 5.0);
    final contentWidth = (width - (28 * scale)).clamp(0.0, 556.0);
    final cellWidth = (contentWidth - (gap * 6)) / 7;
    final dayExtent = (cellWidth * 0.92).clamp(36.0, 48.0);

    return Column(
      children: [
        NewGlassCard(
          highlightColor: NewUi.purple,
          padding: EdgeInsets.fromLTRB(12 * scale, 12 * scale, 12 * scale, 10 * scale),
          child: Column(
            children: [
              Row(
                children: [
                  _NavButton(
                    icon: Icons.chevron_left_rounded,
                    onTap: controller.previousMonth,
                  ),
                  Expanded(
                    child: Text(
                      controller.monthTitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 16 * scale,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  _NavButton(
                    icon: Icons.chevron_right_rounded,
                    onTap: controller.nextMonth,
                  ),
                ],
              ),
              SizedBox(height: 8 * scale),
              _WeekdayHeader(
                fontSize: (11 * scale).clamp(10.0, 12.0),
                horizontalPadding: 0,
              ),
              SizedBox(height: 2 * scale),
              GridView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: controller.monthDays.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: gap,
                  mainAxisExtent: dayExtent,
                ),
                itemBuilder: (context, index) {
                  final day = controller.monthDays[index];
                  return _CalendarDayTile(
                    day: day,
                    scale: scale,
                    onTap: day.inMonth
                        ? () => controller.selectDay(day.day)
                        : null,
                  );
                },
              ),
              SizedBox(height: 4 * scale),
              const _CalendarLegend(),
            ],
          ),
        ),
        SizedBox(height: 12 * scale),
        _SelectedDayPanel(controller: controller),
      ],
    );
  }
}

class _CalendarDayTile extends StatelessWidget {
  const _CalendarDayTile({
    required this.day,
    required this.onTap,
    required this.scale,
  });

  final NewCalendarDay day;
  final VoidCallback? onTap;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final active = day.isSelected;
    final hasMarks =
        day.hasShift || day.hasWarning || day.hasFirewatch || day.hasPaidLunch;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: 2 * scale, vertical: 2 * scale),
        decoration: BoxDecoration(
          gradient: active ? NewUi.accentGradient(NewUi.accent) : null,
          color: active
              ? null
              : day.hasShift
              ? NewUi.accent.withAlpha(18)
              : Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withAlpha(day.inMonth ? 8 : 3)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: active
                ? Colors.transparent
                : day.isToday
                ? NewUi.success
                : day.hasWarning
                ? NewUi.danger.withAlpha(90)
                : day.hasShift
                ? NewUi.accent.withAlpha(80)
                : Theme.of(
                    context,
                  ).dividerColor.withAlpha(day.inMonth ? 75 : 25),
          ),
          boxShadow: active
              ? [BoxShadow(color: NewUi.accent.withAlpha(65), blurRadius: 12)]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                color: active
                    ? Colors.white
                    : day.inMonth
                    ? Theme.of(context).textTheme.bodyLarge?.color
                    : Theme.of(context).brightness == Brightness.dark
                    ? Colors.white38
                    : Colors.black26,
                fontSize: (12 * scale).clamp(11.0, 13.5),
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            if (hasMarks) ...[
              SizedBox(height: 3 * scale),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (day.hasShift)
                    _Dot(color: active ? Colors.white : NewUi.accent),
                  if (day.hasWarning)
                    _Dot(
                      color: active ? const Color(0xFFFFB4BC) : NewUi.danger,
                    ),
                  if (day.hasFirewatch)
                    _Dot(
                      color: active ? const Color(0xFFFFE08A) : NewUi.warning,
                    ),
                  if (day.hasPaidLunch)
                    _Dot(
                      color: active ? const Color(0xFFB7F7DB) : NewUi.success,
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

class _SelectedDayPanel extends StatelessWidget {
  const _SelectedDayPanel({required this.controller});

  final NewCalendarController controller;

  @override
  Widget build(BuildContext context) {
    final shifts = controller.filteredShifts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DayDetailsHeader(
          day: controller.selectedDay.value,
          shiftCount: shifts.length,
        ),
        if (shifts.isEmpty)
          const NewEmptyState(
            title: 'No shift on this day',
            subtitle: 'Assigned shifts will appear here.',
            icon: Icons.calendar_today_rounded,
          )
        else
          ...shifts.map(
            (shift) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ShiftTile(shift: shift),
            ),
          ),
      ],
    );
  }
}

class _DayDetailsHeader extends StatelessWidget {
  const _DayDetailsHeader({required this.day, required this.shiftCount});

  final int day;
  final int shiftCount;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: NewUi.accent.withAlpha(dark ? 32 : 18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: NewUi.accent.withAlpha(45)),
            ),
            child: const Icon(
              Icons.event_note_rounded,
              size: 18,
              color: NewUi.accent,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Day Details · $day',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.35,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: dark ? Colors.white.withAlpha(9) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '$shiftCount ${shiftCount == 1 ? 'shift' : 'shifts'}',
              style: TextStyle(
                color: dark ? NewUi.textMutedDark : NewUi.textMutedLight,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? NewUi.textMutedDark
        : NewUi.textMutedLight;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor.withAlpha(45)),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          _LegendItem(label: 'Shift', color: NewUi.accent, textColor: muted),
          _LegendItem(label: 'Warning', color: NewUi.danger, textColor: muted),
          _LegendItem(
            label: 'Firewatch',
            color: NewUi.warning,
            textColor: muted,
          ),
          _LegendItem(
            label: 'Paid break',
            color: NewUi.success,
            textColor: muted,
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ShiftList extends StatelessWidget {
  const _ShiftList({required this.shifts});

  final List<NewCalendarShift> shifts;

  @override
  Widget build(BuildContext context) {
    if (shifts.isEmpty) {
      return const NewEmptyState(
        title: 'No shifts found',
        subtitle: 'Assigned shifts will appear here.',
        icon: Icons.event_busy_rounded,
      );
    }
    return Column(
      children: shifts
          .map(
            (shift) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ShiftTile(shift: shift),
            ),
          )
          .toList(),
    );
  }
}

class _ShiftTile extends StatelessWidget {
  const _ShiftTile({required this.shift});

  final NewCalendarShift shift;

  @override
  Widget build(BuildContext context) {
    final statusColor = shift.status.toLowerCase().contains('extra')
        ? NewUi.danger
        : shift.status.toLowerCase().contains('permanent')
        ? NewUi.success
        : NewUi.accent;
    return NewGlassCard(
      highlightColor: statusColor.withAlpha(170),
      padding: const EdgeInsets.all(14),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ShiftDateBadge(
              month: _dayLabel(shift.dateText),
              day: _dayNumber(shift.dateText),
              color: statusColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          shift.shiftName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.25,
                              ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      NewPill(text: shift.role, color: NewUi.accent),
                    ],
                  ),
                  const SizedBox(height: 6),
                  NewPill(text: shift.site, color: NewUi.success),
                  const SizedBox(height: 7),
                  _ShiftMetaRow(
                    icon: Icons.calendar_today_rounded,
                    text: shift.fullDateText,
                  ),
                  const SizedBox(height: 5),
                  _ShiftMetaRow(
                    icon: Icons.schedule_rounded,
                    text: shift.timeRange,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 1,
                    color: Theme.of(context).dividerColor.withAlpha(55),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      NewPill(text: shift.status, color: statusColor),
                      NewPill(
                        text:
                            '${shift.breakMinutes} min · ${shift.breakPaid ? 'Paid break' : 'Unpaid break'}',
                        icon: Icons.coffee_rounded,
                        color: NewUi.warning,
                      ),
                      if (shift.firewatch)
                        const NewPill(
                          text: 'Firewatch',
                          icon: Icons.local_fire_department_rounded,
                          color: NewUi.danger,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _dayNumber(String text) {
    final match = RegExp(r'(\d+)').firstMatch(text);
    return match?.group(1) ?? (text == 'Today' ? '19' : '20');
  }

  String _dayLabel(String text) {
    if (text == 'Today') return 'TOD';
    if (text == 'Tomorrow') return 'TMR';
    return text.substring(0, text.length >= 3 ? 3 : text.length).toUpperCase();
  }
}

class _ShiftDateBadge extends StatelessWidget {
  const _ShiftDateBadge({
    required this.month,
    required this.day,
    required this.color,
  });

  final String month;
  final String day;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 52,
        decoration: BoxDecoration(
          color: dark ? Colors.white.withAlpha(8) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(54)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 5),
              color: color.withAlpha(dark ? 30 : 20),
              child: Text(
                month,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .55,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Text(
                day,
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftMetaRow extends StatelessWidget {
  const _ShiftMetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).brightness == Brightness.dark
        ? NewUi.textMutedDark
        : NewUi.textMutedLight;
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({
    required this.fontSize,
    required this.horizontalPadding,
  });

  final double fontSize;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? NewUi.textMutedDark
        : NewUi.textMutedLight;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
            .map(
              (d) => Expanded(
                child: Text(
                  d,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    color: muted,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withAlpha(10)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).dividerColor.withAlpha(80),
          ),
        ),
        child: Icon(icon, color: NewUi.accent2),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      width: 5,
      height: 5,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
