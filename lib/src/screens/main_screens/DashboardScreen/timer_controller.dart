import 'dart:async';
import 'dart:developer' as developer;
import 'dart:developer' show log;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart' as dio;
import 'package:smartnps360/src/screens/controllers/clock_in_window_controller.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/CalendarScreen/calendarcontroller.dart';
import 'package:smartnps360/src/screens/services/notification_manager.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/utilities/sf_time.dart';
import 'package:smartnps360/src/screens/app_storage.dart';
import 'package:smartnps360/src/screens/main_screens/main_controller.dart';
import 'package:smartnps360/src/screens/native_auth_session.dart';
import 'package:smartnps360/src/screens/services/apiservice.dart';
import 'package:smartnps360/src/screens/main_screens/HelpScreen/helpscreen.dart';
import 'package:smartnps360/src/screens/controllers/memory_storage_controller.dart';

void _log(String msg, {String tag = 'APP', Object? error, StackTrace? stack}) {
  if (kDebugMode) {
    developer.log(msg, name: tag, error: error, stackTrace: stack);
  }
}

class TimeController extends GetxController {
  final currentTime = ''.obs;
  final todayStatus = 'none'.obs;

  final onDuty = false.obs;
  final breakActive = false.obs;
  final breakAllowed = true.obs;

  final workBeforeBreakSeconds = 0.obs;
  final breakSeconds = 0.obs;
  final workAfterBreakSeconds = 0.obs;
  final dialProgress = 0.0.obs;

  final shiftStartTime = Rxn<DateTime>();
  final shiftEndTime = Rxn<DateTime>();
  final isShiftEnded = false.obs;

  int totalWorkDuration = 0;
  int breakDuration = 0;
  bool _earlyAddedToTotal = false;

  Timer? _uiTimer;
  Timer? _tickTimer;

  DateTime? clockInTime;
  DateTime? breakStartTime;
  DateTime? breakEndTime;
  bool _noShiftDialogShown = false;

  final ApiService _apiService = ApiService();
  String? sessionId;
  final isLoading = false.obs;
  final dialShimmer = false.obs;
  final scopeLoading = false.obs;
  final scopeSelected = false.obs;
  final displayRegion = ''.obs;
  final displayShift = ''.obs;
  final displaySite = ''.obs;
  final MemoryStorageController _mem =
      Get.isRegistered<MemoryStorageController>()
      ? Get.find<MemoryStorageController>()
      : Get.put(MemoryStorageController());
  bool _hasLoadedSessionOnce = false;
  final upcomingLoading = false.obs;
  final lateByMinutes = 0.obs;
  final lateClockInReason = ''.obs;
  int? _pendingLateByMinutes;
  final earlyByMinutes = 0.obs;
  final earlyClockInReason = ''.obs;
  final lateClockOutReason = ''.obs;
  final earlyClockOutReason = ''.obs;

  bool get hasTakenBreak => breakStartTime != null;
  bool get isBreakDone => breakEndTime != null;
  bool get _isPatrolOfficer {
    final r = box.read('role');
    return r is String && r == patrolOfficer;
  }

  bool get scopeValuesComplete {
    if (_isPatrolOfficer) {
      final region = _mem.getRegionName();
      final shift = _mem.getShiftName();
      return region.isNotEmpty && shift.isNotEmpty;
    }
    final role = box.read('role');
    if (role is String && role == onSiteOfficer) {
      final site = _mem.getSiteName();
      return site.isNotEmpty;
    }
    return _mem.getIsScopeSelected() == true;
  }

  bool get showStartBreakButton =>
      !_isPatrolOfficer &&
      onDuty.value &&
      breakAllowed.value &&
      !breakActive.value &&
      !hasTakenBreak;

  bool get showEndBreakButton =>
      !_isPatrolOfficer &&
      onDuty.value &&
      breakAllowed.value &&
      breakActive.value &&
      !isBreakDone;
  void syncScopeFromStorage() {
    displayRegion.value = _mem.getRegionName();
    displayShift.value = _mem.getShiftName();
    displaySite.value = _mem.getSiteName();
  }

  void _syncScopeSelectedFromStorage() {
    syncScopeFromStorage();
    final complete = scopeValuesComplete;
    scopeSelected.value = complete;
  }

  void notifyScopeChanged() => _syncScopeSelectedFromStorage();

  @override
  void onInit() {
    super.onInit();
    _syncScopeSelectedFromStorage();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = sfNow();
      currentTime.value =
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';
    });
    if (NativeAuthSession.instance.hasValidSessionSync) {
      refreshServerSession(showShimmer: true, blockUI: true);
    }
  }

  Future<void> refreshServerSession({
    bool showShimmer = false,
    bool blockUI = false,
    bool suppressScopeLoading = false,
  }) async {
    try {
      if (showShimmer && !_hasLoadedSessionOnce) {
        dialShimmer.value = true;
      }
      if (blockUI) {
        isLoading.value = true;
      }

      final bool setScopeLoading = !suppressScopeLoading;
      if (setScopeLoading) scopeLoading.value = true;

      const int maxRetries = 3;

      for (int attempt = 0; attempt <= maxRetries; attempt++) {
        final resp = await _apiService.getCurrentSession();

        if (resp == null || resp is! Map) {
          todayStatus.value = 'none';
          sessionId = null;
          onDuty.value = false;
          breakActive.value = false;
          clockInTime = null;
          breakStartTime = null;
          breakEndTime = null;
          workBeforeBreakSeconds.value = 0;
          breakSeconds.value = 0;
          workAfterBreakSeconds.value = 0;
          isShiftEnded.value = false;
          _earlyAddedToTotal = false;
          _tickTimer?.cancel();

          box.remove('regionId');
          box.remove('shiftId');
          box.remove(kSelectedRegionKey);
          box.remove(kSelectedShiftKey);
          box.write('isScopeSelected', false);
          _mem.setIsScopeSelected(false);
          scopeSelected.value = false;

          box.remove('shiftStartTime');
          box.remove('shiftEndTime');

          box.remove('unpaidBreakMinutes');
          box.remove('paidBreakMinutes');
          box.remove('totalBreakMinutes');
          return;
        }

        final Map data = resp;
        final ts = data['today_status']?.toString().trim();
        todayStatus.value = (ts == null || ts.isEmpty) ? 'none' : ts;
        sessionId = data['sessionId']?.toString();
        onDuty.value = data['onDuty'] == true;

        breakActive.value = data['breakActive'] == true;
        if (_isPatrolOfficer) {
          int? toInt(dynamic v) {
            if (v == null) return null;
            if (v is int) return v;
            return int.tryParse(v.toString());
          }

          final rId = toInt(data['regionId']);
          final sId = toInt(data['shiftId']);
          if (rId != null) box.write('regionId', rId);
          if (sId != null) box.write('shiftId', sId);
          if (rId != null) _mem.setRegionId(rId);
          if (sId != null) _mem.setShiftId(sId);

          final rName = data['regionName']?.toString();
          final sName = data['shiftName']?.toString();

          if (rName != null && rName.trim().isNotEmpty) {
            box.write(kSelectedRegionKey, rName.trim());
            _mem.setRegionName(rName.trim());
          }
          if (sName != null && sName.trim().isNotEmpty) {
            box.write(kSelectedShiftKey, sName.trim());
            _mem.setShiftName(sName.trim());
          }
          syncScopeFromStorage();
          final storedRegion = _mem.getRegionName();
          final storedShift = _mem.getShiftName();

          final scopeComplete =
              storedRegion.isNotEmpty && storedShift.isNotEmpty;

          final wasChosen = _mem.getIsScopeSelected() == true;
          final nextChosen = scopeComplete ? true : wasChosen;

          box.write('isScopeSelected', nextChosen);
          _mem.setIsScopeSelected(nextChosen);

          scopeSelected.value = scopeComplete;
          syncScopeFromStorage();
          // API may return "07:00:00" or you may store "07:00" -> both are fine
          final startRawFromApi = data['shift_start_at']?.toString();
          final endRawFromApi = data['shift_end_at']?.toString();

          if (startRawFromApi != null && startRawFromApi.trim().isNotEmpty) {
            box.write('shiftStartTime', startRawFromApi.trim());
            _mem.setShiftStartTime(startRawFromApi.trim());
          }
          if (endRawFromApi != null && endRawFromApi.trim().isNotEmpty) {
            box.write('shiftEndTime', endRawFromApi.trim());
            _mem.setShiftEndTime(endRawFromApi.trim());
          }
          _loadShiftTimingAndBreakFromStorage();
          final end = shiftEndTime.value;
          isShiftEnded.value =
              onDuty.value && end != null && sfNow().isAfter(end);

          box.write('unpaidBreakMinutes', 0);
          box.write('paidBreakMinutes', 0);
          box.write('totalBreakMinutes', 0);
          final hasScopeNow = storedRegion.isNotEmpty && storedShift.isNotEmpty;
          if (onDuty.value && !hasScopeNow && attempt < maxRetries) {
            await Future.delayed(const Duration(milliseconds: 400));
            continue;
          }
        } else {
          int? toInt(dynamic v) {
            if (v == null) return null;
            if (v is int) return v;
            return int.tryParse(v.toString());
          }

          final sId = toInt(data['siteId']);
          final seId = toInt(data['seriesId']);
          if (sId != null) box.write('siteId', sId);
          if (seId != null) box.write('seriesId', seId);
          if (sId != null) _mem.setSiteId(sId);
          if (seId != null) _mem.setSeriesId(seId);

          final sName = data['siteName']?.toString();
          final seName = data['seriesName']?.toString();

          if (sName != null && sName.trim().isNotEmpty) {
            box.write(kSelectedSiteKey, sName.trim());
            _mem.setSiteName(sName.trim());
          }
          if (seName != null && seName.trim().isNotEmpty) {
            box.write(kSelectedShiftKey, seName.trim());
            _mem.setShiftName(seName.trim());
          }
          syncScopeFromStorage();
          // final storedRegion =
          //     box.read(kSelectedRegionKey)?.toString().trim() ?? '';
          // final storedShift =
          //     box.read(kSelectedShiftKey)?.toString().trim() ?? '';

          // final hasScopeNow = storedRegion.isNotEmpty && storedShift.isNotEmpty;
          // box.write('isScopeSelected', hasScopeNow);

          final startRawFromApi = data['series_start_at']?.toString();
          final endRawFromApi = data['series_end_at']?.toString();

          if (startRawFromApi != null && startRawFromApi.trim().isNotEmpty) {
            box.write('shiftStartTime', startRawFromApi.trim());
            _mem.setShiftStartTime(startRawFromApi.trim());
          }
          if (endRawFromApi != null && endRawFromApi.trim().isNotEmpty) {
            box.write('shiftEndTime', endRawFromApi.trim());
            _mem.setShiftEndTime(endRawFromApi.trim());
          }
          _loadShiftTimingAndBreakFromStorage();

          final end = shiftEndTime.value;
          isShiftEnded.value =
              onDuty.value && end != null && sfNow().isAfter(end);

          final breakMin = toInt(data['allowedBreakMinutes']);
          if (breakMin != null) {
            box.write('totalBreakMinutes', breakMin);
          }
          // box.write('unpaidBreakMinutes', 0);
          // box.write('paidBreakMinutes', 0);
        }
        DateTime? parseIso(dynamic v) {
          if (v == null) return null;
          try {
            final dt = DateTime.tryParse(v.toString());
            if (dt != null) return toSf(dt);
          } catch (_) {}
          return null;
        }

        clockInTime = parseIso(data['clockInAt']);
        breakStartTime = parseIso(data['breakStartAt']);
        breakEndTime = parseIso(data['breakEndAt']);

        workBeforeBreakSeconds.value = (data['workBeforeBreakSeconds'] is int)
            ? data['workBeforeBreakSeconds'] as int
            : int.tryParse(data['workBeforeBreakSeconds']?.toString() ?? '') ??
                  0;

        breakSeconds.value = (data['breakSeconds'] is int)
            ? data['breakSeconds'] as int
            : int.tryParse(data['breakSeconds']?.toString() ?? '') ?? 0;

        workAfterBreakSeconds.value = (data['workAfterBreakSeconds'] is int)
            ? data['workAfterBreakSeconds'] as int
            : int.tryParse(data['workAfterBreakSeconds']?.toString() ?? '') ??
                  0;
        final breakEndedByFlags =
            breakActive.value == false &&
            breakStartTime == null &&
            breakEndTime == null &&
            (breakSeconds.value > 0 || workAfterBreakSeconds.value > 0);

        if (breakEndedByFlags && clockInTime != null) {
          breakStartTime = clockInTime!.add(
            Duration(seconds: workBeforeBreakSeconds.value),
          );
          breakEndTime = breakStartTime!.add(
            Duration(seconds: breakSeconds.value),
          );
        }
        _loadShiftTimingAndBreakFromStorage();

        // sync notifications according to server session and current storage
        try {
          if (onDuty.value) {
            final bool breakValid =
                breakActive.value &&
                breakStartTime != null &&
                breakDuration > 0;
            await NotificationManager.instance.scheduleBreakOnly(
              scopeComplete: scopeValuesComplete,
              breakStart: breakStartTime!,
              breakDurationSeconds: breakValid ? breakDuration : 0,
              minutesBefore: 10,
            );
          }
          // 🚫 DO NOTHING if not onDuty
        } catch (e) {
          _log('Notification sync error', tag: 'Timer', error: e);
        }

        try {
          lateByMinutes.value = 0;
          earlyByMinutes.value = 0;

          if (clockInTime != null && shiftStartTime.value != null) {
            final startForCompare = _resolveShiftStartForCompare(
              anchor: clockInTime!,
              parsedShiftStart: shiftStartTime.value!,
              rangeDays: 3,
            );

            if (startForCompare != null) {
              final delta = clockInTime!.difference(startForCompare);

              if (delta.inMinutes >= 1) {
                lateByMinutes.value = delta.inMinutes;
                earlyByMinutes.value = 0;
              } else if (delta.inMinutes <= -1) {
                earlyByMinutes.value = delta.abs().inMinutes;
                lateByMinutes.value = 0;
              } else {
                lateByMinutes.value = 0;
                earlyByMinutes.value = 0;
              }
            }
          }
        } catch (_) {}

        _earlyAddedToTotal = true;

        if (onDuty.value) {
          _startTick();
        } else {
          _tickTimer?.cancel();
        }

        break;
      }
    } finally {
      if (blockUI) {
        isLoading.value = false;
      }
      dialShimmer.value = false;
      _syncScopeSelectedFromStorage();
      if (!suppressScopeLoading) scopeLoading.value = false;
      _hasLoadedSessionOnce = true;
    }
  }

  void resetSegmentTimes() {
    isShiftEnded.value = false;
    workBeforeBreakSeconds.value = 0;
    breakSeconds.value = 0;
    workAfterBreakSeconds.value = 0;
    dialProgress.value = 0.0;
  }

  void _tickOnce() {
    if (!onDuty.value) {
      dialProgress.value = 0.0;
      isShiftEnded.value = false;
      return;
    }
    final end = shiftEndTime.value;
    isShiftEnded.value = end != null && sfNow().isAfter(end);
    if (breakActive.value) {
      if (breakDuration > 0) {
        final baseBreak = breakSeconds.value > breakDuration
            ? breakDuration
            : breakSeconds.value;
        dialProgress.value = (baseBreak / breakDuration).clamp(0.0, 1.0);
      } else {
        dialProgress.value = 0.0;
      }
      return;
    }

    final totalWorkNow =
        workBeforeBreakSeconds.value + workAfterBreakSeconds.value;
    final baseWork = totalWorkNow > totalWorkDuration
        ? totalWorkDuration
        : totalWorkNow;
    final denom = totalWorkDuration > 0 ? totalWorkDuration : 1;
    dialProgress.value = (baseWork / denom).clamp(0.0, 1.0);
  }

  void _startTick() {
    _tickTimer?.cancel();
    _tickOnce();

    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!onDuty.value) return;
      final end = shiftEndTime.value;
      isShiftEnded.value = end != null && sfNow().isAfter(end);

      if (breakActive.value) {
        breakSeconds.value++;
        final baseBreak = breakSeconds.value > breakDuration
            ? breakDuration
            : breakSeconds.value;
        dialProgress.value =
            (baseBreak / (breakDuration > 0 ? breakDuration : 1)).clamp(
              0.0,
              1.0,
            );
        return;
      }

      if (!hasTakenBreak) {
        workBeforeBreakSeconds.value++;
      } else {
        workAfterBreakSeconds.value++;
      }

      final totalWorkNow =
          workBeforeBreakSeconds.value + workAfterBreakSeconds.value;
      final baseWork = totalWorkNow > totalWorkDuration
          ? totalWorkDuration
          : totalWorkNow;

      dialProgress.value =
          (baseWork / (totalWorkDuration > 0 ? totalWorkDuration : 1)).clamp(
            0.0,
            1.0,
          );

      if (baseWork >= totalWorkDuration) {
        breakAllowed.value = false;
      }
    });
  }

  DateTime? _parseShiftDateTime(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty) return null;

    // ✅ supports ISO datetimes like: 2025-06-01T08:00:00
    if (s.contains('T')) {
      // If the ISO string includes a timezone (Z or +/-offset), parse and
      // convert to SF local fields. If it does NOT include a timezone (plain
      // YYYY-MM-DDTHH:MM:SS), treat the fields as already in SF local time
      // and construct a DateTime with those fields (no UTC conversion).
      final tzIndicator = RegExp(r"[zZ]|[+\-]\d{2}:?\d{2}");
      try {
        if (tzIndicator.hasMatch(s)) {
          final dt = DateTime.tryParse(s);
          if (dt != null) return toSf(dt);
        } else {
          // manual parse: YYYY-MM-DDTHH:MM:SS(.sss?)
          final parts = s.split('T');
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
      } catch (_) {}
    }

    // ✅ supports: 07:00 or 07:00:00 (label parsing fallback)
    final parts = s.split(':');
    if (parts.length < 2) return null;

    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    int sec = 0;

    if (parts.length >= 3) {
      sec = int.tryParse(parts[2].split('.').first) ?? 0;
    }

    if (h == null || m == null) return null;
    final now = sfNow();
    return DateTime(now.year, now.month, now.day, h, m, sec);
  }

  void _loadShiftTimingAndBreakFromStorage() {
    totalWorkDuration = 0;
    _earlyAddedToTotal = false;

    dynamic startRaw = _mem.getShiftStartTime();
    dynamic endRaw = _mem.getShiftEndTime();

    // ✅ Handle "18:00-08:00" saved in startRaw (or endRaw) by scope
    String? pickStartFromRange(String s) {
      final m = RegExp(
        r'^\s*(\d{2}:\d{2})(?::\d{2})?\s*-\s*(\d{2}:\d{2})(?::\d{2})?\s*$',
      ).firstMatch(s);
      return m?.group(1);
    }

    String? pickEndFromRange(String s) {
      final m = RegExp(
        r'^\s*(\d{2}:\d{2})(?::\d{2})?\s*-\s*(\d{2}:\d{2})(?::\d{2})?\s*$',
      ).firstMatch(s);
      return m?.group(2);
    }

    if (startRaw != null) {
      final s = startRaw.toString().trim();
      if (s.contains('-') && endRaw == null) {
        final startOnly = pickStartFromRange(s);
        final endOnly = pickEndFromRange(s);
        if (startOnly != null && endOnly != null) {
          startRaw = startOnly;
          endRaw = endOnly;
        }
      }
    }

    // ✅ Onsite fallback: sometimes times exist in selectedCalendarShift
    if (startRaw == null || endRaw == null) {
      final roleRaw = box.read('role');
      final isOnSiteOfficer = roleRaw is String && roleRaw == onSiteOfficer;
      if (isOnSiteOfficer) {
        final selectedCal = box.read('selectedCalendarShift');
        if (selectedCal is Map) {
          startRaw ??=
              selectedCal['shift_start_time'] ??
              selectedCal['startTime'] ??
              selectedCal['start'];
          endRaw ??=
              selectedCal['shift_end_time'] ??
              selectedCal['endTime'] ??
              selectedCal['end'];

          // also support label like "(18:00 - 08:00)"
          if ((startRaw == null || endRaw == null) &&
              selectedCal['label'] != null) {
            final label = selectedCal['label'].toString();
            final m = RegExp(
              r'\((\d{2}:\d{2})\s*-\s*(\d{2}:\d{2})\)',
            ).firstMatch(label);
            if (m != null) {
              startRaw ??= m.group(1);
              endRaw ??= m.group(2);
            }
          }
        }
      }
    }

    DateTime? start = _parseShiftDateTime(startRaw);
    DateTime? end = _parseShiftDateTime(endRaw);

    if (start != null && end != null && end.isBefore(start)) {
      end = end.add(const Duration(days: 1));
    }

    shiftStartTime.value = start;
    shiftEndTime.value = end;

    if (start != null && end != null) {
      final diff = end.difference(start).inSeconds;
      if (diff > 0) {
        totalWorkDuration = diff;
      }
    }

    final unpaid = box.read('unpaidBreakMinutes');
    final paid = box.read('paidBreakMinutes');
    final total = box.read('totalBreakMinutes');

    final unpaidMin = unpaid is int
        ? unpaid
        : int.tryParse(unpaid?.toString() ?? '') ?? 0;
    final paidMin = paid is int
        ? paid
        : int.tryParse(paid?.toString() ?? '') ?? 0;
    final totalMin = total is int
        ? total
        : int.tryParse(total?.toString() ?? '') ?? (unpaidMin + paidMin);

    if (totalMin <= 0) {
      breakDuration = 0;
      breakAllowed.value = false;
    } else {
      breakDuration = totalMin * 60;
      breakAllowed.value = true;
    }

    _log('Dial DEBUG -> startRaw=$startRaw endRaw=$endRaw', tag: 'Timer');
    _log('Dial -> shift seconds: $totalWorkDuration', tag: 'Timer');
  }

  Future<bool> _showFrostDialog({
    required String title,
    required Widget body,
    required String continueText,
    required bool continueEnabled,
    RxBool? continueEnabledRx,
    String cancelText = 'Cancel',
    double maxHeightFactor = 0.85,
  }) async {
    final isDark = Theme.of(Get.context!).brightness == Brightness.dark;
    Widget buildButtons(bool enabled) {
      final width = MediaQuery.of(Get.context!).size.width * 0.36;
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: width,
            child: GestureDetector(
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
                Get.back(result: false);
              },
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: isDark
                      ? cDarkInputFillColor
                      : Colors.white.withAlpha(153),
                  border: isDark
                      ? Border.all(color: cDarkBorderColor, width: 1)
                      : null,
                ),
                child: Center(
                  child: Text(
                    cancelText,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? cDarkTextPrimary
                          : Colors.black.withAlpha(217),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: width,
            child: GestureDetector(
              onTap: enabled
                  ? () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      Get.back(result: true);
                    }
                  : null,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: enabled
                      ? const Color(0xFF007AFF)
                      : (isDark ? cDarkBorderColor : Colors.grey.shade400),
                ),
                child: Center(
                  child: Text(
                    continueText,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final res = await Get.dialog<bool>(
      Dialog(
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: isDark
                      ? [
                          cDarkCardColor.withAlpha(230),
                          cDarkBackground.withAlpha(204),
                        ]
                      : [
                          Colors.white.withAlpha(115),
                          Colors.white.withAlpha(38),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 77 : 38),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16 + MediaQuery.of(Get.context!).viewInsets.bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        MediaQuery.of(Get.context!).size.height *
                        maxHeightFactor,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? cDarkTextPrimary
                                    : Colors.black.withAlpha(217),
                              ),
                            ),
                          ),
                          InkWell(
                            overlayColor: const WidgetStatePropertyAll(
                              Colors.transparent,
                            ),
                            onTap: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              Get.back(result: false);
                            },
                            child: Icon(
                              Icons.close,
                              size: 24,
                              color: isDark
                                  ? cDarkIconColor
                                  : Colors.black.withAlpha(191),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Divider(
                        thickness: 1,
                        color: isDark
                            ? cDarkBorderColor.withAlpha(166)
                            : Colors.white.withAlpha(128),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        fit: FlexFit.loose,
                        child: SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          child: body,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (continueEnabledRx != null)
                        Obx(() => buildButtons(continueEnabledRx.value))
                      else
                        buildButtons(continueEnabled),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      barrierDismissible: false,
      barrierColor: Colors.black.withAlpha(isDark ? 128 : 77),
    );

    return res ?? false;
  }

  Future<void> _showFrostAlert({
    required String title,
    required String message,
    String okText = 'OK',
  }) async {
    final isDark = Theme.of(Get.context!).brightness == Brightness.dark;
    await Get.dialog(
      Dialog(
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: isDark
                      ? [
                          cDarkCardColor.withAlpha(230),
                          cDarkBackground.withAlpha(204),
                        ]
                      : [
                          Colors.white.withAlpha(115),
                          Colors.white.withAlpha(38),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 77 : 38),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? cDarkTextPrimary
                                    : Colors.black.withAlpha(217),
                              ),
                            ),
                          ),
                          InkWell(
                            overlayColor: const WidgetStatePropertyAll(
                              Colors.transparent,
                            ),
                            onTap: () => Get.back(),
                            child: Icon(
                              Icons.close,
                              size: 24,
                              color: isDark
                                  ? cDarkIconColor
                                  : Colors.black.withAlpha(191),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Divider(
                        thickness: 1,
                        color: isDark
                            ? cDarkBorderColor.withAlpha(166)
                            : Colors.white.withAlpha(128),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        message,
                        style: TextStyle(
                          color: isDark
                              ? cDarkTextSecondary
                              : Colors.black.withAlpha(191),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => Get.back(),
                              child: Container(
                                height: 44,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: const Color(0xFF007AFF),
                                ),
                                child: Center(
                                  child: Text(
                                    okText,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      barrierDismissible: false,
      barrierColor: Colors.black.withAlpha(isDark ? 128 : 77),
    );
  }

  String _formatAgo(Duration d) {
    final totalMin = d.inMinutes.abs();
    final h = (totalMin ~/ 60).toString().padLeft(2, '0');
    final m = (totalMin % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<bool> _confirmNoBreakShift() async {
    bool agree = false;
    final isDark = Theme.of(Get.context!).brightness == Brightness.dark;

    final res = await Get.dialog<bool>(
      StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            backgroundColor: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      colors: isDark
                          ? [
                              cDarkCardColor.withAlpha(230),
                              cDarkBackground.withAlpha(204),
                            ]
                          : [
                              Colors.white.withAlpha(115),
                              Colors.white.withAlpha(38),
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(isDark ? 77 : 38),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'No-Break Shift',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? cDarkTextPrimary
                                        : Colors.black.withAlpha(217),
                                  ),
                                ),
                              ),
                              InkWell(
                                overlayColor: const WidgetStatePropertyAll(
                                  Colors.transparent,
                                ),
                                onTap: () => Get.back(result: false),
                                child: Icon(
                                  Icons.close,
                                  size: 24,
                                  color: isDark
                                      ? cDarkIconColor
                                      : Colors.black.withAlpha(191),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Divider(
                            thickness: 1,
                            color: isDark
                                ? cDarkBorderColor.withAlpha(166)
                                : Colors.white.withAlpha(128),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'This shift does not include a break. You must agree to proceed without a break to clock in.',
                            style: TextStyle(
                              color: isDark
                                  ? cDarkTextSecondary
                                  : Colors.black.withAlpha(191),
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            overlayColor: const WidgetStatePropertyAll(
                              Colors.transparent,
                            ),
                            onTap: () => setState(() => agree = !agree),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: agree,
                                  onChanged: (_) =>
                                      setState(() => agree = !agree),
                                ),
                                Expanded(
                                  child: Text(
                                    'I agree to work this shift without a break.',
                                    style: TextStyle(
                                      color: isDark
                                          ? cDarkTextPrimary
                                          : Colors.black.withAlpha(217),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => Get.back(result: false),
                                  child: Container(
                                    height: 44,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      color: isDark
                                          ? cDarkInputFillColor
                                          : Colors.white.withAlpha(153),
                                      border: isDark
                                          ? Border.all(
                                              color: cDarkBorderColor,
                                              width: 1,
                                            )
                                          : null,
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Cancel',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? cDarkTextPrimary
                                              : Colors.black.withAlpha(217),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: agree
                                      ? () => Get.back(result: true)
                                      : null,
                                  child: Container(
                                    height: 44,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      color: agree
                                          ? const Color(0xFF007AFF)
                                          : (isDark
                                                ? cDarkBorderColor
                                                : Colors.grey.shade400),
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'Continue',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      barrierDismissible: false,
      barrierColor: Colors.black.withAlpha(isDark ? 128 : 77),
    );

    return (res ?? false) && agree;
  }

  String _formatLateText({
    required bool isClockIn,
    required bool isLate,
    required Duration diff,
  }) {
    diff.inMinutes.abs();
    final ago = _formatAgo(diff.abs());

    if (isClockIn) {
      return isLate
          ? 'Why are you clocking in late while your shift already started $ago ago?'
          : 'Why are you clocking in early while your shift starts in $ago?';
    } else {
      return isLate
          ? 'Why are you clocking out so late while your shift already ended $ago ago?'
          : 'Why are you clocking out early while your shift ends in $ago?';
    }
  }

  String _dialogTitle({required bool isClockIn, required bool isLate}) {
    if (isClockIn) return isLate ? 'Late clock in' : 'Early clock in';
    return isLate ? 'Late clock out' : 'Early clock out';
  }

  Future<String?> _askEarlyLateReason({
    required bool isClockIn,
    required bool isLate,
    required Duration diff,
  }) async {
    final reasonController = TextEditingController();
    final isContinueEnabled = false.obs;
    final isDark = Theme.of(Get.context!).brightness == Brightness.dark;

    final keyboardOpen = MediaQuery.of(Get.context!).viewInsets.bottom > 0;
    final maxHeight = keyboardOpen ? 0.95 : 0.6;

    final title = _dialogTitle(isClockIn: isClockIn, isLate: isLate);
    final msg = _formatLateText(
      isClockIn: isClockIn,
      isLate: isLate,
      diff: diff,
    );

    final mins = diff.inMinutes.abs();
    final label = isLate ? 'Late by ($mins min).' : 'Early by ($mins min).';

    final ok = await _showFrostDialog(
      title: title,
      continueText: 'Continue',
      continueEnabled: false,
      continueEnabledRx: isContinueEnabled,
      maxHeightFactor: maxHeight,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            msg,
            style: TextStyle(
              color: isDark ? cDarkTextSecondary : Colors.black.withAlpha(191),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Reason',
            style: TextStyle(
              color: isDark ? cDarkTextPrimary : Colors.black.withAlpha(217),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: reasonController,
            onChanged: (v) => isContinueEnabled.value = v.trim().isNotEmpty,
            minLines: 3,
            maxLines: null,
            style: TextStyle(color: isDark ? cDarkTextPrimary : Colors.black87),
            decoration: InputDecoration(
              filled: true,
              fillColor: isDark
                  ? cDarkInputFillColor
                  : Colors.white.withAlpha(153),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark ? cDarkBorderColor : Colors.grey.shade300,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark ? cDarkBorderColor : Colors.grey.shade300,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark ? const Color(0xFF3B82F6) : cPrimary,
                  width: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: isDark ? cDarkTextPrimary : Colors.black.withAlpha(179),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    if (!ok) return null;
    return reasonController.text.trim();
  }

  Future<bool> _confirmLateClockIn(Duration lateBy) async {
    final reason = await _askEarlyLateReason(
      isClockIn: true,
      isLate: true,
      diff: lateBy,
    );
    if (reason == null) return false;

    lateClockInReason.value = reason;
    earlyClockInReason.value = '';

    final mins = lateBy.inMinutes.abs();
    lateByMinutes.value = mins;
    earlyByMinutes.value = 0;

    _pendingLateByMinutes = mins;

    return true;
  }

  Future<bool> _confirmEarlyClockIn(Duration earlyBy) async {
    final reason = await _askEarlyLateReason(
      isClockIn: true,
      isLate: false,
      diff: earlyBy,
    );
    if (reason == null) return false;

    earlyClockInReason.value = reason;
    lateClockInReason.value = '';

    final mins = earlyBy.inMinutes.abs();
    earlyByMinutes.value = mins;
    lateByMinutes.value = 0;

    return true;
  }

  Future<bool> _confirmLateClockOut(Duration lateBy) async {
    final reason = await _askEarlyLateReason(
      isClockIn: false,
      isLate: true,
      diff: lateBy,
    );
    if (reason == null) return false;
    lateClockOutReason.value = reason;
    earlyClockOutReason.value = '';
    return true;
  }

  Future<bool> _confirmEarlyClockOut(Duration earlyBy) async {
    final reason = await _askEarlyLateReason(
      isClockIn: false,
      isLate: false,
      diff: earlyBy,
    );
    if (reason == null) return false;
    earlyClockOutReason.value = reason;
    lateClockOutReason.value = '';
    return true;
  }

  Future<void> showNoShiftDialogIfMissing() async {
    _loadShiftTimingAndBreakFromStorage();

    if (shiftStartTime.value == null || shiftEndTime.value == null) {
      if (_noShiftDialogShown) return;
      _loadShiftTimingAndBreakFromStorage();

      if (shiftStartTime.value == null || shiftEndTime.value == null) {
        _noShiftDialogShown = true;
        final isDark = Theme.of(Get.context!).brightness == Brightness.dark;
        final ok = await _showFrostDialog(
          title: 'No shift today',
          continueText: 'Help & Support',
          continueEnabled: true,
          maxHeightFactor: 0.22,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "You don't have a shift scheduled for today. Please contact support using Help & Support.",
                style: TextStyle(
                  color: isDark
                      ? cDarkTextSecondary
                      : Colors.black.withAlpha(191),
                  height: 1.3,
                ),
              ),
            ],
          ),
        );

        if (ok) {
          if (Get.isRegistered<MainController>()) {
            Get.back();
            Get.find<MainController>().changePage(3);
          } else {
            Get.to(() => const HelpScreen());
          }
        }
      } else {
        _noShiftDialogShown = true;
      }
    }
  }

  Future<void> clockIn({double? latitude, double? longitude}) async {
    try {
      isLoading.value = true;
      await refreshServerSession(
        showShimmer: false,
        blockUI: false,
        suppressScopeLoading: true,
      );

      final hasActiveSession = (sessionId != null) || onDuty.value == true;

      if (!hasActiveSession && todayStatus.value.toLowerCase() == 'closed') {
        final message =
            'You already clocked out for today. You cannot clock in again on the same day.';

        await _showFrostAlert(
          title: 'Already clocked out',
          message: message,
          okText: 'OK',
        );
        return;
      }

      int? toInt(dynamic v) {
        if (v == null) return null;
        if (v is int) return v;
        return int.tryParse(v.toString());
      }

      final roleRaw = box.read('role');
      final bool isPatrolOfficer =
          roleRaw is String && roleRaw == patrolOfficer;
      final bool isOnSiteOfficer =
          roleRaw is String && roleRaw == onSiteOfficer;

      final selectedSiteId = _mem.getSiteId();
      final selectedShiftId = _mem.getShiftId();
      final selectedRegionId = _mem.getRegionId();
      final selectedSeriesId = _mem.getSeriesId();

      final siteId = toInt(selectedSiteId);
      final shiftId = toInt(selectedShiftId);
      final regionId = toInt(selectedRegionId);
      final seriesId = toInt(selectedSeriesId);

      _log(
        'CLOCKIN ATTEMPT -> role=${box.read('role')} siteId=$siteId regionId=$regionId shiftId=$shiftId seriesId=$seriesId',
        tag: 'Timer',
      );

      if (isPatrolOfficer) {
        if (regionId == null || shiftId == null) {
          Get.snackbar(
            'Missing selection',
            'Please select a Region and Shift before clocking in.',
            snackPosition: SnackPosition.BOTTOM,
          );
          isLoading.value = false;
          return;
        }
      } else if (isOnSiteOfficer) {
        final selectedCal = box.read('selectedCalendarShift');
        final series = selectedCal is Map ? selectedCal['seriesId'] : null;
        final seriesId = toInt(series) ?? shiftId;

        if (siteId == null || seriesId == null) {
          Get.snackbar(
            'Missing selection',
            'Please ensure your shift is available in the calendar before clocking in.',
            snackPosition: SnackPosition.BOTTOM,
          );
          isLoading.value = false;
          return;
        }
      } else {
        if (siteId == null || shiftId == null) {
          Get.snackbar(
            'Missing selection',
            'Please select a Site and Shift before clocking in.',
            snackPosition: SnackPosition.BOTTOM,
          );
          isLoading.value = false;
          return;
        }
      }

      _loadShiftTimingAndBreakFromStorage();

      if (isPatrolOfficer) {
        breakAllowed.value = false;
        breakActive.value = false;
        box.write('unpaidBreakMinutes', 0);
        box.write('paidBreakMinutes', 0);
        box.write('totalBreakMinutes', 0);
      }

      if (shiftStartTime.value == null || shiftEndTime.value == null) {
        final isDark = Theme.of(Get.context!).brightness == Brightness.dark;
        final ok = await _showFrostDialog(
          title: 'No shift today',
          continueText: 'Help & Support',
          continueEnabled: true,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "You don't have a shift scheduled for today. Please contact support using Help & Support.",
                style: TextStyle(
                  color: isDark
                      ? cDarkTextSecondary
                      : Colors.black.withAlpha(191),
                  height: 1.3,
                ),
              ),
            ],
          ),
        );

        if (ok) {
          if (Get.isRegistered<MainController>()) {
            Get.back();
            Get.find<MainController>().changePage(3);
          } else {
            Get.to(() => const HelpScreen());
          }
        }
        return;
      }

      final totalBreakMinRaw = box.read('totalBreakMinutes');
      final totalBreakMin = totalBreakMinRaw is int
          ? totalBreakMinRaw
          : int.tryParse(totalBreakMinRaw?.toString() ?? '') ?? 0;

      if (totalBreakMin <= 0) {
        final ok = await _confirmNoBreakShift();
        if (!ok) return;
      }

      final start = shiftStartTime.value;
      _log('shiftStartTime for clock-in check: $start', tag: 'Timer');
      if (start != null) {
        final now = sfNow();

        final startForCompare = _resolveShiftStartForCompare(
          anchor: now,
          parsedShiftStart: start,
          rangeDays: 3,
        );

        if (startForCompare != null) {
          final delta = now.difference(startForCompare);
          _log('shiftDiffTime for clock-in check: $delta', tag: 'Timer');

          if (delta.inMinutes >= 1) {
            final ok = await _confirmLateClockIn(delta);
            if (!ok) return;
          } else if (delta.inMinutes <= -1) {
            final ok = await _confirmEarlyClockIn(delta.abs());
            if (!ok) return;
          }
        }
      }
      final inReasonText = lateClockInReason.value.trim().isNotEmpty
          ? lateClockInReason.value.trim()
          : earlyClockInReason.value.trim();

      dio.Response<dynamic> response;
      if (isPatrolOfficer) {
        response = await _apiService.clockIn(
          regionId: regionId!.toString(),
          shiftId: shiftId!.toString(),
          inReason: inReasonText.isEmpty ? null : inReasonText,
          latitude: latitude,
          longitude: longitude,
        );
      } else if (isOnSiteOfficer) {
        final selectedCal = box.read('selectedCalendarShift');
        final series = selectedCal is Map ? selectedCal['seriesId'] : null;
        final seriesId = toInt(series) ?? shiftId;

        response = await _apiService.clockIn(
          siteId: siteId!.toString(),
          seriesId: seriesId!.toString(),
          inReason: inReasonText.isEmpty ? null : inReasonText,
          latitude: latitude,
          longitude: longitude,
        );
      } else {
        response = await _apiService.clockIn(
          siteId: siteId!.toString(),
          seriesId: shiftId!.toString(),
          inReason: inReasonText.isEmpty ? null : inReasonText,
          latitude: latitude,
          longitude: longitude,
        );
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        sessionId = data is Map ? data['sessionId']?.toString() : null;

        onDuty.value = true;
        try {
          final roleRaw = box.read('role');
          final isOnSiteOfficerInner =
              roleRaw is String && roleRaw == onSiteOfficer;
          if (isOnSiteOfficerInner) {
            final selectedCal = box.read('selectedCalendarShift');
            final series = selectedCal is Map ? selectedCal['seriesId'] : null;
            final parsedSeries = series != null
                ? int.tryParse(series.toString())
                : null;
            final selectedSiteIdRaw = _mem.getSiteId();
            final parsedSiteId = selectedSiteIdRaw is int
                ? selectedSiteIdRaw
                : int.tryParse(selectedSiteIdRaw.toString());

            if (parsedSeries != null) {
              box.write('seriesId', parsedSeries);
              _mem.setSeriesId(parsedSeries);
            }
            if (parsedSeries != null) {
              box.write('shiftId', parsedSeries);
              _mem.setShiftId(parsedSeries);
            }
            if (parsedSiteId != null) {
              box.write('siteId', parsedSiteId);
              _mem.setSiteId(parsedSiteId);
            }

            final siteName = selectedCal is Map
                ? (selectedCal['siteName'] ?? '')
                : '';
            if ((_mem.getSiteName()).toString().trim().isEmpty &&
                siteName.toString().trim().isNotEmpty) {
              box.write(kSelectedSiteKey, siteName.toString());
              _mem.setSiteName(siteName.toString());
            }
          }
        } catch (_) {}
        breakActive.value = false;

        if (isPatrolOfficer) {
          breakAllowed.value = false;
        } else {
          if (totalBreakMin <= 0) breakAllowed.value = false;
        }

        resetSegmentTimes();
        if (_pendingLateByMinutes != null) {
          lateByMinutes.value = _pendingLateByMinutes!;
          _pendingLateByMinutes = null;
        }
        clockInTime = sfNow();
        breakStartTime = null;
        breakEndTime = null;
        final int earlySec = (earlyByMinutes.value) * 60;
        if (earlySec > 0 && !_earlyAddedToTotal) {
          totalWorkDuration += earlySec;
          _earlyAddedToTotal = true;
        }
        _startTick();
      } else if (response.statusCode == 409) {
        final data = response.data;
        final code = data is Map ? data['code']?.toString() : null;

        if (code == 'DAY_ALREADY_CLOSED') {
          final message = data is Map
              ? data['message']?.toString() ??
                    'You already clocked out for today. You cannot clock in again on the same day.'
              : 'You already clocked out for today. You cannot clock in again on the same day.';
          await _showFrostAlert(
            title: 'Already clocked out',
            message: message,
            okText: 'OK',
          );
          return;
        } else if (code == 'SESSION_ALREADY_ACTIVE') {
          final message = data is Map
              ? data['message']?.toString() ??
                    'You already have an active session.'
              : 'You already have an active session.';
          await _showFrostAlert(
            title: 'Already clocked In',
            message: message,
            okText: 'OK',
          );
          return;
        } else {
          Get.snackbar(
            'Warning',
            'Unable to clock in (${response.statusCode})',
            snackPosition: SnackPosition.BOTTOM,
          );
        }
      }
    } on dio.DioException catch (e) {
      final resp = e.response;
      if (resp != null) {
        final data = resp.data;
        final status = resp.statusCode;

        if (status == 409) {
          final code = data is Map ? data['code']?.toString() : null;
          if (code == 'DAY_ALREADY_CLOSED') {
            final message = data is Map
                ? data['message']?.toString() ??
                      'You already clocked out for today. You cannot clock in again on the same day.'
                : 'You already clocked out for today. You cannot clock in again on the same day.';
            await _showFrostAlert(
              title: 'Already clocked out',
              message: message,
              okText: 'OK',
            );
            return;
          } else if (code == 'SESSION_ALREADY_ACTIVE') {
            final message = data is Map
                ? data['message']?.toString() ??
                      'You already have an active session.'
                : 'You already have an active session.';
            await _showFrostAlert(
              title: 'Already clocked In',
              message: message,
              okText: 'OK',
            );
            return;
          }
        }

        Get.snackbar(
          'Warning',
          'Unable to clock in (${status ?? 'error'})',
          snackPosition: SnackPosition.BOTTOM,
        );
      } else {
        Get.snackbar(
          'Warning',
          e.message ?? e.toString(),
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> startBreak({double? latitude, double? longitude}) async {
    if (!breakAllowed.value ||
        !onDuty.value ||
        breakActive.value ||
        hasTakenBreak) {
      return;
    }

    try {
      isLoading.value = true;

      if (sessionId != null) {
        final response = await _apiService.startBreak(
          sessionId!,
          latitude: latitude,
          longitude: longitude,
        );
        breakActive.value = true;
        breakStartTime ??= sfNow();
        final bs = breakStartTime;
        if (bs != null) {
          try {
            await NotificationManager.instance.scheduleBreakOnly(
              scopeComplete: scopeValuesComplete,
              breakStart: bs,
              breakDurationSeconds: breakDuration,
              minutesBefore: 10,
            );
          } catch (_) {}
        }
        if (response.statusCode == 200 || response.statusCode == 201) {
          // ignore: avoid_print
          _log('Break started', tag: 'Timer');
        } else {
          Get.snackbar(
            'Warning',
            'Break error',
            snackPosition: SnackPosition.BOTTOM,
          );
        }
      }
    } catch (_) {
      breakActive.value = true;
      breakStartTime ??= sfNow();
      Get.snackbar(
        'Warning',
        'Break recorded locally',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> endBreak({double? latitude, double? longitude}) async {
    if (!onDuty.value || !breakActive.value) return;

    try {
      isLoading.value = true;

      if (sessionId != null) {
        final response = await _apiService.endBreak(
          sessionId!,
          latitude: latitude,
          longitude: longitude,
        );

        breakActive.value = false;
        breakEndTime ??= sfNow();
        breakAllowed.value = false;
        if (response.statusCode == 200 || response.statusCode == 201) {
          // ignore: avoid_print
          _log('Success', tag: 'Timer');
        } else {
          Get.snackbar(
            'Warning',
            'Break end recorded locally only',
            snackPosition: SnackPosition.BOTTOM,
          );
        }
      } else {
        breakActive.value = false;
        breakEndTime ??= sfNow();
        breakAllowed.value = false;
      }
      await NotificationManager.instance.cancelBreak();
    } catch (_) {
      breakActive.value = false;
      breakEndTime ??= sfNow();
      breakAllowed.value = false;
      Get.snackbar(
        'Warning',
        'Break end recorded locally',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoading.value = false;
      _tickOnce();
    }
  }

  Future<bool> clockOut({double? latitude, double? longitude}) async {
    log(shiftEndTime.value.toString());
    bool didClockOut = false;

    try {
      isLoading.value = true;

      if (sessionId != null) {
        _loadShiftTimingAndBreakFromStorage();

        final end = shiftEndTime.value;
        final now = sfNow();

        if (end != null) {
          final endForCompare = _resolveShiftEndForCompare(
            anchor: now,
            parsedShiftEnd: end,
            rangeDays: 3,
          );

          if (endForCompare != null) {
            final delta = now.difference(endForCompare);

            if (delta.inMinutes >= 1) {
              final ok = await _confirmLateClockOut(delta);
              if (!ok) return false;
            } else if (delta.inMinutes <= -1) {
              final ok = await _confirmEarlyClockOut(delta.abs());
              if (!ok) return false;
            }
          }
        }

        final outReasonText = lateClockOutReason.value.trim().isNotEmpty
            ? lateClockOutReason.value.trim()
            : earlyClockOutReason.value.trim();

        final response = await _apiService.clockOut(
          sessionId!,
          outReason: outReasonText.isEmpty ? null : outReasonText,
          latitude: latitude,
          longitude: longitude,
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          _resetAfterClockOut();
          didClockOut = true;

          // ignore: avoid_print
          _log('Clocked out successfully', tag: 'Timer');
        } else {
          Get.snackbar(
            'Warning',
            'Clock out recorded locally only',
            snackPosition: SnackPosition.BOTTOM,
          );
        }
      } else {
        _resetAfterClockOut();
        isShiftEnded.value = false;
        didClockOut = true;
        Get.snackbar(
          'Info',
          'Clocked out (local only)',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (_) {
      _resetAfterClockOut();
      didClockOut = true;
      Get.snackbar(
        'Warning',
        'Clock out recorded locally',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoading.value = false;
    }

    return didClockOut;
  }

  void _resetAfterClockOut() async {
    resetSegmentTimes();
    isShiftEnded.value = false;
    onDuty.value = false;
    lateClockOutReason.value = '';
    earlyClockOutReason.value = '';
    isLoading.value = false;
    _tickOnce();
    breakAllowed.value = false;
    breakStartTime = null;
    breakEndTime = null;
    sessionId = null;
    lateByMinutes.value = 0;
    earlyByMinutes.value = 0;
    lateClockInReason.value = '';
    earlyClockInReason.value = '';
    _pendingLateByMinutes = null;
    _tickTimer?.cancel();
    _earlyAddedToTotal = false;
    final roleRaw = box.read('role');
    final isOnSiteOfficer = roleRaw is String && roleRaw == onSiteOfficer;
    if (!isOnSiteOfficer) return;

    try {
      if (Get.isRegistered<ScheduleMonthCalendarController>()) {
        upcomingLoading.value = true;
        dialShimmer.value = true;
        try {
          await Get.find<ScheduleMonthCalendarController>().fetchShiftsForMonth(
            sfNow(),
          );
        } catch (_) {}
        upcomingLoading.value = false;
        dialShimmer.value = false;
        scopeLoading.value = false;
      }
    } catch (_) {}

    try {
      if (Get.isRegistered<ClockInWindowController>()) {
        Get.find<ClockInWindowController>().forceRefresh();
      }
    } catch (_) {}
  }

  bool _isTimeOnlyRaw(dynamic raw) {
    if (raw == null) return false;
    final s = raw.toString().trim();
    if (s.isEmpty) return false;
    return !s.contains('T'); // time-only OR "07:00" style
  }

  DateTime? _buildFromRawTimeOnDate(DateTime anchorDate, dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;

    final parts = s.split(':');
    if (parts.length < 2) return null;

    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    int sec = 0;
    if (parts.length >= 3) {
      sec = int.tryParse(parts[2].split('.').first) ?? 0;
    }
    if (h == null || m == null) return null;

    return DateTime(
      anchorDate.year,
      anchorDate.month,
      anchorDate.day,
      h,
      m,
      sec,
    );
  }

  bool _isNightShiftFromRaw(dynamic rawStart, dynamic rawEnd) {
    final s = rawStart?.toString().trim() ?? '';
    final e = rawEnd?.toString().trim() ?? '';
    if (s.isEmpty || e.isEmpty) return false;
    if (s.contains('T') || e.contains('T')) return false;

    int toMin(String t) {
      final p = t.split(':');
      final h = int.tryParse(p[0]) ?? 0;
      final m = int.tryParse(p.length > 1 ? p[1] : '0') ?? 0;
      return h * 60 + m;
    }

    final sm = toMin(s);
    final em = toMin(e);
    return em <= sm;
  }

  DateTime? _resolveShiftEndForCompare({
    required DateTime? anchor,
    required DateTime? parsedShiftEnd,
    int rangeDays = 3,
  }) {
    if (anchor == null || parsedShiftEnd == null) return null;
    final rawStart = _mem.getShiftStartTime();
    final rawEnd = _mem.getShiftEndTime();
    // ignore: unnecessary_null_comparison
    if (rawEnd != null && rawEnd.toString().contains('T')) {
      return parsedShiftEnd;
    }
    if (_isTimeOnlyRaw(rawStart) &&
        _isTimeOnlyRaw(rawEnd) &&
        _isNightShiftFromRaw(rawStart, rawEnd)) {
      final startToday = _buildFromRawTimeOnDate(anchor, rawStart);
      final endToday = _buildFromRawTimeOnDate(anchor, rawEnd);

      if (startToday != null && endToday != null) {
        if (anchor.isBefore(startToday)) {
          return endToday;
        }
        return endToday.add(const Duration(days: 1));
      }
    }

    final end = parsedShiftEnd;

    DateTime candidateFor(DateTime d) =>
        DateTime(d.year, d.month, d.day, end.hour, end.minute, end.second);

    DateTime best = candidateFor(anchor);
    int bestAbsMin = anchor.difference(best).inMinutes.abs();

    for (int i = -rangeDays; i <= rangeDays; i++) {
      final cand = candidateFor(anchor.add(Duration(days: i)));
      final absMin = anchor.difference(cand).inMinutes.abs();
      if (absMin < bestAbsMin) {
        best = cand;
        bestAbsMin = absMin;
      }
    }
    return best;
  }

  DateTime? _resolveShiftStartForCompare({
    required DateTime? anchor,
    required DateTime? parsedShiftStart,
    int rangeDays = 3,
  }) {
    if (anchor == null || parsedShiftStart == null) return null;

    final rawStart = _mem.getShiftStartTime();
    final rawEnd = _mem.getShiftEndTime();

    // ignore: unnecessary_null_comparison
    if (rawStart != null && rawStart.toString().contains('T')) {
      return parsedShiftStart;
    }
    if (_isTimeOnlyRaw(rawStart) &&
        _isTimeOnlyRaw(rawEnd) &&
        _isNightShiftFromRaw(rawStart, rawEnd)) {
      final startToday = _buildFromRawTimeOnDate(anchor, rawStart);
      final endToday = _buildFromRawTimeOnDate(anchor, rawEnd);

      if (startToday != null && endToday != null) {
        if (anchor.isBefore(startToday)) {
          return startToday.subtract(const Duration(days: 1));
        }
        return startToday;
      }
    }

    final start = parsedShiftStart;

    DateTime candidateFor(DateTime d) => DateTime(
      d.year,
      d.month,
      d.day,
      start.hour,
      start.minute,
      start.second,
    );

    DateTime best = candidateFor(anchor);
    int bestAbsMin = anchor.difference(best).inMinutes.abs();

    for (int i = -rangeDays; i <= rangeDays; i++) {
      final cand = candidateFor(anchor.add(Duration(days: i)));
      final absMin = anchor.difference(cand).inMinutes.abs();
      if (absMin < bestAbsMin) {
        best = cand;
        bestAbsMin = absMin;
      }
    }

    return best;
  }

  @override
  void onClose() {
    _uiTimer?.cancel();
    _tickTimer?.cancel();
    super.onClose();
  }
}
