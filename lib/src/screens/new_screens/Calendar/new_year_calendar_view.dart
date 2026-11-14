import 'package:flutter/material.dart';
import 'package:smartnps360/src/screens/new_screens/Widgets/new_common_widgets.dart';
import 'new_calendar_controller.dart';

class NewYearCalendarView extends StatelessWidget {
  const NewYearCalendarView({super.key, required this.controller});

  final NewCalendarController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        NewGlassCard(
          highlightColor: NewUi.purple,
          child: Row(
            children: [
              _NavButton(icon: Icons.chevron_left_rounded, onTap: () => controller.selectedYear.value--),
              Expanded(
                child: Text(
                  '${controller.selectedYear.value}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              _NavButton(icon: Icons.chevron_right_rounded, onTap: () => controller.selectedYear.value++),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth < 320 ? 1 : 2;
            final spacing = crossAxisCount == 1 ? 0.0 : 10.0;
            final itemWidth = (constraints.maxWidth - spacing) / crossAxisCount;
            return Wrap(
              spacing: spacing,
              runSpacing: 12,
              children: controller.yearMonths.map((month) {
                final isCurrentMonth = controller.selectedYear.value == 2026 && month.month == 5;
                return SizedBox(
                  width: itemWidth,
                  child: _YearMonthCard(
                    month: month,
                    isCurrentMonth: isCurrentMonth,
                    onTap: () => controller.selectMonth(month.month),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _YearMonthCard extends StatelessWidget {
  const _YearMonthCard({required this.month, required this.isCurrentMonth, required this.onTap});

  final NewCalendarMonth month;
  final bool isCurrentMonth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlight = isCurrentMonth
        ? NewUi.success
        : month.warningCount > 0
            ? NewUi.danger
            : month.shiftCount > 0
                ? NewUi.accent
                : null;

    return NewGlassCard(
      padding: EdgeInsets.zero,
      highlightColor: highlight,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isCurrentMonth ? NewUi.success.withAlpha(isDark ? 16 : 9) : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: isCurrentMonth ? Border.all(color: NewUi.success.withAlpha(120), width: 1.2) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    month.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: isCurrentMonth ? NewUi.success : null,
                          letterSpacing: -0.2,
                        ),
                  ),
                ),
                if (isCurrentMonth) const _SmallStatusBadge(text: 'NOW', color: NewUi.success),
                if (month.shiftCount > 0) Padding(padding: const EdgeInsets.only(left: 4), child: _SmallStatusBadge(text: '${month.shiftCount}', color: NewUi.accent)),
                if (month.warningCount > 0) Padding(padding: const EdgeInsets.only(left: 4), child: _SmallStatusBadge(text: '${month.warningCount}', color: NewUi.danger)),
              ],
            ),
            const SizedBox(height: 8),
            const _WeekdayHeader(),
            const SizedBox(height: 4),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: month.days.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                crossAxisSpacing: 2.2,
                mainAxisSpacing: 2.2,
                childAspectRatio: .98,
              ),
              itemBuilder: (context, index) => _MiniDayTile(day: month.days[index], currentMonthHighlighted: isCurrentMonth),
            ),
            const SizedBox(height: 7),
            Text(
              isCurrentMonth
                  ? 'Current month · ${month.shiftCount} shifts'
                  : month.warningCount > 0
                      ? '${month.shiftCount} shifts · ${month.warningCount} warnings'
                      : month.shiftCount > 0
                          ? '${month.shiftCount} scheduled shifts'
                          : 'No scheduled shifts',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isCurrentMonth
                    ? NewUi.success
                    : month.warningCount > 0
                        ? NewUi.danger
                        : isDark
                            ? NewUi.textMutedDark
                            : NewUi.textMutedLight,
                fontSize: 10.4,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniDayTile extends StatelessWidget {
  const _MiniDayTile({required this.day, required this.currentMonthHighlighted});

  final NewCalendarDay day;
  final bool currentMonthHighlighted;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showMarker = day.hasShift || day.hasWarning || day.hasFirewatch || day.hasPaidLunch;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: day.isToday
            ? NewUi.success.withAlpha(65)
            : day.hasWarning
                ? NewUi.danger.withAlpha(26)
                : day.hasShift
                    ? NewUi.accent.withAlpha(23)
                    : currentMonthHighlighted && day.inMonth
                        ? NewUi.success.withAlpha(10)
                        : isDark
                            ? Colors.white.withAlpha(day.inMonth ? 8 : 3)
                            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: day.isToday
              ? NewUi.success
              : day.hasWarning
                  ? NewUi.danger.withAlpha(70)
                  : day.hasShift
                      ? NewUi.accent.withAlpha(62)
                      : Colors.transparent,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            '${day.day}',
            style: TextStyle(
              color: day.inMonth
                  ? day.isToday
                      ? NewUi.success
                      : Theme.of(context).textTheme.bodyMedium?.color
                  : isDark
                      ? Colors.white30
                      : Colors.black26,
              fontSize: 7.8,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          if (showMarker)
            Positioned(
              bottom: 2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (day.hasShift) const _TinyDot(color: NewUi.accent),
                  if (day.hasWarning) const _TinyDot(color: NewUi.danger),
                  if (day.hasFirewatch) const _TinyDot(color: NewUi.warning),
                  if (day.hasPaidLunch) const _TinyDot(color: NewUi.success),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
          .map((d) => Expanded(child: Text(d, textAlign: TextAlign.center, style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.w900, color: NewUi.textMutedLight))))
          .toList(),
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
          color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withAlpha(10) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor.withAlpha(80)),
        ),
        child: Icon(icon, color: NewUi.accent2),
      ),
    );
  }
}

class _SmallStatusBadge extends StatelessWidget {
  const _SmallStatusBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(99), border: Border.all(color: color.withAlpha(70))),
      child: Center(child: Text(text, style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w900))),
    );
  }
}

class _TinyDot extends StatelessWidget {
  const _TinyDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(margin: const EdgeInsets.symmetric(horizontal: .5), width: 3, height: 3, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }
}
