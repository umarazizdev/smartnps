// lib/Services/notification_manager.dart
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:smartnps360/src/screens/controllers/memory_storage_controller.dart';
import 'package:smartnps360/src/screens/services/local_notification_service.dart';
import 'package:smartnps360/src/screens/utilities/sf_time.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationManager {
  NotificationManager._();
  static final NotificationManager instance = NotificationManager._();

  bool _inited = false;
  bool _schedulingLock = false;

  static const String _shiftSignatureKey = 'lastShiftSignature';

  // =========================================================
  // INIT
  // =========================================================

  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    await LocalNotificationService.instance.init();
  }

  Future<bool> requestPermissionsIfNeeded() async {
    await init();
    return await LocalNotificationService.instance.requestPermissionIfNeeded();
  }

  Future<bool> isPermissionGranted() async {
    await init();
    return await LocalNotificationService.instance.isPermissionGranted();
  }

  /// Clear the permission request tracking flag
  /// Useful for testing or resetting permission state
  void clearPermissionCache() {
    final box = GetStorage();
    box.remove('askedForNotificationPermission');
    developer.log(
      '🔔 Cleared notification permission cache',
      name: 'NotificationManager',
    );
  }

  Future<void> cancelAll() async {
    await LocalNotificationService.instance.cancelAll();
  }

  Future<void> cancelBreak() async {
    await LocalNotificationService.instance.cancelBreakReminder();
  }

  Future<void> cancel(int id) async {
    await LocalNotificationService.instance.cancel(id);
  }

  // =========================================================
  // SIGNATURE BASED SAFE SCHEDULING
  // =========================================================

  String _buildShiftSignature({
    required DateTime? shiftStart,
    required DateTime? shiftEnd,
    required bool breakActive,
    required DateTime? breakStart,
    required int breakDurationSeconds,
    required int minutesBefore,
  }) {
    return [
      shiftStart?.toIso8601String() ?? '',
      shiftEnd?.toIso8601String() ?? '',
      breakActive,
      breakStart?.toIso8601String() ?? '',
      breakDurationSeconds,
      minutesBefore,
    ].join('|');
  }

  /// Called from refreshServerSession
  Future<void> syncFromSession({
    required bool scopeComplete,
    required String siteName,
    required String shiftName,
    required DateTime? shiftStart,
    required DateTime? shiftEnd,
    required bool breakActive,
    required DateTime? breakStart,
    required int breakDurationSeconds,
    int minutesBefore = 10,
  }) async {
    await init();

    if (_schedulingLock) return;

    final box = GetStorage();

    if (!scopeComplete) {
      await LocalNotificationService.instance.cancelAllShiftRelated();
      await cancelBreak();
      box.remove(_shiftSignatureKey);
      return;
    }

    if (box.read('notificationsEnabled') != true) return;

    final granted = await _ensurePermissionForScheduling(showDialog: true);
    if (!granted) return;

    final newSignature = _buildShiftSignature(
      shiftStart: shiftStart,
      shiftEnd: shiftEnd,
      breakActive: breakActive,
      breakStart: breakStart,
      breakDurationSeconds: breakDurationSeconds,
      minutesBefore: minutesBefore,
    );

    final lastSignature = box.read(_shiftSignatureKey);

    // 🔥 Prevent duplicate scheduling
    if (lastSignature == newSignature) {
      return;
    }

    _schedulingLock = true;

    try {
      await LocalNotificationService.instance.cancelAllShiftRelated();
      await cancelBreak();

      if (shiftStart != null && shiftEnd != null) {
        var s = shiftStart;
        var e = shiftEnd;

        if (e.isBefore(s)) {
          e = e.add(const Duration(days: 1));
        }

        await LocalNotificationService.instance.scheduleShiftReminders(
          siteName: siteName,
          shiftName: shiftName,
          shiftStart: s,
          shiftEnd: e,
          minutesBefore: minutesBefore,
        );
      }

      if (breakActive && breakStart != null && breakDurationSeconds > 0) {
        await LocalNotificationService.instance.scheduleBreakEndReminder(
          breakStart: breakStart,
          breakDurationSeconds: breakDurationSeconds,
          minutesBefore: minutesBefore,
        );
      }

      box.write(_shiftSignatureKey, newSignature);
    } finally {
      _schedulingLock = false;
    }
  }

  /// Called from login or storage recovery
  Future<void> syncFromStorage({
    required bool scopeComplete,
    int minutesBefore = 10,
  }) async {
    await init();

    final box = GetStorage();
    if (box.read('notificationsEnabled') != true) return;

    final granted = await _ensurePermissionForScheduling(showDialog: false);
    if (!granted) return;

    final MemoryStorageController mem =
        Get.isRegistered<MemoryStorageController>()
        ? Get.find<MemoryStorageController>()
        : Get.put(MemoryStorageController());

    final startRaw = mem.getShiftStartTime();
    final endRaw = mem.getShiftEndTime();
    final siteName = mem.getSiteName();
    final shiftName = mem.getShiftName();

    DateTime? parseShift(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      if (s.isEmpty) return null;

      if (s.contains('T')) {
        return DateTime.tryParse(s);
      }

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

    final sStart = parseShift(startRaw);
    var sEnd = parseShift(endRaw);

    await syncFromSession(
      scopeComplete: scopeComplete,
      siteName: siteName,
      shiftName: shiftName,
      shiftStart: sStart,
      shiftEnd: sEnd,
      breakActive: false,
      breakStart: null,
      breakDurationSeconds: 0,
      minutesBefore: minutesBefore,
    );
  }

  /// ✅ BREAK ONLY (add this inside NotificationManager class)
  Future<void> scheduleBreakOnly({
    required bool scopeComplete,
    required DateTime breakStart,
    required int breakDurationSeconds,
    int minutesBefore = 10,
  }) async {
    await init();
    final box = GetStorage();
    if (box.read('notificationsEnabled') != true) return;

    final granted = await _ensurePermissionForScheduling(showDialog: true);
    if (!granted) return;

    // If invalid duration -> cancel only break reminder
    if (breakDurationSeconds <= 0) {
      await cancelBreak();
      return;
    }

    // Always replace the previous break reminder with the new one
    await cancelBreak();

    await LocalNotificationService.instance.scheduleBreakEndReminder(
      breakStart: breakStart,
      breakDurationSeconds: breakDurationSeconds,
      minutesBefore: minutesBefore,
    );
  }
  // =========================================================
  // TOGGLE HANDLER (UNCHANGED BUT SAFE)
  // =========================================================

  Future<bool> handleNotificationToggle(bool enabled) async {
    await init();
    final box = GetStorage();

    if (enabled) {
      final ok = await _ensurePermissionForScheduling(showDialog: true);
      if (!ok) {
        box.write('notificationsEnabled', false);
        return false;
      }

      box.write('notificationsEnabled', true);

      final MemoryStorageController mem =
          Get.isRegistered<MemoryStorageController>()
          ? Get.find<MemoryStorageController>()
          : Get.put(MemoryStorageController());

      final scopeComplete =
          mem.getRegionName().isNotEmpty && mem.getShiftName().isNotEmpty;

      await syncFromStorage(scopeComplete: scopeComplete, minutesBefore: 10);

      // await _maybeShowBatteryTipOptional();

      return true;
    } else {
      box.write('notificationsEnabled', false);
      await LocalNotificationService.instance.cancelAll();
      await LocalNotificationService.instance.cancelBreakReminder();
      box.remove(_shiftSignatureKey);
      return false;
    }
  }

  // =========================================================
  // PERMISSION HANDLING (STORE SAFE)
  // =========================================================

  Future<bool> _ensurePermissionForScheduling({
    required bool showDialog,
  }) async {
    developer.log(
      '🔔 Checking notification permission for scheduling...',
      name: 'NotificationManager',
    );

    final box = GetStorage();

    // First, check if permission is actually granted using native check
    final actuallyGranted = await LocalNotificationService.instance
        .isPermissionGranted();

    developer.log(
      '🔔 Native permission check result: $actuallyGranted',
      name: 'NotificationManager',
    );

    // If granted, we're good
    if (actuallyGranted) {
      developer.log('🔔 Permission granted', name: 'NotificationManager');
      // Mark that permission is granted
      box.write('askedForNotificationPermission', true);
      return true;
    }

    // Not granted, check the raw permission status to determine if first time or denied
    final status = await Permission.notification.status;

    developer.log(
      '🔔 Permission handler status: ${status.name}',
      name: 'NotificationManager',
    );

    final askedBefore = box.read('askedForNotificationPermission') == true;

    developer.log(
      '🔔 Asked before: $askedBefore, isPermanentlyDenied: ${status.isPermanentlyDenied}',
      name: 'NotificationManager',
    );

    // If permission was previously denied, need to go to settings
    if (askedBefore || status.isPermanentlyDenied) {
      developer.log(
        '🔔 Permission was denied previously, need to use Settings',
        name: 'NotificationManager',
      );

      if (showDialog) {
        // Show custom dialog before opening settings (both iOS and Android)
        developer.log(
          '🔔 Showing custom dialog before opening settings',
          name: 'NotificationManager',
        );

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
                                  color: Colors.red.withAlpha(26),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.notifications_off_outlined,
                                  color: Colors.red.shade700,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Notifications Disabled',
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
                            'Notification access was denied',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black.withAlpha(217),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'To receive shift reminders and important updates, you need to enable notification permissions in your device settings:',
                            style: TextStyle(
                              color: Colors.black.withAlpha(191),
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
                                        ? 'Settings > SmartNPS360 > Notifications > Allow Notifications'
                                        : 'Settings > Apps > SmartNPS360 > Notifications > Allow Notifications',
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

        if (open != true) {
          developer.log(
            '🔔 User cancelled opening settings',
            name: 'NotificationManager',
          );
          return false;
        }

        developer.log(
          '🔔 User chose to open settings',
          name: 'NotificationManager',
        );

        // Open app settings (both iOS and Android)
        developer.log(
          '🔔 Opening app settings...',
          name: 'NotificationManager',
        );
        await openAppSettings();

        // Wait for app to resume from background using polling
        developer.log(
          '🔔 Waiting for app to resume from background...',
          name: 'NotificationManager',
        );

        // Poll for app resume by checking if permission has changed
        final startStatus = status;
        var checkCount = 0;
        const maxChecks = 60; // Max 60 seconds
        const checkInterval = Duration(seconds: 1);

        bool appResumed = false;
        bool userReturnedWithoutGranting = false;

        while (checkCount < maxChecks &&
            !appResumed &&
            !userReturnedWithoutGranting) {
          await Future.delayed(checkInterval);
          checkCount++;

          // Check if app is back in foreground (user returned from Settings)
          final lifecycleState = WidgetsBinding.instance.lifecycleState;
          final isAppActive =
              lifecycleState == AppLifecycleState.resumed ||
              lifecycleState == null; // null means active on some platforms

          // Check if status has changed (indicating app likely resumed and user acted)
          final currentStatus = await Permission.notification.status;
          if (currentStatus != startStatus) {
            developer.log(
              '🔔 Permission status changed from ${startStatus.name} to ${currentStatus.name}',
              name: 'NotificationManager',
            );
            appResumed = true;
            break;
          }

          // Check if permission granted
          final freshCheck = await LocalNotificationService.instance
              .isPermissionGranted();
          if (freshCheck) {
            developer.log(
              '🔔 Permission detected as granted during polling',
              name: 'NotificationManager',
            );
            return true;
          }

          // If app is active and we've been polling for 2-3 seconds, assume user returned without granting
          if (isAppActive && checkCount >= 2) {
            developer.log(
              '🔔 App resumed but permission not granted - user likely returned without changing settings',
              name: 'NotificationManager',
            );
            userReturnedWithoutGranting = true;
            break;
          }
        }

        // After app resumes, check permission status
        developer.log(
          '🔔 Checking final permission status after resume/timeout',
          name: 'NotificationManager',
        );

        // Force re-check permission status from system
        final freshStatus = await Permission.notification.status;
        developer.log(
          '🔔 Fresh permission status: ${freshStatus.name}',
          name: 'NotificationManager',
        );

        // Check permission again
        final result = await LocalNotificationService.instance
            .isPermissionGranted();

        developer.log(
          '🔔 Permission after returning from settings: $result',
          name: 'NotificationManager',
        );

        return result;
      }
      return false;
    }

    // First time asking - for Android, show custom explanation dialog first
    if (Platform.isAndroid && showDialog) {
      developer.log(
        '🔔 Android first time request, showing custom explanation dialog',
        name: 'NotificationManager',
      );

      final userAgreed = await Get.dialog<bool>(
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
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Enable Notifications',
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
                      Divider(thickness: 1, color: Colors.white.withAlpha(128)),
                      const SizedBox(height: 16),
                      Text(
                        'Stay informed about your work schedule',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withAlpha(217),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'We\'ll send you timely reminders to help you stay on track:',
                        style: TextStyle(
                          color: Colors.black.withAlpha(191),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildNotificationUsageRow(
                        Icons.access_time_rounded,
                        'Shift start reminders',
                      ),
                      const SizedBox(height: 12),
                      _buildNotificationUsageRow(
                        Icons.notifications_active_outlined,
                        'Break end notifications',
                      ),
                      const SizedBox(height: 12),
                      _buildNotificationUsageRow(
                        Icons.schedule_rounded,
                        'Important updates',
                      ),
                      const SizedBox(height: 24),
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
                                    'Enable Notifications',
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
        barrierDismissible: false,
        barrierColor: Colors.black.withAlpha(77),
      );

      if (userAgreed != true) {
        developer.log(
          '🔔 User declined notification permission from custom dialog',
          name: 'NotificationManager',
        );
        // Mark that we've asked so next time shows settings dialog
        box.write('askedForNotificationPermission', true);
        return false;
      }

      developer.log(
        '🔔 User agreed, now showing system permission dialog',
        name: 'NotificationManager',
      );
    } else {
      // iOS: request permission directly (system dialog will show)
      developer.log(
        '🔔 iOS first time request, showing system permission dialog',
        name: 'NotificationManager',
      );
    }

    final granted = await LocalNotificationService.instance
        .requestPermissionIfNeeded();

    developer.log(
      '🔔 Permission result: $granted',
      name: 'NotificationManager',
    );

    // Mark that we've now asked
    box.write('askedForNotificationPermission', true);

    return granted;
  }

  // Helper method to build notification usage row in explanation dialog
  Widget _buildNotificationUsageRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF007AFF).withAlpha(13),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: const Color(0xFF007AFF)),
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
