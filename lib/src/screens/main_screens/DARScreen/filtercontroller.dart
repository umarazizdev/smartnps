import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/services/apiservice.dart';
import 'package:smartnps360/src/screens/data/api.url.dart';
import 'package:smartnps360/src/screens/utilities/appsnackbar.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/app_storage.dart';

void _log(String msg, {String tag = 'APP', Object? error, StackTrace? stack}) {
  if (kDebugMode) {
    developer.log(msg, name: tag, error: error, stackTrace: stack);
  }
}

class FilterController extends GetxController {
  final RxList<String> shifts = <String>[].obs;
  final RxList<String> sites = <String>[].obs;
  final RxList<Map<String, dynamic>> sitesData = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> filteredSites =
      <Map<String, dynamic>>[].obs;
  final RxString siteSearchQuery = ''.obs;
  final RxBool showSiteDropdown = false.obs;
  final RxList<String> seriousnessLevels = <String>[].obs;

  final RxString selectedShift = ''.obs;
  final RxString selectedSite = ''.obs;
  final RxString selectedSeriousness = ''.obs;

  final RxString appliedShift = ''.obs;
  final RxString appliedSite = ''.obs;
  final RxString appliedSeriousness = ''.obs;

  final RxBool shiftsLoading = false.obs;
  final RxBool sitesLoading = false.obs;
  final RxBool seriousnessLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    _initializeEmptyDefaults();
  }

  final ApiService _api = ApiService();
  bool _hasFetched = false;
  Future<void>? _fetchFuture;

  void _initializeEmptyDefaults() {
    shifts.assignAll(['All Shifts']);
    sites.assignAll(['All Sites']);
    seriousnessLevels.assignAll([
      'Any Level',
      'All Good',
      'Moderate',
      'Critical',
      'Incident',
    ]);

    selectedShift.value = shifts.first;
    selectedSite.value = sites.first;
    selectedSeriousness.value = seriousnessLevels.first;

    appliedShift.value = selectedShift.value;
    appliedSite.value = selectedSite.value;
    appliedSeriousness.value = selectedSeriousness.value;
  }

  void beginEdit() {
    selectedShift.value = appliedShift.value;
    selectedSite.value = appliedSite.value;
    selectedSeriousness.value = appliedSeriousness.value;
  }

  void applyDraft() {
    appliedShift.value = selectedShift.value;
    appliedSite.value = selectedSite.value;
    appliedSeriousness.value = selectedSeriousness.value;
  }

  void resetApplied() {
    reset();
    applyDraft();
  }

  Future<void> fetchFilterLists({bool forceRefresh = false}) async {
    if (!forceRefresh && _hasFetched) return;
    if (_fetchFuture != null && !forceRefresh) return _fetchFuture!;

    _fetchFuture = (() async {
      final futures = <Future<void>>[];
      futures.add(fetchSites());

      if (futures.isNotEmpty) {
        await Future.wait(futures);
      }

      _hasFetched = true;
    })();

    try {
      await _fetchFuture;
    } finally {
      _fetchFuture = null;
    }
  }

  Future<void> fetchShifts({
    int? regionId,
    int? siteId,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && shifts.length > 1) return;
    shiftsLoading.value = true;

    try {
      String apiUrl = ApiURL.shifts;
      if (regionId != null) {
        apiUrl += '?regionId=$regionId';
      } else if (siteId != null) {
        apiUrl += '?siteId=$siteId';
      }

      final resp = await _api.getData(apiUrl);
      List items = [];

      if (resp is Map && resp['data'] is List) {
        items = resp['data'];
      } else if (resp is List) {
        items = resp;
      }

      if (items.isEmpty) {
        _log('Warning: No shifts data received from API', tag: 'Filter');
        shifts.assignAll(['All Shifts']);
        selectedShift.value = 'All Shifts';
        return;
      }

      final list = ['All Shifts'];
      list.addAll(
        items.map((e) {
          if (e is Map) {
            return (e['label'] ?? e['name'] ?? e['title'] ?? e.toString())
                .toString();
          }
          return e.toString();
        }),
      );

      shifts.assignAll(list);
      box.write('shiftsData', items);

      _log('Fetched ${items.length} shifts from API', tag: 'Filter');
    } catch (e) {
      _log('Error fetching shifts', tag: 'Filter', error: e);
      AppSnackBar.show(
        Get.context!,
        'Failed to load shifts: ${e.toString()}',
        type: SnackBarType.error,
      );
      shifts.assignAll(['All Shifts']);
    } finally {
      shiftsLoading.value = false;
      if (!shifts.contains(selectedShift.value)) {
        selectedShift.value = shifts.first;
      }
    }
  }

  Future<void> fetchSites({bool forceRefresh = false}) async {
    if (!forceRefresh && sites.length > 1) return; // already loaded
    sitesLoading.value = true;

    try {
      final resp = await _api.getData(ApiURL.sites);
      List items = [];

      if (resp is Map && resp['data'] is List) {
        items = resp['data'];
      } else if (resp is List) {
        items = resp;
      }

      if (items.isEmpty) {
        _log('Warning: No sites data received from API', tag: 'Filter');
        sites.assignAll(['All Sites']);
        selectedSite.value = 'All Sites';
        return;
      }

      final list = ['All Sites'];
      final mappedStrings = items.map((e) {
        if (e is Map) {
          return (e['label'] ?? e['name'] ?? e['title'] ?? e.toString())
              .toString();
        }
        return e.toString();
      }).toList();

      final List<Map<String, dynamic>> mappedObjects = [];
      for (var e in items) {
        if (e is Map) {
          try {
            final Map<String, dynamic> m = Map<String, dynamic>.from(e);
            m['name'] = (e['label'] ?? e['name'] ?? e['title'] ?? '')
                .toString();
            mappedObjects.add(m);
          } catch (err) {
            mappedObjects.add({
              'id': e['id'],
              'name': (e['label'] ?? e['name'] ?? e['title'] ?? '').toString(),
            });
          }
        } else {
          mappedObjects.add({'id': null, 'name': e.toString()});
        }
      }

      list.addAll(mappedStrings);
      sites.assignAll(list);
      sitesData.assignAll(mappedObjects);
      filteredSites.assignAll(List<Map<String, dynamic>>.from(sitesData));
      box.write('sitesData', items);

      _log('Fetched ${items.length} sites from API', tag: 'Filter');
    } catch (e) {
      _log('Error fetching sites', tag: 'Filter', error: e);
      AppSnackBar.show(
        Get.context!,
        'Failed to load sites: ${e.toString()}',
        type: SnackBarType.error,
      );
      sites.assignAll(['All Sites']);
    } finally {
      sitesLoading.value = false;
      if (!sites.contains(selectedSite.value)) {
        selectedSite.value = sites.first;
      }
    }
  }

  /// Resolve site name by id. Tries cache, then fetches lists, then single-item API.
  Future<String?> getSiteNameById(dynamic id) async {
    if (id == null) return null;
    final sid = id.toString();

    // try cached box
    final cached = box.read('sitesData') as List<dynamic>?;
    if (cached != null) {
      for (final it in cached) {
        if (it is Map) {
          final itId = it['id']?.toString();
          if (itId == sid) {
            return (it['label'] ?? it['name'] ?? it['title'])?.toString();
          }
        }
      }
    }

    // try loaded controller lists
    for (final s in sitesData) {
      final itId = s['id']?.toString();
      if (itId == sid) {
        return (s['label'] ?? s['name'] ?? s['title'])?.toString();
      }
    }

    // fetch fresh lists and retry
    try {
      await fetchSites(forceRefresh: true);
    } catch (_) {}

    final fresh = box.read('sitesData') as List<dynamic>?;
    if (fresh != null) {
      for (final it in fresh) {
        if (it is Map && (it['id']?.toString() ?? '') == sid) {
          final name = (it['label'] ?? it['name'] ?? it['title'])?.toString();
          return name;
        }
      }
    }

    // fallback single-item API
    try {
      final resp = await _api.getData('${ApiURL.sites}/$sid');
      Map<String, dynamic>? item;
      if (resp is Map && resp['data'] is Map) {
        item = Map<String, dynamic>.from(resp['data']);
      } else if (resp is Map)
        // ignore: curly_braces_in_flow_control_structures
        item = Map<String, dynamic>.from(resp);
      if (item != null) {
        final name = (item['label'] ?? item['name'] ?? item['title'])
            ?.toString();
        final list = (box.read('sitesData') as List<dynamic>?) ?? <dynamic>[];
        list.add(item);
        box.write('sitesData', list);
        return name;
      }
    } catch (_) {}

    return null;
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

  /// Resolve region name by id with same strategy as sites
  Future<String?> getRegionNameById(dynamic id) async {
    if (id == null) return null;
    final sid = id.toString();
    final cached = box.read('regionsData') as List<dynamic>?;
    if (cached != null) {
      for (final it in cached) {
        if (it is Map && (it['id']?.toString() ?? '') == sid) {
          return (it['label'] ?? it['name'] ?? it['title'])?.toString();
        }
      }
    }

    // fetch regions via API and retry
    try {
      final resp = await _api.getData(ApiURL.regions);
      List items = [];
      if (resp is Map && resp['data'] is List) {
        items = resp['data'];
      } else if (resp is List)
        // ignore: curly_braces_in_flow_control_structures
        items = resp;
      if (items.isNotEmpty) box.write('regionsData', items);
    } catch (_) {}

    final fresh = box.read('regionsData') as List<dynamic>?;
    if (fresh != null) {
      for (final it in fresh) {
        if (it is Map && (it['id']?.toString() ?? '') == sid) {
          return (it['label'] ?? it['name'] ?? it['title'])?.toString();
        }
      }
    }

    // fallback single-item API
    try {
      final resp = await _api.getData('${ApiURL.regions}/$sid');
      Map<String, dynamic>? item;
      if (resp is Map && resp['data'] is Map) {
        item = Map<String, dynamic>.from(resp['data']);
      } else if (resp is Map)
        // ignore: curly_braces_in_flow_control_structures
        item = Map<String, dynamic>.from(resp);
      if (item != null) {
        final name = (item['label'] ?? item['name'] ?? item['title'])
            ?.toString();
        final list = (box.read('regionsData') as List<dynamic>?) ?? <dynamic>[];
        list.add(item);
        box.write('regionsData', list);
        return name;
      }
    } catch (_) {}

    return null;
  }

  /// Resolve shift name by id
  Future<String?> getShiftNameById(dynamic id) async {
    if (id == null) return null;
    final sid = id.toString();
    final cached = box.read('shiftsData') as List<dynamic>?;
    if (cached != null) {
      for (final it in cached) {
        if (it is Map && (it['id']?.toString() ?? '') == sid) {
          return (it['label'] ?? it['name'] ?? it['title'])?.toString();
        }
      }
    }

    // fetch shifts and retry
    try {
      await fetchShifts(forceRefresh: true);
    } catch (_) {}

    final fresh = box.read('shiftsData') as List<dynamic>?;
    if (fresh != null) {
      for (final it in fresh) {
        if (it is Map && (it['id']?.toString() ?? '') == sid) {
          return (it['label'] ?? it['name'] ?? it['title'])?.toString();
        }
      }
    }

    // fallback single-item API
    try {
      final resp = await _api.getData('${ApiURL.shifts}/$sid');
      Map<String, dynamic>? item;
      if (resp is Map && resp['data'] is Map) {
        item = Map<String, dynamic>.from(resp['data']);
      } else if (resp is Map)
        // ignore: curly_braces_in_flow_control_structures
        item = Map<String, dynamic>.from(resp);
      if (item != null) {
        final name = (item['label'] ?? item['name'] ?? item['title'])
            ?.toString();
        final list = (box.read('shiftsData') as List<dynamic>?) ?? <dynamic>[];
        list.add(item);
        box.write('shiftsData', list);
        return name;
      }
    } catch (_) {}

    return null;
  }

  int? _getRegionIdFromSite(String siteName) {
    final items = box.read('sitesData') as List<dynamic>?;
    if (items == null) {
      _log('Debug: sitesData is null', tag: 'Filter');
      return null;
    }

    for (var item in items) {
      if (item is Map) {
        final itemName = (item['label'] ?? item['name'] ?? item['title'] ?? '')
            .toString();

        if (itemName == siteName) {
          final region =
              item['region'] ?? item['regionId'] ?? item['region_id'];
          if (region != null) {
            final regionId = region is int ? region : int.tryParse('$region');
            return regionId;
          }
        }
      }
    }
    return null;
  }

  void searchSites(String query) {
    siteSearchQuery.value = query;
    if (query.isEmpty) {
      filteredSites.assignAll(sitesData);
    } else {
      filteredSites.assignAll(
        sitesData.where((site) {
          final name = (site['name'] ?? '').toString().toLowerCase();
          return name.contains(query.toLowerCase());
        }).toList(),
      );
    }
  }

  void setShift(String? v) {
    if (v == null) return;
    selectedShift.value = v;
  }

  void setSite(String? v) {
    if (v == null) return;
    selectedSite.value = v;

    if (v != sites.first) {
      final role = box.read('role');
      final isPatrolOfficer =
          role != null && role is String && role == patrolOfficer;

      if (isPatrolOfficer) {
        final regionId = _getRegionIdFromSite(v);
        if (regionId != null) {
          fetchShifts(regionId: regionId);
        } else {
          shifts.assignAll(['All Shifts']);
          selectedShift.value = 'All Shifts';
        }
      } else {
        final siteId = _findIdByName(v, 'sitesData');
        if (siteId != null) {
          fetchShifts(siteId: siteId);
        }
      }
    } else {
      shifts.assignAll(['All Shifts']);
      selectedShift.value = 'All Shifts';
    }
  }

  void setSeriousness(String? v) {
    if (v == null) return;
    selectedSeriousness.value = v;
  }

  void reset() {
    if (shifts.isNotEmpty) selectedShift.value = shifts.first;
    if (sites.isNotEmpty) selectedSite.value = sites.first;
    if (seriousnessLevels.isNotEmpty) {
      selectedSeriousness.value = seriousnessLevels.first;
    }
  }

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> m = {};

    if (appliedSite.value.isNotEmpty && appliedSite.value != sites.first) {
      m['siteName'] = appliedSite.value;
    }

    if (appliedShift.value.isNotEmpty && appliedShift.value != shifts.first) {
      final s = appliedShift.value;
      final idx = s.indexOf('(');
      m['shift'] = (idx == -1 ? s : s.substring(0, idx)).trim();
    }

    if (appliedSeriousness.value.isNotEmpty &&
        appliedSeriousness.value != seriousnessLevels.first) {
      final label = appliedSeriousness.value.trim().toLowerCase();
      if (label == 'all good') m['status'] = 'All Good';
      if (label == 'moderate') m['status'] = 'Moderate';
      if (label == 'critical') m['status'] = 'Critical';
      if (label == 'incident') m['status'] = 'Incident';
    }

    return m;
  }

  bool get hasActiveFilters {
    if (appliedSite.value.isNotEmpty && appliedSite.value != sites.first) {
      return true;
    }
    if (appliedShift.value.isNotEmpty && appliedShift.value != shifts.first) {
      return true;
    }
    if (appliedSeriousness.value.isNotEmpty &&
        appliedSeriousness.value != seriousnessLevels.first) {
      return true;
    }
    return false;
  }

  int get activeFilterCount {
    int c = 0;
    if (appliedSite.value.isNotEmpty && appliedSite.value != sites.first) c++;
    if (appliedShift.value.isNotEmpty && appliedShift.value != shifts.first) {
      c++;
    }
    if (appliedSeriousness.value.isNotEmpty &&
        appliedSeriousness.value != seriousnessLevels.first) {
      c++;
    }
    return c;
  }

  bool get hasDraftActiveFilters {
    if (selectedSite.value.isNotEmpty && selectedSite.value != sites.first) {
      return true;
    }
    if (selectedShift.value.isNotEmpty && selectedShift.value != shifts.first) {
      return true;
    }
    if (selectedSeriousness.value.isNotEmpty &&
        selectedSeriousness.value != seriousnessLevels.first) {
      return true;
    }
    return false;
  }

  List<Map<String, String>> getActiveFilters() {
    final List<Map<String, String>> active = [];

    if (appliedSite.value.isNotEmpty && appliedSite.value != sites.first) {
      active.add({'type': 'site', 'label': appliedSite.value});
    }
    if (appliedShift.value.isNotEmpty && appliedShift.value != shifts.first) {
      active.add({'type': 'shift', 'label': appliedShift.value});
    }
    if (appliedSeriousness.value.isNotEmpty &&
        appliedSeriousness.value != seriousnessLevels.first) {
      active.add({'type': 'seriousness', 'label': appliedSeriousness.value});
    }
    return active;
  }

  void removeFilter(String type) {
    switch (type) {
      case 'site':
        if (sites.isNotEmpty) {
          appliedSite.value = sites.first;
          selectedSite.value = sites.first;
        }
        break;
      case 'shift':
        if (shifts.isNotEmpty) {
          appliedShift.value = shifts.first;
          selectedShift.value = shifts.first;
        }
        break;
      case 'seriousness':
        if (seriousnessLevels.isNotEmpty) {
          appliedSeriousness.value = seriousnessLevels.first;
          selectedSeriousness.value = seriousnessLevels.first;
        }
        break;
    }
  }
}
