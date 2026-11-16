import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:smartnps360/src/screens/services/apiservice.dart';
import 'package:smartnps360/src/screens/data/api.url.dart';
import 'package:smartnps360/src/screens/utilities/sf_time.dart';

void _log(String msg, {String tag = 'APP', Object? error, StackTrace? stack}) {
  if (kDebugMode) {
    developer.log(msg, name: tag, error: error, stackTrace: stack);
  }
}

class TimesheetController extends GetxController {
  final ApiService _api = ApiService();

  var timesheet = <Map<String, dynamic>>[].obs;
  var isLoading = false.obs;
  var errorMessage = ''.obs;
  var totalHours = 0.0.obs;
  bool _hasFetched = false;
  DateTime? _lastFetchedMonth;
  Future<bool>? _fetchFuture;

  Future<bool> fetchMonthly({
    DateTime? month,
    bool forceRefresh = false,
  }) async {
    final dt = month ?? sfNow();

    if (!forceRefresh &&
        _hasFetched &&
        _lastFetchedMonth != null &&
        _lastFetchedMonth!.year == dt.year &&
        _lastFetchedMonth!.month == dt.month) {
      return true;
    }

    if (_fetchFuture != null && !forceRefresh) return _fetchFuture!;

    final monthStr = DateFormat('yyyy-MM').format(dt);
    isLoading.value = true;

    _fetchFuture = (() async {
      try {
        final resp = await _api.getData(
          '${ApiURL.timesheetsMonthly}?month=$monthStr',
        );

        if (resp is Map<String, dynamic>) {
          final dataList = resp['data'] as List?;
          timesheet.value = dataList != null
              ? dataList.map((e) => Map<String, dynamic>.from(e)).toList()
              : [];
          totalHours.value = (resp['totalHours'] is num)
              ? resp['totalHours'].toDouble()
              : 0.0;
          errorMessage.value = '';
          _hasFetched = true;
          _lastFetchedMonth = DateTime(dt.year, dt.month);
          return true;
        } else {
          timesheet.clear();
          totalHours.value = 0.0;
          errorMessage.value = 'Failed to parse server response.';
          return false;
        }
      } catch (e) {
        _log('Error fetching timesheet', tag: 'Timesheet', error: e);
        timesheet.clear();
        totalHours.value = 0.0;
        errorMessage.value = 'Network error. Pull to refresh or try again.';
        return false;
      } finally {
        isLoading.value = false;
      }
    })();

    try {
      return await _fetchFuture!;
    } finally {
      _fetchFuture = null;
    }
  }

  void applySampleMonth(DateTime month) {
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final today = sfNow();
    final todayDate = DateTime(today.year, today.month, today.day);
    const patterns = ['08:00', '08:30', '07:45', '09:15', '08:15', '10:00', '07:30'];
    const workedDays = [1, 2, 4, 5, 6, 8, 9, 11, 12, 13, 15, 16, 18, 19, 20, 22, 23, 25, 26, 27];
    final rows = <Map<String, dynamic>>[];
    var minutes = 0;

    for (final day in workedDays) {
      if (day > lastDay) continue;
      final date = DateTime(month.year, month.month, day);
      if (date.isAfter(todayDate)) continue;
      final worked = patterns[day % patterns.length];
      final parts = worked.split(':');
      minutes += int.parse(parts[0]) * 60 + int.parse(parts[1]);
      rows.add({
        'date': DateFormat('MMM d').format(date),
        'day': DateFormat('EEEE').format(date),
        'worked': worked,
        'status': 'worked',
      });
    }

    timesheet.assignAll(rows);
    totalHours.value = minutes / 60;
    errorMessage.value = '';
    isLoading.value = false;
    _hasFetched = true;
    _lastFetchedMonth = DateTime(month.year, month.month);
  }
}
