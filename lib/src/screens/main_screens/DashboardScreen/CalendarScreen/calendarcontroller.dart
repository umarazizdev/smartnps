import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/CalendarScreen/calendarmodel.dart';
import 'package:smartnps360/src/screens/services/calendarservice.dart';
import 'package:smartnps360/src/screens/services/notification_manager.dart';
import 'package:smartnps360/src/screens/app_storage.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/utilities/sf_time.dart';
import 'package:smartnps360/src/screens/utilities/break_utils.dart';
import 'package:smartnps360/src/screens/controllers/clock_in_window_controller.dart';
import 'package:smartnps360/src/screens/controllers/memory_storage_controller.dart';

class ScheduleMonthCalendarController extends GetxController {
  late final DateTime minMonth;
  late final DateTime today;

  late final Rx<DateTime> currentMonth;
  final Rxn<DateTime> selectedDate = Rxn<DateTime>();

  final RxMap<DateTime, CalendarDay> calendarDays =
      <DateTime, CalendarDay>{}.obs;

  final CalendarService _calendarService = CalendarService();
  final RxBool isLoading = false.obs;
  final Map<String, Map<DateTime, CalendarDay>> _monthlyCache = {};
  final Map<String, Future<void>?> _fetchFutures = {};

  @override
  void onInit() {
    super.onInit();
    final now = sfNow();

    today = DateTime(now.year, now.month, now.day);
    minMonth = DateTime(now.year, now.month);
    currentMonth = minMonth.obs;
    selectedDate.value = today;

    final role = box.read('role');
    final MemoryStorageController mem =
        Get.isRegistered<MemoryStorageController>()
        ? Get.find<MemoryStorageController>()
        : Get.put(MemoryStorageController());
    final isScopeSelected = mem.getIsScopeSelected();
    final isPatrolOfficer =
        role != null && role is String && role == patrolOfficer;
    final isOnSiteOfficer =
        role != null && role is String && role == onSiteOfficer;

    // For onsite officers we want the monthly calendar to load automatically
    if ((!isPatrolOfficer && isScopeSelected) || isOnSiteOfficer) {
      fetchShiftsForMonth(currentMonth.value);
    }
  }

  final MemoryStorageController _mem =
      Get.isRegistered<MemoryStorageController>()
      ? Get.find<MemoryStorageController>()
      : Get.put(MemoryStorageController());

  bool _isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;
  bool get canGoToPreviousMonth => currentMonth.value.isAfter(minMonth);

  void goToPreviousMonth() {
    if (!canGoToPreviousMonth) return;
    currentMonth.value = DateTime(
      currentMonth.value.year,
      currentMonth.value.month - 1,
    );
    _handleMonthChanged();
  }

  void goToNextMonth() {
    currentMonth.value = DateTime(
      currentMonth.value.year,
      currentMonth.value.month + 1,
    );
    _handleMonthChanged();
  }

  void selectDate(DateTime date) {
    selectedDate.value = date;
  }

  void _handleMonthChanged() {
    if (_isSameMonth(currentMonth.value, today)) {
      selectedDate.value = today;
    } else {
      selectedDate.value = null;
    }
    fetchShiftsForMonth(currentMonth.value);
  }

  Future<void> fetchShiftsForMonth(
    DateTime month, {
    bool forceRefresh = false,
    bool silentRefresh = false,
  }) async {
    final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';

    if (forceRefresh) {
      _monthlyCache.remove(monthKey);
      _fetchFutures.remove(monthKey);
    }

    if (_monthlyCache.containsKey(monthKey)) {
      calendarDays.removeWhere(
        (key, _) => key.year == month.year && key.month == month.month,
      );
      calendarDays.addAll(_monthlyCache[monthKey]!);
      _syncTodaySelectedShiftToStorage();
      return;
    }

    if (_fetchFutures[monthKey] != null) return _fetchFutures[monthKey]!;

    _fetchFutures[monthKey] = (() async {
      try {
        if (!silentRefresh) isLoading.value = true;
        final monthStr =
            '${month.year}-${month.month.toString().padLeft(2, '0')}';
        final response = await _calendarService.getMonthlyCalendar(monthStr);

        final Map<DateTime, CalendarDay> monthMap = {};
        for (final day in response.data) {
          final raw = day.date;
          final s = raw.toString().trim();
          if (s.isEmpty) continue;
          try {
            final dateTime = DateTime.parse(s);
            final key = DateTime(dateTime.year, dateTime.month, dateTime.day);
            monthMap[key] = day;
          } catch (_) {
            continue;
          }
        }

        _monthlyCache[monthKey] = monthMap;
        // Replace only this month's entries so we don't drop other months' data
        calendarDays.removeWhere(
          (key, _) => key.year == month.year && key.month == month.month,
        );
        calendarDays.addAll(monthMap);

        _syncTodaySelectedShiftToStorage();
      } catch (e) {
        debugPrint('Error fetching calendar for $month: $e');
      } finally {
        if (!silentRefresh) isLoading.value = false;
      }
    })();

    try {
      await _fetchFutures[monthKey];
    } finally {
      _fetchFutures.remove(monthKey);
    }
  }

  DateTime? _parse(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    try {
      if (s.contains('T')) return DateTime.parse(s).toLocal();
    } catch (_) {}
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final sec = parts.length >= 3 ? int.tryParse(parts[2]) ?? 0 : 0;
    if (h == null || m == null) return null;
    final now = sfNow();
    return DateTime(now.year, now.month, now.day, h, m, sec);
  }

  Future<void> _syncTodaySelectedShiftToStorage() async {
    final role = box.read('role');
    final isPatrolOfficer =
        role != null && role is String && role == patrolOfficer;
    final isOnSiteOfficer =
        role != null && role is String && role == onSiteOfficer;
    if (isPatrolOfficer) return;

    final selectedSiteId = _mem.getSiteId();

    final selectedStart = _parse(_mem.getShiftStartTime());
    final selectedEnd = _parse(_mem.getShiftEndTime());

    final todayKey = DateTime(today.year, today.month, today.day);
    final day = calendarDays[todayKey];
    if (day == null || day.shifts.isEmpty) return;

    // For onsite officers: if no explicit site/selected scope, pick the first available
    // shift for today and sync it to storage so the dial timer can use it.
    List<ShiftDay> candidates = [];
    if (isOnSiteOfficer) {
      candidates = List<ShiftDay>.from(day.shifts);
    } else {
      if (selectedSiteId == null) return;
      candidates = day.shifts.where((s) => s.siteId == selectedSiteId).toList();
      if (candidates.isEmpty) return;
    }

    List<ShiftDay> matches = candidates;

    if (selectedStart != null && selectedEnd != null && !isOnSiteOfficer) {
      matches = candidates.where((s) {
        final sStart = DateTime.tryParse(s.startDateTime)?.toLocal();
        DateTime? sEnd = DateTime.tryParse(s.endDateTime)?.toLocal();
        if (sStart == null || sEnd == null) return false;
        if (sEnd.isBefore(sStart)) sEnd = sEnd.add(const Duration(days: 1));

        final selStart = DateTime(
          selectedStart.year,
          selectedStart.month,
          selectedStart.day,
          selectedStart.hour,
          selectedStart.minute,
        );
        final selEnd = selectedEnd.isBefore(selectedStart)
            ? selectedEnd.add(const Duration(days: 1))
            : selectedEnd;
        final selEndNorm = DateTime(
          selEnd.year,
          selEnd.month,
          selEnd.day,
          selEnd.hour,
          selEnd.minute,
        );

        final sStartNorm = DateTime(
          sStart.year,
          sStart.month,
          sStart.day,
          sStart.hour,
          sStart.minute,
        );
        final sEndNorm = DateTime(
          sEnd.year,
          sEnd.month,
          sEnd.day,
          sEnd.hour,
          sEnd.minute,
        );

        return sStartNorm.isAtSameMomentAs(selStart) &&
            sEndNorm.isAtSameMomentAs(selEndNorm);
      }).toList();

      if (matches.isEmpty) {
        matches = candidates;
      }
    }

    // For onsite officers prefer the shift whose start time is nearest to now.
    if (isOnSiteOfficer) {
      final nowLocal = sfNow();
      matches.sort((a, b) {
        final aStart =
            DateTime.tryParse(a.startDateTime)?.toLocal() ?? DateTime(2100);
        final bStart =
            DateTime.tryParse(b.startDateTime)?.toLocal() ?? DateTime(2100);
        final da = nowLocal.difference(aStart).inMinutes.abs();
        final db = nowLocal.difference(bStart).inMinutes.abs();
        return da.compareTo(db);
      });
    } else {
      matches.sort((a, b) {
        final aStart =
            DateTime.tryParse(a.startDateTime)?.toLocal() ?? DateTime(2100);
        final bStart =
            DateTime.tryParse(b.startDateTime)?.toLocal() ?? DateTime(2100);
        return aStart.compareTo(bStart);
      });
    }

    final pick = matches.first;

    // persist selected site for onsite officers (so UI can show it)
    if (isOnSiteOfficer) {
      box.write('siteId', pick.siteId);
      _mem.setSiteId(pick.siteId);
      box.write(kSelectedSiteKey, pick.siteName);
      _mem.setSiteName(pick.siteName);
      _mem.setShiftName(pick.title);
    }

    box.write('shiftStartTime', pick.startDateTime);
    _mem.setShiftStartTime(pick.startDateTime);
    box.write('shiftEndTime', pick.endDateTime);
    _mem.setShiftEndTime(pick.endDateTime);

    final parsed = parseBreakMinutes(
      unpaidField: pick.unpaidBreakMinutes,
      paidField: pick.paidBreakMinutes,
      note: pick.note,
    );

    box.write('unpaidBreakMinutes', parsed['unpaid']);
    box.write('paidBreakMinutes', parsed['paid']);
    box.write('totalBreakMinutes', parsed['total']);

    box.write('shiftId', pick.seriesId);
    _mem.setShiftId(pick.seriesId);

    box.write('selectedCalendarShift', {
      'occurrenceId': pick.occurrenceId,
      'seriesId': pick.seriesId,
      'assignmentId': pick.assignmentId,
      'date': pick.date,
      'status': pick.status,
      'rawStatus': pick.rawStatus,
      'workStatus': pick.workStatus ?? '',
      'title': pick.title,
      'timeRange': pick.timeRange,
      'startDateTime': pick.startDateTime,
      'endDateTime': pick.endDateTime,
      'unpaidBreakMinutes': pick.unpaidBreakMinutes,
      'paidBreakMinutes': pick.paidBreakMinutes,
      'note': pick.note ?? '',
      'siteId': pick.siteId,
      'siteName': pick.siteName,
    });
    final startDt = DateTime.tryParse(pick.startDateTime);
    DateTime? endDt = DateTime.tryParse(pick.endDateTime);
    if (startDt != null && endDt != null) {
      if (endDt.isBefore(startDt)) {
        endDt = endDt.add(const Duration(days: 1));
      }
      // determine scope completeness (onsite vs other)
      bool scopeComplete;
      if (isPatrolOfficer) {
        scopeComplete = false;
      } else if (isOnSiteOfficer) {
        scopeComplete = _mem.getSiteName().isNotEmpty;
      } else {
        scopeComplete = _mem.getIsScopeSelected() == true;
      }

      await NotificationManager.instance.syncFromSession(
        scopeComplete: scopeComplete,
        siteName: _mem.getSiteName(),
        shiftName: _mem.getShiftName(),
        shiftStart: startDt,
        shiftEnd: endDt,
        breakActive: false,
        breakStart: null,
        breakDurationSeconds: 0,
        minutesBefore: 10,
      );
    }
    try {
      if (Get.isRegistered<ClockInWindowController>()) {
        Get.find<ClockInWindowController>().forceRefresh();
      }
    } catch (_) {}
  }
}
