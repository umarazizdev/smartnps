// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smartnps360/src/screens/services/apiservice.dart';
import 'package:smartnps360/src/screens/data/api.url.dart';
import 'package:smartnps360/src/screens/utilities/appsnackbar.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/controllers/usercontroller.dart';
import 'package:smartnps360/src/screens/utilities/sf_time.dart';

void _log(String msg, {String tag = 'APP', Object? error, StackTrace? stack}) {
  if (kDebugMode) {
    developer.log(msg, name: tag, error: error, stackTrace: stack);
  }
}

enum LocationPermissionStatus { unknown, denied, granted, permanentlyDenied }

class LogVisitController extends GetxController {
  final ApiService _apiService = ApiService();
  final int scheduleId;
  final int siteId;

  LogVisitController({required this.scheduleId, required this.siteId});

  // Observable properties
  final Rx<LocationPermissionStatus> locationPermissionStatus =
      LocationPermissionStatus.unknown.obs;
  final Rx<Position?> currentLocation = Rx<Position?>(null);
  final Rx<Map<String, dynamic>?> siteCoordinates = Rx<Map<String, dynamic>?>(
    null,
  );
  final RxBool isLoadingLocation = false.obs;
  final RxBool isLoadingSiteData = false.obs;
  final RxBool isLoggingVisit = false.obs;
  final RxString timeAgo = ''.obs;
  final RxDouble distanceToSite = 0.0.obs;
  final RxBool isWithinRange = false.obs;
  Timer? _timeAgoTimer;

  // Google Maps
  GoogleMapController? mapController;
  final RxList<Marker> markers = <Marker>[].obs;
  final RxSet<Circle> circles = <Circle>{}.obs;
  bool _isMapInitialized = false;
  final RxBool isMapReady = false.obs;

  @override
  void onInit() {
    super.onInit();
    _initializeLocationAccess();
    _startTimeAgoUpdater();
  }

  @override
  void onClose() {
    _timeAgoTimer?.cancel();
    mapController?.dispose();
    super.onClose();
  }

  /// Start timer to update time ago every minute
  void _startTimeAgoUpdater() {
    _timeAgoTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (currentLocation.value?.timestamp != null) {
        _updateTimeAgo();
      }
    });
  }

  /// Update the time ago string
  void _updateTimeAgo() {
    if (currentLocation.value?.timestamp != null) {
      timeAgo.value = _formatTimestamp(currentLocation.value!.timestamp);
    }
  }

  /// Format timestamp to human readable time ago
  String _formatTimestamp(DateTime timestamp) {
    final now = sfNow();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  /// Initialize location access by checking permissions
  Future<void> _initializeLocationAccess() async {
    _log('=== INITIALIZATION START ===', tag: 'LogVisit');
    await checkLocationPermission();
    _log(
      'Permission status: ${locationPermissionStatus.value}',
      tag: 'LogVisit',
    );
    if (locationPermissionStatus.value == LocationPermissionStatus.granted) {
      _log('Fetching location and site coordinates...', tag: 'LogVisit');
      await Future.wait([getCurrentLocation(), fetchSiteCoordinates()]);
    }
    _log('=== INITIALIZATION END ===', tag: 'LogVisit');
  }

  /// Check current location permission status
  Future<void> checkLocationPermission() async {
    try {
      _log('Checking location service...', tag: 'LogVisit');
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      _log('Location service enabled: $serviceEnabled', tag: 'LogVisit');

      if (!serviceEnabled) {
        locationPermissionStatus.value = LocationPermissionStatus.denied;
        _log('Location service is disabled', tag: 'LogVisit');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      _log('Location permission: $permission', tag: 'LogVisit');

      if (permission == LocationPermission.denied) {
        locationPermissionStatus.value = LocationPermissionStatus.denied;
      } else if (permission == LocationPermission.deniedForever) {
        locationPermissionStatus.value =
            LocationPermissionStatus.permanentlyDenied;
      } else if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        locationPermissionStatus.value = LocationPermissionStatus.granted;
      }
    } catch (e) {
      _log('Error checking location permission', tag: 'LogVisit', error: e);
      locationPermissionStatus.value = LocationPermissionStatus.denied;
    }
  }

  /// Request location permission from the user with explanation dialog
  Future<void> requestLocationPermission() async {
    try {
      // First check if location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _log(
          '📍 Location services disabled, showing enable dialog',
          tag: 'LogVisit',
        );

        // Only show custom dialog on Android
        bool? enable;
        if (Platform.isAndroid) {
          final isDarkDialog =
              Theme.of(Get.context!).brightness == Brightness.dark;
          enable = await Get.dialog<bool>(
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
                        colors: isDarkDialog
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
                          color: Colors.black.withAlpha(isDarkDialog ? 77 : 38),
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
                                    'Enable Location Services',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: isDarkDialog
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
                                    color: isDarkDialog
                                        ? cDarkIconColor
                                        : Colors.black.withAlpha(191),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Divider(
                              thickness: 1,
                              color: isDarkDialog
                                  ? cDarkBorderColor.withAlpha(166)
                                  : Colors.white.withAlpha(128),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Location services are currently disabled on your device. Please enable location services in your device settings to log your visit.',
                              style: TextStyle(
                                color: isDarkDialog
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
                                    onTap: () => Get.back(result: false),
                                    child: Container(
                                      height: 44,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        color: isDarkDialog
                                            ? cDarkInputFillColor
                                            : Colors.white.withAlpha(153),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'Cancel',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: isDarkDialog
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
            barrierColor: Colors.black.withAlpha(isDarkDialog ? 128 : 77),
          );
        } else {
          // iOS: Just open location settings directly
          _log('📍 iOS: Opening location settings directly', tag: 'LogVisit');
          enable = true;
        }

        if (enable == true) {
          _log('📍 User chose to open location settings', tag: 'LogVisit');
          await Geolocator.openLocationSettings();
        }
        return;
      }

      // Check current permission status
      PermissionStatus status = await Permission.locationWhenInUse.status;
      LocationPermission geoPermission = await Geolocator.checkPermission();
      _log(
        '📍 Current permission status: ${status.name}, Geolocator: ${geoPermission.name}',
        tag: 'LogVisit',
      );

      // If permission is denied (not permanently), show explanation dialog first
      if (status.isDenied) {
        _log(
          '📍 Showing location permission explanation dialog',
          tag: 'LogVisit',
        );

        // Only show custom dialog on Android
        bool? shouldRequest;
        if (Platform.isAndroid) {
          final isDarkDialog =
              Theme.of(Get.context!).brightness == Brightness.dark;
          shouldRequest = await Get.dialog<bool>(
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
                        colors: isDarkDialog
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
                          color: Colors.black.withAlpha(isDarkDialog ? 77 : 38),
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
                                      color: isDarkDialog
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
                                    color: isDarkDialog
                                        ? cDarkIconColor
                                        : Colors.black.withAlpha(191),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Divider(
                              thickness: 1,
                              color: isDarkDialog
                                  ? cDarkBorderColor.withAlpha(166)
                                  : Colors.white.withAlpha(128),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Why we need your location',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: isDarkDialog
                                    ? cDarkTextPrimary
                                    : Colors.black.withAlpha(217),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Your location is used only while the app is open to:',
                              style: TextStyle(
                                color: isDarkDialog
                                    ? cDarkTextSecondary
                                    : Colors.black.withAlpha(191),
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildLocationUsageRow(
                              Icons.pin_drop_outlined,
                              'Verify you are at the site location',
                            ),
                            const SizedBox(height: 8),
                            _buildLocationUsageRow(
                              Icons.assignment_outlined,
                              'Log your visit with accurate coordinates',
                            ),
                            const SizedBox(height: 8),
                            _buildLocationUsageRow(
                              Icons.track_changes_outlined,
                              'Calculate distance to site',
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
                                      'Your location is securely sent to your employer\'s system and used only for site visit verification.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDarkDialog
                                            ? cDarkTextSecondary
                                            : Colors.black.withAlpha(191),
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
                                        color: isDarkDialog
                                            ? cDarkInputFillColor
                                            : Colors.white.withAlpha(153),
                                        border: Border.all(
                                          color: isDarkDialog
                                              ? cDarkBorderColor
                                              : Colors.black.withAlpha(26),
                                          width: 1,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'Not Now',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: isDarkDialog
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
            barrierColor: Colors.black.withAlpha(isDarkDialog ? 128 : 77),
          );
        } else {
          // iOS: Skip custom dialog, system dialog will show with Info.plist explanation
          _log(
            '📍 iOS: Skipping custom dialog, requesting permission directly',
            tag: 'LogVisit',
          );
          shouldRequest = true;
        }

        if (shouldRequest != true) {
          _log(
            '📍 User declined location access from explanation dialog',
            tag: 'LogVisit',
          );
          return;
        }

        _log(
          '📍 User agreed to explanation, now requesting permission from system',
          tag: 'LogVisit',
        );
        geoPermission = await Geolocator.requestPermission();
        _log(
          '📍 Geolocator permission request result: ${geoPermission.name}',
          tag: 'LogVisit',
        );

        status = await Permission.locationWhenInUse.status;
        _log(
          '📍 Updated permission_handler status: ${status.name}',
          tag: 'LogVisit',
        );
      }

      // Handle permanently denied
      if (status.isPermanentlyDenied ||
          geoPermission == LocationPermission.deniedForever) {
        _log(
          '📍 Location permission permanently denied, showing settings dialog',
          tag: 'LogVisit',
        );
        locationPermissionStatus.value =
            LocationPermissionStatus.permanentlyDenied;

        // Show custom dialog on both iOS and Android to ask before opening settings
        final isDarkDialog =
            Theme.of(Get.context!).brightness == Brightness.dark;
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
                      colors: isDarkDialog
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
                        color: Colors.black.withAlpha(isDarkDialog ? 77 : 38),
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
                                  color: Colors.red.withAlpha(26),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.location_off_outlined,
                                  color: Colors.red.shade700,
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
                                    color: isDarkDialog
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
                                  color: isDarkDialog
                                      ? cDarkIconColor
                                      : Colors.black.withAlpha(191),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Divider(
                            thickness: 1,
                            color: isDarkDialog
                                ? cDarkBorderColor.withAlpha(166)
                                : Colors.white.withAlpha(128),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Location access was denied',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isDarkDialog
                                  ? cDarkTextPrimary
                                  : Colors.black.withAlpha(217),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'To log site visits and verify your location, you need to enable location permissions in your device settings:',
                            style: TextStyle(
                              color: isDarkDialog
                                  ? cDarkTextSecondary
                                  : Colors.black.withAlpha(191),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withAlpha(13),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.red.withAlpha(51),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.settings_outlined,
                                  size: 20,
                                  color: Colors.red.shade700,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    Platform.isIOS
                                        ? 'Settings > Apps > SmartNPS360 > Location > Allow only while using the app'
                                        : 'Settings > Apps > SmartNPS360 > Permissions > Location > Allow only while using the app',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: isDarkDialog
                                          ? cDarkTextSecondary
                                          : Colors.black.withAlpha(191),
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
                                      color: isDarkDialog
                                          ? cDarkInputFillColor
                                          : Colors.white.withAlpha(153),
                                      border: Border.all(
                                        color: isDarkDialog
                                            ? cDarkBorderColor
                                            : Colors.black.withAlpha(26),
                                        width: 1,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Not Now',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: isDarkDialog
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
          barrierColor: Colors.black.withAlpha(isDarkDialog ? 128 : 77),
        );

        if (open == true) {
          _log('📍 User chose to open app settings', tag: 'LogVisit');
          await openAppSettings();
        }
        return;
      }

      // Check if permission is granted
      if (geoPermission == LocationPermission.whileInUse ||
          geoPermission == LocationPermission.always) {
        _log(
          '📍 Location permission granted, fetching location',
          tag: 'LogVisit',
        );
        locationPermissionStatus.value = LocationPermissionStatus.granted;
        // Fetch location and site data
        await Future.wait([getCurrentLocation(), fetchSiteCoordinates()]);
      } else {
        _log(
          '📍 Location permission not granted: ${geoPermission.name}',
          tag: 'LogVisit',
        );
        locationPermissionStatus.value = LocationPermissionStatus.denied;
      }
    } catch (e) {
      _log('Error requesting location permission', tag: 'LogVisit', error: e);
      AppSnackBar.show(
        Get.context!,
        type: SnackBarType.error,
        'Failed to request location permission',
      );
    }
  }

  /// Helper widget to build location usage row with icon
  Widget _buildLocationUsageRow(IconData icon, String text) {
    final isDark = Theme.of(Get.context!).brightness == Brightness.dark;
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
              color: isDark ? cDarkTextSecondary : Colors.black.withAlpha(191),
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  /// Get current user location
  Future<void> getCurrentLocation() async {
    _log('\n--- Getting Current Location ---', tag: 'LogVisit');
    if (locationPermissionStatus.value != LocationPermissionStatus.granted) {
      _log('Permission not granted, skipping location fetch', tag: 'LogVisit');
      return;
    }

    isLoadingLocation.value = true;
    _log('Loading location...', tag: 'LogVisit');
    try {
      // First check if location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _log('✗ Location service is not enabled', tag: 'LogVisit');
        AppSnackBar.show(
          Get.context!,
          type: SnackBarType.error,
          'Please turn on location services in your device settings',
        );
        isLoadingLocation.value = false;
        return;
      }

      _log(
        'Location service is enabled, fetching position...',
        tag: 'LogVisit',
      );
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      currentLocation.value = position;
      _updateTimeAgo();
      _calculateDistanceAndCheckRange();
      _updateMarkers();

      // Animate camera to new position if map is initialized
      if (_isMapInitialized && mapController != null) {
        try {
          _log(
            'Map initialized, animating camera to new position',
            tag: 'LogVisit',
          );
          mapController!.animateCamera(
            CameraUpdate.newLatLng(
              LatLng(position.latitude, position.longitude),
            ),
          );
        } catch (e) {
          _log('⚠ Could not animate camera', tag: 'LogVisit', error: e);
        }
      } else {
        _log(
          'Map not yet initialized, skipping camera animation',
          tag: 'LogVisit',
        );
      }

      _log(
        '✓ Current location: ${position.latitude}, ${position.longitude}',
        tag: 'LogVisit',
      );
      _log('✓ Accuracy: ${position.accuracy}m', tag: 'LogVisit');
    } on LocationServiceDisabledException catch (e) {
      _log('✗ Location service disabled', tag: 'LogVisit', error: e);
      AppSnackBar.show(
        Get.context!,
        type: SnackBarType.error,
        'Location service is disabled. Please enable it in device settings',
      );
    } on PermissionDeniedException catch (e) {
      _log('✗ Permission denied', tag: 'LogVisit', error: e);
      AppSnackBar.show(
        Get.context!,
        type: SnackBarType.error,
        'Location permission denied. Please grant location access',
      );
    } on TimeoutException catch (e) {
      _log('✗ Timeout getting location', tag: 'LogVisit', error: e);
      AppSnackBar.show(
        Get.context!,
        type: SnackBarType.error,
        'Location request timed out. Make sure GPS is enabled',
      );
    } catch (e) {
      _log('✗ Error getting current location', tag: 'LogVisit', error: e);
      String errorMessage = e.toString().replaceFirst('Exception: ', '');
      AppSnackBar.show(
        Get.context!,
        type: SnackBarType.error,
        errorMessage.isEmpty
            ? 'Failed to fetch location. Please try again.'
            : errorMessage,
      );
    } finally {
      isLoadingLocation.value = false;
      _log('--- Location Fetch Complete ---\n', tag: 'LogVisit');
    }
  }

  /// Callback when map is created
  void onMapCreated(GoogleMapController controller) {
    _log('\n--- Map Created Callback ---', tag: 'LogVisit');
    if (_isMapInitialized) {
      _log('⚠ Map already initialized, skipping', tag: 'LogVisit');
      return; // Prevent multiple initializations
    }

    mapController = controller;
    _isMapInitialized = true;
    _log('✓ Map controller initialized', tag: 'LogVisit');
    _updateMarkers();

    // Delay animation to ensure map is fully loaded
    Future.delayed(const Duration(milliseconds: 800), () {
      _log('Animating camera to show both locations', tag: 'LogVisit');
      _animateToShowBothLocations();
      // Mark map as ready after positioning
      Future.delayed(const Duration(milliseconds: 500), () {
        isMapReady.value = true;
        _log('✓ Map is ready', tag: 'LogVisit');
      });
    });
    _log('--- Map Creation Complete ---\n', tag: 'LogVisit');
  }

  /// Update markers on map
  void _updateMarkers() {
    markers.clear();
    circles.clear();
    _calculateDistanceAndCheckRange();

    final location = currentLocation.value;
    final siteCoords = siteCoordinates.value;

    // Add user location marker (if available)
    if (location != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('user_location'),
          position: LatLng(location.latitude, location.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(
            title: 'Your Location',
            snippet: 'You are here',
          ),
        ),
      );
    }

    // Add site location marker and radius circle (if available)
    if (siteCoords != null) {
      final siteLat = siteCoords['latitude'] as double;
      final siteLng = siteCoords['longitude'] as double;

      markers.add(
        Marker(
          markerId: const MarkerId('site_location'),
          position: LatLng(siteLat, siteLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(
            title: 'Site Location',
            snippet: 'Assignment site',
          ),
        ),
      );

      // Add 200m radius circle around site
      circles.add(
        Circle(
          circleId: const CircleId('site_radius'),
          center: LatLng(siteLat, siteLng),
          radius: 200, // 200 meters
          fillColor: const Color(0xFF2196F3).withAlpha(51),
          strokeColor: const Color(0xFF2196F3),
          strokeWidth: 2,
        ),
      );
    }
  }

  /// Animate camera to show both user and site locations
  void _animateToShowBothLocations() {
    // Safety checks
    if (!_isMapInitialized || mapController == null) {
      _log('⚠ Cannot animate: map not initialized', tag: 'LogVisit');
      return;
    }

    final location = currentLocation.value;
    final siteCoords = siteCoordinates.value;

    if (location == null) {
      _log('⚠ Cannot animate: missing user location', tag: 'LogVisit');
      return;
    }

    try {
      // If no site coordinates, just show user location
      if (siteCoords == null || siteCoords.isEmpty) {
        mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(location.latitude, location.longitude),
            16, // Good default zoom level
          ),
        );
        _log(
          '✓ Camera animated to user location (no site coords)',
          tag: 'LogVisit',
        );
        return;
      }

      // Calculate bounds to show both markers
      final siteLat = siteCoords['latitude'] as double;
      final siteLng = siteCoords['longitude'] as double;

      // Calculate distance between points
      final distance = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        siteLat,
        siteLng,
      );

      _log(
        'Distance between markers: ${distance.toStringAsFixed(2)}m',
        tag: 'LogVisit',
      );

      // If points are very close (less than 100m), center between them with good zoom
      if (distance < 100) {
        final centerLat = (location.latitude + siteLat) / 2;
        final centerLng = (location.longitude + siteLng) / 2;

        mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(centerLat, centerLng),
            17, // Good zoom level for close points
          ),
        );
        _log('✓ Points are close, centered between them', tag: 'LogVisit');
      } else if (distance > 50000) {
        // If distance is more than 50km, something might be wrong, just show user location
        mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(location.latitude, location.longitude),
            15,
          ),
        );
        _log(
          '⚠ Points are very far (${(distance / 1000).toStringAsFixed(2)}km), showing user location',
          tag: 'LogVisit',
        );
      } else {
        // Calculate bounds for moderate distances
        final minLat = location.latitude < siteLat
            ? location.latitude
            : siteLat;
        final maxLat = location.latitude > siteLat
            ? location.latitude
            : siteLat;
        final minLng = location.longitude < siteLng
            ? location.longitude
            : siteLng;
        final maxLng = location.longitude > siteLng
            ? location.longitude
            : siteLng;

        // Add small buffer to prevent bounds being too tight
        final latBuffer = (maxLat - minLat) * 0.1; // 10% buffer
        final lngBuffer = (maxLng - minLng) * 0.1;

        final bounds = LatLngBounds(
          southwest: LatLng(minLat - latBuffer, minLng - lngBuffer),
          northeast: LatLng(maxLat + latBuffer, maxLng + lngBuffer),
        );

        // Use larger padding to prevent extreme zoom out
        mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
        _log(
          '✓ Camera animated to show both locations with buffered bounds',
          tag: 'LogVisit',
        );
      }
    } catch (e) {
      // If animation fails, fall back to showing user location
      _log('⚠ Could not animate camera', tag: 'LogVisit', error: e);
      try {
        mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(location.latitude, location.longitude),
            16,
          ),
        );
        _log('✓ Fallback: Centered on user location', tag: 'LogVisit');
      } catch (e2) {
        _log('⚠ Fallback also failed', tag: 'LogVisit', error: e2);
      }
    }
  }

  /// Refresh location manually
  Future<void> refreshLocation() async {
    _log('\n🔄 === MANUAL REFRESH TRIGGERED ===', tag: 'LogVisit');
    // Only refresh user location, not site coordinates (they don't change)
    await getCurrentLocation();
    _log('🔄 === REFRESH COMPLETE ===\n', tag: 'LogVisit');
  }

  /// Fetch site coordinates from API
  Future<void> fetchSiteCoordinates() async {
    _log('\n--- Fetching Site Coordinates ---', tag: 'LogVisit');
    isLoadingSiteData.value = true;
    try {
      // Call API: apiurl.sites with assignment.id
      final url = '${ApiURL.sites}/$siteId';
      _log('API URL: $url', tag: 'LogVisit');
      final response = await _apiService.getData(url);
      _log('API Response received: ${response != null}', tag: 'LogVisit');

      if (response != null) {
        // Parse the response to get coordinates
        if (response is Map<String, dynamic>) {
          // Check if response has data key
          final data = response['data'] ?? response;
          _log(
            'Response data keys: ${data is Map ? (data).keys.toList() : "Not a map"}',
            tag: 'LogVisit',
          );

          if (data is Map<String, dynamic>) {
            // Check for gps_coordinates string format: "37.777436,-122.395819"
            if (data['gps_coordinates'] != null &&
                data['gps_coordinates'] is String) {
              _log(
                'Found gps_coordinates field: ${data['gps_coordinates']}',
                tag: 'LogVisit',
              );
              final gpsString = data['gps_coordinates'] as String;
              final parts = gpsString.split(',');

              if (parts.length == 2) {
                try {
                  final lat = double.parse(parts[0].trim());
                  final lng = double.parse(parts[1].trim());

                  siteCoordinates.value = {'latitude': lat, 'longitude': lng};
                  _log(
                    '✓ Site coordinates parsed: ${siteCoordinates.value}',
                    tag: 'LogVisit',
                  );
                  _updateMarkers();
                  // Don't animate camera here - it causes disposal errors
                  // Camera will be positioned in onMapCreated callback
                  return;
                } catch (e) {
                  _log(
                    '✗ Error parsing gps_coordinates',
                    tag: 'LogVisit',
                    error: e,
                  );
                }
              }
            }

            // Try to extract coordinates - other possible formats
            final coordinates =
                data['coordinates'] ??
                data['location'] ??
                data['gpsLocation'] ??
                data;

            if (coordinates is Map<String, dynamic>) {
              // Extract latitude and longitude
              final lat =
                  coordinates['latitude'] ??
                  coordinates['lat'] ??
                  coordinates['y'];
              final lng =
                  coordinates['longitude'] ??
                  coordinates['lng'] ??
                  coordinates['lon'] ??
                  coordinates['x'];

              if (lat != null && lng != null) {
                siteCoordinates.value = {
                  'latitude': lat is num
                      ? lat.toDouble()
                      : double.parse(lat.toString()),
                  'longitude': lng is num
                      ? lng.toDouble()
                      : double.parse(lng.toString()),
                };
                _log(
                  'Site coordinates: ${siteCoordinates.value}',
                  tag: 'LogVisit',
                );
                _updateMarkers();
                // Don't animate camera here
              }
            } else if (data['latitude'] != null && data['longitude'] != null) {
              // Direct latitude/longitude in data
              siteCoordinates.value = {
                'latitude': data['latitude'] is num
                    ? data['latitude'].toDouble()
                    : double.parse(data['latitude'].toString()),
                'longitude': data['longitude'] is num
                    ? data['longitude'].toDouble()
                    : double.parse(data['longitude'].toString()),
              };
              _log(
                'Site coordinates: ${siteCoordinates.value}',
                tag: 'LogVisit',
              );
              _updateMarkers();
              // Don't animate camera here
            }
          }
        }
      }
    } catch (e) {
      _log('Error fetching site coordinates', tag: 'LogVisit', error: e);
      AppSnackBar.show(
        Get.context!,
        type: SnackBarType.error,
        'Failed to fetch site coordinates',
      );
    } finally {
      isLoadingSiteData.value = false;
    }
  }

  /// Calculate distance and check if within 200m range
  void _calculateDistanceAndCheckRange() {
    if (currentLocation.value == null || siteCoordinates.value == null) {
      distanceToSite.value = 0.0;
      isWithinRange.value = false;
      return;
    }

    final userLat = currentLocation.value!.latitude;
    final userLng = currentLocation.value!.longitude;
    final siteLat = siteCoordinates.value!['latitude'] as double;
    final siteLng = siteCoordinates.value!['longitude'] as double;

    // Calculate distance using Haversine formula
    final distance = Geolocator.distanceBetween(
      userLat,
      userLng,
      siteLat,
      siteLng,
    );
    distanceToSite.value = distance;
    isWithinRange.value = distance <= 200;

    _log(
      '📏 Distance to site: ${distance.toStringAsFixed(2)}m - Within range: ${isWithinRange.value}',
      tag: 'LogVisit',
    );
  }

  /// Calculate distance between user location and site coordinates (for backward compatibility)
  double calculateDistance() {
    return distanceToSite.value;
  }

  /// Open app settings
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  /// Log visit - fetch fresh location and submit to API
  Future<void> logVisit() async {
    _log('\n🚀 === LOG VISIT STARTED ===', tag: 'LogVisit');
    _log('Schedule ID: $scheduleId', tag: 'LogVisit');
    _log('Site ID: $siteId', tag: 'LogVisit');

    isLoggingVisit.value = true;

    try {
      // Step 1: Validate site coordinates are available
      if (siteCoordinates.value == null) {
        _log('❌ Site coordinates not available', tag: 'LogVisit');
        AppSnackBar.show(
          Get.context!,
          type: SnackBarType.error,
          'Site location not available. Please try refreshing.',
        );
        return;
      }

      // Step 2: Fetch fresh location
      _log('📍 Fetching fresh location...', tag: 'LogVisit');
      Position freshPosition;

      try {
        freshPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
        _log(
          '✓ Fresh location obtained: ${freshPosition.latitude}, ${freshPosition.longitude}',
          tag: 'LogVisit',
        );
      } catch (e) {
        _log('❌ Failed to get fresh location', tag: 'LogVisit', error: e);
        AppSnackBar.show(
          Get.context!,
          type: SnackBarType.error,
          'Failed to get current location. Please try again.',
        );
        return;
      }

      // Step 3: Calculate distance with fresh location and verify 200m range
      final siteLat = siteCoordinates.value!['latitude'] as double;
      final siteLng = siteCoordinates.value!['longitude'] as double;
      final freshDistance = Geolocator.distanceBetween(
        freshPosition.latitude,
        freshPosition.longitude,
        siteLat,
        siteLng,
      );

      _log(
        '📏 Fresh distance calculated: ${freshDistance.toStringAsFixed(2)}m',
        tag: 'LogVisit',
      );

      // Critical validation: Check if user is within 200m
      if (freshDistance > 200) {
        _log(
          '❌ User is ${freshDistance.toStringAsFixed(0)}m away - Outside 200m range',
          tag: 'LogVisit',
        );
        AppSnackBar.show(
          Get.context!,
          type: SnackBarType.error,
          'You are ${freshDistance.toStringAsFixed(0)}m away from the site. Please move within 200m to log your visit.',
        );

        // Update the UI with fresh location data
        currentLocation.value = freshPosition;
        _calculateDistanceAndCheckRange();
        _updateMarkers();
        return;
      }

      _log(
        '✓ Distance check passed - User is within 200m range',
        tag: 'LogVisit',
      );

      // Step 2: Get device information
      _log('📱 Fetching device information...', tag: 'LogVisit');
      final deviceInfo = DeviceInfoPlugin();
      String deviceId = 'unknown';
      String deviceModel = 'unknown';
      String deviceOs = 'unknown';

      try {
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          // Use androidId or device fingerprint as ID
          deviceId = androidInfo.id.isNotEmpty
              ? androidInfo.id
              : '${androidInfo.brand}-${androidInfo.device}-${androidInfo.model}'
                    .toLowerCase();
          deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}';
          deviceOs = 'Android ${androidInfo.version.release}';

          _log('✓ Device info retrieved:', tag: 'LogVisit');
          _log('  ID: $deviceId', tag: 'LogVisit');
          _log('  Model: $deviceModel', tag: 'LogVisit');
          _log('  OS: $deviceOs', tag: 'LogVisit');
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          deviceId =
              iosInfo.identifierForVendor ??
              'ios-${iosInfo.name}-${iosInfo.model}';
          deviceModel = '${iosInfo.name} ${iosInfo.model}';
          deviceOs = 'iOS ${iosInfo.systemVersion}';

          _log('✓ Device info retrieved:', tag: 'LogVisit');
          _log('  ID: $deviceId', tag: 'LogVisit');
          _log('  Model: $deviceModel', tag: 'LogVisit');
          _log('  OS: $deviceOs', tag: 'LogVisit');
        }
      } catch (e) {
        _log('⚠ Failed to get device info', tag: 'LogVisit', error: e);
        _log('Stack trace: ${StackTrace.current}', tag: 'LogVisit');
        // Even on error, try to provide some basic info
        if (Platform.isAndroid) {
          deviceOs = 'Android';
          deviceModel = 'Android Device';
          deviceId = 'Unknown';
        } else if (Platform.isIOS) {
          deviceOs = 'iOS';
          deviceModel = 'iOS Device';
          deviceId = 'Unknown';
        }
      }

      // Step 3: Prepare API payload
      // Get officer_id from UserController
      final userController = Get.find<UserController>();
      final profile = userController.profileData.value ?? {};
      final officerId = profile['id'] ?? 0;

      final payload = {
        'schedule_id': scheduleId,
        'officer_id': officerId,
        'latitude': freshPosition.latitude,
        'longitude': freshPosition.longitude,
        'device_id': deviceId,
        'device_model': deviceModel,
        'device_os': deviceOs,
        'browser': Platform.isAndroid || Platform.isIOS
            ? 'Mobile App'
            : 'WebView',
      };

      _log('📤 Sending log visit request...', tag: 'LogVisit');
      _log('Payload: $payload', tag: 'LogVisit');

      // Step 4: Call API
      final response = await _apiService.postData(ApiURL.logVisit, payload);

      // ignore: unnecessary_null_comparison
      _log('📥 API Response received: ${response != null}', tag: 'LogVisit');

      // Extract data from response (handle both Response object and Map)
      final responseData = response is Map<String, dynamic>
          ? response
          : (response as dynamic).data;

      if (responseData != null && responseData is Map<String, dynamic>) {
        // Check for both 'status' and 'success' fields
        final isSuccess =
            responseData['status'] == 'success' ||
            responseData['success'] == true;

        if (isSuccess) {
          _log('✅ Visit logged successfully', tag: 'LogVisit');
          AppSnackBar.show(
            Get.context!,
            type: SnackBarType.success,
            'Visit logged successfully!',
          );

          // Update current location with fresh position
          currentLocation.value = freshPosition;
          _updateTimeAgo();
          _updateMarkers();
        } else {
          final message = responseData['message'] ?? 'Failed to log visit';
          _log('❌ API returned error: $message', tag: 'LogVisit');
          AppSnackBar.show(Get.context!, type: SnackBarType.error, message);
        }
      } else {
        _log('❌ Invalid API response data', tag: 'LogVisit');
        AppSnackBar.show(
          Get.context!,
          type: SnackBarType.error,
          'Failed to log visit. Please try again.',
        );
      }
    } catch (e) {
      _log('❌ Error logging visit', tag: 'LogVisit', error: e);
      String errorMessage = e.toString().replaceFirst('Exception: ', '');
      AppSnackBar.show(
        Get.context!,
        type: SnackBarType.error,
        errorMessage.isEmpty
            ? 'Failed to log visit. Please try again.'
            : errorMessage,
      );
    } finally {
      isLoggingVisit.value = false;
      _log('🚀 === LOG VISIT COMPLETED ===\n', tag: 'LogVisit');
    }
  }
}
// 300 meters away
// 37.791042, -122.406486

// 📍 400 meters away
// 37.791942, -122.406486
