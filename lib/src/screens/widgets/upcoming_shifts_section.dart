// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/CalendarScreen/calendarcontroller.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/CalendarScreen/calendarmodel.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/CalendarScreen/calendarscreen.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/utilities/sf_time.dart';

class UpcomingShiftsSection extends StatefulWidget {
  const UpcomingShiftsSection({super.key});

  @override
  State<UpcomingShiftsSection> createState() => _UpcomingShiftsSectionState();
}

class _UpcomingShiftsSectionState extends State<UpcomingShiftsSection> {
  int _selectedTab = 0;
  static const _tabs = ['Today', 'Tomorrow', 'Next Week', 'Month'];

  ScheduleMonthCalendarController get _ctrl =>
      Get.find<ScheduleMonthCalendarController>();

  @override
  void initState() {
    super.initState();
    _ensureDataLoaded(0);
  }

  Future<void> _ensureDataLoaded(int tab) async {
    if (tab == 3) return;
    final now = sfNow();
    final ctrl = _ctrl;
    // Silently ensure current month data is loaded
    await ctrl.fetchShiftsForMonth(now, silentRefresh: true);

    if (tab == 2) {
      // Next Week can span into next month
      final nextWeekEnd = now.add(const Duration(days: 8));
      if (nextWeekEnd.month != now.month || nextWeekEnd.year != now.year) {
        await ctrl.fetchShiftsForMonth(nextWeekEnd, silentRefresh: true);
      }
    }
  }

  List<_ShiftWithDate> _getShiftsForTab(int tab) {
    final now = sfNow();
    final today = DateTime(now.year, now.month, now.day);
    final List<_ShiftWithDate> result = [];

    if (tab == 0) {
      final shifts = _ctrl.calendarDays[today]?.shifts ?? [];
      for (final s in shifts) {
        result.add(_ShiftWithDate(shift: s, date: today));
      }
    } else if (tab == 1) {
      final tomorrow = today.add(const Duration(days: 1));
      final shifts = _ctrl.calendarDays[tomorrow]?.shifts ?? [];
      for (final s in shifts) {
        result.add(_ShiftWithDate(shift: s, date: tomorrow));
      }
    } else if (tab == 2) {
      // Days 2 through 8 from today (i.e. the "next week" window)
      for (int i = 2; i <= 8; i++) {
        final day = today.add(Duration(days: i));
        final shifts = _ctrl.calendarDays[day]?.shifts ?? [];
        for (final s in shifts) {
          result.add(_ShiftWithDate(shift: s, date: day));
        }
      }
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Tab bar ────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? cDarkCardColor : const Color(0xFFEEF0F6),
            borderRadius: BorderRadius.circular(30),
            border: isDark
                ? Border.all(color: cDarkBorderColor.withAlpha(120), width: 1)
                : null,
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withAlpha(10),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final isSelected = _selectedTab == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (_selectedTab == i) return;
                    setState(() => _selectedTab = i);
                    _ensureDataLoaded(i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isDark ? cDarkTextPrimary : Colors.white)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Colors.black.withAlpha(isDark ? 50 : 28),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        _tabs[i],
                        style: theme.textTheme.bodySmall!.copyWith(
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 13,
                          color: isSelected
                              ? (isDark ? cDarkBackground : cDarkText)
                              : (isDark ? cDarkTextSecondary : cDarkGreyclr),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),

        const SizedBox(height: 16),

        // ── Content ────────────────────────────────────────────
        if (_selectedTab == 3)
          ScheduleMonthCalendar()
        else
          Obx(() {
            // Observe calendarDays so the view rebuilds on data arrival
            final _ = _ctrl.calendarDays.length;
            final isLoading = _ctrl.isLoading.value;

            if (isLoading) {
              return _buildShimmer(isDark);
            }

            final shifts = _getShiftsForTab(_selectedTab);

            if (shifts.isEmpty) {
              return _buildEmpty(context, isDark, theme);
            }

            return _buildShiftList(context, isDark, theme, shifts);
          }),
      ],
    );
  }

  // ── Shimmer skeleton ───────────────────────────────────────

  // ── Shimmer skeleton ───────────────────────────────────────
  Widget _buildShimmer(bool isDark) {
    return Column(
      children: List.generate(2, (_) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Shimmer.fromColors(
            baseColor: isDark ? cDarkBorderColor : Colors.grey.shade300,
            highlightColor: isDark ? cDarkCardColor : Colors.grey.shade100,
            child: Container(
              height: 118,
              decoration: BoxDecoration(
                color: isDark ? cDarkBorderColor : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
        );
      }),
    );
  }

  // ── Empty state ────────────────────────────────────────────
  Widget _buildEmpty(BuildContext context, bool isDark, ThemeData theme) {
    const labels = ['today', 'tomorrow', 'next week'];
    final label = labels[_selectedTab.clamp(0, 2)];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
      decoration: BoxDecoration(
        color: isDark ? cDarkCardColor : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? cDarkBorderColor.withAlpha(110)
              : const Color(0xFFE9EEF7),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 48 : 14),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cPrimary.withAlpha(isDark ? 32 : 18),
            ),
            child: Icon(
              Icons.event_available_rounded,
              size: 28,
              color: isDark ? const Color(0xFF93C5FD) : cPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No shifts scheduled for $label',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium!.copyWith(
              color: isDark ? cDarkTextSecondary : const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ── Shift list ─────────────────────────────────────────────
  Widget _buildShiftList(
    BuildContext context,
    bool isDark,
    ThemeData theme,
    List<_ShiftWithDate> shifts,
  ) {
    // For "Next Week" group cards by date so we can show a date divider
    if (_selectedTab == 2) {
      final Map<DateTime, List<_ShiftWithDate>> grouped = {};
      for (final item in shifts) {
        grouped.putIfAbsent(item.date, () => []).add(item);
      }
      final sortedDates = grouped.keys.toList()..sort();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sortedDates.expand((date) {
          final dayShifts = grouped[date]!;
          return [
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Text(
                _formatDateLabel(date),
                style: theme.textTheme.bodySmall!.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isDark ? cDarkTextSecondary : const Color(0xFF64748B),
                ),
              ),
            ),
            ...dayShifts.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ShiftCard(
                  shift: item.shift,
                  date: item.date,
                  isDark: isDark,
                  theme: theme,
                ),
              ),
            ),
            const SizedBox(height: 4),
          ];
        }).toList(),
      );
    }

    return Column(
      children: shifts.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ShiftCard(
            shift: item.shift,
            date: item.date,
            isDark: isDark,
            theme: theme,
          ),
        );
      }).toList(),
    );
  }

  String _formatDateLabel(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weekday = days[date.weekday - 1];
    final month = months[date.month - 1];
    return '$weekday, $month ${date.day}';
  }
}

// ── Helper data class ──────────────────────────────────────────
class _ShiftWithDate {
  final ShiftDay shift;
  final DateTime date;
  const _ShiftWithDate({required this.shift, required this.date});
}

// ── Shift card ─────────────────────────────────────────────────
class _ShiftCard extends StatelessWidget {
  final ShiftDay shift;
  final DateTime date;
  final bool isDark;
  final ThemeData theme;

  const _ShiftCard({
    required this.shift,
    required this.date,
    required this.isDark,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final month = _monthName(date.month);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? cDarkCardColor : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? cDarkBorderColor.withAlpha(110)
              : const Color(0xFFE9EEF7),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 48 : 14),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SmallDateBadge(day: '${date.day}', month: month, isDark: isDark),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          shift.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge!.copyWith(
                            fontWeight: FontWeight.w800,
                            color: isDark ? cDarkTextPrimary : cDarkText,
                            height: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _statusChip(shift.status),
                    ],
                  ),
                  if ((shift.workStatus ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _workStatusChip(shift.workStatus),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _metaRow(
                    icon: Icons.schedule_rounded,
                    text: shift.timeRange,
                    iconColor: isDark ? const Color(0xFF93C5FD) : cPrimary,
                  ),
                  const SizedBox(height: 7),
                  _metaRow(
                    icon: Icons.location_on_outlined,
                    text: shift.siteName,
                    iconColor: isDark
                        ? cDarkIconColor
                        : const Color(0xFF8B93A3),
                  ),
                  if ((shift.note ?? '').isNotEmpty) ...[
                    const SizedBox(height: 7),
                    _metaRow(
                      icon: Icons.notes_rounded,
                      text: shift.note!,
                      iconColor: isDark
                          ? cDarkIconColor
                          : const Color(0xFF8B93A3),
                      maxLines: 2,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaRow({
    required IconData icon,
    required String text,
    required Color iconColor,
    int maxLines = 1,
  }) {
    return Row(
      children: [
        Icon(icon, size: 17, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall!.copyWith(
              color: isDark ? cDarkTextSecondary : const Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: getShiftStatusBgColor(status, isDark: isDark),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: getShiftStatusTextColor(
            status,
            isDark: isDark,
          ).withAlpha(isDark ? 90 : 40),
          width: 1,
        ),
      ),
      child: Text(
        status,
        style: theme.textTheme.labelSmall!.copyWith(
          fontWeight: FontWeight.w800,
          color: getShiftStatusTextColor(status, isDark: isDark),
          height: 1.1,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _workStatusChip(String? workStatus) {
    if (workStatus == null || workStatus.isEmpty) {
      return const SizedBox.shrink();
    }
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        camelWorkStatus(workStatus),
        style: theme.textTheme.labelSmall!.copyWith(
          fontWeight: FontWeight.w800,
          color: text,
          height: 1.1,
        ),
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}

class _SmallDateBadge extends StatelessWidget {
  final String day;
  final String month;
  final bool isDark;

  const _SmallDateBadge({
    required this.day,
    required this.month,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 66,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: isDark
            ? cDarkBorderColor.withAlpha(120)
            : cPrimary.withAlpha(18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            day,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              height: 1,
              color: isDark ? cDarkTextPrimary : cPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            month,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              height: 1,
              color: isDark ? cDarkTextSecondary : cPrimary.withAlpha(210),
            ),
          ),
        ],
      ),
    );
  }
}
