import 'dart:async';

import 'package:get/get.dart';
import 'package:smartnps360/src/screens/services/apiservice.dart';
import 'package:smartnps360/src/screens/data/api.url.dart';
import 'package:smartnps360/src/screens/main_screens/DARScreen/darmodel.dart';
import 'package:smartnps360/src/screens/utilities/appsnackbar.dart';

class DarListController extends GetxController {
  final ApiService _api = ApiService();

  final RxList<DarModel> allDars = <DarModel>[].obs; // All fetched DARs
  final RxList<DarModel> dars = <DarModel>[].obs; // Filtered DARs for display
  final RxBool loading = false.obs;
  final RxBool loadingMore = false.obs;
  final RxBool hasMore = true.obs;
  final RxBool isFabVisible = true.obs;

  int _page = 0;
  int pageSize = 20;
  Future<void>? _fetchFuture;

  // search & filters
  final RxString searchQuery = ''.obs;
  Timer? _debounce;

  final Map<String, dynamic> _filters = {};

  @override
  void onInit() {
    super.onInit();
    // debounce search input
    debounce(searchQuery, (_) {
      _applyLocalFilters();
    }, time: const Duration(milliseconds: 450));
  }

  void setFilter(String key, dynamic value) {
    if (value == null) {
      _filters.remove(key);
    } else {
      _filters[key] = value;
    }
  }

  Future<void> applyFilters(Map<String, dynamic> filters) async {
    _filters
      ..clear()
      ..addAll(filters);
    _applyLocalFilters();
  }

  String _norm(String? v) => (v ?? '').trim().toLowerCase();

  /// Apply filters + search locally to fetched data
  /// ✅ consistent pipeline:
  /// allDars -> filters -> search -> dars
  void _applyLocalFilters() {
    List<DarModel> filtered = List.from(allDars);

    // 1) Apply filters (keys from FilterController.toMap(): siteName, shift, status)
    if (_filters.containsKey('siteName')) {
      final site = _norm(_filters['siteName']?.toString());
      filtered = filtered.where((dar) => _norm(dar.siteName) == site).toList();
    }

    if (_filters.containsKey('shift')) {
      final raw = _filters['shift']?.toString() ?? '';
      final idx = raw.indexOf('(');
      final shift = _norm(
        idx == -1 ? raw : raw.substring(0, idx),
      ); // ✅ remove timing
      filtered = filtered.where((dar) => _norm(dar.shift) == shift).toList();
    }
    if (_filters.containsKey('status')) {
      final status = _norm(
        _filters['status']?.toString(),
      ); // all_good/moderate/critical
      filtered = filtered.where((dar) => _norm(dar.status) == status).toList();
    }

    // 2) Apply search on filtered results
    final q = _norm(searchQuery.value);
    if (q.isNotEmpty) {
      filtered = filtered.where((dar) {
        return _norm(dar.siteName).contains(q) ||
            _norm(dar.shift).contains(q) ||
            _norm(dar.shiftType).contains(q) ||
            _norm(dar.status).contains(q) ||
            _norm(dar.description).contains(q) ||
            _norm(dar.activityType).contains(q);
      }).toList();
    }

    dars.value = filtered;
  }

  Future<void> fetchDars({bool reset = false, bool loadMore = false}) async {
    if (!reset && !loadMore && allDars.isNotEmpty) return;

    if (_fetchFuture != null && !reset && !loadMore) return _fetchFuture!;

    if (reset) {
      _page = 0;
      hasMore.value = true;
      allDars.clear();
      dars.clear();
    }

    if (!hasMore.value) return;

    if (_page == 0) {
      loading.value = true;
    } else {
      loadingMore.value = true;
    }

    _fetchFuture = (() async {
      try {
        final params = <String, String>{
          'page': _page.toString(),
          'pageSize': pageSize.toString(),
        };

        final query = params.entries
            .map(
              (e) =>
                  '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
            )
            .join('&');

        final endpoint = '${ApiURL.getDars}?$query';

        final resp = await _api.getData(endpoint);

        List items = [];
        if (resp == null) {
          items = [];
        } else if (resp is List)
          // ignore: curly_braces_in_flow_control_structures
          items = resp;
        else if (resp is Map) {
          if (resp['data'] is List) {
            items = resp['data'];
          } else if (resp['data'] is Map && resp['data']['items'] is List)
            // ignore: curly_braces_in_flow_control_structures
            items = resp['data']['items'];
          else if (resp['items'] is List)
            // ignore: curly_braces_in_flow_control_structures
            items = resp['items'];
        }

        final fetched = items.map((e) => DarModel.fromJson(e)).toList();

        if (fetched.length < pageSize) {
          hasMore.value = false;
        }

        allDars.addAll(fetched);
        _page += 1;

        // Apply filters+search after fetching
        _applyLocalFilters();
      } catch (e) {
        AppSnackBar.show(
          Get.context!,
          'Failed to load DARs: ${e.toString()}',
          type: SnackBarType.error,
        );
      } finally {
        loading.value = false;
        loadingMore.value = false;
      }
    })();

    try {
      await _fetchFuture;
    } finally {
      _fetchFuture = null;
    }
  }

  @override
  Future<void> refresh() async {
    await fetchDars(reset: true);
  }

  void search(String q) {
    searchQuery.value = q;
  }

  void setFabVisible(bool v) => isFabVisible.value = v;

  @override
  void onClose() {
    _debounce?.cancel();
    super.onClose();
  }
}
