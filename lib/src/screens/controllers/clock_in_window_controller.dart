import 'dart:async';
import 'dart:developer' as developer;

import 'package:get/get.dart';
import 'package:flutter/foundation.dart';
import 'package:smartnps360/src/screens/controllers/memory_storage_controller.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/timer_controller.dart';
import 'package:smartnps360/src/screens/utilities/sf_time.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/app_storage.dart';

void _log(String msg, {String tag = 'APP', Object? error, StackTrace? stack}) {
  if (kDebugMode) {
    developer.log(msg, name: tag, error: error, stackTrace: stack);
  }
}

class ClockInWindowController extends GetxController {
  final RxBool canClockIn = false.obs;

  Timer? _timer;

  @override
  void onInit() {
    super.onInit();
    _recompute();
    // Do a quick one-off refresh after 1s, then poll every 1 minute.
    _timer = Timer(const Duration(seconds: 1), () {
      _recompute();
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => _recompute());
    });
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  Future<void> forceRefresh() async {
    _recompute();
  }

  void _recompute() {
    try {
      // If the server/session says the officer is already on-duty,
      // there's no need to enforce a local "clock-in window" check.
      if (Get.isRegistered<TimeController>()) {
        final TimeController tc = Get.find<TimeController>();
        if (tc.onDuty.value == true) {
          canClockIn.value = true;
          return;
        }
      }
      final MemoryStorageController mem =
          Get.isRegistered<MemoryStorageController>()
          ? Get.find<MemoryStorageController>()
          : Get.put(MemoryStorageController());
      final rawStart = mem.getShiftStartTime();
      final rawEnd = mem.getShiftEndTime();
      final role = box.read('role');
      final isOnSiteOfficer = role is String && role == onSiteOfficer;
      final isPatrolOfficer = role is String && role == patrolOfficer;
      final selectedCal = box.read('selectedCalendarShift');
      final bool hasCalendarSelection =
          selectedCal != null ||
          (mem.getSeriesId() != null && mem.getSiteId() != null);

      final scopeSelected = isOnSiteOfficer
          ? hasCalendarSelection
          : (isPatrolOfficer ? (mem.getIsScopeSelected()) : true);

      // ignore: unnecessary_null_comparison
      if (rawStart == null || rawEnd == null || scopeSelected != true) {
        _log(
          'ClockInWindow: missing start/end or scope - rawStart=$rawStart rawEnd=$rawEnd scope=$scopeSelected',
          tag: 'ClockInWindow',
        );
        canClockIn.value = false;
        return;
      }

      final now = sfNow();

      var start = _parseFlexible(rawStart, now);
      var end = _parseFlexible(rawEnd, now);

      if (start == null || end == null) {
        canClockIn.value = false;
        return;
      }

      if (!end.isAfter(start)) {
        if (now.isBefore(end)) {
          start = start.subtract(const Duration(days: 1));
        } else {
          end = end.add(const Duration(days: 1));
        }
      }

      final windowStart = start.subtract(const Duration(minutes: 10));

      final withinWindow = !now.isBefore(windowStart) && now.isBefore(end);

      _log(
        'ClockInWindow: now=$now start=$start end=$end windowStart=$windowStart withinWindow=$withinWindow scope=$scopeSelected',
        tag: 'ClockInWindow',
      );

      canClockIn.value = withinWindow && scopeSelected == true;
    } catch (e) {
      canClockIn.value = false;
    }
  }

  DateTime? _parseFlexible(dynamic raw, DateTime reference) {
    if (raw == null) return null;

    if (raw is DateTime) return raw.toLocal();

    final s = raw.toString().trim();
    if (s.isEmpty) return null;

    // ISO with date component
    if (s.contains('T')) {
      final tzIndicator = RegExp(r"[zZ]|[+\-]\d{2}:?\d{2}");
      try {
        if (tzIndicator.hasMatch(s)) {
          final dt = DateTime.tryParse(s);
          if (dt != null) return toSf(dt);
        } else {
          final parts = s.split('T');
          final date = parts[0].split('-');
          final time = parts.length > 1 ? parts[1] : '00:00:00';
          final tp = time.split(':');
          final y = int.tryParse(date[0]);
          final mo = int.tryParse(date[1]);
          final d = int.tryParse(date[2]);
          final h = int.tryParse(tp[0]);
          final m = tp.length > 1 ? int.tryParse(tp[1]) : 0;
          int sec = 0;
          if (tp.length > 2) sec = int.tryParse(tp[2].split('.').first) ?? 0;
          if (y != null && mo != null && d != null && h != null && m != null) {
            // construct a local DateTime from the explicit fields
            return DateTime(y, mo, d, h, m, sec);
          }
        }
      } catch (_) {}
    }

    final hm = RegExp(r'^(\d{1,2}):(\d{2})$');
    final m = hm.firstMatch(s);
    if (m != null) {
      final h = int.tryParse(m.group(1)!) ?? 0;
      final min = int.tryParse(m.group(2)!) ?? 0;
      return DateTime(reference.year, reference.month, reference.day, h, min);
    }

    return null;
  }
}
