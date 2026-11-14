import 'package:get/get.dart';
import 'package:smartnps360/src/screens/app_storage.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

class MemoryStorageController extends GetxController {
  final regionId = RxnInt();
  final shiftId = RxnInt();
  final siteId = RxnInt();
  final seriesId = RxnInt();

  final regionName = ''.obs;
  final shiftName = ''.obs;
  final siteName = ''.obs;

  final isScopeSelected = false.obs;
  final shiftStartTime = ''.obs;
  final shiftEndTime = ''.obs;

  void setRegionId(int? v) => regionId.value = v;
  void setShiftId(int? v) => shiftId.value = v;
  void setSiteId(int? v) => siteId.value = v;
  void setSeriesId(int? v) => seriesId.value = v;

  void setRegionName(String? v) => regionName.value = v?.trim() ?? '';
  void setShiftName(String? v) => shiftName.value = v?.trim() ?? '';
  void setSiteName(String? v) => siteName.value = v?.trim() ?? '';

  void setIsScopeSelected(bool v) => isScopeSelected.value = v;
  void setShiftStartTime(String? v) => shiftStartTime.value = v?.trim() ?? '';
  void setShiftEndTime(String? v) => shiftEndTime.value = v?.trim() ?? '';

  int? getRegionId() {
    if (regionId.value != null) return regionId.value;
    final v = box.read('regionId');
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  int? getShiftId() {
    if (shiftId.value != null) return shiftId.value;
    final v = box.read('shiftId');
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  int? getSeriesId() {
    if (seriesId.value != null) return seriesId.value;
    final v = box.read('seriesId');
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  int? getSiteId() {
    if (siteId.value != null) return siteId.value;
    final v = box.read('siteId');
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  String getRegionName() {
    if (regionName.value.isNotEmpty) return regionName.value;
    return (box.read(kSelectedRegionKey) ?? '').toString().trim();
  }

  String getShiftName() {
    if (shiftName.value.isNotEmpty) return shiftName.value;
    return (box.read(kSelectedShiftKey) ?? '').toString().trim();
  }

  String getSiteName() {
    if (siteName.value.isNotEmpty) return siteName.value;
    return (box.read(kSelectedSiteKey) ?? '').toString().trim();
  }

  bool getIsScopeSelected() {
    if (isScopeSelected.value) return true;
    return (box.read('isScopeSelected') ?? false) == true;
  }

  String getShiftStartTime() {
    if (shiftStartTime.value.isNotEmpty) return shiftStartTime.value;
    return (box.read('shiftStartTime') ?? '').toString();
  }

  String getShiftEndTime() {
    if (shiftEndTime.value.isNotEmpty) return shiftEndTime.value;
    return (box.read('shiftEndTime') ?? '').toString();
  }
}
