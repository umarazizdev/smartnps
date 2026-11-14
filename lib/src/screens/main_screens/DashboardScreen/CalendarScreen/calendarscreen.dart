import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/CalendarScreen/calendarcontroller.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

class ScheduleMonthCalendar extends StatelessWidget {
  ScheduleMonthCalendar({super.key});

  final ScheduleMonthCalendarController controller = Get.put(
    ScheduleMonthCalendarController(),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textTheme = theme.textTheme;

    return Container(
      decoration: cMainBoxDecoration.copyWith(
        color: isDark ? cDarkCardColor : cSurface,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.only(bottom: 12),
      child: Obx(() {
        final currentMonth = controller.currentMonth.value;
        final daysInMonth = _daysInMonth(currentMonth);
        final firstWeekday =
            DateTime(currentMonth.year, currentMonth.month, 1).weekday % 7;
        final isLoading = controller.isLoading.value;

        final todayOnly = DateTime(
          controller.today.year,
          controller.today.month,
          controller.today.day,
        );

        final visibleMonthOnly = DateTime(
          currentMonth.year,
          currentMonth.month,
        );

        final currentSystemMonthOnly = DateTime(
          controller.today.year,
          controller.today.month,
        );

        final canGoPrevious =
            !isLoading && visibleMonthOnly.isAfter(currentSystemMonthOnly);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---------- Month Header ----------
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Row(
                children: [
                  _HeaderIconButton(
                    icon: Icons.chevron_left_rounded,
                    enabled: canGoPrevious,
                    onTap: controller.goToPreviousMonth,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${_monthName(currentMonth.month)} ${currentMonth.year}',
                        style: textTheme.titleMedium?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? cDarkTextPrimary : cDarkText,
                        ),
                      ),
                    ),
                  ),
                  _HeaderIconButton(
                    icon: Icons.chevron_right_rounded,
                    enabled: !isLoading,
                    onTap: controller.goToNextMonth,
                  ),
                ],
              ),
            ),

            // ---------- Weekday Labels ----------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children:
                    const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                        .map(
                          (day) => Expanded(
                            child: Center(
                              child: Text(
                                day,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? cDarkTextSecondary
                                      : const Color(0xFF9FA4B4),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
              ),
            ),

            const SizedBox(height: 6),

            // ---------- Legend ----------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: cOrange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'You have a shift scheduled',
                    style: textTheme.bodySmall?.copyWith(
                      fontSize: 12.5,
                      color: isDark ? cDarkTextSecondary : Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

            // ---------- Calendar Grid ----------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: isLoading
                  ? _buildLoadingSkeleton(isDark, firstWeekday)
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.86,
                          ),
                      itemCount: firstWeekday + daysInMonth,
                      itemBuilder: (context, index) {
                        if (index < firstWeekday) {
                          return const SizedBox.shrink();
                        }

                        final day = index - firstWeekday + 1;
                        final date = DateTime(
                          currentMonth.year,
                          currentMonth.month,
                          day,
                        );
                        final key = DateTime(date.year, date.month, date.day);

                        final calendarDay = controller.calendarDays[key];
                        final shiftCount = calendarDay?.count ?? 0;
                        final selected = controller.selectedDate.value;
                        final isSelected =
                            selected != null && _isSameDate(selected, date);
                        final isToday = _isSameDate(date, todayOnly);
                        final isPast = date.isBefore(todayOnly);

                        final hasMissed =
                            (controller.calendarDays[key]?.shifts.any(
                              (s) =>
                                  (s.workStatus ?? '').toLowerCase() ==
                                  'missed',
                            )) ??
                            false;

                        final canTap = !isPast && !isLoading;

                        return GestureDetector(
                          onTap: canTap
                              ? () => controller.selectDate(date)
                              : null,
                          child: _DayCell(
                            day: day,
                            shiftCount: shiftCount,
                            isSelected: isSelected,
                            isToday: isToday,
                            isPast: isPast,
                            theme: theme,
                            hasMissed: hasMissed,
                          ),
                        );
                      },
                    ),
            ),

            if (isLoading) ...[
              const SizedBox(height: 16),
              _buildSelectedDaySkeleton(context),
            ],

            if (!isLoading && controller.selectedDate.value != null) ...[
              const SizedBox(height: 16),
              _buildSelectedDayDetails(
                context,
                theme,
                controller.selectedDate.value!,
                controller,
              ),
            ],
            const SizedBox(height: 10),
          ],
        );
      }),
    );
  }

  Widget _buildLoadingSkeleton(bool isDark, int firstWeekday) {
    const totalCells = 42;

    return Shimmer.fromColors(
      baseColor: isDark ? cDarkBorderColor : Colors.grey.shade300,
      highlightColor: isDark
          ? cDarkCardColor.withAlpha(128)
          : Colors.grey.shade100,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.88,
        ),
        itemCount: totalCells,
        itemBuilder: (context, index) {
          if (index < firstWeekday) {
            return const SizedBox.shrink();
          }

          final cellColor = isDark
              ? cDarkBorderColor.withAlpha(179)
              : Colors.grey.shade300;
          final innerColor = isDark
              ? cDarkBorderColor.withAlpha(128)
              : Colors.grey.shade200;

          return Container(
            decoration: BoxDecoration(
              color: cellColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 12,
                  width: 18,
                  decoration: BoxDecoration(
                    color: innerColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 6,
                  width: 18,
                  decoration: BoxDecoration(
                    color: innerColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectedDayDetails(
    BuildContext context,
    ThemeData theme,
    DateTime date,
    ScheduleMonthCalendarController controller,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final key = DateTime(date.year, date.month, date.day);
    final calendarDay = controller.calendarDays[key];

    final dateLabel =
        '${date.day} ${_monthName(date.month)} ${date.year.toString()}';

    if (calendarDay == null || calendarDay.shifts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isDark ? cDarkTextPrimary : cDarkText,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'No shifts for this day. Contact with support team',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? cDarkTextSecondary : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              dateLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: isDark ? cDarkTextPrimary : cDarkText,
              ),
            ),
          ),
          const SizedBox(height: 12),

          ...calendarDay.shifts.map(
            (shift) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                decoration: getCardDecoration(
                  context,
                ).copyWith(borderRadius: BorderRadius.circular(22)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // top badges
                    Row(
                      children: [
                        _StatusChip(
                          label: shift.status,
                          bg: getShiftStatusBgColor(
                            shift.status,
                            isDark: isDark,
                          ),
                          textColor: getShiftStatusTextColor(
                            shift.status,
                            isDark: isDark,
                          ),
                          isDark: isDark,
                        ),
                        const Spacer(),
                        if ((shift.workStatus ?? '').isNotEmpty)
                          _WorkStatusChip(
                            workStatus: shift.workStatus!,
                            isDark: isDark,
                            theme: theme,
                          ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // title
                    Text(
                      shift.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: isDark ? cDarkTextPrimary : cDarkText,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // time
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 18,
                          color: isDark ? const Color(0xFF3B82F6) : cPrimary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            shift.timeRange,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark ? cDarkTextPrimary : cDarkText,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // location
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 18,
                          color: isDark
                              ? cDarkTextSecondary
                              : const Color(0xFF8B93A3),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            shift.siteName,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isDark
                                  ? cDarkTextSecondary
                                  : Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (shift.note != null && shift.note!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? cDarkInputFillColor
                              : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.free_breakfast_rounded,
                              size: 14,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                shift.note!.toLowerCase().contains('break')
                                    ? shift.note!
                                    : '${shift.note!} break',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isDark
                                      ? cDarkTextPrimary
                                      : const Color(0xFF374151),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildSelectedDaySkeleton(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Shimmer.fromColors(
      baseColor: isDark ? cDarkBorderColor : Colors.grey.shade300,
      highlightColor: isDark
          ? cDarkCardColor.withAlpha(128)
          : Colors.grey.shade100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 16,
            width: 160,
            decoration: BoxDecoration(
              color: isDark ? cDarkBorderColor : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(2, (_) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                decoration: getCardDecoration(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 20,
                          width: 92,
                          decoration: BoxDecoration(
                            color: isDark
                                ? cDarkBorderColor
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          height: 20,
                          width: 78,
                          decoration: BoxDecoration(
                            color: isDark
                                ? cDarkBorderColor
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      height: 18,
                      width: 200,
                      decoration: BoxDecoration(
                        color: isDark ? cDarkBorderColor : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 14,
                      width: 150,
                      decoration: BoxDecoration(
                        color: isDark ? cDarkBorderColor : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 14,
                      width: 170,
                      decoration: BoxDecoration(
                        color: isDark ? cDarkBorderColor : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    ),
  );
}

int _daysInMonth(DateTime date) {
  final firstOfNextMonth = (date.month == 12)
      ? DateTime(date.year + 1)
      : DateTime(date.year, date.month + 1);
  return firstOfNextMonth.subtract(const Duration(days: 1)).day;
}

bool _isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _monthName(int month) {
  const names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return names[month - 1];
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _HeaderIconButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: enabled
              ? (isDark ? cDarkCardColor : Colors.white)
              : (isDark ? cDarkDividerColor : const Color(0xFFF1F3F6)),
          shape: BoxShape.circle,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 38 : 10),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: 26,
          color: enabled
              ? (isDark ? cDarkTextPrimary : cPrimary)
              : (isDark ? cDarkTextSecondary : Colors.grey.shade400),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final int shiftCount;
  final bool isSelected;
  final bool isToday;
  final bool isPast;
  final ThemeData theme;
  final bool hasMissed;

  const _DayCell({
    required this.day,
    required this.shiftCount,
    required this.isSelected,
    required this.isToday,
    required this.isPast,
    required this.theme,
    this.hasMissed = false,
  });

  @override
  Widget build(BuildContext context) {
    final primary = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    final green = const Color(0xFF16A34A);

    Color bgColor;
    Color textColor;
    Color borderColor;
    double borderWidth = 1;

    if (isToday) {
      bgColor = green;
      textColor = Colors.white;
      borderColor = green;
      borderWidth = 0;
    } else if (isSelected) {
      bgColor = primary;
      textColor = Colors.white;
      borderColor = primary;
      borderWidth = 0;
    } else if (hasMissed) {
      bgColor = isDark ? const Color(0xFF3A1E1E) : const Color(0xFFFFEBEE);
      textColor = isDark ? const Color(0xFFF5B3B3) : const Color(0xFFB91C1C);
      borderColor = isDark ? const Color(0xFFB66A6A) : const Color(0xFFFCA5A5);
      borderWidth = 1;
    } else if (isPast) {
      bgColor = isDark ? cDarkDividerColor : const Color(0xFFF8F9FB);
      textColor = isDark ? cDarkTextSecondary : const Color(0xFFC5CAD3);
      borderColor = isDark ? cDarkBorderColor : const Color(0xFFE7EBF0);
      borderWidth = 1;
    } else {
      bgColor = isDark ? cDarkCardColor : Colors.white;
      textColor = isDark ? cDarkTextPrimary : const Color(0xFF1F2937);
      borderColor = isDark ? cDarkBorderColor : const Color(0xFFDDE3EA);
      borderWidth = 1;
    }

    final dotColor = shiftCount > 0
        ? (isToday || isSelected
              ? Colors.white
              : (hasMissed ? theme.colorScheme.error : cOrange))
        : Colors.transparent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: (isSelected || isToday)
            ? [
                BoxShadow(
                  color: (isToday ? green : primary).withAlpha(36),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$day',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          const SizedBox(height: 5),
          _buildDots(dotColor, shiftCount),
        ],
      ),
    );
  }

  Widget _buildDots(Color dotColor, int count) {
    if (count == 0) {
      return const SizedBox(width: 6, height: 6);
    }

    if (count == 1) {
      return Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color textColor;
  final bool isDark;

  const _StatusChip({
    required this.label,
    required this.bg,
    required this.textColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: textColor.withAlpha(isDark ? 90 : 40),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: textColor,
          height: 1.05,
        ),
      ),
    );
  }
}

class _WorkStatusChip extends StatelessWidget {
  final String workStatus;
  final bool isDark;
  final ThemeData theme;

  const _WorkStatusChip({
    required this.workStatus,
    required this.isDark,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final ws = workStatus.toLowerCase();

    Color bg;
    Color text;

    if (ws == 'missed') {
      bg = isDark ? const Color(0xFF4A2323) : Colors.red.shade100;
      text = isDark ? const Color(0xFFF7B0B0) : Colors.red.shade700;
    } else if (ws == 'on-going' || ws == 'ongoing') {
      bg = isDark ? const Color(0xFF4A3418) : Colors.orange.shade100;
      text = isDark ? const Color(0xFFF3C98A) : Colors.orange.shade800;
    } else if (ws == 'completed') {
      bg = isDark ? const Color(0xFF183D2B) : const Color(0xFFE6F4EA);
      text = isDark ? const Color(0xFF95E8BE) : const Color(0xFF0F9D58);
    } else if (ws == 'scheduled') {
      bg = isDark ? const Color(0xFF1C2F4A) : Colors.blue.shade50;
      text = isDark ? const Color(0xFFAED4FF) : Colors.blue.shade800;
    } else {
      bg = isDark ? cDarkInputFillColor : Colors.grey.shade100;
      text = isDark ? cDarkTextSecondary : Colors.grey.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        camelWorkStatus(workStatus),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: text,
          height: 1.05,
        ),
      ),
    );
  }
}
