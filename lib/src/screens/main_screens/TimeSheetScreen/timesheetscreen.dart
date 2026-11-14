// ignore_for_file: use_super_parameters

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/utilities/sf_time.dart';
import 'package:shimmer/shimmer.dart';
import 'timesheetcontroller.dart';

class TimesheetScreen extends StatefulWidget {
  const TimesheetScreen({Key? key}) : super(key: key);

  @override
  State<TimesheetScreen> createState() => _TimesheetScreenState();
}

class _TimesheetScreenState extends State<TimesheetScreen> {
  DateTime selectedMonth = sfNow();
  final TimesheetController _ctrl = Get.put(TimesheetController());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
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

    if (Platform.isIOS) {
      DateTime tempPicked = selectedMonth;

      final DateTime? picked = await showCupertinoModalPopup<DateTime>(
        context: context,
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return Container(
            height: 320,
            decoration: BoxDecoration(
              color: isDark ? cDarkCardColor : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          'Select Month',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? cDarkTextPrimary : cDarkText,
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.pop(context, tempPicked),
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              color: cPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? cDarkBorderColor : const Color(0xFFE5EAF1),
                  ),
                  Expanded(
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.monthYear,
                      initialDateTime: selectedMonth.isAfter(now)
                          ? now
                          : selectedMonth,
                      minimumDate: DateTime(2020),
                      maximumDate: now,
                      onDateTimeChanged: (DateTime value) {
                        tempPicked = value;
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (picked != null) {
        setState(() {
          selectedMonth = DateTime(picked.year, picked.month, 1);
        });
        _load();
      }

      return;
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedMonth.isAfter(now) ? now : selectedMonth,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'Select Month',
    );

    if (picked != null) {
      setState(() {
        selectedMonth = DateTime(picked.year, picked.month, 1);
      });
      _load();
    }
  }

  void _goToPreviousMonth() {
    setState(() {
      selectedMonth = DateTime(selectedMonth.year, selectedMonth.month - 1, 1);
    });
    _load();
  }

  void _goToNextMonth() {
    setState(() {
      selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + 1, 1);
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formattedMonth = DateFormat('MMMM yyyy').format(selectedMonth);
    final textTheme = Theme.of(context).textTheme;
    final DateTime now = sfNow();
    final bool isOnCurrentMonth =
        selectedMonth.year == now.year && selectedMonth.month == now.month;
    final bool nextEnabled = !isOnCurrentMonth;

    return Scaffold(
      backgroundColor: isDark ? cDarkBackground : const Color(0xFFF4F7FB),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(forceRefresh: true),
          color: cPrimary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Monthly TimeSheet',
                  style: textTheme.headlineMedium?.copyWith(
                    fontSize: 24,
                    color: isDark ? cDarkTextPrimary : const Color(0xff030B17),
                    fontWeight: FontWeight.w700,
                    height: 1.08,
                    letterSpacing: -0.35,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Track and review your monthly work hours.',
                  style: textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    color: isDark
                        ? cDarkTextSecondary
                        : const Color(0xFF6B7280),
                    fontWeight: FontWeight.w400,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 18),

                _MonthSelectorCard(
                  formattedMonth: formattedMonth,
                  nextEnabled: nextEnabled,
                  onPrevious: _goToPreviousMonth,
                  onNext: nextEnabled ? _goToNextMonth : null,
                  onMonthTap: () => _selectMonth(context),
                ),

                const SizedBox(height: 14),

                Obx(() {
                  if (_ctrl.isLoading.value) {
                    return _TotalWorkedSkeleton();
                  }

                  return _TotalWorkedCard(
                    formattedMonth: formattedMonth,
                    totalHours: _ctrl.totalHours.value.toStringAsFixed(2),
                  );
                }),

                const SizedBox(height: 16),

                _DailyDetailsCard(ctrl: _ctrl, selectedMonth: selectedMonth),
              ],
            ),
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
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: _premiumCardDecoration(context, radius: 22),
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
                          fontSize: 15.5,
                          color: isDark ? cDarkTextPrimary : cPrimary,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 18,
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

    final iconWidget = Icon(icon, size: 22, color: color);
    final textWidget = Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        fontSize: 14,
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
      height: 34,
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
      constraints: const BoxConstraints(minHeight: 80),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _premiumCardDecoration(context, radius: 22),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isDark ? cDarkInputFillColor : cPrimary.withAlpha(16),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(
              Icons.timer_outlined,
              color: isDark ? const Color(0xFF93C5FD) : cPrimary,
              size: 25,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Total Worked Time',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 14.5,
                    color: isDark ? cDarkTextPrimary : const Color(0xFF111827),
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formattedMonth,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
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
                  fontSize: 20,
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
                  fontSize: 13,
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
      constraints: const BoxConstraints(minHeight: 80),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _premiumCardDecoration(context, radius: 22),
      child: _shimmerWrap(
        context: context,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isDark ? cDarkBorderColor : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(17),
              ),
            ),
            const SizedBox(width: 13),
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

  const _DailyDetailsCard({required this.ctrl, required this.selectedMonth});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: _premiumCardDecoration(context, radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month_rounded,
                color: isDark ? const Color(0xFF93C5FD) : cPrimary,
                size: 22,
              ),
              const SizedBox(width: 9),
              Text(
                'Daily Details',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 18,
                  color: isDark ? cDarkTextPrimary : const Color(0xff030B17),
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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

            final list = ctrl.timesheet;

            if (list.isEmpty) {
              return _EmptyState(isDark: isDark);
            }

            return ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark ? cDarkBorderColor : const Color(0xFFE7ECF3),
                    width: 1,
                  ),
                ),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2.55),
                    1: FlexColumnWidth(2.25),
                    2: FlexColumnWidth(1.45),
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
                        _TableHeaderCell('WORKED\nHH:MM', alignRight: true),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Text(
        text,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontSize: 12,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 14,
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
