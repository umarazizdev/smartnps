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
    return NewAnimatedShell(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 150),
        children: [
          Obx(
            () => Row(
              children: [
                Expanded(child: Text('Calendar', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.7))),
                NewPill(text: controller.selectedView.value == NewCalendarView.year ? '${controller.selectedYear.value}' : controller.monthTitle, icon: Icons.calendar_month_rounded, color: NewUi.purple),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Obx(
            () => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: NewCalendarView.values.map((view) {
                  final active = controller.selectedView.value == view;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => controller.changeView(view),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          gradient: active ? NewUi.accentGradient(NewUi.accent) : null,
                          color: active ? null : Theme.of(context).brightness == Brightness.dark ? Colors.white.withAlpha(10) : Colors.white,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: active ? Colors.transparent : Theme.of(context).dividerColor.withAlpha(80)),
                          boxShadow: active ? [BoxShadow(color: NewUi.accent.withAlpha(60), blurRadius: 14)] : null,
                        ),
                        child: Text(_label(view), style: TextStyle(color: active ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color, fontWeight: FontWeight.w900, fontSize: 12)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Obx(
            () => AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: _Body(controller: controller, key: ValueKey('${controller.selectedView.value}${controller.selectedMonth.value}${controller.selectedYear.value}${controller.selectedDay.value}')),
            ),
          ),
        ],
      ),
    );
  }

  String _label(NewCalendarView view) {
    switch (view) {
      case NewCalendarView.today:
        return 'Today';
      case NewCalendarView.tomorrow:
        return 'Tomorrow';
      case NewCalendarView.week:
        return 'This Week';
      case NewCalendarView.month:
        return 'This Month';
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
    return Column(
      children: [
        NewGlassCard(
          highlightColor: NewUi.purple,
          child: Column(
            children: [
              Row(
                children: [
                  _NavButton(icon: Icons.chevron_left_rounded, onTap: controller.previousMonth),
                  Expanded(child: Text(controller.monthTitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.3))),
                  _NavButton(icon: Icons.chevron_right_rounded, onTap: controller.nextMonth),
                ],
              ),
              const SizedBox(height: 14),
              const _WeekdayHeader(fontSize: 11, horizontalPadding: 0),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: controller.monthDays.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, crossAxisSpacing: 6, mainAxisSpacing: 6, childAspectRatio: .82),
                itemBuilder: (context, index) {
                  final day = controller.monthDays[index];
                  return _CalendarDayTile(day: day, onTap: day.inMonth ? () => controller.selectDay(day.day) : null);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SelectedDayPanel(controller: controller),
      ],
    );
  }
}

class _CalendarDayTile extends StatelessWidget {
  const _CalendarDayTile({required this.day, required this.onTap});

  final NewCalendarDay day;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = day.isSelected;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          gradient: active ? NewUi.accentGradient(NewUi.accent) : null,
          color: active ? null : day.hasShift ? NewUi.accent.withAlpha(18) : Theme.of(context).brightness == Brightness.dark ? Colors.white.withAlpha(day.inMonth ? 8 : 3) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: active ? Colors.transparent : day.isToday ? NewUi.success : day.hasWarning ? NewUi.danger.withAlpha(90) : day.hasShift ? NewUi.accent.withAlpha(80) : Theme.of(context).dividerColor.withAlpha(day.inMonth ? 75 : 25)),
          boxShadow: active ? [BoxShadow(color: NewUi.accent.withAlpha(65), blurRadius: 14)] : null,
        ),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Text('${day.day}', style: TextStyle(color: active ? Colors.white : day.inMonth ? Theme.of(context).textTheme.bodyLarge?.color : Theme.of(context).brightness == Brightness.dark ? Colors.white38 : Colors.black26, fontSize: 12, fontWeight: FontWeight.w900)),
            ),
            const Spacer(),
            if (day.hasShift || day.hasWarning)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (day.hasShift) _Dot(color: active ? Colors.white : NewUi.accent),
                  if (day.hasWarning) _Dot(color: active ? Colors.white : NewUi.danger),
                  if (day.hasFirewatch) _Dot(color: active ? Colors.white : NewUi.warning),
                  if (day.hasPaidLunch) _Dot(color: active ? Colors.white : NewUi.success),
                ],
              ),
            if (day.isToday) Padding(padding: const EdgeInsets.only(top: 3), child: Text('TOD', style: TextStyle(color: active ? Colors.white70 : NewUi.success, fontSize: 8, fontWeight: FontWeight.w900))),
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
    return NewGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NewSectionTitle(title: 'Day Details · ${controller.selectedDay.value}', icon: Icons.event_note_rounded),
          if (shifts.isEmpty)
            const NewEmptyState(title: 'No shift on this day', subtitle: 'Assigned shifts will appear here.', icon: Icons.calendar_today_rounded)
          else
            ...shifts.map((shift) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _ShiftTile(shift: shift))),
        ],
      ),
    );
  }
}

class _ShiftList extends StatelessWidget {
  const _ShiftList({required this.shifts});

  final List<NewCalendarShift> shifts;

  @override
  Widget build(BuildContext context) {
    if (shifts.isEmpty) {
      return const NewEmptyState(title: 'No shifts found', subtitle: 'Assigned shifts will appear here.', icon: Icons.event_busy_rounded);
    }
    return Column(children: shifts.map((shift) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _ShiftTile(shift: shift))).toList());
  }
}

class _ShiftTile extends StatelessWidget {
  const _ShiftTile({required this.shift});

  final NewCalendarShift shift;

  @override
  Widget build(BuildContext context) {
    final statusColor = shift.status.toLowerCase().contains('extra') ? NewUi.danger : shift.status.toLowerCase().contains('permanent') ? NewUi.success : NewUi.accent;
    return NewGlassCard(
      highlightColor: statusColor.withAlpha(170),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 64,
            decoration: BoxDecoration(gradient: NewUi.accentGradient(statusColor), borderRadius: BorderRadius.circular(17), boxShadow: [BoxShadow(color: statusColor.withAlpha(55), blurRadius: 14)]),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_dayNumber(shift.dateText), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20, height: 1)),
                const SizedBox(height: 3),
                Text(_dayLabel(shift.dateText), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 9, letterSpacing: .5)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Expanded(child: Text(shift.site, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.2))), NewPill(text: shift.status, color: statusColor)]),
                const SizedBox(height: 5),
                Text(shift.timeRange, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  NewPill(text: shift.role, icon: Icons.badge_rounded, color: NewUi.accent),
                  if (shift.firewatch) const NewPill(text: 'Firewatch', icon: Icons.local_fire_department_rounded, color: NewUi.danger),
                  if (shift.paidLunch) const NewPill(text: 'Paid Lunch', icon: Icons.coffee_rounded, color: NewUi.warning),
                ]),
              ],
            ),
          ),
        ],
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

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({required this.fontSize, required this.horizontalPadding});

  final double fontSize;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        children: ['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d) => Expanded(child: Text(d, textAlign: TextAlign.center, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, color: NewUi.textMutedLight)))).toList(),
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
      child: Container(width: 36, height: 36, decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withAlpha(10) : const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).dividerColor.withAlpha(80))), child: Icon(icon, color: NewUi.accent2)),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(margin: const EdgeInsets.symmetric(horizontal: 1.5), width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }
}
