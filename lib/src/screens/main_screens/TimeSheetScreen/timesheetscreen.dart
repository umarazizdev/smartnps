// ignore_for_file: use_super_parameters

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/utilities/sf_time.dart';
import 'package:shimmer/shimmer.dart';
import 'timesheetcontroller.dart';

class TimesheetScreen extends StatefulWidget {
  const TimesheetScreen({
    Key? key,
    this.sampleData = false,
    this.scrollBottomPadding = 0,
  }) : super(key: key);

  final bool sampleData;
  final double scrollBottomPadding;

  @override
  State<TimesheetScreen> createState() => _TimesheetScreenState();
}

class _TimesheetScreenState extends State<TimesheetScreen> {
  DateTime selectedMonth = sfNow();
  DateTime? selectedDay;
  final TimesheetController _ctrl = Get.put(TimesheetController());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (widget.sampleData) {
      _ctrl.applySampleMonth(selectedMonth);
      return;
    }

    if (_ctrl.isLoading.value) return;

    final success = await _ctrl.fetchMonthly(
      month: selectedMonth,
      forceRefresh: forceRefresh,
    );
    if (!success) {
      // ignore: use_build_context_synchronously
      final isDark = Theme.of(context).brightness == Brightness.dark;
      Get.snackbar(
        'Error',
        'Failed to load timesheet. Pull to refresh or try again later.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: isDark ? cDarkCardColor : Colors.black87,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _selectMonth(BuildContext context) async {
    final DateTime now = sfNow();
    final DateTime minimum = DateTime(2020, 1, 1);
    DateTime initialMonth = selectedMonth.isAfter(now) ? now : selectedMonth;
    if (initialMonth.isBefore(minimum)) initialMonth = minimum;
    final initialDay = selectedDay == null
        ? DateTime(initialMonth.year, initialMonth.month, 1)
        : selectedDay!.isAfter(now)
        ? now
        : selectedDay!.isBefore(minimum)
        ? minimum
        : selectedDay!;

    final result = await showCupertinoModalPopup<_TimesheetPickerResult>(
      context: context,
      builder: (context) => _TimesheetDatePickerSheet(
        initialMonth: DateTime(initialMonth.year, initialMonth.month, 1),
        initialDay: initialDay,
        minimumDate: minimum,
        maximumDate: now,
        startInDayMode: selectedDay != null,
      ),
    );

    if (result == null) return;

    setState(() {
      selectedMonth = DateTime(result.date.year, result.date.month, 1);
      selectedDay = result.dayMode
          ? DateTime(result.date.year, result.date.month, result.date.day)
          : null;
    });
    _load();
  }

  void _goToPreviousMonth() {
    setState(() {
      selectedMonth = DateTime(selectedMonth.year, selectedMonth.month - 1, 1);
      selectedDay = null;
    });
    _load();
  }

  void _goToNextMonth() {
    setState(() {
      selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + 1, 1);
      selectedDay = null;
    });
    _load();
  }

  void _clearSelectedDay() {
    setState(() => selectedDay = null);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formattedMonth = DateFormat('MMMM yyyy').format(selectedMonth);
    final selectorLabel = selectedDay == null
        ? formattedMonth
        : DateFormat('MMM d, yyyy').format(selectedDay!);
    final textTheme = Theme.of(context).textTheme;
    final DateTime now = sfNow();
    final bool isOnCurrentMonth =
        selectedMonth.year == now.year && selectedMonth.month == now.month;
    final bool nextEnabled = !isOnCurrentMonth;

    return Scaffold(
      backgroundColor: isDark ? cDarkBackground : const Color(0xFFF4F7FB),
      body: SafeArea(
        top: false,
        bottom: widget.scrollBottomPadding == 0,
        child: RefreshIndicator(
          onRefresh: () => _load(forceRefresh: true),
          color: cPrimary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              10,
              16,
              widget.scrollBottomPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Monthly Timesheet',
                  style: textTheme.headlineMedium?.copyWith(
                    fontSize: 22,
                    color: isDark ? cDarkTextPrimary : const Color(0xff030B17),
                    fontWeight: FontWeight.w700,
                    height: 1.08,
                    letterSpacing: -0.35,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  selectedDay == null
                      ? 'Track and review your monthly work hours.'
                      : 'Showing hours for ${DateFormat('MMMM d, yyyy').format(selectedDay!)}.',
                  style: textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: isDark
                        ? cDarkTextSecondary
                        : const Color(0xFF6B7280),
                    fontWeight: FontWeight.w400,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 14),

                _MonthSelectorCard(
                  formattedMonth: selectorLabel,
                  nextEnabled: nextEnabled,
                  onPrevious: _goToPreviousMonth,
                  onNext: nextEnabled ? _goToNextMonth : null,
                  onMonthTap: () => _selectMonth(context),
                ),

                const SizedBox(height: 10),

                Obx(() {
                  if (_ctrl.isLoading.value) {
                    return _TotalWorkedSkeleton();
                  }

                  return _TotalWorkedCard(
                    formattedMonth: formattedMonth,
                    totalHours: _ctrl.totalHours.value.toStringAsFixed(2),
                  );
                }),

                const SizedBox(height: 12),

                _DailyDetailsCard(
                  ctrl: _ctrl,
                  selectedMonth: selectedMonth,
                  selectedDay: selectedDay,
                  onClearDay: _clearSelectedDay,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimesheetPickerResult {
  const _TimesheetPickerResult({required this.date, required this.dayMode});

  final DateTime date;
  final bool dayMode;
}

class _TimesheetDatePickerSheet extends StatefulWidget {
  const _TimesheetDatePickerSheet({
    required this.initialMonth,
    required this.initialDay,
    required this.minimumDate,
    required this.maximumDate,
    required this.startInDayMode,
  });

  final DateTime initialMonth;
  final DateTime initialDay;
  final DateTime minimumDate;
  final DateTime maximumDate;
  final bool startInDayMode;

  @override
  State<_TimesheetDatePickerSheet> createState() =>
      _TimesheetDatePickerSheetState();
}

class _TimesheetDatePickerSheetState extends State<_TimesheetDatePickerSheet> {
  late bool _dayMode;
  late DateTime _picked;

  @override
  void initState() {
    super.initState();
    _dayMode = widget.startInDayMode;
    _picked = _dayMode ? widget.initialDay : widget.initialMonth;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? cDarkTextSecondary : const Color(0xFF6B7280);
    final text = isDark ? cDarkTextPrimary : const Color(0xFF111827);
    final line = isDark ? cDarkBorderColor : const Color(0xFFE5EAF1);
    final accent = isDark ? const Color(0xFF93C5FD) : cPrimary;
    final scale = (MediaQuery.sizeOf(context).width / 390).clamp(0.9, 1.15);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      height: 360 * scale + bottomInset,
      decoration: BoxDecoration(
        color: isDark ? cDarkCardColor : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: muted.withAlpha(70),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    height: 40,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: muted,
                        backgroundColor: isDark
                            ? Colors.white.withAlpha(8)
                            : const Color(0xFFF3F5F8),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        minimumSize: const Size(84, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: line),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _dayMode ? 'Select date' : 'Select month',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: text,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        _TimesheetPickerResult(
                          date: _picked,
                          dayMode: _dayMode,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: cPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        minimumSize: const Size(84, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<bool>(
                  groupValue: _dayMode,
                  backgroundColor: isDark
                      ? Colors.white.withAlpha(10)
                      : const Color(0xFFF1F5F9),
                  thumbColor: isDark ? const Color(0xFF243247) : Colors.white,
                  children: {
                    false: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Month',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: !_dayMode
                              ? (isDark ? cDarkTextPrimary : accent)
                              : muted,
                        ),
                      ),
                    ),
                    true: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Date',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: _dayMode
                              ? (isDark ? cDarkTextPrimary : accent)
                              : muted,
                        ),
                      ),
                    ),
                  },
                  onValueChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _dayMode = value;
                      if (_dayMode) {
                        final day = _picked.day.clamp(1, 28);
                        _picked = DateTime(_picked.year, _picked.month, day);
                        if (_picked.isAfter(widget.maximumDate)) {
                          _picked = widget.maximumDate;
                        }
                        if (_picked.isBefore(widget.minimumDate)) {
                          _picked = widget.minimumDate;
                        }
                      } else {
                        _picked = DateTime(_picked.year, _picked.month, 1);
                      }
                    });
                  },
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: CupertinoTheme(
                  data: CupertinoThemeData(
                    brightness: isDark ? Brightness.dark : Brightness.light,
                    primaryColor: cPrimary,
                    textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: TextStyle(
                        fontSize: 20 * scale,
                        fontWeight: FontWeight.w500,
                        color: text,
                      ),
                    ),
                  ),
                  child: CupertinoDatePicker(
                    key: ValueKey(_dayMode),
                    mode: _dayMode
                        ? CupertinoDatePickerMode.date
                        : CupertinoDatePickerMode.monthYear,
                    initialDateTime: _picked,
                    minimumDate: widget.minimumDate,
                    maximumDate: widget.maximumDate,
                    onDateTimeChanged: (value) {
                      _picked = value;
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthSelectorCard extends StatelessWidget {
  final String formattedMonth;
  final bool nextEnabled;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onMonthTap;

  const _MonthSelectorCard({
    required this.formattedMonth,
    required this.nextEnabled,
    required this.onPrevious,
    required this.onNext,
    required this.onMonthTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final disabledColor = isDark
        ? cDarkTextSecondary.withAlpha(100)
        : const Color(0xFFC2C7D0);

    return Container(
      width: double.infinity,
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      decoration: _premiumCardDecoration(context, radius: 18),
      child: Row(
        children: [
          Expanded(
            child: _MonthActionButton(
              icon: Icons.chevron_left_rounded,
              label: 'Prev',
              enabled: true,
              onTap: onPrevious,
            ),
          ),
          _VerticalDivider(isDark: isDark),
          Expanded(
            flex: 2,
            child: InkWell(
              onTap: onMonthTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        formattedMonth,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontSize: 14.5,
                          color: isDark ? cDarkTextPrimary : cPrimary,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.calendar_month_rounded,
                      size: 17,
                      color: isDark ? cDarkIconColor : cPrimary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          _VerticalDivider(isDark: isDark),
          Expanded(
            child: _MonthActionButton(
              icon: Icons.chevron_right_rounded,
              label: 'Next',
              enabled: nextEnabled,
              disabledColor: disabledColor,
              iconAfterText: true,
              onTap: onNext,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final Color? disabledColor;
  final bool iconAfterText;
  final VoidCallback? onTap;

  const _MonthActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    this.disabledColor,
    this.iconAfterText = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = enabled
        ? (isDark ? cDarkTextPrimary : const Color(0xFF0F172A))
        : (disabledColor ?? Colors.grey.shade400);

    final iconWidget = Icon(icon, size: 20, color: color);
    final textWidget = Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        fontSize: 13,
        color: color,
        fontWeight: FontWeight.w800,
      ),
    );

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: iconAfterText
              ? [textWidget, const SizedBox(width: 3), iconWidget]
              : [iconWidget, const SizedBox(width: 3), textWidget],
        ),
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  final bool isDark;

  const _VerticalDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      color: isDark ? cDarkBorderColor : const Color(0xFFE9EDF3),
    );
  }
}

class _TotalWorkedCard extends StatelessWidget {
  final String formattedMonth;
  final String totalHours;

  const _TotalWorkedCard({
    required this.formattedMonth,
    required this.totalHours,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: _premiumCardDecoration(context, radius: 18),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isDark ? cDarkInputFillColor : cPrimary.withAlpha(16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.timer_outlined,
              color: isDark ? const Color(0xFF93C5FD) : cPrimary,
              size: 22,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Total Worked Time',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 14,
                    color: isDark ? cDarkTextPrimary : const Color(0xFF111827),
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formattedMonth,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: isDark
                        ? cDarkTextSecondary
                        : const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                totalHours,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 19,
                  color: isDark ? cDarkTextPrimary : cPrimary,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'hrs',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontSize: 12,
                  color: isDark ? const Color(0xFF93C5FD) : cPrimary,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalWorkedSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: _premiumCardDecoration(context, radius: 18),
      child: _shimmerWrap(
        context: context,
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isDark ? cDarkBorderColor : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _skelLine(h: 15, radius: 8, context: context),
                  const SizedBox(height: 7),
                  _skelLine(w: 110, h: 12, radius: 8, context: context),
                ],
              ),
            ),
            const SizedBox(width: 13),
            _skelLine(w: 66, h: 24, radius: 10, context: context),
          ],
        ),
      ),
    );
  }
}

class _DailyDetailsCard extends StatelessWidget {
  final TimesheetController ctrl;
  final DateTime selectedMonth;
  final DateTime? selectedDay;
  final VoidCallback onClearDay;

  const _DailyDetailsCard({
    required this.ctrl,
    required this.selectedMonth,
    required this.selectedDay,
    required this.onClearDay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dayLabel = selectedDay == null
        ? null
        : DateFormat('MMM d').format(selectedDay!);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: _premiumCardDecoration(context, radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month_rounded,
                color: isDark ? const Color(0xFF93C5FD) : cPrimary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Daily Details',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 17,
                    color: isDark ? cDarkTextPrimary : const Color(0xff030B17),
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
              if (dayLabel != null)
                TextButton(
                  onPressed: onClearDay,
                  style: TextButton.styleFrom(
                    foregroundColor: isDark
                        ? const Color(0xFF93C5FD)
                        : cPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '$dayLabel · Clear',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Obx(() {
            if (ctrl.isLoading.value) {
              return _DailyDetailsSkeleton();
            }

            if (ctrl.errorMessage.value.isNotEmpty) {
              return _ErrorState(
                message: ctrl.errorMessage.value,
                onRetry: () =>
                    ctrl.fetchMonthly(month: selectedMonth, forceRefresh: true),
              );
            }

            final list = dayLabel == null
                ? ctrl.timesheet.toList()
                : ctrl.timesheet
                      .where((row) => (row['date'] ?? '') == dayLabel)
                      .toList();

            if (list.isEmpty) {
              return _EmptyState(isDark: isDark);
            }

            return ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? cDarkBorderColor : const Color(0xFFE7ECF3),
                    width: 1,
                  ),
                ),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1.65),
                    1: FlexColumnWidth(2.2),
                    2: FlexColumnWidth(1.55),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        color: isDark
                            ? cDarkInputFillColor
                            : const Color(0xFFF3F7FF),
                      ),
                      children: const [
                        _TableHeaderCell('DATE'),
                        _TableHeaderCell('DAY'),
                        _TableHeaderCell('WORKED', alignRight: true),
                      ],
                    ),
                    for (int i = 0; i < list.length; i++)
                      TableRow(
                        decoration: BoxDecoration(
                          color: isDark
                              ? cDarkCardColor
                              : (i.isEven
                                    ? Colors.white
                                    : const Color(0xFFFCFDFF)),
                          border: Border(
                            top: BorderSide(
                              color: isDark
                                  ? cDarkBorderColor
                                  : const Color(0xFFE7ECF3),
                              width: 1,
                            ),
                          ),
                        ),
                        children: [
                          _TableDataCell(list[i]['date'] ?? ''),
                          _TableDataCell(list[i]['day'] ?? ''),
                          _TableDataCell(
                            list[i]['worked'] ?? '',
                            alignRight: true,
                            bold: true,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  final String text;
  final bool alignRight;

  const _TableHeaderCell(this.text, {this.alignRight = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Text(
        text,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontSize: 10.5,
          color: isDark ? const Color(0xFFBFDBFE) : cPrimary,
          fontWeight: FontWeight.w800,
          height: 1.12,
          letterSpacing: 0.15,
        ),
      ),
    );
  }
}

class _TableDataCell extends StatelessWidget {
  final String text;
  final bool alignRight;
  final bool bold;

  const _TableDataCell(this.text, {this.alignRight = false, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          color: isDark ? cDarkTextPrimary : const Color(0xFF111827),
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          height: 1.2,
        ),
      ),
    );
  }
}

class _DailyDetailsSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _shimmerWrap(
      context: context,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Expanded(child: _skelLine(h: 13, context: context)),
                const SizedBox(width: 14),
                Expanded(child: _skelLine(h: 13, context: context)),
                const SizedBox(width: 14),
                Expanded(child: _skelLine(h: 13, context: context)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(5, (_) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Row(
                children: [
                  Expanded(child: _skelLine(h: 14, context: context)),
                  const SizedBox(width: 14),
                  Expanded(child: _skelLine(h: 14, context: context)),
                  const SizedBox(width: 14),
                  Expanded(child: _skelLine(h: 14, context: context)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isDark;

  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
      decoration: BoxDecoration(
        color: isDark ? cDarkInputFillColor : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? cDarkBorderColor : const Color(0xFFE7ECF3),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.hourglass_empty_rounded,
            size: 32,
            color: isDark ? cDarkTextSecondary : const Color(0xFF94A3B8),
          ),
          const SizedBox(height: 10),
          Text(
            'No Data Available',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: isDark ? cDarkTextSecondary : const Color(0xFF64748B),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<bool> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A1F26) : Colors.red.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF7F1D1D) : Colors.red.shade100,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

BoxDecoration _premiumCardDecoration(
  BuildContext context, {
  double radius = 20,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: isDark ? cDarkCardColor : Colors.white,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: isDark ? cDarkBorderColor.withAlpha(140) : const Color(0xFFE8EDF5),
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withAlpha(isDark ? 45 : 12),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

Widget _shimmerWrap({required BuildContext context, required Widget child}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Shimmer.fromColors(
    baseColor: isDark ? cDarkBorderColor : Colors.grey.shade300.withAlpha(255),
    highlightColor: isDark
        ? cDarkCardColor.withAlpha(128)
        : Colors.grey.shade100.withAlpha(255),
    child: child,
  );
}

Widget _skelLine({
  required BuildContext context,
  double? w,
  double h = 14,
  double radius = 6,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: isDark
          ? cDarkBorderColor.withAlpha(179)
          : Colors.grey.shade300.withAlpha(255),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}
