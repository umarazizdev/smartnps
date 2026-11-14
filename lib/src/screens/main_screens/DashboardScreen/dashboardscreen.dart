// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'dart:developer' as developer;
import 'dart:developer' show log;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/controllers/dashboardcontroller.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/CalendarScreen/calendarcontroller.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/assignmentmodel.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/CalendarScreen/calendarmodel.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/timer_controller.dart';
import 'package:smartnps360/src/screens/main_screens/LogVisitScreen/logvisitscreen.dart';
import 'package:smartnps360/src/screens/services/local_notification_service.dart';
import 'package:smartnps360/src/screens/services/notification_manager.dart';
import 'package:smartnps360/src/screens/utilities/appsnackbar.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/utilities/sf_time.dart';
import 'package:smartnps360/src/screens/widgets/appheader.dart';
import 'package:smartnps360/src/screens/widgets/show_region_shift_dialog.dart';
import 'package:smartnps360/src/screens/controllers/scopecontroller.dart';
import 'package:smartnps360/src/screens/controllers/usercontroller.dart';
import 'package:smartnps360/src/screens/controllers/clock_in_window_controller.dart';
import 'package:smartnps360/src/screens/controllers/memory_storage_controller.dart';
import 'package:smartnps360/src/screens/main_screens/SettingsScreen/settingscontroller.dart';
import 'package:smartnps360/src/screens/app_storage.dart';
import 'package:smartnps360/src/screens/widgets/next_shift_card.dart';
import 'package:smartnps360/src/screens/widgets/upcoming_shifts_section.dart';
import 'package:shimmer/shimmer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:ui';

void _log(String msg, {String tag = 'APP', Object? error, StackTrace? stack}) {
  if (kDebugMode) {
    developer.log(msg, name: tag, error: error, stackTrace: stack);
  }
}

class DashBoardScreen extends StatefulWidget {
  const DashBoardScreen({super.key});

  @override
  State<DashBoardScreen> createState() => _DashBoardScreenState();
}

class _DashBoardScreenState extends State<DashBoardScreen> {
  final timeController = Get.find<TimeController>();
  final ClockInWindowController clockInWindow = Get.put(
    ClockInWindowController(),
    permanent: true,
  );
  final ScopeController sc = Get.isRegistered<ScopeController>()
      ? Get.find<ScopeController>()
      : Get.put(ScopeController());

  final DashboardController _dc = Get.put(
    DashboardController(),
    permanent: true,
  );
  final ScheduleMonthCalendarController calendarController =
      Get.isRegistered<ScheduleMonthCalendarController>()
      ? Get.find<ScheduleMonthCalendarController>()
      : Get.put(ScheduleMonthCalendarController());

  final RxBool isScopeSelected = false.obs;
  final RxBool attendanceProcessing = false.obs;
  final MemoryStorageController _mem =
      Get.isRegistered<MemoryStorageController>()
      ? Get.find<MemoryStorageController>()
      : Get.put(MemoryStorageController());

  bool get _isPatrolOfficer {
    final role = box.read('role');
    return role is String && role == patrolOfficer;
  }

  bool get _isOnSiteOfficer {
    final role = box.read('role');
    return role is String && role == onSiteOfficer;
  }

  @override
  void initState() {
    super.initState();
    ever<bool>(timeController.scopeSelected, (v) {
      isScopeSelected.value = v;
      if (v == true) {
        Future.microtask(() async {
          await _loadDashboardData(forceRefresh: _dc.firstLoad);
          if (_dc.firstLoad) _dc.markAsLoaded();
          await clockInWindow.forceRefresh();
        });
      }
    });

    Future.microtask(
      () => Get.find<UserController>().fetchProfileData(enableLoading: false),
    );
    isScopeSelected.value = _mem.getIsScopeSelected();

    timeController.notifyScopeChanged();

    if (_isPatrolOfficer) {
      _seedPatrolDummyCalendar();
    }

    if (isScopeSelected.value || _isOnSiteOfficer) {
      // if (_isOnSiteOfficer &&
      //     !Get.isRegistered<ScheduleMonthCalendarController>()) {
      //   Get.put(ScheduleMonthCalendarController());
      // }

      Future.microtask(() async {
        await _loadDashboardData(forceRefresh: _dc.firstLoad);
        if (_dc.firstLoad) {
          _dc.markAsLoaded();
        }

        await clockInWindow.forceRefresh();
        if (_isOnSiteOfficer && timeController.onDuty.value == false) {
          await timeController.showNoShiftDialogIfMissing();
        }
      });
    } else {
      Future.microtask(() => sc.fetchScopeLists());
    }
  }

  /// Seeds the [ScheduleMonthCalendarController] with dummy shift data so the
  /// calendar and next-shift card are visible for patrol officers while the
  /// real API integration is pending.
  void _seedPatrolDummyCalendar() {
    if (!Get.isRegistered<ScheduleMonthCalendarController>()) {
      Get.put(ScheduleMonthCalendarController(), permanent: true);
    }
    final ctrl = Get.find<ScheduleMonthCalendarController>();

    // Build a handful of dummy shifts spread across this and next month.
    final dummyShifts = <ShiftDay>[
      _dummyShift(
        id: 1,
        dayOffset: 0,
        start: '08:00',
        end: '16:00',
        title: 'Morning Patrol',
      ),
      _dummyShift(
        id: 2,
        dayOffset: 1,
        start: '14:00',
        end: '22:00',
        title: 'Afternoon Patrol',
      ),
      _dummyShift(
        id: 3,
        dayOffset: 3,
        start: '22:00',
        end: '06:00',
        title: 'Night Patrol',
        nextDay: true,
      ),
      _dummyShift(
        id: 4,
        dayOffset: 5,
        start: '08:00',
        end: '16:00',
        title: 'Morning Patrol',
      ),
      _dummyShift(
        id: 5,
        dayOffset: 7,
        start: '14:00',
        end: '22:00',
        title: 'Afternoon Patrol',
      ),
      _dummyShift(
        id: 6,
        dayOffset: 10,
        start: '08:00',
        end: '16:00',
        title: 'Morning Patrol',
      ),
      _dummyShift(
        id: 7,
        dayOffset: 14,
        start: '14:00',
        end: '22:00',
        title: 'Afternoon Patrol',
      ),
      _dummyShift(
        id: 8,
        dayOffset: 18,
        start: '22:00',
        end: '06:00',
        title: 'Night Patrol',
        nextDay: true,
      ),
    ];

    // Group by date key and write into calendarDays.
    final grouped = <DateTime, List<ShiftDay>>{};
    for (final s in dummyShifts) {
      final parts = s.date.split('-');
      if (parts.length != 3) continue;
      final key = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
      grouped.putIfAbsent(key, () => []).add(s);
    }
    for (final entry in grouped.entries) {
      ctrl.calendarDays[entry.key] = CalendarDay(
        date: entry.key.toIso8601String().split('T').first,
        count: entry.value.length,
        shifts: entry.value,
      );
    }
  }

  ShiftDay _dummyShift({
    required int id,
    required int dayOffset,
    required String start,
    required String end,
    required String title,
    bool nextDay = false,
  }) {
    final now = sfNow();
    final baseDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(days: dayOffset));
    final endDate = nextDay ? baseDate.add(const Duration(days: 1)) : baseDate;
    final dateStr =
        '${baseDate.year}-${baseDate.month.toString().padLeft(2, '0')}-${baseDate.day.toString().padLeft(2, '0')}';
    final startDt =
        '${baseDate.year}-${baseDate.month.toString().padLeft(2, '0')}-${baseDate.day.toString().padLeft(2, '0')}T$start:00';
    final endDt =
        '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}T$end:00';
    return ShiftDay(
      occurrenceId: id,
      seriesId: id,
      assignmentId: id,
      date: dateStr,
      workStatus: 'scheduled',
      status: 'Scheduled',
      rawStatus: 'scheduled',
      title: title,
      timeRange: '$start - $end',
      startDateTime: startDt,
      endDateTime: endDt,
      unpaidBreakMinutes: 0,
      paidBreakMinutes: 30,
      siteId: 0,
      siteName: 'Patrol Zone',
    );
  }

  Future<void> _loadDashboardData({bool forceRefresh = false}) async {
    final regionId = _mem.getRegionId();
    final shiftId = _mem.getShiftId();
    // ignore: unnecessary_null_comparison
    if (regionId != null && shiftId != null) {
      await _dc.fetchAssignments(regionId, shiftId, forceRefresh: forceRefresh);
    }

    if (_isPatrolOfficer) {
      _dc.syncPatrolShiftTimeToStorageIfMissing();

      return;
    }

    final hasCalendar = Get.isRegistered<ScheduleMonthCalendarController>();
    if (_isOnSiteOfficer) {
      if (hasCalendar) {
        await Get.find<ScheduleMonthCalendarController>().fetchShiftsForMonth(
          sfNow(),
          forceRefresh: forceRefresh,
        );
      }
      return;
    }

    if (hasCalendar) {
      Get.find<ScheduleMonthCalendarController>().fetchShiftsForMonth(
        sfNow(),
        forceRefresh: forceRefresh,
      );
    }
  }

  String _formatDuration(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _clockIn({double? latitude, double? longitude}) async {
    if (!_isOnSiteOfficer && !isScopeSelected.value) {
      showRegionShiftDialog(
        context,
        onSave: () async {
          // After the user saves a scope, load data first so the UI
          // doesn't show the selected-scope skeleton while data is being fetched.
          await _loadDashboardData();

          box.write('isScopeSelected', true);
          _mem.setIsScopeSelected(true);
          isScopeSelected.value = true;

          await Get.find<TimeController>().refreshServerSession();

          // timeController.notifyScopeChanged();

          await clockInWindow.forceRefresh();

          // Show notification permission prompt after first scope selection
          await _showNotificationOptInPrompt();

          await _clockIn(latitude: latitude, longitude: longitude);
        },
      );

      return;
    }

    if (_isPatrolOfficer) {
      _dc.syncPatrolShiftTimeToStorageIfMissing();
    }
    if (_isPatrolOfficer) {
      final s = _mem.getShiftStartTime();
      final e = _mem.getShiftEndTime();
      final hasTimes = (s.trim().isNotEmpty) && (e.trim().isNotEmpty);

      if (!hasTimes) {
        await _loadDashboardData();
      }
    }

    _log(
      "CLOCKIN: role=${box.read('role')} siteId=${_mem.getSiteId()} regionId=${_mem.getRegionId()} shiftId=${_mem.getShiftId()} seriesId=${_mem.getSeriesId()} start=${_mem.getShiftStartTime()} end=${_mem.getShiftEndTime()}",
      tag: 'Dashboard',
    );

    await clockInWindow.forceRefresh();
    await _showNotificationOptInPrompt();

    await timeController.clockIn(latitude: latitude, longitude: longitude);
    if (_isOnSiteOfficer) {
      await calendarController.fetchShiftsForMonth(
        sfNow(),
        forceRefresh: true,
        silentRefresh: true,
      );
    }
  }

  Future<void> _clearScopeState() async {
    if (_isPatrolOfficer) {
      await LocalNotificationService.instance.cancelAllShiftRelated();
      await NotificationManager.instance.cancelBreak();
    }
    const keys = [
      'isScopeSelected',
      'selectedShift',
      'selectedRegion',
      'selectedSite',
      'shiftStartTime',
      'shiftEndTime',
      'selectedShiftData',
      'selectedCalendarShift',
      'unpaidBreakMinutes',
      'paidBreakMinutes',
      'totalBreakMinutes',
      'siteId',
      'shiftId',
      'regionId',
    ];

    for (final k in keys) {
      box.remove(k);
    }

    sc.selectedShift.value = '';
    sc.selectedRegion.value = '';

    isScopeSelected.value = false;
    clockInWindow.forceRefresh();
    _mem.setRegionId(null);
    _mem.setShiftId(null);
    _mem.setSiteId(null);
    _mem.setSeriesId(null);
    _mem.setRegionName('');
    _mem.setShiftName('');
    _mem.setSiteName('');
    _mem.setIsScopeSelected(false);
    _mem.setShiftStartTime(null);
    _mem.setShiftEndTime(null);
  }

  Future<void> _clockOut({double? latitude, double? longitude}) async {
    final didClockOut = await timeController.clockOut(
      latitude: latitude,
      longitude: longitude,
    );

    if (!didClockOut) return;
    _clearScopeState();
    Future.microtask(() => sc.fetchScopeLists());

    if (_isOnSiteOfficer) {
      Get.find<ScheduleMonthCalendarController>().fetchShiftsForMonth(
        sfNow(),
        forceRefresh: true,
        silentRefresh: true,
      );
    }
    if (_isPatrolOfficer) {
      showRegionShiftDialog(
        // ignore: use_build_context_synchronously
        context,
        onSave: () async {
          box.write('isScopeSelected', true);
          _mem.setIsScopeSelected(true);
          isScopeSelected.value = true;

          // timeController.notifyScopeChanged();
          await _loadDashboardData();
          await Get.find<TimeController>().refreshServerSession();

          // Show notification permission prompt after first scope selection
          await _showNotificationOptInPrompt();
        },
        onCancel: () async {
          _clearScopeState();
        },
      );
    }
    await clockInWindow.forceRefresh();
  }

  Future<void> _startBreak({double? latitude, double? longitude}) async {
    await timeController.startBreak(latitude: latitude, longitude: longitude);
  }

  Future<void> _endBreak({double? latitude, double? longitude}) async {
    await timeController.endBreak(latitude: latitude, longitude: longitude);
  }

  Future<void> _showNotificationOptInPrompt() async {
    // Don't show if notifications are already enabled
    final notificationsEnabled = box.read('notificationsEnabled') ?? false;
    if (notificationsEnabled) return;

    // Don't show if user already made a choice
    final hasSeenPrompt = box.read('notificationPromptShown') ?? false;
    if (hasSeenPrompt) return;

    if (Platform.isIOS) {
      developer.log(
        '🔔 iOS: Skipping custom dialog, requesting system notification permission directly',
        name: 'Dashboard',
      );

      box.write('notificationPromptShown', true);

      final granted = await NotificationManager.instance
          .requestPermissionsIfNeeded();

      if (granted) {
        box.write('notificationsEnabled', true);

        // Update SettingsController toggle if registered
        if (Get.isRegistered<SettingsController>()) {
          Get.find<SettingsController>().notificationsEnabled.value = true;
        }

        developer.log(
          '🔔 iOS: User granted notification permission',
          name: 'Dashboard',
        );
      } else {
        developer.log(
          '🔔 iOS: User denied notification permission',
          name: 'Dashboard',
        );
      }
      return;
    }

    // Android: Show custom explanation dialog before system permission
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final result = await Get.dialog<bool>(
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
                  colors: isDarkMode
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
                    color: Colors.black.withAlpha(isDarkMode ? 77 : 38),
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
                              color:
                                  (isDarkMode
                                          ? const Color(0xFF3B82F6)
                                          : cPrimary)
                                      .withAlpha(26),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.notifications_outlined,
                              color: isDarkMode
                                  ? const Color(0xFF3B82F6)
                                  : cPrimary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Notification Access',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: isDarkMode
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
                              color: isDarkMode
                                  ? cDarkIconColor
                                  : Colors.black.withAlpha(191),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Divider(
                        thickness: 1,
                        color: isDarkMode
                            ? cDarkBorderColor.withAlpha(166)
                            : Colors.white.withAlpha(128),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Why we send notifications',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode
                              ? cDarkTextPrimary
                              : Colors.black.withAlpha(217),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Get timely reminders 10 minutes before:',
                        style: TextStyle(
                          color: isDarkMode
                              ? cDarkTextSecondary
                              : Colors.black.withAlpha(191),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildNotificationUsageRow(
                        Icons.work_outline,
                        'Your shift starts',
                      ),
                      const SizedBox(height: 8),
                      _buildNotificationUsageRow(
                        Icons.logout_outlined,
                        'Your shift ends',
                      ),
                      const SizedBox(height: 8),
                      _buildNotificationUsageRow(
                        Icons.coffee_outlined,
                        'Your break ends',
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color:
                              (isDarkMode ? const Color(0xFF3B82F6) : cPrimary)
                                  .withAlpha(13),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                (isDarkMode
                                        ? const Color(0xFF3B82F6)
                                        : cPrimary)
                                    .withAlpha(51),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 20,
                              color: isDarkMode
                                  ? const Color(0xFF3B82F6)
                                  : cPrimary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Stay on top of your schedule and never miss important work updates.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDarkMode
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
                            flex: 1,
                            child: GestureDetector(
                              onTap: () => Get.back(result: false),
                              child: Container(
                                height: 44,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: isDarkMode
                                      ? cDarkInputFillColor
                                      : Colors.white.withAlpha(153),
                                  border: Border.all(
                                    color: isDarkMode
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
                                      color: isDarkMode
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
                            flex: 2,
                            child: GestureDetector(
                              onTap: () => Get.back(result: true),
                              child: Container(
                                height: 44,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: isDarkMode
                                      ? const Color(0xFF3B82F6)
                                      : const Color(0xFF007AFF),
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
      ),
      barrierDismissible: false,
      barrierColor: Colors.black.withAlpha(isDarkMode ? 128 : 77),
    );

    box.write('notificationPromptShown', true);

    if (result == true) {
      final granted = await NotificationManager.instance
          .requestPermissionsIfNeeded();

      if (granted) {
        box.write('notificationsEnabled', true);

        // Update SettingsController toggle if registered
        if (Get.isRegistered<SettingsController>()) {
          Get.find<SettingsController>().notificationsEnabled.value = true;
        }

        developer.log(
          '🔔 User enabled notifications from prompt',
          name: 'Dashboard',
        );
      } else {
        final status = await Permission.notification.status;
        if (status.isPermanentlyDenied) {
          await openAppSettings();
        }
        developer.log(
          '🔔 User denied notifications from prompt',
          name: 'Dashboard',
        );
      }
    } else {
      developer.log(
        '🔔 User chose "Not Now" for notifications',
        name: 'Dashboard',
      );
    }
  }

  // Helper method to build notification usage row in explanation dialog
  Widget _buildNotificationUsageRow(IconData icon, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF3B82F6) : cPrimary).withAlpha(13),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isDark ? const Color(0xFF3B82F6) : cPrimary,
          ),
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

  Future<void> handleAttendance(String type) async {
    log('📍 Checking location permission status for attendance type: $type');

    // First check if location services are enabled on the device
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    log('📍 Location services enabled: $serviceEnabled');

    if (!serviceEnabled) {
      log('📍 Location services disabled, prompting user to enable');
      // Clear the asked flag so we'll ask again once services are enabled
      box.remove('askedLocationWhenInUse');
      if (!mounted) return;
      final isDarkMode = Theme.of(context).brightness == Brightness.dark;
      final enable = await Get.dialog<bool>(
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
                    colors: isDarkMode
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
                      color: Colors.black.withAlpha(isDarkMode ? 77 : 38),
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
                                  color: isDarkMode
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
                                color: isDarkMode
                                    ? cDarkIconColor
                                    : Colors.black.withAlpha(191),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Divider(
                          thickness: 1,
                          color: isDarkMode
                              ? cDarkBorderColor.withAlpha(166)
                              : Colors.white.withAlpha(128),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Location services are currently disabled on your device. Please enable location services in your device settings to use this feature.',
                          style: TextStyle(
                            color: isDarkMode
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
                                    color: isDarkMode
                                        ? cDarkInputFillColor
                                        : Colors.white.withAlpha(153),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Cancel',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: isDarkMode
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
                                    color: isDarkMode
                                        ? const Color(0xFF3B82F6)
                                        : const Color(0xFF007AFF),
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
        barrierColor: Colors.black.withAlpha(isDarkMode ? 128 : 77),
      );

      if (enable == true) {
        log('📍 User chose to open location settings');
        await Geolocator.openLocationSettings();
      }
      return;
    }

    PermissionStatus status = await Permission.locationWhenInUse.status;
    log('📍 Current permission status: ${status.name}');

    // Also check with Geolocator for comparison
    LocationPermission geoPermission = await Geolocator.checkPermission();
    log('📍 Geolocator permission status: ${geoPermission.name}');

    Position? pos;
    final bool askedBefore = (box.read('askedLocationWhenInUse') == true);
    log('📍 Asked for permission before: $askedBefore');

    // If permission is denied (not permanently), show explanation and request it
    if (status.isDenied && !askedBefore) {
      log(
        '📍 First time - showing explanation dialog before requesting permission',
      );

      // Show explanation dialog BEFORE requesting permission (Android only)
      bool? shouldRequest;
      if (Platform.isAndroid) {
        if (!mounted) return;
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
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
                      colors: isDarkMode
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
                        color: Colors.black.withAlpha(isDarkMode ? 77 : 38),
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
                                  color:
                                      (isDarkMode
                                              ? const Color(0xFF3B82F6)
                                              : cPrimary)
                                          .withAlpha(26),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.location_on_outlined,
                                  color: isDarkMode
                                      ? const Color(0xFF3B82F6)
                                      : cPrimary,
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
                                    color: isDarkMode
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
                                  color: isDarkMode
                                      ? cDarkIconColor
                                      : Colors.black.withAlpha(191),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Divider(
                            thickness: 1,
                            color: isDarkMode
                                ? cDarkBorderColor.withAlpha(166)
                                : Colors.white.withAlpha(128),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Why we need your location',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isDarkMode
                                  ? cDarkTextPrimary
                                  : Colors.black.withAlpha(217),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your location is used only while the app is open to verify:',
                            style: TextStyle(
                              color: isDarkMode
                                  ? cDarkTextSecondary
                                  : Colors.black.withAlpha(191),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildLocationUsageRow(
                            Icons.access_time_outlined,
                            'Clock-in and clock-out times',
                          ),
                          const SizedBox(height: 8),
                          _buildLocationUsageRow(
                            Icons.coffee_outlined,
                            'Break start and end times',
                          ),
                          const SizedBox(height: 8),
                          _buildLocationUsageRow(
                            Icons.assignment_outlined,
                            'Site visits and activity reports',
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  (isDarkMode
                                          ? const Color(0xFF3B82F6)
                                          : cPrimary)
                                      .withAlpha(13),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                    (isDarkMode
                                            ? const Color(0xFF3B82F6)
                                            : cPrimary)
                                        .withAlpha(51),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.security_outlined,
                                  size: 20,
                                  color: isDarkMode
                                      ? const Color(0xFF3B82F6)
                                      : cPrimary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Your location is securely sent to your employer\'s attendance system and not used for any other purpose.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDarkMode
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
                                      color: isDarkMode
                                          ? cDarkInputFillColor
                                          : Colors.white.withAlpha(153),
                                      border: Border.all(
                                        color: isDarkMode
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
                                          color: isDarkMode
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
                                      color: isDarkMode
                                          ? const Color(0xFF3B82F6)
                                          : const Color(0xFF007AFF),
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
          barrierColor: Colors.black.withAlpha(isDarkMode ? 128 : 77),
        );
      } else {
        // iOS: Skip custom dialog, system dialog will show with info from Info.plist
        log('📍 iOS: Skipping custom dialog, using system permission request');
        shouldRequest = true;
      }

      if (shouldRequest != true) {
        log('📍 User declined location access from explanation dialog');
        return;
      }

      log(
        '📍 User agreed to explanation, now requesting permission from system',
      );

      // Now request permission after user understands why
      geoPermission = await Geolocator.requestPermission();
      log('📍 Geolocator permission request result: ${geoPermission.name}');

      // Update the permission_handler status to match
      status = await Permission.locationWhenInUse.status;
      log('📍 Updated permission_handler status: ${status.name}');

      // Only mark as asked after we actually requested
      box.write('askedLocationWhenInUse', true);
    }

    // Handle permanently denied regardless of whether we asked before
    // This handles cases where permission was denied in a previous app session
    if (status.isPermanentlyDenied ||
        geoPermission == LocationPermission.deniedForever) {
      log('📍 Location permission permanently denied, showing settings dialog');

      // Show custom dialog on both iOS and Android to ask before opening settings
      if (!mounted) return;
      final isDarkMode = Theme.of(context).brightness == Brightness.dark;
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
                    colors: isDarkMode
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
                      color: Colors.black.withAlpha(isDarkMode ? 77 : 38),
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
                                  color: isDarkMode
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
                                color: isDarkMode
                                    ? cDarkIconColor
                                    : Colors.black.withAlpha(191),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Divider(
                          thickness: 1,
                          color: isDarkMode
                              ? cDarkBorderColor.withAlpha(166)
                              : Colors.white.withAlpha(128),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Location access was denied',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode
                                ? cDarkTextPrimary
                                : Colors.black.withAlpha(217),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'To use attendance tracking and location-based features, you need to enable location permissions in your device settings:',
                          style: TextStyle(
                            color: isDarkMode
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
                                    color: isDarkMode
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
                                    color: isDarkMode
                                        ? cDarkInputFillColor
                                        : Colors.white.withAlpha(153),
                                    border: Border.all(
                                      color: isDarkMode
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
                                        color: isDarkMode
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
                                    color: isDarkMode
                                        ? const Color(0xFF3B82F6)
                                        : const Color(0xFF007AFF),
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
        barrierColor: Colors.black.withAlpha(isDarkMode ? 128 : 77),
      );

      if (open == true) {
        log('📍 User chose to open app settings');
        await openAppSettings();
      } else {
        log('📍 User cancelled opening app settings');
      }
      return;
    }

    if (status.isDenied) {
      log('📍 Location permission denied, showing rationale dialog');

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
                              Expanded(
                                child: Text(
                                  'Location required',
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
                          const SizedBox(height: 8),
                          Divider(
                            thickness: 1,
                            color: Colors.white.withAlpha(128),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Location is used to verify your attendance and duty actions (clock-in, breaks, clock-out, and reports).',
                            style: TextStyle(
                              color: Colors.black.withAlpha(191),
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
          ),
          barrierDismissible: false,
          barrierColor: Colors.black.withAlpha(77),
        );
      } else {
        // iOS: Skip custom dialog, request permission directly
        log(
          '📍 iOS: Skipping rationale dialog, requesting permission directly',
        );
        should = true;
      }

      if (should != true) {
        log('📍 User cancelled permission request from rationale dialog');
        return;
      }

      log('📍 Requesting location permission after showing rationale');
      // Request permission again using Geolocator
      geoPermission = await Geolocator.requestPermission();
      log(
        '📍 Geolocator second permission request result: ${geoPermission.name}',
      );

      // Update permission_handler status
      status = await Permission.locationWhenInUse.status;
      log('📍 permission_handler second request result: ${status.name}');

      if (status.isPermanentlyDenied ||
          geoPermission == LocationPermission.deniedForever) {
        log(
          '📍 Location permission permanently denied after second request, showing settings dialog',
        );

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
                            'To use attendance tracking and location-based features, you need to enable location permissions in your device settings:',
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
                                        ? 'Settings > Apps > SmartNPS360 > Location > Allow only while using the app'
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

        if (open == true) {
          log('📍 User chose to open app settings from second dialog');
          await openAppSettings();
        } else {
          log('📍 User cancelled opening app settings from second dialog');
        }
        return;
      }

      // Re-check permission status after second request
      status = await Permission.locationWhenInUse.status;
      geoPermission = await Geolocator.checkPermission();
      log(
        '📍 Final permission status - permission_handler: ${status.name}, Geolocator: ${geoPermission.name}',
      );

      if (!status.isGranted &&
          geoPermission != LocationPermission.always &&
          geoPermission != LocationPermission.whileInUse) {
        log(
          '📍 Location permission not granted after second request, aborting',
        );
        return;
      }
    } else {
      if (!status.isGranted &&
          geoPermission != LocationPermission.always &&
          geoPermission != LocationPermission.whileInUse) {
        log('📍 Location permission not granted, aborting');
        return;
      }
    }

    log('📍 Location permission granted, attempting to get current position');
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
        forceAndroidLocationManager: false,
      );
      log(
        '📍 Successfully obtained location: lat=${pos.latitude}, lon=${pos.longitude}',
      );
    } catch (e) {
      log('📍 Failed to get current position: $e');
      final retry = await Get.dialog<bool>(
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
                            Expanded(
                              child: Text(
                                'Unable to get location',
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
                        const SizedBox(height: 8),
                        Divider(
                          thickness: 1,
                          color: Colors.white.withAlpha(128),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Unable to obtain a fresh GPS fix. Please ensure GPS is enabled and try again.',
                          style: TextStyle(
                            color: Colors.black.withAlpha(191),
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
                                      'Retry',
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

      if (retry == true) {
        log('📍 User chose to retry getting location');
        try {
          pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 15),
            forceAndroidLocationManager: false,
          );
          log(
            '📍 Successfully obtained location on retry: lat=${pos.latitude}, lon=${pos.longitude}',
          );
        } catch (e) {
          log('📍 Failed to get location on retry: $e');
          AppSnackBar.show(
            // ignore: use_build_context_synchronously
            context,
            'Unable to obtain current location.',
            type: SnackBarType.error,
          );
          return;
        }
      } else {
        log('📍 User cancelled location retry');
        return;
      }
    }

    final lat = pos.latitude;
    final lng = pos.longitude;
    log('📍 Proceeding with $type action using location: lat=$lat, lon=$lng');

    switch (type) {
      case 'clock_in':
        await _clockIn(latitude: lat, longitude: lng);
        break;
      case 'start_break':
        await _startBreak(latitude: lat, longitude: lng);
        break;
      case 'end_break':
        await _endBreak(latitude: lat, longitude: lng);
        break;
      case 'clock_out':
        await _clockOut(latitude: lat, longitude: lng);
        break;
      default:
        break;
    }
  }

  // Helper method to build location usage row in explanation dialog
  Widget _buildLocationUsageRow(IconData icon, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF3B82F6) : cPrimary).withAlpha(13),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isDark ? const Color(0xFF3B82F6) : cPrimary,
          ),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final h = MediaQuery.of(context).size.height;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: isDark ? cDarkBackground : Color(0xffF6F8FB),
      body: Column(
        children: [
          InkWell(
            overlayColor: WidgetStatePropertyAll(cTransparent),
            onTap: () {},
            child: AppHeader(height: h),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await timeController.refreshServerSession();
                final regionId = _mem.getRegionId();
                final shiftId = _mem.getShiftId();
                if (regionId != null &&
                    shiftId != null &&
                    role != onSiteOfficer) {
                  await _dc.fetchAssignments(
                    regionId,
                    shiftId,
                    forceRefresh: true,
                  );
                }

                await _loadDashboardData();
                await clockInWindow.forceRefresh();
                Get.find<ScheduleMonthCalendarController>().fetchShiftsForMonth(
                  sfNow(),
                  forceRefresh: true,
                  silentRefresh: true,
                );
              },
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                children: [
                  // if (_isPatrolOfficer) ...[
                  //   SizedBox(height: h * 0.020),
                  //   Obx(() {
                  //     final scopeSelected = isScopeSelected.value;
                  //     return InkWell(
                  //       overlayColor: WidgetStatePropertyAll(cTransparent),
                  //       onTap: () {
                  //         if (scopeSelected) return;

                  //         if (_isPatrolOfficer) {
                  //           showRegionShiftDialog(
                  //             context,
                  //             onSave: () async {
                  //               box.write('isScopeSelected', true);
                  //               _mem.setIsScopeSelected(true);
                  //               isScopeSelected.value = true;

                  //               timeController.notifyScopeChanged();

                  //               await _loadDashboardData();
                  //               await clockInWindow.forceRefresh();

                  //               await timeController.refreshServerSession();
                  //             },
                  //           );
                  //         }
                  //       },
                  //       child: Stack(
                  //         children: [
                  //           Builder(
                  //             builder: (_) {
                  //               final isDark =
                  //                   Theme.of(context).brightness ==
                  //                   Brightness.dark;
                  //               return Container(
                  //                 width: double.infinity,
                  //                 padding: const EdgeInsets.all(12),
                  //                 decoration: getCardDecoration(context),
                  //                 child: Obx(() {
                  //                   final scopeSelected =
                  //                       isScopeSelected.value;

                  //                   final showLoading =
                  //                       timeController.dialShimmer.value ||
                  //                       timeController.scopeLoading.value;

                  //                   final showIncompleteSelected =
                  //                       scopeSelected &&
                  //                       !timeController.scopeValuesComplete;

                  //                   if (showLoading ||
                  //                       showIncompleteSelected) {
                  //                     return const ScopeSkeleton();
                  //                   }

                  //                   if (_isOnSiteOfficer || scopeSelected) {
                  //                     log('scopeSelected: $scopeSelected');
                  //                     return Column(
                  //                       crossAxisAlignment:
                  //                           CrossAxisAlignment.start,
                  //                       children: [
                  //                         RichText(
                  //                           text: TextSpan(
                  //                             style: const TextStyle(
                  //                               fontSize: 15,
                  //                               color: Colors.black87,
                  //                               fontWeight: FontWeight.w500,
                  //                             ),
                  //                             children: [
                  //                               TextSpan(
                  //                                 text: 'Scope: ',
                  //                                 style: textTheme.bodyLarge!
                  //                                     .copyWith(
                  //                                       height: 1.2,
                  //                                       fontWeight:
                  //                                           FontWeight.w600,
                  //                                     ),
                  //                               ),
                  //                               TextSpan(
                  //                                 text: timeController
                  //                                     .displayRegion
                  //                                     .value,
                  //                                 style: textTheme.bodyLarge!
                  //                                     .copyWith(
                  //                                       height: 1.2,
                  //                                       color: isDark
                  //                                           ? cDarkTextPrimary
                  //                                           : cDarkText,
                  //                                       fontSize: 15,
                  //                                     ),
                  //                               ),
                  //                             ],
                  //                           ),
                  //                         ),

                  //                         // Late badge (compact)
                  //                         // Builder(builder: (_) {
                  //                         //   final lateMin = box.read('lateByMinutes') is int
                  //                         //       ? box.read('lateByMinutes') as int
                  //                         //       : int.tryParse((box.read('lateByMinutes') ?? '').toString()) ?? 0;
                  //                         //   if (lateMin <= 0) return SizedBox.shrink();
                  //                         //   return Padding(
                  //                         //     padding: const EdgeInsets.only(top: 6.0),
                  //                         //     child: Row(
                  //                         //       children: [
                  //                         //         Container(
                  //                         //           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  //                         //           decoration: BoxDecoration(
                  //                         //             color: Colors.red.shade50,
                  //                         //             borderRadius: BorderRadius.circular(12),
                  //                         //             border: Border.all(color: Colors.red.shade700, width: 1),
                  //                         //           ),
                  //                         //           child: Text('Late ${lateMin}m',
                  //                         //             style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w700, fontSize: 12),
                  //                         //           ),
                  //                         //         ),
                  //                         //       ],
                  //                         //     ),
                  //                         //   );
                  //                         // }),
                  //                         SizedBox(height: 4),
                  //                         RichText(
                  //                           text: TextSpan(
                  //                             style: const TextStyle(
                  //                               fontSize: 15,
                  //                               color: Colors.black87,
                  //                               fontWeight: FontWeight.w500,
                  //                             ),
                  //                             children: [
                  //                               TextSpan(
                  //                                 text: 'Shift: ',
                  //                                 style: textTheme.bodyLarge!
                  //                                     .copyWith(
                  //                                       height: 1.2,
                  //                                       fontWeight:
                  //                                           FontWeight.w600,
                  //                                     ),
                  //                               ),
                  //                               TextSpan(
                  //                                 text: timeController
                  //                                     .displayShift
                  //                                     .value,
                  //                                 style: textTheme.bodyLarge!
                  //                                     .copyWith(
                  //                                       height: 1.2,
                  //                                       color: isDark
                  //                                           ? cDarkTextPrimary
                  //                                           : cDarkText,
                  //                                       fontSize: 15,
                  //                                     ),
                  //                               ),
                  //                             ],
                  //                           ),
                  //                         ),
                  //                       ],
                  //                     );
                  //                   }
                  //                   return Row(
                  //                     mainAxisAlignment:
                  //                         MainAxisAlignment.center,
                  //                     children: [
                  //                       RichText(
                  //                         text: TextSpan(
                  //                           style: const TextStyle(
                  //                             fontSize: 15,
                  //                             color: Colors.black87,
                  //                             fontWeight: FontWeight.w500,
                  //                           ),
                  //                           children: [
                  //                             TextSpan(
                  //                               text:
                  //                                   box.read(role) ==
                  //                                       patrolOfficer
                  //                                   ? 'Select scope (Region & Shift)'
                  //                                   : 'Select scope (Site & Shift)',
                  //                               style: textTheme.bodyMedium!
                  //                                   .copyWith(
                  //                                     height: 1,
                  //                                     color: isDark
                  //                                         ? cDarkTextPrimary
                  //                                         : cDarkText,
                  //                                     fontWeight:
                  //                                         FontWeight.w600,
                  //                                   ),
                  //                             ),
                  //                           ],
                  //                         ),
                  //                       ),
                  //                       SizedBox(width: h * 0.01),
                  //                       Icon(
                  //                         Icons.keyboard_arrow_right_rounded,
                  //                         color: isDark
                  //                             ? cDarkIconColor
                  //                             : cIconDefault,
                  //                       ),
                  //                     ],
                  //                   );
                  //                 }),
                  //               );

                  //               // if (isScopeSelected.value)
                  //               //   Positioned(
                  //               //     right: 10,
                  //               //     top: 10,
                  //               //     child: Tooltip(
                  //               //       message: 'Remove scope',
                  //               //       child: Material(
                  //               //         color: Colors.transparent,
                  //               //         child: InkWell(
                  //               //           borderRadius: BorderRadius.circular(20),
                  //               //           onTap: () {
                  //               //             _clearScopeState();
                  //               //             Future.microtask(
                  //               //               () => sc.fetchScopeLists(),
                  //               //             );
                  //               //           },
                  //               //           child: Container(
                  //               //             width: 40,
                  //               //             height: 40,
                  //               //             decoration: BoxDecoration(
                  //               //               color: Colors.white,
                  //               //               borderRadius: BorderRadius.circular(20),
                  //               //               boxShadow: [
                  //               //                 BoxShadow(
                  //               //                   color: Colors.black.withOpacity(
                  //               //                     0.06,
                  //               //                   ),
                  //               //                   blurRadius: 6,
                  //               //                   offset: Offset(0, 2),
                  //               //                 ),
                  //               //               ],
                  //               //               border: Border.all(
                  //               //                 color: Colors.red.shade700,
                  //               //                 width: 1,
                  //               //               ),
                  //               //             ),
                  //               //             padding: const EdgeInsets.all(8),
                  //               //             child: Center(
                  //               //               child: Image.asset(
                  //               //                 'assets/Icons/delete.png',
                  //               //                 width: 18,
                  //               //                 height: 18,
                  //               //                 fit: BoxFit.contain,
                  //               //               ),
                  //               //             ),
                  //               //           ),
                  //               //         ),
                  //               //       ),
                  //               //     ),
                  //               //   ),
                  //             },
                  //           ),
                  //         ],
                  //       ),
                  //     );
                  //   }),
                  //   SizedBox(height: h * 0.02),
                  // ],
                  Obx(() {
                    final role = box.read('role');
                    final isPatrol = role is String && role == patrolOfficer;

                    final totalBreakRaw = box.read('totalBreakMinutes');
                    final totalBreakMin = totalBreakRaw is int
                        ? totalBreakRaw
                        : int.tryParse('${totalBreakRaw ?? 0}') ?? 0;
                    final hasBreak = totalBreakMin > 0;

                    final int workedSeconds = isPatrol
                        ? timeController.workBeforeBreakSeconds.value
                        : (timeController.workBeforeBreakSeconds.value +
                              timeController.workAfterBreakSeconds.value);

                    int totalShiftSeconds = timeController.totalWorkDuration;

                    final start = timeController.shiftStartTime.value;
                    final end = timeController.shiftEndTime.value;
                    if (start != null && end != null) {
                      final diff = end.difference(start).inSeconds;
                      if (diff > 0) totalShiftSeconds = diff;
                    }

                    final int lateSeconds =
                        (timeController.lateByMinutes.value * 60).clamp(
                          0,
                          totalShiftSeconds,
                        );

                    final int effectiveShiftSeconds =
                        (totalShiftSeconds - lateSeconds).clamp(
                          0,
                          totalShiftSeconds,
                        );
                    final int breakTaken = timeController.breakSeconds.value;
                    final int remainingShiftSeconds =
                        (effectiveShiftSeconds - workedSeconds - breakTaken)
                            .clamp(0, effectiveShiftSeconds);

                    final int remainingBreakSeconds =
                        (timeController.breakDuration -
                                timeController.breakSeconds.value)
                            .clamp(0, timeController.breakDuration);

                    final bool showBreakRemaining =
                        timeController.onDuty.value &&
                        hasBreak &&
                        timeController.breakActive.value;

                    final String remainingLabel = showBreakRemaining
                        ? 'Remaining Break'
                        : 'Remaining Shift';

                    final String remainingValue = showBreakRemaining
                        ? formatMMSS(remainingBreakSeconds)
                        : formatHHMMSS(remainingShiftSeconds);

                    final onDuty = timeController.onDuty.value;
                    final breakActive = timeController.breakActive.value;
                    final workBeforeBreakSeconds =
                        timeController.workBeforeBreakSeconds.value;
                    final breakSeconds = timeController.breakSeconds.value;
                    final workAfterBreakSeconds =
                        timeController.workAfterBreakSeconds.value;

                    final int totalWorkSeconds =
                        workBeforeBreakSeconds + workAfterBreakSeconds;

                    int mainSeconds;
                    if (!onDuty) {
                      mainSeconds = 0;
                    } else if (breakActive) {
                      mainSeconds = breakSeconds;
                    } else {
                      mainSeconds = totalWorkSeconds;
                    }
                    final bool shiftEndedNow =
                        onDuty && timeController.isShiftEnded.value;
                    final double currentProgress = onDuty
                        ? timeController.dialProgress.value
                        : 0.0;
                    final bool breakEndedNow =
                        onDuty &&
                        breakActive &&
                        hasBreak &&
                        timeController.breakDuration > 0 &&
                        breakSeconds >= timeController.breakDuration;

                    final Color statusColor = !onDuty
                        ? cPrimary
                        : breakActive
                        ? cOrange
                        : cPrimary;

                    final Color currentColor = isDark
                        ? (breakActive
                              ? const Color(0xFFF59E0B)
                              : const Color(
                                  0xFF60A5FA,
                                )) // Brighter blue for better visibility
                        : statusColor;

                    final Color darkModeUnusedProgressColor = breakActive
                        ? const Color(0xFF78350F)
                        : const Color(
                            0xFF1E40AF,
                          ); // Slightly lighter navy for better contrast

                    final Color dialBgColor = !onDuty
                        ? (isDark
                              ? const Color(0xff162033)
                              : Colors.grey.shade100)
                        : breakActive
                        ? (isDark
                              ? const Color(0xFF78350F)
                              : breakEndedNow
                              ? (isDark
                                    ? Colors.red.shade700.withAlpha(56)
                                    : const Color(0xFFFFE5E5))
                              : const Color(0xFFFFF6D8))
                        : (shiftEndedNow || breakEndedNow)
                        ? (isDark
                              ? Colors.red.shade700.withAlpha(56)
                              : const Color(0xFFFFE5E5))
                        : isDark
                        ? darkModeUnusedProgressColor
                        : const Color.fromARGB(255, 198, 219, 255);

                    final Color mainTimeColor = isDark
                        ? currentColor
                        : statusColor;

                    final bool shiftHasBreak = totalBreakMin > 0;

                    final int lateMinutesNow =
                        timeController.lateByMinutes.value;
                    final int earlyMinutesNow =
                        timeController.earlyByMinutes.value;
                    String arrivalText;
                    Color arrivalColor = isDark ? cDarkTextPrimary : cDarkText;

                    if (earlyMinutesNow > 0) {
                      arrivalText = '${formatHM(earlyMinutesNow)} Early';
                    } else if (lateMinutesNow > 0) {
                      arrivalText = '${formatHM(lateMinutesNow)} Late';
                      arrivalColor = Colors.red.shade700;
                    } else {
                      arrivalText = 'On Time';
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: !timeController.dialShimmer.value
                          ? getCardDecoration(context)
                          : null,
                      child: Obx(
                        () => timeController.dialShimmer.value
                            ? DashboardDialSkeleton(h: h)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12.0,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Obx(() {
                                                if (timeController
                                                    .dialShimmer
                                                    .value) {
                                                  return Shimmer.fromColors(
                                                    baseColor: isDark
                                                        ? cDarkBorderColor
                                                        : Colors.grey.shade300,
                                                    highlightColor: isDark
                                                        ? cDarkCardColor
                                                              .withAlpha(128)
                                                        : Colors.grey.shade100,
                                                    child: Container(
                                                      height: 22,
                                                      width: 64,
                                                      decoration: BoxDecoration(
                                                        color: isDark
                                                            ? cDarkBorderColor
                                                                  .withAlpha(
                                                                    179,
                                                                  )
                                                            : Colors
                                                                  .grey
                                                                  .shade300,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              20,
                                                            ),
                                                      ),
                                                    ),
                                                  );
                                                }

                                                return _Badge(
                                                  label: onDuty
                                                      ? "On Duty"
                                                      : "Off Duty",
                                                  backgroundColor: onDuty
                                                      ? cPrimary.withAlpha(204)
                                                      : cDarkGreyclr,
                                                  textColor: cWhiteText,
                                                );
                                              }),
                                              const SizedBox(height: 6),
                                              Text(
                                                "Track Your Time",
                                                style: textTheme.bodyLarge!
                                                    .copyWith(
                                                      height: 1,
                                                      color: isDark
                                                          ? cDarkTextPrimary
                                                          : cDarkText,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            if (!isPatrol &&
                                                onDuty &&
                                                shiftHasBreak) ...[
                                              _TimeRow(
                                                label: "Work before break",
                                                value: _formatDuration(
                                                  workBeforeBreakSeconds,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              _TimeRow(
                                                label: "Break",
                                                value: _formatDuration(
                                                  breakSeconds,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              _TimeRow(
                                                label: "Work after break",
                                                value: _formatDuration(
                                                  workAfterBreakSeconds,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Divider(color: cBorder),
                                  SizedBox(height: h * 0.024),
                                  Center(
                                    child: SizedBox(
                                      height: 230,
                                      width: 260,
                                      child: Obx(() {
                                        if (timeController.dialShimmer.value) {
                                          return Shimmer.fromColors(
                                            baseColor: isDark
                                                ? cDarkBorderColor
                                                : Colors.grey.shade300,
                                            highlightColor: isDark
                                                ? cDarkCardColor.withAlpha(128)
                                                : Colors.grey.shade100,
                                            child: Container(
                                              height: 230,
                                              width: 260,
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? cDarkBorderColor
                                                          .withAlpha(179)
                                                    : Colors.grey.shade300,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          );
                                        }

                                        return Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            CustomPaint(
                                              size: const Size(260, 260),
                                              painter: DialPainter(
                                                progress: currentProgress,
                                                color: currentColor,
                                                active: onDuty,
                                                showTick: true,
                                                backgroundFillColor:
                                                    dialBgColor,
                                                lateMinutes:
                                                    !onDuty || breakActive
                                                    ? 0
                                                    : timeController
                                                          .lateByMinutes
                                                          .value,
                                                earlySeconds:
                                                    timeController
                                                        .earlyByMinutes
                                                        .value *
                                                    60,
                                                memoryStorage: _mem,
                                              ),
                                            ),
                                            Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  _formatDuration(
                                                    onDuty ? mainSeconds : 0,
                                                  ),
                                                  style: TextStyle(
                                                    fontSize: 40,
                                                    fontWeight: FontWeight.w800,
                                                    color:
                                                        shiftEndedNow ||
                                                            breakEndedNow
                                                        ? Colors.red[700]
                                                        : mainTimeColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        );
                                      }),
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (!onDuty)
                                        Obx(() {
                                          final canClockIn =
                                              clockInWindow.canClockIn.value;
                                          return ElevatedButton(
                                            onPressed:
                                                (timeController
                                                        .isLoading
                                                        .value ||
                                                    attendanceProcessing
                                                        .value ||
                                                    !canClockIn)
                                                ? null
                                                : () async {
                                                    attendanceProcessing.value =
                                                        true;
                                                    try {
                                                      await handleAttendance(
                                                        'clock_in',
                                                      );
                                                    } finally {
                                                      attendanceProcessing
                                                              .value =
                                                          false;
                                                    }
                                                  },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: canClockIn
                                                  ? (isDark
                                                        ? const Color(
                                                            0xFF3B82F6,
                                                          )
                                                        : cPrimary)
                                                  : Colors.grey.shade400,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 44,
                                                    vertical: 14,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                            child:
                                                (attendanceProcessing.value ||
                                                    timeController
                                                        .isLoading
                                                        .value)
                                                ? const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                          color: Colors.white,
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : const Text(
                                                    'Clock In',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                          );
                                        })
                                      else ...[
                                        if (timeController.showEndBreakButton)
                                          ElevatedButton(
                                            onPressed:
                                                (timeController
                                                        .isLoading
                                                        .value ||
                                                    attendanceProcessing.value)
                                                ? null
                                                : () async {
                                                    attendanceProcessing.value =
                                                        true;
                                                    try {
                                                      await handleAttendance(
                                                        'end_break',
                                                      );
                                                    } finally {
                                                      attendanceProcessing
                                                              .value =
                                                          false;
                                                    }
                                                  },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: isDark
                                                  ? const Color(0xFFF59E0B)
                                                  : cOrange,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 20,
                                                    vertical: 14,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                            child:
                                                (attendanceProcessing.value ||
                                                    timeController
                                                        .isLoading
                                                        .value)
                                                ? const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                          color: Colors.white,
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : const Text(
                                                    'End Break',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                          )
                                        else if (timeController
                                            .showStartBreakButton)
                                          ElevatedButton(
                                            onPressed:
                                                (timeController
                                                        .isLoading
                                                        .value ||
                                                    attendanceProcessing.value)
                                                ? null
                                                : () async {
                                                    attendanceProcessing.value =
                                                        true;
                                                    try {
                                                      await handleAttendance(
                                                        'start_break',
                                                      );
                                                    } finally {
                                                      attendanceProcessing
                                                              .value =
                                                          false;
                                                    }
                                                  },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: isDark
                                                  ? const Color(0xFF3B82F6)
                                                  : cPrimary,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 20,
                                                    vertical: 14,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                            child:
                                                (attendanceProcessing.value ||
                                                    timeController
                                                        .isLoading
                                                        .value)
                                                ? const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                          color: Colors.white,
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : const Text(
                                                    'Start Break',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                          ),
                                        if (!breakActive) ...[
                                          if (timeController
                                                  .showStartBreakButton ||
                                              timeController.showEndBreakButton)
                                            const SizedBox(width: 14),
                                          ElevatedButton(
                                            onPressed:
                                                (timeController
                                                        .isLoading
                                                        .value ||
                                                    attendanceProcessing.value)
                                                ? null
                                                : () async {
                                                    attendanceProcessing.value =
                                                        true;
                                                    try {
                                                      await handleAttendance(
                                                        'clock_out',
                                                      );
                                                    } finally {
                                                      attendanceProcessing
                                                              .value =
                                                          false;
                                                    }
                                                  },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.red.shade700,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 20,
                                                    vertical: 12,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                            child:
                                                (attendanceProcessing.value ||
                                                    timeController
                                                        .isLoading
                                                        .value)
                                                ? const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                          color: Colors.white,
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : const Text(
                                                    'Clock Out',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                          ),
                                        ],
                                      ],
                                    ],
                                  ),

                                  if (onDuty) ...[
                                    if (breakEndedNow) ...[
                                      SizedBox(height: h * 0.016),
                                      Center(
                                        child: Text(
                                          '❗ Break Ended — Please End Break',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.red.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (shiftEndedNow && !breakActive) ...[
                                      SizedBox(height: h * 0.016),
                                      Center(
                                        child: Text(
                                          '❗ Shift Ended — Please Clock Out',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.red.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                    SizedBox(height: h * 0.016),

                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                      ),
                                      child: Divider(color: cBorder),
                                    ),
                                    const SizedBox(height: 10),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Arrival Time',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: isDark
                                                            ? cDarkTextSecondary
                                                            : Colors.black
                                                                  .withAlpha(
                                                                    140,
                                                                  ),
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  arrivalText,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: arrivalColor,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            height: 34,
                                            width: 1,
                                            color: cBorder,
                                          ),
                                          Expanded(
                                            child: Column(
                                              children: [
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.end,
                                                  children: [
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .end,
                                                      children: [
                                                        Text(
                                                          remainingLabel,
                                                          style: Theme.of(context)
                                                              .textTheme
                                                              .bodySmall
                                                              ?.copyWith(
                                                                color: isDark
                                                                    ? cDarkTextSecondary
                                                                    : Colors
                                                                          .black
                                                                          .withAlpha(
                                                                            140,
                                                                          ),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          remainingValue,
                                                          style: Theme.of(context)
                                                              .textTheme
                                                              .titleMedium
                                                              ?.copyWith(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                                color: isDark
                                                                    ? cDarkTextPrimary
                                                                    : cDarkText,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 10),
                                ],
                              ),
                      ),
                    );
                  }),
                  if (_isPatrolOfficer) ...[
                    const SizedBox(height: 12),
                    Obx(
                      () => NextShiftCard(
                        loading: calendarController.isLoading.value,
                      ),
                    ),
                  ],

                  if (_isOnSiteOfficer) ...[
                    const SizedBox(height: 12),
                    Obx(
                      () => NextShiftCard(
                        loading: calendarController.isLoading.value,
                      ),
                    ),
                  ],

                  Obx(() {
                    if (!isScopeSelected.value) return SizedBox.shrink();
                    if (box.read(role) != patrolOfficer) {
                      return SizedBox.shrink();
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 18),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Obx(() {
                            final isDark =
                                Theme.of(context).brightness == Brightness.dark;
                            if (_dc.loadingAssignments.value &&
                                _dc.assignments.isEmpty) {
                              return Shimmer.fromColors(
                                baseColor: isDark
                                    ? cDarkBorderColor
                                    : Colors.grey.shade300,
                                highlightColor: isDark
                                    ? cDarkCardColor.withAlpha(128)
                                    : Colors.grey.shade100,
                                child: Container(
                                  height: 18,
                                  width: 180,
                                  color: isDark
                                      ? cDarkBorderColor
                                      : Colors.grey.shade300,
                                ),
                              );
                            }

                            return Text(
                              "Today's Assignments",
                              style: textTheme.bodyLarge!.copyWith(
                                fontSize: 18,
                                height: 1,
                                color: isDark ? cDarkTextPrimary : cDarkText,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          }),
                        ),

                        const SizedBox(height: 12),
                        Obx(() {
                          if (_dc.loadingAssignments.value &&
                              _dc.assignments.isEmpty) {
                            return ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: EdgeInsets.zero,
                              itemCount: 3,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (_, _) =>
                                  const AssignmentCardAltShimmer(),
                            );
                          }

                          if (_dc.assignments.isEmpty &&
                              !_dc.loadingAssignments.value) {
                            final isDark =
                                Theme.of(context).brightness == Brightness.dark;
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Text(
                                  "No assignments for today.",
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: isDark
                                        ? cDarkTextSecondary
                                        : Colors.black54,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            itemCount: _dc.assignments.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, i) {
                              final assignmentData = _dc.assignments[i];
                              final assignment = Assignment.fromJson(
                                assignmentData,
                              );

                              return AssignmentCardAlt(
                                assignment: assignment,
                                onTap: () {},
                                onLogVisit: () {
                                  Get.to(
                                    () =>
                                        LogVisitScreen(assignment: assignment),
                                  );
                                },
                              );
                            },
                          );
                        }),
                        const SizedBox(height: 20),
                      ],
                    );
                  }),
                  Builder(
                    builder: (context) {
                      if (box.read(role) != onSiteOfficer &&
                          box.read(role) != patrolOfficer) {
                        return SizedBox.shrink();
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 18),
                          Text(
                            "Upcoming Shifts",
                            style: textTheme.bodyLarge!.copyWith(
                              fontSize: 18,
                              height: 1,
                              color: isDark ? cDarkTextPrimary : cDarkText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const UpcomingShiftsSection(),
                          const SizedBox(height: 100),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  const _Badge({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class DialPainter extends CustomPainter {
  final double progress;
  final bool active;
  final Color color;
  final bool showTick;
  final Color backgroundFillColor;
  final int lateMinutes;
  final int earlySeconds;
  final MemoryStorageController memoryStorage;

  DialPainter({
    required this.progress,
    required this.color,
    required this.active,
    this.showTick = false,
    required this.backgroundFillColor,
    this.lateMinutes = 0,
    this.earlySeconds = 0,
    required this.memoryStorage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 12.0;

    final fillPaint = Paint()
      ..color = backgroundFillColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius - 22, fillPaint);

    final bgPaint = Paint()
      ..color = backgroundFillColor.withAlpha(230)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    final latePaint = Paint()
      ..color = Colors.red.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    const startAngle = 1.25 * math.pi / 2 + (math.pi / 8);
    const sweepAngle = 1.5 * math.pi;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    int totalShiftSeconds = 3600;
    try {
      final sRaw = memoryStorage.getShiftStartTime();
      final eRaw = memoryStorage.getShiftEndTime();
      DateTime? s = DateTime.tryParse(sRaw.toString());
      DateTime? e = DateTime.tryParse(eRaw.toString());
      if (s == null || e == null) {
        // ignore: unnecessary_type_check
        if (sRaw is String &&
            sRaw.contains(':') &&
            // ignore: unnecessary_type_check
            eRaw is String &&
            eRaw.contains(':')) {
          final now = sfNow();
          final sh = int.tryParse(sRaw.split(':')[0]) ?? now.hour;
          final sm = int.tryParse(sRaw.split(':')[1]) ?? 0;
          final eh = int.tryParse(eRaw.split(':')[0]) ?? sh;
          final em = int.tryParse(eRaw.split(':')[1]) ?? 0;
          s = DateTime(now.year, now.month, now.day, sh, sm);
          e = DateTime(now.year, now.month, now.day, eh, em);
        }
      }
      if (s != null && e != null) {
        if (e.isBefore(s)) e = e.add(const Duration(days: 1));
        final diff = e.difference(s).inSeconds;
        if (diff > 0) totalShiftSeconds = diff;
      }
    } catch (_) {}

    if (earlySeconds > 0) {
      totalShiftSeconds = (totalShiftSeconds + earlySeconds).clamp(1, 1 << 30);
    }

    final lateSeconds = (lateMinutes * 60).clamp(0, totalShiftSeconds);
    final lateFrac = totalShiftSeconds > 0
        ? lateSeconds / totalShiftSeconds
        : 0.0;
    final workFrac = progress.clamp(0.0, 1.0);

    final redSweep = sweepAngle * lateFrac.clamp(0.0, 1.0);
    final blueSweep = sweepAngle * workFrac.clamp(0.0, 1.0);

    if (redSweep > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        redSweep,
        false,
        latePaint,
      );
    }

    if (blueSweep > 0) {
      final blueStart = startAngle + redSweep;
      final combined = (redSweep + blueSweep).clamp(0.0, sweepAngle);
      final blueDraw = (combined - redSweep).clamp(0.0, sweepAngle);
      if (blueDraw > 0) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          blueStart,
          blueDraw,
          false,
          fgPaint,
        );
      }
    }

    final totalSweepForKnob = (redSweep + blueSweep).clamp(0.0, sweepAngle);
    if (totalSweepForKnob > 0) {
      final knobAngle = startAngle + totalSweepForKnob;
      final knobOffset = Offset(
        center.dx + radius * math.cos(knobAngle),
        center.dy + radius * math.sin(knobAngle),
      );

      final knobBgPaint = Paint()
        ..color = cWhite
        ..style = PaintingStyle.fill;

      final knobInnerPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawCircle(knobOffset, 9, knobBgPaint);
      canvas.drawCircle(knobOffset, 6, knobInnerPaint);
    }

    if (showTick) {
      final tickPaint = Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;

      const tickCount = 16;
      const tickGap = sweepAngle / tickCount;
      const tickLength = 6.0;
      const tickOffset = -18.0;

      for (int i = 0; i <= tickCount; i++) {
        final angle = startAngle + tickGap * i;
        final inner = Offset(
          center.dx + (radius + tickOffset) * math.cos(angle),
          center.dy + (radius + tickOffset) * math.sin(angle),
        );
        final outer = Offset(
          center.dx + (radius + tickOffset + tickLength) * math.cos(angle),
          center.dy + (radius + tickOffset + tickLength) * math.sin(angle),
        );
        canvas.drawLine(inner, outer, tickPaint);
      }
    }
  }

  @override
  bool shouldRepaint(DialPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.active != active ||
      oldDelegate.color != color ||
      oldDelegate.lateMinutes != lateMinutes ||
      oldDelegate.earlySeconds != earlySeconds ||
      oldDelegate.memoryStorage != memoryStorage;
}

class AssignmentCardAlt extends StatelessWidget {
  final Assignment assignment;
  final VoidCallback onTap;
  final VoidCallback onLogVisit;

  const AssignmentCardAlt({
    super.key,
    required this.assignment,
    required this.onTap,
    required this.onLogVisit,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      container: true,
      button: true,
      label:
          'Assignment ${assignment.index}: ${assignment.site}. Status ${assignment.status}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: getCardDecoration(context),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assignment.site,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? cDarkTextPrimary : cDarkText,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              size: 16,
                              color: isDark
                                  ? cDarkTextSecondary
                                  : Color(0xFF6B7280),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              assignment.roundType,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w400,
                                color: isDark
                                    ? cDarkTextPrimary
                                    : Color(0xFF2E3A59),
                              ),
                            ),
                          ],
                        ),
                        _MiniChip(
                          label: assignment.frequency,
                          color: isDark
                              ? cDarkCardColor.withAlpha(179)
                              : const Color(0xFFEFF8FF),
                          textColor: isDark
                              ? cDarkTextPrimary
                              : const Color(0xFF0369A1),
                        ),
                        _MiniChip(
                          label: '${assignment.completed}/${assignment.total}',
                          color: assignment.status == 'Completed'
                              ? (isDark
                                    ? const Color(0xFF103528)
                                    : const Color(0xFFEFFDF3))
                              : (isDark
                                    ? const Color(0xFF3D2B10)
                                    : const Color(0xFFFFF7EB)),
                          textColor: assignment.status == 'Completed'
                              ? (isDark
                                    ? const Color(0xFF7EE2B8)
                                    : const Color(0xFF065F46))
                              : (isDark
                                    ? const Color(0xFFF2C27B)
                                    : const Color(0xFF92400E)),
                        ),
                        _MiniChip(
                          label: assignment.status,
                          color: assignment.status == 'Completed'
                              ? (isDark
                                    ? const Color(0xFF113D2D)
                                    : const Color(0xFFE6F9EE))
                              : (isDark
                                    ? const Color(0xFF4B3311)
                                    : const Color(0xFFFFF5E6)),
                          textColor: assignment.status == 'Completed'
                              ? (isDark
                                    ? const Color(0xFF9CF0C8)
                                    : const Color(0xFF027A3C))
                              : (isDark
                                    ? const Color(0xFFF8D49A)
                                    : const Color(0xFFB76E00)),
                          withBorder: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: 'Log Visit (share location)',
                    preferBelow: false,
                    child: SizedBox(
                      width: 92,
                      height: 38,
                      child: ElevatedButton(
                        onPressed: onLogVisit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark
                              ? cPrimary
                              : const Color(0xff0D1A33),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: EdgeInsets.zero,
                          elevation: 2,
                        ),
                        child: Center(
                          child: const Text(
                            "Log Visit",
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: cWhite,
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
    );
  }
}

class AssignmentCardAltShimmer extends StatelessWidget {
  const AssignmentCardAltShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: getCardDecoration(context),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ShimmerLine(height: 15, widthFactor: 1.0, radius: 4),
                const SizedBox(height: 4),
                const _ShimmerLine(height: 15, widthFactor: 0.62, radius: 4),

                const SizedBox(height: 8),

                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: const [
                    _ShimmerIconWithText(),

                    _ShimmerChip(width: 70),
                    _ShimmerChip(width: 58),
                    _ShimmerChip(width: 78),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          const _ShimmerButton(width: 92, height: 38),
        ],
      ),
    );
  }
}

class _ShimmerLine extends StatelessWidget {
  final double height;
  final double widthFactor;
  final double radius;

  const _ShimmerLine({
    required this.height,
    required this.widthFactor,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final w = MediaQuery.of(context).size.width;

    final maxTextWidth = w - (12 + 12) - 92 - 12;
    final width = (maxTextWidth * widthFactor).clamp(80.0, maxTextWidth);

    return Shimmer.fromColors(
      baseColor: isDark ? cDarkBorderColor : Colors.grey.shade300,
      highlightColor: isDark
          ? cDarkCardColor.withAlpha(128)
          : Colors.grey.shade100,
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: isDark ? cDarkBorderColor : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

class _ShimmerIconWithText extends StatelessWidget {
  const _ShimmerIconWithText();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        _ShimmerBox(width: 16, height: 16, radius: 3),
        SizedBox(width: 6),
        _ShimmerBox(width: 92, height: 14, radius: 4),
      ],
    );
  }
}

class _ShimmerChip extends StatelessWidget {
  final double width;
  const _ShimmerChip({required this.width});

  @override
  Widget build(BuildContext context) {
    return _ShimmerBox(width: width, height: 26, radius: 999);
  }
}

class _ShimmerButton extends StatelessWidget {
  final double width;
  final double height;

  const _ShimmerButton({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? cDarkBorderColor : Colors.grey.shade300,
      highlightColor: isDark
          ? cDarkCardColor.withAlpha(128)
          : Colors.grey.shade100,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isDark ? cDarkBorderColor : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _ShimmerBox({
    required this.width,
    required this.height,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? cDarkBorderColor : Colors.grey.shade300,
      highlightColor: isDark
          ? cDarkCardColor.withAlpha(128)
          : Colors.grey.shade100,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isDark ? cDarkBorderColor : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

Widget _skelBox({double? w, double? h, BorderRadius? r, ShapeBorder? shape}) {
  if (shape != null) {
    return Container(
      width: w,
      height: h,
      decoration: ShapeDecoration(color: Colors.grey.shade300, shape: shape),
    );
  }

  return Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: Colors.grey.shade300,
      borderRadius: r ?? BorderRadius.circular(10),
    ),
  );
}

class DashboardDialSkeleton extends StatelessWidget {
  final double h;
  const DashboardDialSkeleton({super.key, required this.h});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: getCardDecoration(context),
      child: Shimmer.fromColors(
        baseColor: isDark ? cDarkBorderColor : Colors.grey.shade300,
        highlightColor: isDark
            ? cDarkCardColor.withAlpha(128)
            : Colors.grey.shade100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _skelBox(w: 72, h: 22, r: BorderRadius.circular(20)),
                        const SizedBox(height: 8),
                        _skelBox(w: 150, h: 14, r: BorderRadius.circular(6)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _skelBox(w: 110, h: 10, r: BorderRadius.circular(6)),
                      const SizedBox(height: 6),
                      _skelBox(w: 80, h: 10, r: BorderRadius.circular(6)),
                      const SizedBox(height: 6),
                      _skelBox(w: 120, h: 10, r: BorderRadius.circular(6)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            Divider(
              color: Theme.of(context).brightness == Brightness.dark
                  ? cDarkBorderColor
                  : cBorder,
            ),

            SizedBox(height: h * 0.024),

            Center(
              child: SizedBox(
                height: 230,
                width: 260,
                child: Center(
                  child: _skelBox(w: 230, h: 230, shape: const CircleBorder()),
                ),
              ),
            ),

            const SizedBox(height: 14),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _skelBox(w: 140, h: 44, r: BorderRadius.circular(12)),
                const SizedBox(width: 14),
                _skelBox(w: 120, h: 44, r: BorderRadius.circular(12)),
              ],
            ),

            const SizedBox(height: 14),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [
                  Divider(color: isDark ? cDarkBorderColor : cBorder),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _skelBox(w: 90, h: 10, r: BorderRadius.circular(6)),
                            const SizedBox(height: 8),
                            _skelBox(
                              w: 110,
                              h: 14,
                              r: BorderRadius.circular(6),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 34,
                        width: 1,
                        color: isDark ? cDarkBorderColor : cBorder,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _skelBox(
                              w: 110,
                              h: 10,
                              r: BorderRadius.circular(6),
                            ),
                            const SizedBox(height: 8),
                            _skelBox(
                              w: 100,
                              h: 14,
                              r: BorderRadius.circular(6),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class ScopeSkeleton extends StatelessWidget {
  const ScopeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? cDarkBorderColor : Colors.grey.shade300,
      highlightColor: isDark
          ? cDarkCardColor.withAlpha(128)
          : Colors.grey.shade100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 14,
            decoration: BoxDecoration(
              color: isDark ? cDarkBorderColor : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: 240,
            height: 14,
            decoration: BoxDecoration(
              color: isDark ? cDarkBorderColor : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final bool withBorder;
  const _MiniChip({
    required this.label,
    required this.color,
    required this.textColor,
    this.withBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: withBorder ? Border.all(color: Colors.grey.shade200) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  final String label;
  final String value;

  const _TimeRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: TextStyle(
            fontSize: 11,
            color: isDark ? cDarkTextSecondary : const Color(0xFF6B7280),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? cDarkTextPrimary : cDarkText,
          ),
        ),
      ],
    );
  }

  Widget buildArrivalTimeRow({
    required int earlyMinutes,
    required int lateMinutes,
  }) {
    if (earlyMinutes <= 0 && lateMinutes <= 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Divider(height: 24),
          Text(
            "Arrival Time",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 6),
          Text("On Time", style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        const Text(
          "Arrival Time",
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),

        Row(
          children: [
            if (earlyMinutes > 0)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Early",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatHM(earlyMinutes),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

            if (earlyMinutes > 0 && lateMinutes > 0) const VerticalDivider(),

            if (lateMinutes > 0)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Late",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatHM(lateMinutes),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
