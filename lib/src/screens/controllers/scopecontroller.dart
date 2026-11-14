import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/services/apiservice.dart';
import 'package:smartnps360/src/screens/data/api.url.dart';
import 'package:smartnps360/src/screens/services/notification_manager.dart';
import 'package:smartnps360/src/screens/utilities/appsnackbar.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/utilities/sf_time.dart';
import 'package:smartnps360/src/screens/app_storage.dart';
import 'package:smartnps360/src/screens/utilities/break_utils.dart';
import 'package:smartnps360/src/screens/controllers/clock_in_window_controller.dart';
import 'package:smartnps360/src/screens/controllers/memory_storage_controller.dart';

void _log(String msg, {String tag = 'APP', Object? error, StackTrace? stack}) {
  if (kDebugMode) {
    developer.log(msg, name: tag, error: error, stackTrace: stack);
  }
}

class ScopeController extends GetxController {
  final ApiService _api = ApiService();
  final RxList<String> shifts = <String>[].obs;
  final RxList<String> regions = <String>[].obs;

  final RxString selectedShift = ''.obs;
  final RxString selectedRegion = ''.obs;
  final RxString regionQuery = ''.obs;
  final RxBool shiftsLoading = false.obs;
  final RxBool sitesLoading = false.obs;
  final RxBool regionsLoading = false.obs;

  final MemoryStorageController _mem =
      Get.isRegistered<MemoryStorageController>()
      ? Get.find<MemoryStorageController>()
      : Get.put(MemoryStorageController());

  @override
  void onInit() {
    super.onInit();
    _initializeDefaults();
  }

  void _initializeDefaults() {
    shifts.clear();
    regions.clear();
    selectedShift.value = '';
    selectedRegion.value = '';
  }

  Future<void> fetchScopeLists({bool forceRefresh = false}) async {
    final r = box.read('role');
    final isOnSiteOfficer = r != null && r is String && r == onSiteOfficer;

    final futures = <Future<void>>[];
    if (!isOnSiteOfficer) {
      futures.add(fetchRegions(forceRefresh: forceRefresh));
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  Future<void> fetchShifts({int? regionId}) async {
    shiftsLoading.value = true;
    try {
      String apiUrl = ApiURL.shifts;
      if (regionId != null) {
        apiUrl += '?regionId=$regionId';
      }
      final resp = await _api.getData(apiUrl);
      List items = [];

      if (resp is Map && resp['data'] is List) {
        items = resp['data'];
      } else if (resp is List) {
        items = resp;
      }

      if (items.isEmpty) {
        shifts.clear();
        selectedShift.value = '';
        return;
      }

      final list = items.map((e) {
        if (e is Map) {
          return (e['label'] ?? e['name'] ?? e['title'] ?? e.toString())
              .toString();
        }
        return e.toString();
      }).toList();

      shifts.assignAll(list);
      box.write('shiftsData', items);
    } catch (e) {
      AppSnackBar.show(
        Get.context!,
        'Failed to load shifts: ${e.toString()}',
        type: SnackBarType.error,
      );
      shifts.clear();
    } finally {
      shiftsLoading.value = false;
    }
  }

  Future<void> fetchRegions({bool forceRefresh = false}) async {
    final r = box.read('role');
    if (r != null && r is String && r == onSiteOfficer) {
      return;
    }
    if (!forceRefresh && regions.isNotEmpty) return;

    regionsLoading.value = true;
    try {
      final resp = await _api.getData(ApiURL.regions);
      List items = [];

      if (resp is Map && resp['data'] is List) {
        items = resp['data'];
      } else if (resp is List) {
        items = resp;
      }

      if (items.isEmpty) {
        regions.clear();
        selectedRegion.value = '';
        return;
      }

      final regs = items.map((e) {
        if (e is Map) {
          return (e['label'] ?? e['name'] ?? e['title'] ?? e.toString())
              .toString();
        }
        return e.toString();
      }).toList();

      regions.assignAll(regs);
      box.write('regionsData', items);
    } catch (e) {
      AppSnackBar.show(
        Get.context!,
        'Failed to load regions: ${e.toString()}',
        type: SnackBarType.error,
      );
      regions.clear();
    } finally {
      regionsLoading.value = false;
    }
  }

  int? _findIdByName(String name, String dataKey) {
    final items = box.read(dataKey) as List<dynamic>?;
    if (items == null) return null;

    for (var item in items) {
      if (item is Map) {
        final itemName = (item['label'] ?? item['name'] ?? item['title'] ?? '')
            .toString();
        if (itemName == name) {
          return item['id'] is int ? item['id'] : int.tryParse('${item['id']}');
        }
      }
    }
    return null;
  }

  Map<String, dynamic>? _findItemByName(String name, String dataKey) {
    final items = box.read(dataKey);
    if (items is! List) return null;
    for (final item in items) {
      if (item is Map) {
        final itemName = (item['label'] ?? item['name'] ?? item['title'] ?? '')
            .toString();
        if (itemName == name) {
          return Map<String, dynamic>.from(item);
        }
      }
    }
    return null;
  }

  Future<void> setShift(String? v, {bool persist = true}) async {
    if (v == null || v.isEmpty) return;

    selectedShift.value = v;
    if (!persist) return;
    box.write(kSelectedShiftKey, v);
    _mem.setShiftName(v);

    final roleRaw = box.read('role');
    final bool isPatrolOfficer = roleRaw is String && roleRaw == patrolOfficer;

    final shiftId = _findIdByName(v, 'shiftsData');
    final shiftItem = _findItemByName(v, 'shiftsData');

    if (shiftId != null) {
      box.write('shiftId', shiftId);
      _mem.setShiftId(shiftId);
    } else {
      box.remove('shiftId');
    }

    box.remove('shiftStartTime');
    box.remove('shiftEndTime');
    box.remove('unpaidBreakMinutes');
    box.remove('paidBreakMinutes');
    box.remove('totalBreakMinutes');

    if (shiftItem == null) {
      box.remove('selectedShiftData');
      box.remove('seriesId');

      if (isPatrolOfficer) {
        final match = RegExp(
          r'\((\d{2}:\d{2})\s*-\s*(\d{2}:\d{2})\)',
        ).firstMatch(v);
        if (match != null) {
          box.write('shiftStartTime', match.group(1));
          _mem.setShiftStartTime(match.group(1));
          box.write('shiftEndTime', match.group(2));
          _mem.setShiftEndTime(match.group(2));
        }
        box.write('unpaidBreakMinutes', 0);
        box.write('paidBreakMinutes', 0);
        box.write('totalBreakMinutes', 0);
      }
      return;
    }

    box.write('selectedShiftData', shiftItem);

    String? firstNonEmpty(dynamic x) {
      if (x == null) return null;
      final s = x.toString().trim();
      return s.isEmpty ? null : s;
    }

    String? startVal =
        firstNonEmpty(shiftItem['startTime']) ??
        firstNonEmpty(shiftItem['start_time']) ??
        firstNonEmpty(shiftItem['start']) ??
        firstNonEmpty(shiftItem['from']) ??
        firstNonEmpty(shiftItem['shiftStart']) ??
        firstNonEmpty(shiftItem['shift_start']) ??
        firstNonEmpty(shiftItem['startDateTime']) ??
        firstNonEmpty(shiftItem['start_date_time']);
    String? endVal =
        firstNonEmpty(shiftItem['endTime']) ??
        firstNonEmpty(shiftItem['end_time']) ??
        firstNonEmpty(shiftItem['end']) ??
        firstNonEmpty(shiftItem['to']) ??
        firstNonEmpty(shiftItem['shiftEnd']) ??
        firstNonEmpty(shiftItem['shift_end']) ??
        firstNonEmpty(shiftItem['endDateTime']) ??
        firstNonEmpty(shiftItem['end_date_time']);

    if (startVal == null || endVal == null) {
      final label = (shiftItem['label'] ?? shiftItem['name'] ?? '').toString();
      final m = RegExp(
        r'\((\d{2}:\d{2})\s*-\s*(\d{2}:\d{2})\)',
      ).firstMatch(label);
      if (m != null) {
        startVal ??= m.group(1);
        endVal ??= m.group(2);
      }
    }

    if (startVal == null || endVal == null) {
      final idRef =
          shiftItem['id'] ?? shiftItem['seriesId'] ?? shiftItem['series_id'];
      final tryLists = ['shiftsData', 'sitesData', 'regionsData'];
      for (final key in tryLists) {
        final list = box.read(key);
        if (list is List) {
          for (final it in list) {
            if (it is Map) {
              final itId = it['id'] ?? it['seriesId'] ?? it['series_id'];
              if (itId != null &&
                  idRef != null &&
                  itId.toString() == idRef.toString()) {
                startVal ??=
                    firstNonEmpty(it['startTime']) ??
                    firstNonEmpty(it['start']);
                endVal ??=
                    firstNonEmpty(it['endTime']) ?? firstNonEmpty(it['end']);
                if (startVal != null && endVal != null) break;
              }
              final sitNested = it['series'] ?? it['seriesData'];
              if ((startVal == null || endVal == null) && sitNested is List) {
                for (final s in sitNested) {
                  if (s is Map) {
                    startVal ??=
                        firstNonEmpty(s['startTime']) ??
                        firstNonEmpty(s['start']);
                    endVal ??=
                        firstNonEmpty(s['endTime']) ?? firstNonEmpty(s['end']);
                    if (startVal != null && endVal != null) break;
                  }
                }
                if (startVal != null && endVal != null) break;
              }
            }
          }
        }
        if (startVal != null && endVal != null) break;
      }
    }

    if (startVal != null) {
      box.write('shiftStartTime', startVal);
      _mem.setShiftStartTime(startVal);
    }
    if (endVal != null) {
      box.write('shiftEndTime', endVal);
      _mem.setShiftEndTime(endVal);
    }
    DateTime? parseHHmm(String? v) {
      if (v == null) return null;
      final s = v.trim();
      if (s.isEmpty) return null;
      final parts = s.split(':');
      if (parts.length < 2) return null;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) return null;
      final now = sfNow();
      return DateTime(now.year, now.month, now.day, h, m);
    }

    final st = parseHHmm(startVal);
    DateTime? en = parseHHmm(endVal);

    if (st != null && en != null) {
      if (en.isBefore(st)) en = en.add(const Duration(days: 1));
      // determine scope completeness same as in TimeController
      bool scopeComplete;
      if (isPatrolOfficer) {
        final regionName = _mem.getRegionName();
        final shiftName = _mem.getShiftName();
        scopeComplete = regionName.isNotEmpty && shiftName.isNotEmpty;
      } else {
        final role = box.read('role');
        if (role is String && role == onSiteOfficer) {
          scopeComplete = _mem.getSiteName().isNotEmpty;
        } else {
          scopeComplete = _mem.getIsScopeSelected() == true;
        }
      }

      await NotificationManager.instance.syncFromSession(
        scopeComplete: scopeComplete,
        siteName: _mem.getSiteName(),
        shiftName: _mem.getShiftName(),
        shiftStart: st,
        shiftEnd: en,
        breakActive: false,
        breakStart: null,
        breakDurationSeconds: 0,
        minutesBefore: 10,
      );
    }
    if (_mem.getShiftStartTime().isEmpty || _mem.getShiftEndTime().isEmpty) {
      _log(
        'DEBUG: shift times missing for selected shiftItem -> $shiftItem',
        tag: 'Scope',
      );
    } else {
      _log(
        "DEBUG: saved shift times -> start=${_mem.getShiftStartTime()} end=${_mem.getShiftEndTime()}",
        tag: 'Scope',
      );
    }

    if (isPatrolOfficer) {
      box.write('unpaidBreakMinutes', 0);
      box.write('paidBreakMinutes', 0);
      box.write('totalBreakMinutes', 0);
      return;
    }

    // Non-patrol: parse break information from the shift item
    final rawUnpaid =
        shiftItem['unpaidBreakMinutes'] ??
        shiftItem['unpaid_break_minutes'] ??
        shiftItem['unpaidBreak'];
    final rawPaid =
        shiftItem['paidBreakMinutes'] ??
        shiftItem['paid_break_minutes'] ??
        shiftItem['paidBreak'];
    final noteRaw =
        shiftItem['note'] ?? shiftItem['notes'] ?? shiftItem['breakNote'];

    final parsed = parseBreakMinutes(
      unpaidField: rawUnpaid,
      paidField: rawPaid,
      note: noteRaw,
    );
    box.write('unpaidBreakMinutes', parsed['unpaid']);
    box.write('paidBreakMinutes', parsed['paid']);
    box.write('totalBreakMinutes', parsed['total']);
    return;
  }

  void setRegion(String? v, {bool fetch = true}) {
    if (v == null || v.isEmpty) return;
    selectedRegion.value = v;
    box.write(kSelectedRegionKey, v);
    _mem.setRegionName(v);

    final regionId = _findIdByName(v, 'regionsData');
    if (regionId != null) {
      box.write('regionId', regionId);
      _mem.setRegionId(regionId);
      try {
        if (Get.isRegistered<ClockInWindowController>()) {
          Get.find<ClockInWindowController>().forceRefresh();
        }
      } catch (_) {}
      if (fetch) {
        fetchShifts(regionId: regionId);
      }
    } else {
      box.remove('regionId');
    }
  }

  void reset() {
    if (shifts.isNotEmpty) selectedShift.value = shifts.first;
    if (regions.isNotEmpty) selectedRegion.value = regions.first;

    box.remove(kSelectedSiteKey);
    box.remove(kSelectedShiftKey);
    box.remove(kSelectedRegionKey);
    box.remove('siteId');
    box.remove('shiftId');
    box.remove('regionId');
    box.remove('selectedShiftData');
    box.remove('shiftStartTime');
    box.remove('shiftEndTime');
    box.remove('unpaidBreakMinutes');
    box.remove('paidBreakMinutes');
    box.remove('totalBreakMinutes');
    _mem.setRegionId(null);
    _mem.setShiftId(null);
    _mem.setSiteId(null);
    _mem.setRegionName('');
    _mem.setShiftName('');
    _mem.setSiteName('');
    _mem.setShiftStartTime(null);
    _mem.setShiftEndTime(null);
    try {
      if (Get.isRegistered<ClockInWindowController>()) {
        Get.find<ClockInWindowController>().forceRefresh();
      }
    } catch (_) {}
  }
}
