import 'dart:io';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smartnps360/src/screens/services/apiservice.dart';
import 'package:smartnps360/src/screens/data/api.url.dart';
import 'package:smartnps360/src/screens/utilities/appsnackbar.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/utilities/sf_time.dart';
import 'dar_list_controller.dart';
import 'package:smartnps360/src/screens/controllers/memory_storage_controller.dart';
import 'dar_camera_screen.dart';

void _log(String msg, {String tag = 'APP', Object? error, StackTrace? stack}) {
  if (kDebugMode) {
    developer.log(msg, name: tag, error: error, stackTrace: stack);
  }
}

class _PermissionCanceled implements Exception {}

class DARController extends GetxController {
  final ApiService _apiService = ApiService();
  final box = GetStorage();
  final MemoryStorageController _mem =
      Get.isRegistered<MemoryStorageController>()
      ? Get.find<MemoryStorageController>()
      : Get.put(MemoryStorageController());

  RxString site = ''.obs;
  RxString reportDetails = ''.obs;
  RxString seriousness = "All Good".obs;
  RxnString selectedActivityType = RxnString();
  Rx<DateTime> reportDateTime = sfNow().obs;

  RxList<File> photos = <File>[].obs;

  RxList<String> activityTypes = <String>[].obs;
  RxBool isLoadingActivityTypes = false.obs;

  RxnString selectedSite = RxnString();

  RxBool isSubmitting = false.obs;

  // These are only submitted when true (and when incidentReportEnabled is true)
  RxBool policeNotified = false.obs;
  RxString policeReportNumber = ''.obs;

  RxBool managerNotified = false.obs;
  RxString managerName = ''.obs;

  void setIncidentReportEnabled(String v) {
    seriousness.value = v;
    if (v != 'Incident') {
      // Reset dependent fields when disabling the section
      policeNotified.value = false;
      policeReportNumber.value = '';
      managerNotified.value = false;
      managerName.value = '';
    }
  }

  void setPoliceNotified(bool v) {
    policeNotified.value = v;
    if (!v) policeReportNumber.value = '';
  }

  void setPoliceReportNumber(String v) => policeReportNumber.value = v;

  void setManagerNotified(bool v) {
    managerNotified.value = v;
    if (!v) managerName.value = '';
  }

  void setManagerName(String v) => managerName.value = v;

  final ImagePicker _picker = ImagePicker();

  @override
  void onInit() {
    super.onInit();
    seriousness.value = "All Good";

    fetchActivityTypes();
    initializeOnSiteOfficerSite();
  }

  void initializeOnSiteOfficerSite() {
    final r = box.read('role');
    if (r != null && r is String && r == onSiteOfficer) {
      final scopeSiteName = _mem.getSiteName();
      if (scopeSiteName.isNotEmpty) {
        selectedSite.value = scopeSiteName;
      }
    }
  }

  void setSite(String value) => site.value = value;
  void setReportDetails(String value) => reportDetails.value = value;
  void setSeriousness(String value) {
    seriousness.value = value;
  }

  void setActivityType(String? value) => selectedActivityType.value = value;
  void setReportDateTime(DateTime dateTime) => reportDateTime.value = dateTime;
  Future<void> pickImages() async {
    final pickedFiles = await _picker.pickMultiImage(imageQuality: 75);
    if (pickedFiles.isNotEmpty) {
      photos.addAll(pickedFiles.map((e) => File(e.path)));
    }
  }

  Future<void> pickFromCamera() async {
    final pickedFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 75,
    );
    if (pickedFile != null) photos.add(File(pickedFile.path));
  }

  Future<void> openDARCamera() async {
    final result = await Get.to<File>(() => const DARCameraScreen());
    if (result != null) {
      photos.add(result);
    }
  }

  void removePhoto(int index) => photos.removeAt(index);

  Future<void> fetchActivityTypes() async {
    try {
      isLoadingActivityTypes.value = true;
      final resp = await _apiService.getData(ApiURL.activityTypes);

      if (resp['success'] == true) {
        final list = List<String>.from(resp['data'] ?? []);
        activityTypes.assignAll(list);

        if (selectedActivityType.value == null ||
            !activityTypes.contains(selectedActivityType.value)) {
          selectedActivityType.value = activityTypes.isNotEmpty
              ? activityTypes.first
              : null;
        }
      } else {
        activityTypes.clear();
        selectedActivityType.value = null;
        AppSnackBar.show(
          Get.context!,
          resp['message'] ?? "Failed to load activity types",
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      activityTypes.clear();
      selectedActivityType.value = null;
      String errorMessage = e.toString().replaceFirst('Exception: ', '');
      AppSnackBar.show(
        Get.context!,
        errorMessage.isEmpty
            ? 'Failed to load activity types. Please try again.'
            : errorMessage,
        type: SnackBarType.error,
      );
    } finally {
      isLoadingActivityTypes.value = false;
    }
  }

  Future<void> submitDAR() async {
    if (selectedSite.value == null || selectedSite.value!.isEmpty) {
      AppSnackBar.show(Get.context!, 'Please select a site');
      return;
    }

    if (seriousness.value == 'Incident') {
      if (policeNotified.value && policeReportNumber.value.trim().isEmpty) {
        AppSnackBar.show(
          Get.context!,
          'Please enter police report number',
          type: SnackBarType.error,
        );
        return;
      }
      if (managerNotified.value && managerName.value.trim().isEmpty) {
        AppSnackBar.show(
          Get.context!,
          'Please enter manager name',
          type: SnackBarType.error,
        );
        return;
      }
    }
    if (reportDetails.value.isEmpty) {
      AppSnackBar.show(Get.context!, 'Please enter report details');
      return;
    }
    if (selectedActivityType.value == null) {
      AppSnackBar.show(Get.context!, 'Please select activity type');
      return;
    }
    if (photos.isEmpty) {
      AppSnackBar.show(Get.context!, 'Please select images');
      return;
    }
    try {
      isSubmitting.value = true;

      final shiftId = _mem.getShiftId();
      final siteId = _mem.getSiteId();

      final fields = {
        'dateTime': reportDateTime.value.toUtc().toIso8601String(),
        'activityType': selectedActivityType.value,
        'seriousness': seriousness.value,
        'reportDetails': reportDetails.value.trim(),
        'series_id': shiftId.toString(),
        'site_id': siteId.toString(),
      };

      if (seriousness.value == 'Incident') {
        if (policeNotified.value) {
          fields['police_notified'] = policeNotified.value ? '1' : '0';
          if (policeReportNumber.value.trim().isNotEmpty) {
            fields['police_report_number'] = policeReportNumber.value.trim();
          }
        }
        if (managerNotified.value) {
          fields['manager_notified'] = managerNotified.value ? '1' : '0';
          if (managerName.value.trim().isNotEmpty) {
            fields['manager_name'] = managerName.value.trim();
          }
        }
      }

      final filePaths = photos.map((f) => f.path).toList();

      // Try to attach coordinates if available
      try {
        final coords = await _fetchCoordinates();
        if (coords != null) {
          fields['latitude'] = coords['latitude']?.toString();
          fields['longitude'] = coords['longitude']?.toString();
          fields['lat'] = coords['latitude']?.toString();
          fields['lng'] = coords['longitude']?.toString();
        }
      } on _PermissionCanceled {
        isSubmitting.value = false;
        AppSnackBar.show(
          Get.context!,
          'Action cancelled',
          type: SnackBarType.info,
        );
        return;
      } catch (_) {}

      final resp = await _apiService.postMultipart(
        ApiURL.createDar,
        fields,
        filePaths,
        'photos',
      );
      final bool isSuccess = resp.statusCode == 200 || resp.statusCode == 201;

      if (isSuccess) {
        resetForm();

        try {
          final listController = Get.find<DarListController>();
          listController.fetchDars(reset: true);
        } catch (e) {
          _log('DAR list controller not found', tag: 'DAR', error: e);
        }
        Get.back();

        AppSnackBar.show(
          Get.context!,
          resp.data?['message'] ?? 'DAR created successfully',
          type: SnackBarType.success,
        );
      } else {
        AppSnackBar.show(
          Get.context!,
          resp.data?['message'] ?? 'Failed to create DAR',
          type: SnackBarType.error,
        );
      }
    } catch (e) {
      AppSnackBar.show(
        Get.context!,
        'Error: ${e.toString()}',
        type: SnackBarType.error,
      );
    } finally {
      isSubmitting.value = false;
    }
  }

  Future<Map<String, double>?> _fetchCoordinates() async {
    final status = await Permission.locationWhenInUse.status;

    Future<bool> requestDialogAndAsk() async {
      // Only show custom dialog on Android
      bool? should;
      if (Platform.isAndroid) {
        should = await Get.dialog<bool>(
          Dialog(
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
                      colors: [
                        Colors.white.withAlpha(115),
                        Colors.white.withAlpha(38),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(38),
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
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: cPrimary.withAlpha(26),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.location_on_outlined,
                                  color: cPrimary,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Location Access',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black.withAlpha(217),
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
                                  color: Colors.black.withAlpha(191),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Divider(
                            thickness: 1,
                            color: Colors.white.withAlpha(128),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Why we need your location',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black.withAlpha(217),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your location is used only while the app is open to verify:',
                            style: TextStyle(
                              color: Colors.black.withAlpha(191),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildLocationUsageRow(
                            Icons.assignment_outlined,
                            'Daily Activity Report (DAR) submissions',
                          ),
                          const SizedBox(height: 8),
                          _buildLocationUsageRow(
                            Icons.pin_drop_outlined,
                            'Verify you are at the incident location',
                          ),
                          const SizedBox(height: 8),
                          _buildLocationUsageRow(
                            Icons.track_changes_outlined,
                            'Accurate GPS coordinates for reports',
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withAlpha(13),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: cPrimary.withAlpha(51),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.security_outlined,
                                  size: 20,
                                  color: cPrimary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Your location is securely sent to your employer\'s system and used only for incident reporting.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black.withAlpha(191),
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => Get.back(result: false),
                                  child: Container(
                                    height: 44,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      color: Colors.white.withAlpha(153),
                                      border: Border.all(
                                        color: Colors.black.withAlpha(26),
                                        width: 1,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Not Now',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black.withAlpha(217),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => Get.back(result: true),
                                  child: Container(
                                    height: 44,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      color: const Color(0xFF007AFF),
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'Allow Location',
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
          ),
          barrierDismissible: false,
          barrierColor: Colors.black.withAlpha(77),
        );
      } else {
        // iOS: Skip custom dialog, system dialog will show with Info.plist explanation
        should = true;
      }

      if (should != true) throw _PermissionCanceled();
      final res = await Permission.locationWhenInUse.request();
      if (res.isPermanentlyDenied) {
        await openAppSettings();
        throw _PermissionCanceled();
      }
      if (!res.isGranted) throw _PermissionCanceled();
      return true;
    }

    bool granted = status.isGranted;
    if (!granted) {
      if (status.isPermanentlyDenied) {
        // Show custom dialog on both iOS and Android to ask before opening settings
        final open = await Get.dialog<bool>(
          Dialog(
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
                      colors: [
                        Colors.white.withAlpha(115),
                        Colors.white.withAlpha(38),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(38),
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
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withAlpha(26),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.location_off_outlined,
                                  color: Colors.orange.shade700,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Location Disabled',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black.withAlpha(217),
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
                                  color: Colors.black.withAlpha(191),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Divider(
                            thickness: 1,
                            color: Colors.white.withAlpha(128),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Location access was denied',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black.withAlpha(217),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'To submit Daily Activity Reports (DAR) and verify incident locations, you need to enable location permissions in your device settings:',
                            style: TextStyle(
                              color: Colors.black.withAlpha(191),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withAlpha(13),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.orange.withAlpha(51),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.settings_outlined,
                                  size: 20,
                                  color: Colors.orange.shade700,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    Platform.isIOS
                                        ? 'Settings > Privacy > Location Services > SmartNPS360 > Select "While Using the App"'
                                        : 'Settings > Apps > SmartNPS360 > Permissions > Location > Allow only while using the app',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black.withAlpha(191),
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
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
                                      color: Colors.white.withAlpha(153),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Cancel',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black.withAlpha(217),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => Get.back(result: true),
                                  child: Container(
                                    height: 44,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      color: const Color(0xFF007AFF),
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'Open Settings',
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
          ),
          barrierDismissible: false,
          barrierColor: Colors.black.withAlpha(77),
        );
        if (open == true) await openAppSettings();
        throw _PermissionCanceled();
      }

      granted = await requestDialogAndAsk();
      if (!granted) return null;
    }

    try {
      // Always request a fresh position — never accept cached/last-known coords.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return {'latitude': pos.latitude, 'longitude': pos.longitude};
    } catch (_) {
      // Do NOT fall back to getLastKnownPosition — it returns a cached/stale
      // OS location and must not be sent as the user's current location.
      return null;
    }
  }

  void resetForm() {
    site.value = '';
    reportDetails.value = '';
    seriousness.value = 'All Good';
    selectedActivityType.value = null;
    selectedSite.value = null;
    policeNotified.value = false;
    policeReportNumber.value = '';
    managerNotified.value = false;
    managerName.value = '';
    reportDateTime.value = sfNow();
    photos.clear();
  }

  Widget _buildLocationUsageRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cPrimary.withAlpha(13),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: cPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.black.withAlpha(191),
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
