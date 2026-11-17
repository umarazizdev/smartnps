import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../Notifications/new_notifications_screen.dart';
import 'package:smartnps360/src/screens/app_storage.dart';
import 'package:smartnps360/src/screens/controllers/memory_storage_controller.dart';
import 'package:smartnps360/src/screens/main_screens/SettingsScreen/settingscontroller.dart';
import 'package:smartnps360/src/utilities/app_config.dart';
import '../Features/new_feature_flows.dart';
import '../Profile/new_profile_screen.dart';
import '../new_main_controller.dart';
import '../new_models.dart';
import 'new_dashboard_dialogs.dart';

class NewDashboardController extends GetxController {
  final officerName = 'Hamid Khan'.obs;
  final officerRole = 'On-Site'.obs;
  final roleBadgeText = 'On-Site'.obs;
  final greetingPrefix = 'Good morning,'.obs;
  final demoDialPeriod = 'morning'.obs;
  final selectedSite = 'BayCrest'.obs;
  final selectedShift = '9 PM – 5 AM · 8hr'.obs;
  // The supplied controller bootstraps a sample schedule. The real schedule
  // integration must explicitly publish availability after a successful load.
  final hasAssignedShift = true.obs;
  final selectedDate = 'Tuesday, May 5'.obs;
  final status = NewOfficerStatus.standby.obs;
  final timerText = '0:00:00'.obs;
  final timerLabel = 'Shift Timer'.obs;
  final ringInfoTitle = 'Upcoming Shift'.obs;
  final ringInfoSubtitle = 'BayCrest'.obs;
  final arrivalText = 'Pending'.obs;
  final arrivalStatus = NewArrivalStatus.pending.obs;
  final breakBadgeText = 'Break'.obs;
  final blinkTier = NewTimerBlinkTier.none.obs;
  final timerCompact = false.obs;
  final lateStartedStyle = false.obs;
  final dialLateEnd = 0.0.obs;
  final dialWork1End = 0.0.obs;
  final dialBreakEnd = 0.0.obs;
  final dialLiveEnd = 0.0.obs;
  final dialActiveDots = 0.obs;
  final isDarkMode = false.obs;
  final sideMenuOpen = false.obs;
  final complianceExpanded = false.obs;
  final shortcutEditing = false.obs;
  final quickActionsEditing = false.obs;
  final warningTab = NewWarningTab.late.obs;
  final reminderTab = NewReminderTab.upcoming.obs;
  final selectedReminderRepeat = NewReminderRepeat.once.obs;
  final reminderCritical = false.obs;
  final reminderAutoSnooze = false.obs;
  final reminderShowCalendar = true.obs;
  final taskOpenTab = true.obs;
  final warningStatIndex = 0.obs;
  final weekStatIndex = 0.obs;
  final onTimeStatIndex = 0.obs;
  final monthStatOffset = 0.obs;
  final onTimeValue = '-'.obs;
  final onTimeMeta = 'No shifts yet'.obs;
  final onTimeMonthTag = 'NOV'.obs;
  final warningCountValue = '0'.obs;
  final warningMetaText = 'No active warnings'.obs;
  final warningHasUnread = false.obs;
  final liveStatusText = 'On Standby'.obs;
  final liveStatusMode = NewLiveStatusMode.idle.obs;

  final reminderTitleCtrl = TextEditingController();
  final reminderNoteCtrl = TextEditingController();
  final complaintNoteCtrl = TextEditingController();
  final profileNameCtrl = TextEditingController(text: 'Hamid Khan');
  final profilePhoneCtrl = TextEditingController(text: '+1 555 0100');
  final profileEmailCtrl = TextEditingController(
    text: 'hamid.khan@smartnps360.com',
  );

  Timer? _timer;
  Timer? _dialDemoTimer;
  int _dialDemoIndex = 0;
  DateTime? _clockInAt;
  DateTime? _breakStartAt;
  DateTime? _breakEndAt;
  int _workedBeforeBreak = 0;
  final int _breakDurationMs = 30 * 60 * 1000;
  final _shiftClockedInLock = false.obs;
  late DateTime scheduledShiftStart;
  late DateTime scheduledShiftEnd;

  String get firstName => officerName.value.split(' ').first;
  bool get isRunning => status.value != NewOfficerStatus.standby;
  bool get isOnBreak => status.value == NewOfficerStatus.onBreak;
  bool get hasActiveDuty =>
      _shiftClockedInLock.value || status.value != NewOfficerStatus.standby;
  // Never hide a running duty/standby session even if a refresh finds no shift.
  bool get showNoAssignedShift {
    final assigned = hasAssignedShift.value;
    final activeStatus = status.value;
    return !assigned &&
        !_shiftClockedInLock.value &&
        activeStatus == NewOfficerStatus.standby;
  }

  /// Call only after the assigned-shift request has resolved successfully.
  /// Populate the real shift start/end/site/label before passing true.
  /// Do not use false for network errors or loading states.
  void setShiftAvailability(bool available) {
    hasAssignedShift.value = available;
    if (showNoAssignedShift) {
      blinkTier.value = NewTimerBlinkTier.none;
      return;
    }
    _syncRing();
  }

  bool get isStandbyMode =>
      _shiftClockedInLock.value && status.value == NewOfficerStatus.standby;
  bool get isOnActiveShift =>
      status.value == NewOfficerStatus.onShift ||
      status.value == NewOfficerStatus.onBreak;
  bool get breakActionEnabled =>
      status.value == NewOfficerStatus.onShift ||
      status.value == NewOfficerStatus.onBreak;
  bool get breakTaken => breakBadgeText.value == 'Taken';
  String get shiftActionMainLabel {
    if (isStandbyMode) return 'Stand By';
    if (isOnActiveShift) return 'Clock Out';
    return 'Clock In';
  }

  String get shiftActionSubLabel {
    if (isStandbyMode) {
      return 'Shift starts at ${_fmtAmpm(scheduledShiftStart)}';
    }
    if (isOnActiveShift) return 'End Shift';
    return 'Start Shift';
  }

  String get breakActionLabel {
    if (status.value == NewOfficerStatus.onBreak) return 'End Break';
    if (breakTaken) return 'Break Complete';
    return 'Start Break';
  }

  void _syncGreeting() {
    final h = DateTime.now().hour;
    final next = h < 12
        ? 'Good morning,'
        : h < 17
        ? 'Good afternoon,'
        : 'Good evening,';
    if (greetingPrefix.value != next) greetingPrefix.value = next;
  }

  void _syncLiveStatus() {
    if (status.value == NewOfficerStatus.onBreak) {
      liveStatusText.value = 'On Break';
      liveStatusMode.value = NewLiveStatusMode.breakMode;
      return;
    }
    if (isStandbyMode) {
      liveStatusText.value = 'Stand By';
      liveStatusMode.value = NewLiveStatusMode.standby;
      return;
    }
    if (status.value == NewOfficerStatus.onShift) {
      liveStatusText.value = 'On Duty';
      liveStatusMode.value = NewLiveStatusMode.active;
      return;
    }
    liveStatusText.value = 'On Standby';
    liveStatusMode.value = NewLiveStatusMode.idle;
  }

  int get shiftTotalSeconds {
    final total = scheduledShiftEnd.difference(scheduledShiftStart).inSeconds;
    return total < 1 ? 1 : total;
  }

  String get initials => officerName.value
      .split(' ')
      .where((e) => e.isNotEmpty)
      .map((e) => e[0])
      .take(2)
      .join()
      .toUpperCase();
  int get unreadNotifications => notifications.where((e) => e.unread).length;
  int get unreadComplaints => complaints.where((e) => e.unread).length;
  int get openTasksCount => tasks.where((e) => !e.completed).length;
  int get doneTasks => tasks.where((e) => e.completed).length;

  final complianceItems = const [
    'App Usage & GPS Tracking Consent',
    'Company Vehicle Agreement',
    'Officer Conduct Policy',
    'Attendance & Timekeeping Policy',
    'Uniform & Equipment Agreement',
    'Incident Reporting Policy',
    'Updated Policies',
  ];

  final stats = <NewStatItem>[].obs;
  final shortcuts = List<NewShortcutItem>.from(defaultPinnedShortcuts).obs;
  final allQuickActions = List<NewShortcutItem>.from(defaultQuickActions).obs;
  final lateItems = <NewWarningItem>[].obs;
  final writeUps = <NewWarningItem>[].obs;
  final complaints = <NewComplaintItem>[].obs;
  final reminders = <NewReminderItem>[].obs;
  final tasks = <NewTaskItem>[].obs;
  final notifications = <NewNotificationItem>[].obs;

  static const _monthTags = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  final Map<int, int?> _onTimeByMonthOffset = {0: null, -1: 100, -2: 71};

  NewDashboardStatData get warningStat => NewDashboardStatData(
    title: 'Warnings',
    value: warningCountValue.value,
    meta: warningMetaText.value,
  );

  NewDashboardStatData get onTimeStat => NewDashboardStatData(
    title: 'On-Time',
    value: onTimeValue.value,
    meta: onTimeMeta.value,
    tag: onTimeMonthTag.value,
  );

  int get warningTotalCount =>
      lateItems.length + writeUps.length + complaints.length;

  int get warningUnreadCount =>
      lateItems.where((e) => e.unread).length +
      writeUps.where((e) => e.unread).length +
      complaints.where((e) => e.unread).length;

  @override
  void onInit() {
    super.onInit();
    isDarkMode.value = box.read('isDarkMode') ?? false;
    _bootstrapSchedule();
    _loadDummyData();
    _syncStats();
    refreshWarningStat();
    refreshOnTimeStat();
    _syncGreeting();
    _syncLiveStatus();
    _startTicker();
    _syncRing();
    _startDialVisualStateDemo();
  }

  @override
  void onClose() {
    _timer?.cancel();
    _dialDemoTimer?.cancel();
    reminderTitleCtrl.dispose();
    reminderNoteCtrl.dispose();
    complaintNoteCtrl.dispose();
    profileNameCtrl.dispose();
    profilePhoneCtrl.dispose();
    profileEmailCtrl.dispose();
    super.onClose();
  }

  static const _demoDialPeriods = ['morning', 'afternoon', 'evening', 'night'];

  void _startDialVisualStateDemo() {
    if (!AppConfig.enableDialVisualStateDemo) return;
    _dialDemoIndex = 0;
    _applyDialVisualStateDemo();
    _dialDemoTimer?.cancel();
    _dialDemoTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _dialDemoIndex++;
      _applyDialVisualStateDemo();
    });
  }

  /// Preview all dial states including empty assignment.
  /// Day-period loops independently (6 states x 4 periods).
  void _applyDialVisualStateDemo() {
    blinkTier.value = NewTimerBlinkTier.none;
    timerCompact.value = false;
    ringInfoSubtitle.value = selectedSite.value;
    _breakStartAt = null;
    _breakEndAt = null;
    _workedBeforeBreak = 0;
    _shiftClockedInLock.value = false;
    _clockInAt = null;
    lateStartedStyle.value = false;
    breakBadgeText.value = 'Break';
    dialLateEnd.value = 0;
    dialWork1End.value = 0;
    dialBreakEnd.value = 0;
    dialLiveEnd.value = 0;
    dialActiveDots.value = 0;
    demoDialPeriod.value = _demoDialPeriods[_dialDemoIndex % 4];

    switch (_dialDemoIndex % 6) {
      case 0: // Not started yet
        hasAssignedShift.value = true;
        status.value = NewOfficerStatus.standby;
        timerLabel.value = 'Starts In';
        timerText.value = '0:45:00';
        arrivalText.value = 'Upcoming';
        arrivalStatus.value = NewArrivalStatus.pending;
        ringInfoTitle.value = 'Upcoming Shift';
        break;
      case 1: // Start passed, still not clocked in
        hasAssignedShift.value = true;
        status.value = NewOfficerStatus.standby;
        lateStartedStyle.value = true;
        timerLabel.value = 'Late By';
        timerText.value = '0:15:07';
        arrivalText.value = 'Late';
        arrivalStatus.value = NewArrivalStatus.late;
        ringInfoTitle.value = 'Upcoming Shift';
        break;
      case 2: // Working, arrived on time
        hasAssignedShift.value = true;
        status.value = NewOfficerStatus.onShift;
        _shiftClockedInLock.value = true;
        _clockInAt = DateTime.now().subtract(
          const Duration(hours: 2, minutes: 15),
        );
        timerLabel.value = 'Current Shift';
        timerText.value = '2:15:30';
        arrivalText.value = 'On Time';
        arrivalStatus.value = NewArrivalStatus.onTime;
        ringInfoTitle.value = 'Current Shift';
        dialWork1End.value = .28;
        dialBreakEnd.value = .28;
        dialLiveEnd.value = .28;
        dialActiveDots.value = 30;
        break;
      case 3: // Working, but checked in late (green + red warning)
        hasAssignedShift.value = true;
        status.value = NewOfficerStatus.onShift;
        _shiftClockedInLock.value = true;
        _clockInAt = DateTime.now().subtract(
          const Duration(hours: 2, minutes: 15),
        );
        timerLabel.value = 'Current Shift';
        timerText.value = '2:15:30';
        arrivalText.value = 'Late 15m';
        arrivalStatus.value = NewArrivalStatus.late;
        ringInfoTitle.value = 'Current Shift';
        dialLateEnd.value = .03125;
        dialWork1End.value = .31;
        dialBreakEnd.value = .31;
        dialLiveEnd.value = .31;
        dialActiveDots.value = 30;
        break;
      case 4: // On break during an active shift
        hasAssignedShift.value = true;
        status.value = NewOfficerStatus.onBreak;
        _shiftClockedInLock.value = true;
        _clockInAt = DateTime.now().subtract(const Duration(hours: 2));
        _breakStartAt = DateTime.now().subtract(
          const Duration(minutes: 15, seconds: 30),
        );
        _workedBeforeBreak = 2 * 60 * 60;
        timerLabel.value = 'Break Remaining';
        timerText.value = '0:14:30';
        arrivalText.value = 'On Time';
        arrivalStatus.value = NewArrivalStatus.onTime;
        ringInfoTitle.value = 'Current Shift';
        breakBadgeText.value = 'On Break';
        dialWork1End.value = .25;
        dialBreakEnd.value = .283;
        dialLiveEnd.value = .283;
        dialActiveDots.value = 30;
        break;
      default: // No assigned shift
        hasAssignedShift.value = false;
        status.value = NewOfficerStatus.standby;
        timerLabel.value = 'No Shift';
        timerText.value = '—';
        arrivalText.value = 'Pending';
        arrivalStatus.value = NewArrivalStatus.pending;
        ringInfoTitle.value = 'No Shift Scheduled';
        break;
    }
    _syncLiveStatus();
  }

  void _loadDummyData() {
    final now = DateTime.now();
    selectedDate.value = _formatGreetingDate(now);
    ensureShortcutsSeeded(force: true);
    lateItems.assignAll(const [
      NewWarningItem(
        id: 'l1',
        title: 'Late Arrival',
        time: '5/1/2026, 9:05 PM',
        detail: 'Arrived 5 minutes after scheduled start.',
      ),
      NewWarningItem(
        id: 'l2',
        title: 'Late Arrival',
        time: '5/2/2026, 9:08 PM',
        detail: 'Arrived 8 minutes after scheduled start.',
        unread: true,
      ),
    ]);
    writeUps.assignAll(const [
      NewWarningItem(
        id: 'w1',
        title: '1st Write-Up Warning',
        time: '5/1/2026, 9:05 PM',
        detail: 'Formal attendance warning.',
        acknowledged: true,
      ),
      NewWarningItem(
        id: 'w2',
        title: '2nd Write-Up Warning',
        time: '5/2/2026, 9:08 PM',
        detail: 'Second warning for repeated late arrival.',
        acknowledged: true,
      ),
      NewWarningItem(
        id: 'w3',
        title: '3rd Write-Up Warning',
        time: '5/3/2026, 9:10 PM',
        detail: 'Final warning requires acknowledgment.',
        unread: true,
      ),
    ]);
    complaints.assignAll(const [
      NewComplaintItem(
        id: 'c1',
        title: 'Resident reported delayed lobby response',
        site: 'BayCrest',
        severity: 'Medium',
        filedBy: 'Sarah Chen, Site Manager',
        filedAt: '5/3/2026, 4:12 PM',
        incidentDate: '5/2/2026, 11:14 PM',
        detail:
            'Resident reported waiting at the front desk while lobby was unattended.',
        expectedAction:
            'Notify relief or supervisor before leaving front desk.',
        unread: true,
      ),
      NewComplaintItem(
        id: 'c2',
        title: 'Visitor sign-in policy not followed',
        site: 'BayCrest',
        severity: 'Low',
        filedBy: 'David Park, Property Manager',
        filedAt: '4/28/2026, 9:45 AM',
        incidentDate: '4/27/2026, 8:22 PM',
        detail:
            'Delivery contractor was allowed past lobby without visitor log.',
        expectedAction: 'All non-resident entries must complete visitor log.',
        unread: true,
      ),
      NewComplaintItem(
        id: 'c3',
        title: 'Tenant complaint — dismissive tone',
        site: 'Prism',
        severity: 'High',
        filedBy: 'Marcus Webb, Building Manager',
        filedAt: '4/22/2026, 2:30 PM',
        incidentDate: '4/21/2026, 6:45 PM',
        detail:
            'Tenant reported confrontational tone during after-hours access request.',
        expectedAction: 'Maintain professional and courteous tone.',
        acknowledged: true,
        note: 'Reviewed after-hours access list.',
      ),
    ]);
    reminders.assignAll(const [
      NewReminderItem(
        id: 'r1',
        title: 'Submit weekly report',
        dateText: 'Today',
        timeText: '7:30 PM',
        repeat: NewReminderRepeat.weekly,
        note: 'Upload before shift starts.',
      ),
      NewReminderItem(
        id: 'r2',
        title: 'Check fire panel',
        dateText: 'Tomorrow',
        timeText: '9:15 PM',
        repeat: NewReminderRepeat.daily,
        fromManagement: true,
      ),
      NewReminderItem(
        id: 'r3',
        title: 'Uniform inspection',
        dateText: 'May 8',
        timeText: '8:30 PM',
        repeat: NewReminderRepeat.once,
        completed: true,
      ),
    ]);
    tasks.assignAll(const [
      NewTaskItem(
        id: 't1',
        title: 'Inspect east stairwell',
        detail: 'Confirm all emergency lights are active.',
        dueText: 'Today · 10 PM',
        priority: 'High',
      ),
      NewTaskItem(
        id: 't2',
        title: 'Upload lobby report',
        detail: 'Attach photos and visitor log summary.',
        dueText: 'Today · 11 PM',
      ),
      NewTaskItem(
        id: 't3',
        title: 'Review site manual update',
        detail: 'Read updated access control policy.',
        dueText: 'Tomorrow',
      ),
    ]);
    notifications.assignAll(const [
      NewNotificationItem(
        id: 'n1',
        title: 'Shift starts in 1 hour',
        body:
            'BayCrest lobby shift begins soon. Arrive on site before 9:00 PM and complete clock-in.',
        dateText: 'Today',
        timeText: '8:00 PM',
        type: 'Shift Reminder',
        source: 'System',
        site: 'BayCrest',
        shiftText: '9 PM – 5 AM',
        actionLabel: 'View Shift',
        iconKey: 'shift',
        colorKey: 'blue',
        unread: true,
      ),
      NewNotificationItem(
        id: 'n2',
        title: 'Reminder from Management',
        body:
            'Check fire panel at the start of shift and add a note in the shift log.',
        dateText: 'Today',
        timeText: '6:15 PM',
        type: 'Reminder',
        source: 'Management',
        site: 'BayCrest',
        actionLabel: 'Open Reminder',
        iconKey: 'reminder',
        colorKey: 'amber',
        unread: true,
      ),
      NewNotificationItem(
        id: 'n3',
        title: 'New task assigned',
        body:
            'Inspect east stairwell and confirm all emergency lights are active.',
        dateText: 'Today',
        timeText: '5:40 PM',
        type: 'Task',
        source: 'Dispatch',
        site: 'BayCrest',
        actionLabel: 'View Task',
        iconKey: 'task',
        colorKey: 'purple',
      ),
      NewNotificationItem(
        id: 'n4',
        title: 'Complaint requires acknowledgment',
        body:
            'A resident complaint was filed for delayed lobby response. Review and submit your response.',
        dateText: 'Yesterday',
        timeText: '4:12 PM',
        type: 'Complaint',
        source: 'Management',
        site: 'BayCrest',
        actionLabel: 'Review Complaint',
        iconKey: 'warning',
        colorKey: 'red',
        unread: true,
        critical: true,
      ),
      NewNotificationItem(
        id: 'n5',
        title: 'Dispatch message',
        body: 'Parking level B2 requires extra patrol after 10:00 PM.',
        dateText: 'Yesterday',
        timeText: '2:25 PM',
        type: 'Message',
        source: 'Dispatch',
        site: 'BayCrest',
        actionLabel: 'Open Messages',
        iconKey: 'message',
        colorKey: 'teal',
      ),
    ]);
    refreshActionBadges();
  }

  void _syncStats() {
    refreshWarningStat();
    refreshOnTimeStat();
    stats.assignAll([
      NewStatItem(
        title: warningStat.title,
        value: warningStat.value,
        meta: warningStat.meta,
        iconKey: 'warning',
        isWarning: true,
      ),
      NewStatItem(
        title: onTimeStat.title,
        value: onTimeStat.value,
        meta: onTimeStat.meta,
        iconKey: 'check',
      ),
    ]);
  }

  void refreshWarningStat() {
    final total = warningTotalCount;
    final unread = warningUnreadCount;
    warningCountValue.value = '$total';
    warningHasUnread.value = unread > 0;
    if (total == 0) {
      warningMetaText.value = 'No active warnings';
    } else if (unread > 0) {
      warningMetaText.value = '$unread new · tap to review';
    } else {
      warningMetaText.value = '$total on record';
    }
  }

  void refreshOnTimeStat() {
    final now = DateTime.now();
    final display = DateTime(now.year, now.month + monthStatOffset.value, 1);
    final tag = _monthTags[display.month - 1];
    onTimeMonthTag.value = tag;
    final thisVal = _onTimeByMonthOffset[monthStatOffset.value];
    final prevVal = _onTimeByMonthOffset[monthStatOffset.value - 1];
    if (thisVal == null) {
      onTimeValue.value = '-';
      onTimeMeta.value = 'No shifts in $tag';
      return;
    }
    onTimeValue.value = '$thisVal%';
    if (prevVal == null) {
      onTimeMeta.value = 'Across $tag shifts';
      return;
    }
    final delta = thisVal - prevVal;
    final compare = monthStatOffset.value == 0 ? 'MoM' : 'vs prior';
    if (delta > 0) {
      onTimeMeta.value = '↑ $delta% $compare';
    } else if (delta < 0) {
      onTimeMeta.value = '↓ ${delta.abs()}% $compare';
    } else {
      onTimeMeta.value = 'Same as prior month';
    }
  }

  DateTime? _onTimeResetAt;

  void handleOnTimeStatTap() {
    final now = DateTime.now();
    final last = _onTimeResetAt;
    if (last != null && now.difference(last).inMilliseconds < 350) {
      monthStatOffset.value = 0;
      refreshOnTimeStat();
      _onTimeResetAt = null;
      return;
    }
    monthStatOffset.value -= 1;
    refreshOnTimeStat();
    _onTimeResetAt = now;
    Future.delayed(const Duration(seconds: 5), () {
      if (_onTimeResetAt == now) {
        monthStatOffset.value = 0;
        refreshOnTimeStat();
        _onTimeResetAt = null;
      }
    });
  }

  void resetOnTimeStat() {
    monthStatOffset.value = 0;
    refreshOnTimeStat();
  }

  void _bootstrapSchedule() {
    final now = DateTime.now();
    final todayNine = DateTime(now.year, now.month, now.day, 21);
    final yesterdayNine = todayNine.subtract(const Duration(days: 1));
    final yesterdayEnd = yesterdayNine.add(const Duration(hours: 8));
    final todayEnd = todayNine.add(const Duration(hours: 8));
    late DateTime start;
    late DateTime end;
    if (!now.isBefore(yesterdayNine) && now.isBefore(yesterdayEnd)) {
      start = yesterdayNine;
      end = yesterdayEnd;
    } else if (!now.isBefore(todayNine) && now.isBefore(todayEnd)) {
      start = todayNine;
      end = todayEnd;
    } else if (now.isBefore(todayNine)) {
      start = todayNine;
      end = todayEnd;
    } else {
      start = todayNine.add(const Duration(days: 1));
      end = start.add(const Duration(hours: 8));
    }
    scheduledShiftStart = start;
    scheduledShiftEnd = end;
    selectedShift.value = '${_fmtAmpm(start)} – ${_fmtAmpm(end)} · 8hr';
  }

  void toggleTheme() {
    final next = !isDarkMode.value;
    isDarkMode.value = next;
    box.write('isDarkMode', next);
    Get.changeThemeMode(next ? ThemeMode.dark : ThemeMode.light);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: next ? Brightness.light : Brightness.dark,
        statusBarBrightness: next ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: next
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
      ),
    );
    if (Get.isRegistered<SettingsController>()) {
      Get.find<SettingsController>().isDarkMode.value = next;
    }
  }

  void openSideMenu() => sideMenuOpen.value = true;
  void closeSideMenu() => sideMenuOpen.value = false;
  void toggleCompliance() => complianceExpanded.toggle();
  static const int pinnedShortcutCount = 9;

  void toggleShortcutEdit() => shortcutEditing.toggle();
  void toggleQuickActionEdit() => quickActionsEditing.toggle();

  void ensureShortcutsSeeded({bool force = false}) {
    if (force || shortcuts.isEmpty) {
      shortcuts.assignAll(defaultPinnedShortcuts);
    }
    if (force || allQuickActions.isEmpty) {
      allQuickActions.assignAll(defaultQuickActions);
    }
  }

  void healShortcuts() {
    if (shortcuts.isEmpty ||
        shortcuts.length != defaultPinnedShortcuts.length) {
      shortcuts.assignAll(defaultPinnedShortcuts);
    }
    if (allQuickActions.isEmpty) {
      allQuickActions.assignAll(defaultQuickActions);
    }
    refreshActionBadges();
  }

  List<NewShortcutItem> visibleShortcuts() {
    final source = shortcuts.isEmpty
        ? defaultPinnedShortcuts
        : List<NewShortcutItem>.from(shortcuts);
    return source.where((e) => !e.hidden).take(pinnedShortcutCount).toList();
  }

  List<NewShortcutItem> visibleQuickActions() {
    final source = allQuickActions.isEmpty
        ? defaultQuickActions
        : List<NewShortcutItem>.from(allQuickActions);
    return source.where((e) => !e.hidden).toList();
  }

  List<NewShortcutItem> shortcutEditItems() {
    final pinned = visibleShortcuts();
    final pinnedIds = pinned.map((e) => e.id).toSet();
    final extras = visibleQuickActions()
        .where((e) => !pinnedIds.contains(e.id))
        .toList();
    return [...pinned, ...extras];
  }

  void reorderShortcut(NewShortcutItem from, NewShortcutItem to) {
    if (shortcutEditing.value) {
      _reorderShortcutEdit(from, to);
      return;
    }
    _reorderInList(shortcuts, from, to);
  }

  void reorderQuickAction(NewShortcutItem from, NewShortcutItem to) {
    _reorderInList(allQuickActions, from, to);
  }

  void _reorderShortcutEdit(NewShortcutItem from, NewShortcutItem to) {
    if (from.id == to.id) return;
    final list = shortcutEditItems();
    final fromIndex = list.indexWhere((e) => e.id == from.id);
    final toIndex = list.indexWhere((e) => e.id == to.id);
    if (fromIndex < 0 || toIndex < 0 || fromIndex == toIndex) return;
    final item = list.removeAt(fromIndex);
    list.insert(toIndex, item);
    final nextPinned = list.take(pinnedShortcutCount).toList();
    final nextExtras = list.skip(pinnedShortcutCount).toList();
    shortcuts.assignAll(nextPinned);
    final byId = <String, NewShortcutItem>{
      for (final e in allQuickActions) e.id: e,
    };
    for (final e in list) {
      byId[e.id] = e;
    }
    allQuickActions.assignAll([
      ...nextPinned.map((e) => byId[e.id] ?? e),
      ...nextExtras.map((e) => byId[e.id] ?? e),
      ...allQuickActions.where((e) => !list.any((x) => x.id == e.id)),
    ]);
    refreshActionBadges();
  }

  void _reorderInList(
    RxList<NewShortcutItem> target,
    NewShortcutItem from,
    NewShortcutItem to,
  ) {
    if (from.id == to.id) return;
    final list = List<NewShortcutItem>.from(target);
    final fromIndex = list.indexWhere((e) => e.id == from.id);
    final toIndex = list.indexWhere((e) => e.id == to.id);
    if (fromIndex < 0 || toIndex < 0 || fromIndex == toIndex) return;
    final item = list.removeAt(fromIndex);
    list.insert(toIndex, item);
    target
      ..assignAll(list)
      ..refresh();
  }

  @override
  void onReady() {
    super.onReady();
    healShortcuts();
  }

  static const List<NewShortcutItem> defaultPinnedShortcuts = [
    NewShortcutItem(
      id: 'shiftLog',
      title: 'Shift Log',
      iconKey: 'log',
      colorKey: 'teal',
    ),
    NewShortcutItem(
      id: 'patrol',
      title: 'Patrol',
      iconKey: 'patrol',
      colorKey: 'purple',
    ),
    NewShortcutItem(
      id: 'incident',
      title: 'Incident Report',
      iconKey: 'incident',
      colorKey: 'red',
    ),
    NewShortcutItem(
      id: 'issue',
      title: 'Report Issue',
      iconKey: 'warning',
      colorKey: 'amber',
    ),
    NewShortcutItem(
      id: 'tasks',
      title: 'Tasks',
      iconKey: 'tasks',
      colorKey: 'blue',
      badge: '3',
    ),
    NewShortcutItem(
      id: 'reminders',
      title: 'Reminders',
      iconKey: 'bell',
      colorKey: 'amber',
    ),
    NewShortcutItem(
      id: 'walkthrough',
      title: 'Site Walkthrough',
      iconKey: 'walkthrough',
      colorKey: 'teal',
    ),
    NewShortcutItem(
      id: 'manual',
      title: 'Site Manual',
      iconKey: 'manual',
      colorKey: 'purple',
    ),
    NewShortcutItem(
      id: 'payroll',
      title: 'Payroll',
      iconKey: 'payroll',
      colorKey: 'green',
    ),
  ];

  static const List<NewShortcutItem> defaultQuickActions = [
    NewShortcutItem(
      id: 'clock',
      title: 'Clock In',
      iconKey: 'clock',
      colorKey: 'blue',
    ),
    NewShortcutItem(
      id: 'issue',
      title: 'Report Issue',
      iconKey: 'warning',
      colorKey: 'amber',
    ),
    NewShortcutItem(
      id: 'walkthrough',
      title: 'Site Walkthrough',
      iconKey: 'walkthrough',
      colorKey: 'teal',
    ),
    NewShortcutItem(
      id: 'patrol',
      title: 'Patrol',
      iconKey: 'patrol',
      colorKey: 'purple',
    ),
    NewShortcutItem(
      id: 'patrolPlan',
      title: 'Patrol Plan',
      iconKey: 'tasks',
      colorKey: 'purple',
      badge: '4',
    ),
    NewShortcutItem(
      id: 'shiftLog',
      title: 'Shift Log',
      iconKey: 'log',
      colorKey: 'teal',
    ),
    NewShortcutItem(
      id: 'incident',
      title: 'Incident Report',
      iconKey: 'incident',
      colorKey: 'red',
    ),
    NewShortcutItem(
      id: 'parking',
      title: 'Parking Management',
      iconKey: 'parking',
      colorKey: 'slate',
    ),
    NewShortcutItem(
      id: 'fleet',
      title: 'Fleet',
      iconKey: 'fleet',
      colorKey: 'pink',
    ),
    NewShortcutItem(
      id: 'move',
      title: 'Pre/Post Inspection',
      iconKey: 'home',
      colorKey: 'green',
    ),
    NewShortcutItem(
      id: 'tasks',
      title: 'Tasks',
      iconKey: 'tasks',
      colorKey: 'blue',
      badge: '3',
    ),
    NewShortcutItem(
      id: 'manual',
      title: 'Site Manual',
      iconKey: 'manual',
      colorKey: 'purple',
    ),
    NewShortcutItem(
      id: 'firewatch',
      title: 'Firewatch',
      iconKey: 'fire',
      colorKey: 'red',
      enabled: false,
    ),
    NewShortcutItem(
      id: 'reminders',
      title: 'Reminders',
      iconKey: 'bell',
      colorKey: 'amber',
    ),
    NewShortcutItem(
      id: 'reportAssist',
      title: 'Report Assist',
      iconKey: 'assist',
      colorKey: 'blue',
    ),
    NewShortcutItem(
      id: 'payroll',
      title: 'Payroll',
      iconKey: 'payroll',
      colorKey: 'green',
    ),
    NewShortcutItem(
      id: 'break',
      title: 'Start Break',
      iconKey: 'coffee',
      colorKey: 'amber',
    ),
  ];

  NewShortcutItem _withLiveBadge(NewShortcutItem e) {
    final open = openTasksCount;
    final pendingReminders = reminders.where((r) => !r.completed).length;
    if (e.id == 'tasks') {
      return NewShortcutItem(
        id: e.id,
        title: e.title,
        iconKey: e.iconKey,
        colorKey: e.colorKey,
        enabled: e.enabled,
        hidden: e.hidden,
        badge: open > 0 ? '$open' : null,
      );
    }
    if (e.id == 'reminders') {
      return NewShortcutItem(
        id: e.id,
        title: e.title,
        iconKey: e.iconKey,
        colorKey: e.colorKey,
        enabled: e.enabled,
        hidden: e.hidden,
        badge: pendingReminders > 0 ? '$pendingReminders' : null,
      );
    }
    if (e.id == 'clock') {
      return NewShortcutItem(
        id: e.id,
        title: hasActiveDuty ? 'Clock Out' : 'Clock In',
        iconKey: e.iconKey,
        colorKey: e.colorKey,
        enabled: e.enabled,
        hidden: e.hidden,
        badge: e.badge,
      );
    }
    if (e.id == 'break') {
      return NewShortcutItem(
        id: e.id,
        title: breakActionLabel,
        iconKey: e.iconKey,
        colorKey: e.colorKey,
        enabled: breakActionEnabled && !breakTaken,
        hidden: e.hidden,
        badge: e.badge,
      );
    }
    return e;
  }

  void refreshActionBadges() {
    final pinned = shortcuts.isEmpty
        ? List<NewShortcutItem>.from(defaultPinnedShortcuts)
        : List<NewShortcutItem>.from(shortcuts);
    final all = allQuickActions.isEmpty
        ? List<NewShortcutItem>.from(defaultQuickActions)
        : List<NewShortcutItem>.from(allQuickActions);
    shortcuts.assignAll(pinned.map(_withLiveBadge).toList());
    allQuickActions.assignAll(all.map(_withLiveBadge).toList());
  }

  String _formatGreetingDate(DateTime date) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  void startShiftFlow() {
    if (showNoAssignedShift) {
      showInfoText(
        'No Shift Scheduled',
        'If you believe a shift is missing, please contact the Dispatch team.',
      );
      return;
    }
    if (!hasActiveDuty) {
      final minsToStart = scheduledShiftStart
          .difference(DateTime.now())
          .inMinutes;
      if (minsToStart > 30) {
        showInfoText(
          'Too Early',
          'You can clock in starting 30 minutes before ${_fmtAmpm(scheduledShiftStart)}.',
        );
        return;
      }
      _confirm('Start Shift', 'Clock in for $selectedSite now?', () {
        if (showNoAssignedShift) return;
        final now = DateTime.now();
        _applyArrival(now);
        _shiftClockedInLock.value = true;
        if (now.isBefore(scheduledShiftStart)) {
          status.value = NewOfficerStatus.standby;
          _clockInAt = null;
          timerLabel.value = 'Stand By';
          breakBadgeText.value = 'Break';
        } else {
          _clockInAt = now;
          status.value = NewOfficerStatus.onShift;
          timerLabel.value = 'Current Shift';
        }
        _breakStartAt = null;
        _breakEndAt = null;
        _workedBeforeBreak = 0;
        ringInfoTitle.value = 'Current Shift';
        ringInfoSubtitle.value = selectedSite.value;
        _syncLiveStatus();
        _syncRing();
        refreshActionBadges();
      });
      return;
    }
    _confirm(
      _clockInAt == null ? 'Leave Stand By' : 'End Shift',
      _clockInAt == null
          ? 'Cancel stand-by and leave the site check-in?'
          : 'Clock out and finish this shift?',
      () {
        status.value = NewOfficerStatus.standby;
        _clockInAt = null;
        _breakStartAt = null;
        _breakEndAt = null;
        _workedBeforeBreak = 0;
        _shiftClockedInLock.value = false;
        breakBadgeText.value = 'Break';
        arrivalText.value = 'Pending';
        arrivalStatus.value = NewArrivalStatus.pending;
        dialLateEnd.value = 0;
        dialWork1End.value = 0;
        dialBreakEnd.value = 0;
        dialLiveEnd.value = 0;
        dialActiveDots.value = 0;
        _syncLiveStatus();
        _syncRing();
        refreshActionBadges();
      },
      danger: true,
    );
  }

  void toggleBreak() {
    if (showNoAssignedShift) {
      showInfoText('Break Unavailable', 'No shift is scheduled.');
      return;
    }
    if (!isRunning && !_shiftClockedInLock.value) {
      showInfoText('Break Unavailable', 'Start shift before taking a break.');
      return;
    }
    if (_clockInAt == null) {
      showInfoText(
        'Break Unavailable',
        'Break starts after your scheduled shift begins.',
      );
      return;
    }
    if (status.value == NewOfficerStatus.onShift) {
      _workedBeforeBreak = _workedSeconds();
      _breakStartAt = DateTime.now();
      _breakEndAt = null;
      status.value = NewOfficerStatus.onBreak;
      breakBadgeText.value = 'On Break';
      _syncLiveStatus();
      _syncRing();
      return;
    }
    if (status.value == NewOfficerStatus.onBreak) {
      _breakEndAt = DateTime.now();
      status.value = NewOfficerStatus.onShift;
      breakBadgeText.value = 'Taken';
      _syncLiveStatus();
      _syncRing();
    }
  }

  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _syncGreeting();
      if (AppConfig.enableDialVisualStateDemo) {
        _applyDialVisualStateDemo();
        return;
      }
      if (showNoAssignedShift) return;
      if (_shiftClockedInLock.value &&
          _clockInAt == null &&
          !DateTime.now().isBefore(scheduledShiftStart)) {
        _clockInAt = scheduledShiftStart;
        status.value = NewOfficerStatus.onShift;
        timerLabel.value = 'Current Shift';
        _syncLiveStatus();
        refreshActionBadges();
      }
      if (isOnBreak &&
          _breakStartAt != null &&
          DateTime.now().difference(_breakStartAt!).inMilliseconds >=
              _breakDurationMs) {
        _breakEndAt = _breakStartAt!.add(
          Duration(milliseconds: _breakDurationMs),
        );
        status.value = NewOfficerStatus.onShift;
        breakBadgeText.value = 'Taken';
        _syncLiveStatus();
      }
      _syncRing();
    });
  }

  void _applyArrival(DateTime clockIn) {
    final mins = scheduledShiftStart.difference(clockIn).inMinutes;
    if (mins >= 10) {
      arrivalStatus.value = NewArrivalStatus.onTime;
      arrivalText.value = 'On-Time ${_fmtLateDuration(mins)}';
    } else if (mins >= 0) {
      arrivalStatus.value = NewArrivalStatus.early;
      arrivalText.value = 'Early ${_fmtLateDuration(mins)}';
    } else if (mins >= -5) {
      arrivalStatus.value = NewArrivalStatus.onTime;
      arrivalText.value = 'On Time';
    } else if (mins >= -15) {
      arrivalStatus.value = NewArrivalStatus.slight;
      arrivalText.value = 'Slightly Late ${_fmtLateDuration(-mins)}';
    } else {
      arrivalStatus.value = NewArrivalStatus.late;
      arrivalText.value = 'Late ${_fmtLateDuration(-mins)}';
    }
  }

  int _lateSeconds() {
    final clockIn = _clockInAt;
    if (clockIn == null) return 0;
    final late = clockIn.difference(scheduledShiftStart).inSeconds;
    return late > 0 ? late : 0;
  }

  int _workedSeconds() {
    final clockIn = _clockInAt;
    if (clockIn == null) return 0;
    final now = DateTime.now();
    if (isOnBreak && _breakStartAt != null) return _workedBeforeBreak;
    if (_breakStartAt != null && _breakEndAt != null) {
      return _workedBeforeBreak +
          now.difference(_breakEndAt!).inSeconds.clamp(0, shiftTotalSeconds);
    }
    return now.difference(clockIn).inSeconds.clamp(0, shiftTotalSeconds * 2);
  }

  int _progressNow() => _clampSec(_lateSeconds() + _workedSeconds());

  int _breakProgressStart() => _clampSec(_lateSeconds() + _workedBeforeBreak);

  int? _breakProgressEnd() {
    if (_breakStartAt == null) return null;
    final dur = _breakEndAt != null
        ? _breakEndAt!.difference(_breakStartAt!).inSeconds
        : DateTime.now().difference(_breakStartAt!).inSeconds;
    return _clampSec(_breakProgressStart() + (dur < 0 ? 0 : dur));
  }

  int _clampSec(int v) {
    if (v < 0) return 0;
    if (v > shiftTotalSeconds) return shiftTotalSeconds;
    return v;
  }

  double _frac(int sec) => sec / shiftTotalSeconds;

  void _drawSegs() {
    if (_clockInAt == null) {
      dialLateEnd.value = 0;
      dialWork1End.value = 0;
      dialBreakEnd.value = 0;
      dialLiveEnd.value = 0;
      dialActiveDots.value = 0;
      return;
    }
    final late = _lateSeconds();
    final live = _progressNow();
    dialLateEnd.value = _frac(late);
    if (_breakStartAt != null) {
      final bs = _breakProgressStart();
      final be = _breakProgressEnd() ?? bs;
      dialWork1End.value = _frac(bs > late ? bs : late);
      dialBreakEnd.value = _frac(be > bs ? be : bs);
      dialLiveEnd.value = !isOnBreak && be < live ? _frac(live) : _frac(be);
    } else {
      dialWork1End.value = live > late ? _frac(live) : _frac(late);
      dialBreakEnd.value = dialWork1End.value;
      dialLiveEnd.value = dialWork1End.value;
    }
  }

  void _syncRing() {
    if (AppConfig.enableDialVisualStateDemo) {
      _applyDialVisualStateDemo();
      return;
    }
    if (showNoAssignedShift) return;
    final now = DateTime.now();
    ringInfoSubtitle.value = selectedSite.value;

    if (_clockInAt != null ||
        (_shiftClockedInLock.value && !now.isBefore(scheduledShiftStart))) {
      blinkTier.value = NewTimerBlinkTier.none;
      lateStartedStyle.value = false;
      timerCompact.value = false;
      if (isOnBreak && _breakStartAt != null) {
        final remainingMs =
            _breakDurationMs - now.difference(_breakStartAt!).inMilliseconds;
        final sec = remainingMs > 0 ? (remainingMs / 1000).ceil() : 0;
        timerLabel.value = remainingMs > 0 ? 'Break Remaining' : 'Break Over';
        timerText.value = _fmtCountdown(sec);
        dialActiveDots.value = sec % 60;
      } else {
        final w = _workedSeconds();
        timerLabel.value = 'Current Shift';
        timerText.value = _fmtCountdown(w);
        dialActiveDots.value = w % 60;
      }
      ringInfoTitle.value = 'Current Shift';
      _drawSegs();
      return;
    }

    dialLateEnd.value = 0;
    dialWork1End.value = 0;
    dialBreakEnd.value = 0;
    dialLiveEnd.value = 0;

    final msToStart = scheduledShiftStart.difference(now).inMilliseconds;
    NewTimerBlinkTier tier = NewTimerBlinkTier.none;

    dialActiveDots.value = 0;

    if (msToStart <= 0) {
      final elapsedLate = now.difference(scheduledShiftStart).inSeconds;
      timerLabel.value = 'Late By';
      timerText.value = _fmtCountdown(elapsedLate);
      lateStartedStyle.value = true;
      timerCompact.value = false;
      if (!_shiftClockedInLock.value) tier = NewTimerBlinkTier.red;
      arrivalText.value = 'Late';
      arrivalStatus.value = NewArrivalStatus.late;
      ringInfoTitle.value = 'Upcoming Shift';
    } else {
      final seconds = msToStart ~/ 1000;
      lateStartedStyle.value = false;
      if (seconds <= 86400) {
        timerLabel.value = _shiftClockedInLock.value ? 'Stand By' : 'Starts In';
        timerText.value = _fmtCountdown(seconds);
        timerCompact.value = false;
        if (!_shiftClockedInLock.value) {
          arrivalText.value = 'Upcoming';
          arrivalStatus.value = NewArrivalStatus.pending;
          if (seconds <= 30 * 60) {
            tier = NewTimerBlinkTier.red;
          } else if (seconds <= 45 * 60) {
            tier = NewTimerBlinkTier.orange;
          } else if (seconds <= 60 * 60) {
            tier = NewTimerBlinkTier.yellow;
          }
        }
      } else {
        timerLabel.value = 'Upcoming Shift';
        timerText.value = 'No coverage 24h';
        timerCompact.value = true;
        if (!_shiftClockedInLock.value) {
          arrivalText.value = 'Upcoming';
          arrivalStatus.value = NewArrivalStatus.pending;
        }
      }
      ringInfoTitle.value = 'Upcoming Shift';
    }
    blinkTier.value = tier;
  }

  String _fmtCountdown(int sec) {
    final s = sec < 0 ? 0 : sec;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final r = s % 60;
    return '$h:${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  String _fmtLateDuration(int mins) {
    if (mins < 60) return '${mins}m';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  String _fmtAmpm(DateTime d) {
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    if (d.minute == 0) return '$hour $ap';
    return '$hour:${d.minute.toString().padLeft(2, '0')} $ap';
  }

  void handleShortcut(String id) {
    switch (id) {
      case 'shiftLog':
        if (Get.isRegistered<NewMainController>()) {
          Get.find<NewMainController>().openShiftLog();
        }
        break;
      case 'clock':
        startShiftFlow();
        break;
      case 'break':
        toggleBreak();
        break;
      case 'tasks':
        openTasks();
        break;
      case 'reminders':
        openReminders();
        break;
      case 'issue':
        if (status.value == NewOfficerStatus.standby) {
          showInfoText(
            'Not On Shift',
            'Start your shift before reporting an issue.',
          );
          return;
        }
        NewFeatureFlows.openReportIssue();
        break;
      case 'patrol':
        if (status.value == NewOfficerStatus.standby) {
          showInfoText(
            'Not On Shift',
            'Start your shift before starting a patrol.',
          );
          return;
        }
        NewFeatureFlows.openPatrol();
        break;
      case 'patrolPlan':
        NewFeatureFlows.openPatrolPlan();
        break;
      case 'incident':
        NewFeatureFlows.openIncident();
        break;
      case 'parking':
        NewFeatureFlows.openParking();
        break;
      case 'fleet':
        NewFeatureFlows.openFleet();
        break;
      case 'move':
        NewFeatureFlows.openMoveInspection();
        break;
      case 'manual':
        NewFeatureFlows.openSiteManual();
        break;
      case 'firewatch':
        showInfoText(
          'Firewatch Disabled',
          'Firewatch is available only when the active shift has firewatch enabled.',
        );
        break;
      case 'walkthrough':
        NewFeatureFlows.openWalkthrough();
        break;
      case 'payroll':
        NewFeatureFlows.openPayroll();
        break;
      case 'reportAssist':
        NewFeatureFlows.openReportAssist();
        break;
      default:
        showInfoText('Action', 'This action is not available yet.');
    }
  }

  void setWarningTab(NewWarningTab tab) => warningTab.value = tab;
  void setReminderTab(NewReminderTab tab) => reminderTab.value = tab;
  void setReminderRepeat(NewReminderRepeat repeat) =>
      selectedReminderRepeat.value = repeat;
  void toggleReminderCritical(bool value) => reminderCritical.value = value;
  void toggleReminderAutoSnooze(bool value) => reminderAutoSnooze.value = value;
  void toggleReminderCalendar(bool value) => reminderShowCalendar.value = value;

  List<NewReminderItem> get filteredReminders {
    switch (reminderTab.value) {
      case NewReminderTab.upcoming:
        return reminders.where((e) => !e.completed).toList();
      case NewReminderTab.completed:
        return reminders.where((e) => e.completed).toList();
      case NewReminderTab.all:
        return reminders;
    }
  }

  List<NewTaskItem> get filteredTasks => tasks
      .where((e) => taskOpenTab.value ? !e.completed : e.completed)
      .toList();

  void saveReminder() {
    final title = reminderTitleCtrl.text.trim();
    if (title.isEmpty) {
      showInfoText('Missing Title', 'Please enter reminder title.');
      return;
    }
    reminders.insert(
      0,
      NewReminderItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        dateText: 'Today',
        timeText: '9:00 PM',
        repeat: selectedReminderRepeat.value,
        note: reminderNoteCtrl.text.trim(),
        critical: reminderCritical.value,
        autoSnooze: reminderAutoSnooze.value,
        showOnCalendar: reminderShowCalendar.value,
      ),
    );
    reminderTitleCtrl.clear();
    reminderNoteCtrl.clear();
    refreshActionBadges();
    Get.back();
  }

  void completeTask(NewTaskItem task) {
    final index = tasks.indexWhere((e) => e.id == task.id);
    if (index == -1) return;
    tasks[index] = task.copyWith(completed: true);
    refreshActionBadges();
  }

  void markAllNotificationsRead() {
    notifications.assignAll(
      notifications.map((e) => e.copyWith(unread: false)).toList(),
    );
  }

  void clearNotifications() {
    notifications.clear();
  }

  void acknowledgeComplaint(NewComplaintItem item) {
    final index = complaints.indexWhere((e) => e.id == item.id);
    if (index == -1) return;
    complaints[index] = item.copyWith(
      unread: false,
      acknowledged: true,
      note: complaintNoteCtrl.text.trim(),
    );
    complaintNoteCtrl.clear();
    refreshWarningStat();
    _syncStats();
    Get.back();
  }

  void openWarnings() => Get.dialog(NewWarningsDialog(controller: this));
  void openNotifications() => Get.to(() => const NewNotificationsScreen());
  void openReminders() => Get.dialog(NewRemindersDialog(controller: this));
  void openReminderEditor() =>
      Get.dialog(NewReminderEditorDialog(controller: this));
  void openEditProfile() => Get.dialog(NewEditProfileDialog(controller: this));
  void openTasks() => Get.dialog(NewTasksDialog(controller: this));

  void openProfileScreen() {
    closeSideMenu();
    if (Get.isRegistered<NewMainController>()) {
      Get.find<NewMainController>().changePage(4);
      return;
    }
    Get.to(() => const NewProfileScreen(), transition: Transition.cupertino);
  }

  void handleNotificationAction(NewNotificationItem item) {
    final type = item.type.toLowerCase();
    if (type.contains('complaint') || type.contains('warning')) {
      openWarnings();
      return;
    }
    if (type.contains('reminder')) {
      openReminders();
      return;
    }
    if (type.contains('task')) {
      openTasks();
      return;
    }
    if (type.contains('message')) {
      if (Get.isRegistered<NewMainController>()) {
        Get.find<NewMainController>().changePage(2);
      }
      return;
    }
    if (type.contains('shift')) {
      if (Get.isRegistered<NewMainController>()) {
        Get.find<NewMainController>().openShiftLog();
      }
    }
  }

  void openComplaint(NewComplaintItem complaint) {
    complaintNoteCtrl.text = complaint.note;
    Get.dialog(NewComplaintDialog(controller: this, complaint: complaint));
  }

  void saveProfile() {
    final name = profileNameCtrl.text.trim();
    if (name.isNotEmpty) officerName.value = name;
    Get.back();
  }

  void showInfoOnsite() =>
      showInfoText('On-Site SCH', 'On-site schedule preview is ready.');
  void showInfoPatrol() => showInfoText(
    'Patrol Officer SCH',
    'Patrol officer schedule preview is ready.',
  );
  void showInfoSettings() =>
      showInfoText('Settings', 'Settings UI will be connected later.');
  void showInfoJobs() =>
      showInfoText('Job Applications', 'Job applications preview.');
  void showInfoTraining() =>
      showInfoText('Training & Onboarding', 'Training and onboarding preview.');
  void showInfoDispatch() => showInfoText(
    'Contact Dispatch',
    'Dispatch contact actions will be connected later.',
  );

  void showInfoText(String title, String body) {
    Get.dialog(NewInfoDialog(title: title, body: body));
  }

  void showLogoutConfirm() {
    _confirm(
      'Logout',
      'Are you sure you want to logout?',
      () => unawaited(_performLogout()),
      danger: true,
    );
  }

  Future<void> _performLogout() async {
    sideMenuOpen.value = false;

    final mem = Get.isRegistered<MemoryStorageController>()
        ? Get.find<MemoryStorageController>()
        : Get.put(MemoryStorageController());
    mem.setRegionId(null);
    mem.setShiftId(null);
    mem.setSiteId(null);
    mem.setSeriesId(null);
    mem.setRegionName('');
    mem.setShiftName('');
    mem.setSiteName('');
    mem.setIsScopeSelected(false);
    mem.setShiftStartTime(null);
    mem.setShiftEndTime(null);

    final settings = Get.isRegistered<SettingsController>()
        ? Get.find<SettingsController>()
        : Get.put(SettingsController());
    final context = Get.context;
    if (context == null || !context.mounted) return;
    await settings.handleLogout(context);
  }

  void _confirm(
    String title,
    String body,
    VoidCallback onConfirm, {
    bool danger = false,
  }) {
    Get.dialog(
      NewConfirmDialog(
        title: title,
        body: body,
        onConfirm: onConfirm,
        danger: danger,
      ),
    );
  }
}

class NewDashboardStatData {
  const NewDashboardStatData({
    required this.title,
    required this.value,
    required this.meta,
    this.tag,
  });

  final String title;
  final String value;
  final String meta;
  final String? tag;
}
