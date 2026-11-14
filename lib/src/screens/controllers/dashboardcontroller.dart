import 'package:get/get.dart';
import 'package:smartnps360/src/screens/services/apiservice.dart';
import 'package:smartnps360/src/screens/data/api.url.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/app_storage.dart';
import 'package:smartnps360/src/screens/controllers/memory_storage_controller.dart';
import 'package:smartnps360/src/screens/utilities/sf_time.dart';
import 'package:smartnps360/src/screens/utilities/appsnackbar.dart';

class DashboardController extends GetxController {
  final ApiService _api = ApiService();

  final RxList<dynamic> assignments = <dynamic>[].obs;
  final RxBool loadingAssignments = false.obs;

  String? _lastAssignmentsKey;
  bool _hasFetchedAssignments = false;
  Future<void>? _assignmentsFuture;
  final RxBool _firstLoad = true.obs;
  final MemoryStorageController _mem =
      Get.isRegistered<MemoryStorageController>()
      ? Get.find<MemoryStorageController>()
      : Get.put(MemoryStorageController());
  bool get firstLoad => _firstLoad.value;
  void markAsLoaded() => _firstLoad.value = false;

  String _assignmentsKey(int? regionId, int? shiftId) =>
      'r:${regionId ?? "all"}|s:${shiftId ?? "all"}';

  Future<void> fetchAssignments(
    int? regionId,
    int? shiftId, {
    bool forceRefresh = false,
  }) async {
    final r = box.read('role');
    if (r is String && r == onSiteOfficer) return;
    final key = _assignmentsKey(regionId, shiftId);

    if (!forceRefresh && _hasFetchedAssignments && _lastAssignmentsKey == key) {
      return;
    }

    if (_assignmentsFuture != null) {
      if (!forceRefresh) return _assignmentsFuture!;
      await _assignmentsFuture;
    }

    loadingAssignments.value = true;

    _assignmentsFuture = (() async {
      try {
        String apiUrl = ApiURL.assignments;
        final params = <String>[];

        if (regionId != null) params.add('regionId=$regionId');
        if (shiftId != null) params.add('shiftId=$shiftId');

        params.add('page=1');
        params.add('pageSize=20');

        if (params.isNotEmpty) apiUrl += '?${params.join('&')}';

        final resp = await _api.getData(apiUrl);

        List items = [];
        if (resp == null) {
          items = [];
        } else if (resp is List) {
          items = resp;
        } else if (resp is Map) {
          if (resp['data'] is List) items = resp['data'];
          if (resp['items'] is List) items = resp['items'];
        }

        final role = box.read('role');
        if (role is String && role.toLowerCase() != 'admin') {
          final allowedSites = (box.read('allowedSites') as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList();

          if (allowedSites != null && allowedSites.isNotEmpty) {
            items = items.where((it) {
              try {
                final m = it as Map;
                final siteName =
                    (m['site'] ??
                            m['siteName'] ??
                            m['site_name'] ??
                            m['siteTitle'] ??
                            m['site_title'])
                        ?.toString() ??
                    '';
                if (siteName.trim().isEmpty) return true;
                return allowedSites.contains(siteName);
              } catch (_) {
                return true;
              }
            }).toList();
          }
        }

        assignments.assignAll(items);

        _hasFetchedAssignments = true;
        _lastAssignmentsKey = key;

        final rr = box.read('role');
        final isPatrol = rr is String && rr == patrolOfficer;
        if (isPatrol) {
          syncPatrolShiftTimeToStorageIfMissing();
        }
      } catch (e) {
        AppSnackBar.show(
          Get.context!,
          'Failed to load assignments: ${e.toString()}',
          type: SnackBarType.error,
        );
      } finally {
        loadingAssignments.value = false;
      }
    })();

    try {
      await _assignmentsFuture;
    } finally {
      _assignmentsFuture = null;
    }
  }

  void syncPatrolShiftTimeToStorageIfMissing() {
    final role = box.read('role');
    final isPatrol = role is String && role == patrolOfficer;
    if (!isPatrol) return;

    final startRaw = _mem.getShiftStartTime().toString().trim();
    final endRaw = _mem.getShiftEndTime().toString().trim();

    final hasTimes = startRaw.isNotEmpty && endRaw.isNotEmpty;
    if (hasTimes) {
      box.write('unpaidBreakMinutes', 0);
      box.write('paidBreakMinutes', 0);
      box.write('totalBreakMinutes', 0);
      return;
    }

    if (assignments.isEmpty) return;

    DateTime normalizeDate(DateTime d) => DateTime(d.year, d.month, d.day);
    final today = normalizeDate(sfNow());

    Map<String, dynamic>? pick;

    for (final it in assignments) {
      if (it is! Map) continue;
      final st = it['startTime']?.toString();
      final en = it['endTime']?.toString();
      if (st == null || en == null) continue;

      final stDt = DateTime.tryParse(st)?.toLocal();
      if (stDt == null) continue;

      if (normalizeDate(stDt) == today) {
        pick = Map<String, dynamic>.from(it);
        break;
      }
    }

    pick ??= assignments.first is Map
        ? Map<String, dynamic>.from(assignments.first)
        : null;
    if (pick == null) return;

    final st = pick['startTime']?.toString();
    final en = pick['endTime']?.toString();
    if (st != null && st.trim().isNotEmpty) {
      box.write('shiftStartTime', st.trim());
    }
    if (en != null && en.trim().isNotEmpty) {
      box.write('shiftEndTime', en.trim());
    }

    box.write('unpaidBreakMinutes', 0);
    box.write('paidBreakMinutes', 0);
    box.write('totalBreakMinutes', 0);
  }
}
