import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/main_screens/HelpScreen/helpscreen.dart';
import 'package:smartnps360/src/screens/main_screens/main_controller.dart';
import 'package:shimmer/shimmer.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/CalendarScreen/calendarmodel.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/CalendarScreen/calendarcontroller.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'dart:async';
import 'package:smartnps360/src/screens/utilities/sf_time.dart';

typedef ShiftTap = void Function(ShiftDay shift);

class NextShiftCard extends StatefulWidget {
  final ShiftDay? shift;
  final ShiftTap? onPress;
  final bool loading;

  const NextShiftCard({
    super.key,
    this.shift,
    this.onPress,
    this.loading = false,
  });

  @override
  State<NextShiftCard> createState() => _NextShiftCardState();
}

String upcomingShiftHeading(DateTime nearestShiftStartLocal) {
  final now = sfNow();
  final today = DateTime(now.year, now.month, now.day);

  final shiftDay = DateTime(
    nearestShiftStartLocal.year,
    nearestShiftStartLocal.month,
    nearestShiftStartLocal.day,
  );

  final diffDays = shiftDay.difference(today).inDays;

  if (diffDays == 0) return "Your Today’s Shift";
  if (diffDays == 1) return "Your Tomorrow’s Shift";
  return "Your Upcoming Shift";
}

class _NextShiftCardState extends State<NextShiftCard> {
  final now = sfNow().obs;
  Timer? _timer;

  DateTime? _parseStart(String s) {
    final str = s.trim();
    if (str.isEmpty) return null;
    try {
      if (str.contains('T')) {
        final tzIndicator = RegExp(r"[zZ]|[+\-]\d{2}:?\d{2}");
        if (tzIndicator.hasMatch(str)) {
          final dt = DateTime.tryParse(str);
          if (dt != null) return toSf(dt);
        } else {
          final parts = str.split('T');
          final dateParts = parts[0].split('-');
          final timePart = parts.length > 1 ? parts[1] : '00:00:00';
          final timeParts = timePart.split(':');

          final y = int.tryParse(dateParts[0]);
          final mo = int.tryParse(dateParts[1]);
          final d = int.tryParse(dateParts[2]);
          final h = int.tryParse(timeParts[0]);
          final m = int.tryParse(timeParts.length > 1 ? timeParts[1] : '0');
          int sec = 0;
          if (timeParts.length > 2) {
            sec = int.tryParse(timeParts[2].split('.').first) ?? 0;
          }
          if (y != null && mo != null && d != null && h != null && m != null) {
            return DateTime(y, mo, d, h, m, sec);
          }
        }
      }

      final parts = str.split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final sec = parts.length >= 3 ? int.tryParse(parts[2]) ?? 0 : 0;
        if (h == null || m == null) return null;
        final now = sfNow();
        return DateTime(now.year, now.month, now.day, h, m, sec);
      }
    } catch (_) {}
    return null;
  }

  ShiftDay? _computeNext(DateTime nowVal) {
    final shift = widget.shift;
    if (shift != null) return shift;
    if (!Get.isRegistered<ScheduleMonthCalendarController>()) return null;
    final ctrl = Get.find<ScheduleMonthCalendarController>();
    ShiftDay? nearestFuture;
    DateTime? nearestFutureStart;

    ShiftDay? nearestToday;
    DateTime? nearestTodayStart;

    for (final s in ctrl.calendarDays.values.expand((d) => d.shifts)) {
      final st = _parseStart(s.startDateTime);
      if (st == null) continue;
      final en = _parseStart(s.endDateTime);
      if (en != null && nowVal.isAfter(en)) {
        continue;
      }

      if (en != null &&
          (st.isBefore(nowVal) || st.isAtSameMomentAs(nowVal)) &&
          !en.isBefore(nowVal)) {
        final ws = (s.workStatus ?? '').toLowerCase();
        if (ws == 'on-going' ||
            ws == 'ongoing' ||
            ws == 'completed' ||
            ws == 'missed') {
          continue;
        }

        return s;
      }

      // Prefer upcoming shifts later today.
      if (st.year == nowVal.year &&
          st.month == nowVal.month &&
          st.day == nowVal.day) {
        // Skip today's shifts that are marked ongoing or completed
        final ws = (s.workStatus ?? '').toLowerCase();
        if (ws == 'ongoing' || ws == 'on-going' || ws == 'completed') continue;

        if (st.isAfter(nowVal) || st.isAtSameMomentAs(nowVal)) {
          if (nearestTodayStart == null || st.isBefore(nearestTodayStart)) {
            nearestToday = s;
            nearestTodayStart = st;
          }
        }
        continue;
      }

      // Otherwise track the nearest future shift.
      if (st.isAfter(nowVal)) {
        if (nearestFutureStart == null || st.isBefore(nearestFutureStart)) {
          nearestFuture = s;
          nearestFutureStart = st;
        }
      }
    }

    // Show today's upcoming shift if present, otherwise the nearest future shift.
    if (nearestToday != null) return nearestToday;

    try {
      final todayKey = DateTime(nowVal.year, nowVal.month, nowVal.day);
      final day = ctrl.calendarDays[todayKey];
      if (day != null) {
        ShiftDay? best;
        DateTime? bestStart;
        for (final s in day.shifts) {
          final ws = (s.workStatus ?? '').toLowerCase();
          if (ws != 'scheduled') continue;
          final st = _parseStart(s.startDateTime);
          if (st == null) continue;
          if (st.isAfter(nowVal) || st.isAtSameMomentAs(nowVal)) {
            if (bestStart == null || st.isBefore(bestStart)) {
              best = s;
              bestStart = st;
            }
          }
        }
        if (best != null) return best;
      }
    } catch (_) {}

    return nearestFuture;
  }

  String _formatShiftDate(DateTime dt) {
    final w = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][dt.weekday % 7];
    final m = [
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
    ][dt.month - 1];
    return '$w, $m ${dt.day}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  String _timeRange(DateTime s, DateTime? e) {
    final end = e ?? s;
    return '${_formatTime(s)} – ${_formatTime(end)}';
  }

  String _countdownCompact(DateTime start, DateTime now) {
    var diff = start.isAfter(now)
        ? start.difference(now)
        : now.difference(start);

    final days = diff.inDays;
    diff -= Duration(days: days);
    final hours = diff.inHours;
    diff -= Duration(hours: hours);
    final mins = diff.inMinutes;

    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0 && parts.length < 2) parts.add('${hours}h');
    if (mins > 0 && parts.length < 2) parts.add('${mins}m');

    if (parts.isEmpty) return '< 1m';
    return parts.join(' ');
  }

  String _statusLabel(DateTime start, DateTime now, DateTime? end) {
    if (start.isAfter(now)) return 'Starts in ${_countdownCompact(start, now)}';
    if (end != null && !end.isBefore(now)) {
      return 'Late by ${_countdownCompact(start, now)}';
    }
    return '';
  }

  Color _countdownColor(DateTime start, DateTime nowVal, bool isDark) {
    if (!start.isAfter(nowVal)) {
      return isDark ? cDarkTextSecondary : const Color(0xFF6B7280);
    }
    final diff = start.difference(nowVal);
    if (diff.inHours < 24) {
      return isDark
          ? const Color(0xFF3B82F6)
          : cPrimary; // keep consistent (no red)
    }
    return isDark ? const Color(0xFF3B82F6) : cPrimary.withAlpha(242);
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => now.value = sfNow(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final nowVal = now.value;
      final s = _computeNext(nowVal);
      final has = s != null;
      final textTheme = Theme.of(context).textTheme;
      final isDark = Theme.of(context).brightness == Brightness.dark;

      return Container(
        width: double.infinity,
        color: cTransparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.loading) _HeaderRowSkeleton(),

            const SizedBox(height: 12),
            if (widget.loading)
              _NextShiftExactSkeletonCard()
            else if (has)
              _buildContent(context, s, textTheme, isDark)
            else
              _buildEmpty(context, textTheme, isDark),
          ],
        ),
      );
    });
  }

  Widget _buildEmpty(BuildContext context, TextTheme textTheme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HeaderRow(title: 'Your Upcoming Shift', subtitle: ''),
        const SizedBox(height: 12),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? cDarkCardColor : Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 51 : 20),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Big soft badge
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cPrimary.withAlpha(38), cPrimary.withAlpha(13)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: cPrimary,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: cPrimary.withAlpha(102),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.event_busy_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'No upcoming shifts scheduled',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: isDark ? cDarkTextPrimary : cDarkText,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? cDarkBorderColor.withAlpha(128)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'No Shifts',
                            style: textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? cDarkTextSecondary
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Text(
                      'No upcoming shifts in the next few days. '
                      'If you think this is a mistake, contact support.',
                      style: textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? cDarkTextSecondary
                            : const Color(0xFF6B7280),
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Full width button
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: _goToSupport,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cPrimary,
                          elevation: 4,
                          shadowColor: cPrimary.withAlpha(115),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(
                          Icons.support_agent_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        label: const Text(
                          'Contact Support',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _goToSupport() {
    if (Get.isRegistered<MainController>()) {
      if (Get.key.currentState?.canPop() ?? false) {
        Get.back();
      }
      Get.find<MainController>().changePage(3);
    } else {
      Get.to(() => const HelpScreen());
    }
  }

  Widget _buildContent(
    BuildContext context,
    ShiftDay s,
    TextTheme textTheme,
    bool isDark,
  ) {
    final start = _parseStart(s.startDateTime)!;
    final end = _parseStart(s.endDateTime);
    final nowVal = now.value;

    final month = [
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
    ][start.month - 1];

    final statusLabel = _statusLabel(start, nowVal, end);
    final isLate = statusLabel.toLowerCase().startsWith('late');
    final statusColor = isLate
        ? const Color(0xFFEF4444)
        : _countdownColor(start, nowVal, isDark);

    final heading = upcomingShiftHeading(start);
    final shiftBg = getShiftStatusBgColor(s.status, isDark: isDark);
    final shiftText = getShiftStatusTextColor(s.status, isDark: isDark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderRow(title: heading, subtitle: '', showViewAll: true),
        const SizedBox(height: 10),

        GestureDetector(
          onTap: widget.onPress == null ? null : () => widget.onPress!(s),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? cDarkCardColor : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border(
                left: BorderSide(
                  color: isLate ? const Color(0xFFEF4444) : cPrimary,
                  width: 4,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 55 : 16),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DateBadge(day: '${start.day}', month: month),
                          const SizedBox(width: 12),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        s.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.titleSmall?.copyWith(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          color: isDark
                                              ? cDarkTextPrimary
                                              : cDarkText,
                                          height: 1.1,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: shiftBg,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: shiftText.withAlpha(
                                            isDark ? 90 : 42,
                                          ),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        s.status,
                                        style: textTheme.labelSmall?.copyWith(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: shiftText,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 10),

                                Row(
                                  children: [
                                    _MiniIcon(
                                      icon: Icons.schedule_rounded,
                                      isDark: isDark,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _timeRange(start, end),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.bodySmall?.copyWith(
                                          color: isDark
                                              ? cDarkTextPrimary
                                              : cDarkText,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 7),

                                Row(
                                  children: [
                                    _MiniIcon(
                                      icon: Icons.calendar_month_rounded,
                                      isDark: isDark,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _formatShiftDate(start),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.bodySmall?.copyWith(
                                          color: isDark
                                              ? cDarkTextPrimary
                                              : cDarkText,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 7),

                                Row(
                                  children: [
                                    _MiniIcon(
                                      icon: Icons.location_on_outlined,
                                      isDark: isDark,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        s.siteName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.bodySmall?.copyWith(
                                          color: isDark
                                              ? cDarkTextSecondary
                                              : const Color(0xFF475569),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                if ((s.note ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? cDarkBorderColor.withAlpha(
                                                    120,
                                                  )
                                                : const Color(0xFFF4F6FA),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Text(
                                            s.note!.toLowerCase().contains(
                                                  'break',
                                                )
                                                ? s.note!
                                                : '${s.note!} break',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: textTheme.bodySmall
                                                ?.copyWith(
                                                  color: isDark
                                                      ? cDarkTextPrimary
                                                      : const Color(0xFF475569),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],

                                if (statusLabel.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    height: 1,
                                    color: isDark
                                        ? cDarkBorderColor.withAlpha(110)
                                        : const Color(0xFFE9EDF3),
                                  ),
                                  const SizedBox(height: 9),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.schedule_rounded,
                                        size: 16,
                                        color: statusColor,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          statusLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: textTheme.bodySmall?.copyWith(
                                            color: statusColor,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool showViewAll;

  const _HeaderRow({
    required this.title,
    required this.subtitle,
    this.showViewAll = false,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style:
                textTheme.titleMedium?.copyWith(
                  fontSize: 18,
                  height: 1.05,
                  color: isDark ? cDarkTextPrimary : cDarkText,
                  fontWeight: FontWeight.w800,
                ) ??
                TextStyle(
                  fontSize: 18,
                  height: 1.05,
                  color: isDark ? cDarkTextPrimary : cDarkText,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        Text(
          subtitle,
          style: textTheme.bodySmall?.copyWith(
            color: isDark ? cDarkTextSecondary : const Color(0xFF6B7280),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MiniIcon extends StatelessWidget {
  final IconData icon;
  final bool isDark;

  const _MiniIcon({required this.icon, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: 16,
      color: isDark ? cDarkTextSecondary : const Color(0xFF8B93A3),
    );
  }
}

class _DateBadge extends StatelessWidget {
  final String day;
  final String month;

  const _DateBadge({required this.day, required this.month});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 62,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [cPrimary.withAlpha(230), cPrimary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: cPrimary.withAlpha(45),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            day,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            month,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white.withAlpha(230),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _NextShiftExactSkeletonCard extends StatelessWidget {
  const _NextShiftExactSkeletonCard();

  static const double _cardMinHeight = 132;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? cDarkBorderColor : Colors.grey.shade300;
    final highlight = isDark
        ? cDarkCardColor.withAlpha(128)
        : Colors.grey.shade100;
    final fill = isDark
        ? cDarkBorderColor.withAlpha(179)
        : Colors.grey.shade200;

    Widget line({double h = 12, double? w, double r = 8}) {
      return Container(
        height: h,
        width: w,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(r),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(minHeight: _cardMinHeight),
      decoration: BoxDecoration(
        color: isDark ? cDarkCardColor : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border(
          left: BorderSide(color: cPrimary.withAlpha(153), width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 51 : 15),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                child: Shimmer.fromColors(
                  baseColor: base,
                  highlightColor: highlight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56,
                        height: 62,
                        decoration: BoxDecoration(
                          color: fill,
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: line(h: 16, r: 8)),
                                const SizedBox(width: 10),
                                line(h: 24, w: 72, r: 999),
                              ],
                            ),
                            const SizedBox(height: 10),
                            line(h: 12, w: 170, r: 8),
                            const SizedBox(height: 8),
                            line(h: 12, w: 130, r: 8),
                            const SizedBox(height: 8),
                            line(h: 12, w: 150, r: 8),
                            const SizedBox(height: 10),
                            line(h: 1, r: 0),
                            const SizedBox(height: 8),
                            line(h: 13, w: 140, r: 8),
                          ],
                        ),
                      ),
                    ],
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

class _HeaderRowSkeleton extends StatelessWidget {
  const _HeaderRowSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? cDarkBorderColor : Colors.grey.shade300;
    final highlight = isDark
        ? cDarkCardColor.withAlpha(128)
        : Colors.grey.shade100;
    final fill = isDark
        ? cDarkBorderColor.withAlpha(179)
        : Colors.grey.shade200;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                height: 18,
                width: 175,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          Container(
            height: 16,
            width: 70,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ],
      ),
    );
  }
}
