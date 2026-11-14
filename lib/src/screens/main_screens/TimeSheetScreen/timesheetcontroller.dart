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
}
