import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../Notifications/new_notifications_screen.dart';
import 'package:smartnps360/src/screens/controllers/memory_storage_controller.dart';
import 'package:smartnps360/src/screens/main_screens/SettingsScreen/settingscontroller.dart';
import 'package:smartnps360/src/screens/new_screens/Widgets/new_common_widgets.dart';
import '../new_models.dart';
import 'new_dashboard_dialogs.dart';

class NewDashboardController extends GetxController {
  final officerName = 'Hamid Khan'.obs;
  final officerRole = 'On-Site'.obs;
  final selectedSite = 'BayCrest'.obs;
  final selectedShift = '9 PM – 5 AM · 8hr'.obs;
  final selectedDate = 'Tuesday, May 5'.obs;
  final status = NewOfficerStatus.standby.obs;
  final timerText = '00:00:00'.obs;
  final timerLabel = 'Shift Timer'.obs;
  final ringInfoTitle = 'Upcoming Shift'.obs;
  final ringInfoSubtitle = 'BayCrest'.obs;
  final arrivalText = 'Pending'.obs;
  final breakBadgeText = 'Break'.obs;
  final isDarkMode = true.obs;
  final sideMenuOpen = false.obs;
  final complianceExpanded = false.obs;
  final quickActionsEditing = false.obs;
  final shortcutEditing = false.obs;
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

  final reminderTitleCtrl = TextEditingController();
  final reminderNoteCtrl = TextEditingController();
  final complaintNoteCtrl = TextEditingController();
  final profileNameCtrl = TextEditingController(text: 'Hamid Khan');
  final profilePhoneCtrl = TextEditingController(text: '+1 555 0100');
  final profileEmailCtrl = TextEditingController(text: 'hamid.khan@smartnps360.com');

  Timer? _timer;
  DateTime? _startedAt;
  int _workedBeforeBreak = 0;

  String get firstName => officerName.value.split(' ').first;
  String get initials => officerName.value.split(' ').where((e) => e.isNotEmpty).map((e) => e[0]).take(2).join().toUpperCase();
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
  final shortcuts = <NewShortcutItem>[].obs;
  final allQuickActions = <NewShortcutItem>[].obs;
  final lateItems = <NewWarningItem>[].obs;
  final writeUps = <NewWarningItem>[].obs;
  final complaints = <NewComplaintItem>[].obs;
  final reminders = <NewReminderItem>[].obs;
  final tasks = <NewTaskItem>[].obs;
  final notifications = <NewNotificationItem>[].obs;

  final List<NewDashboardStatData> warningStats = const [
    NewDashboardStatData(title: 'Warnings', value: '8', meta: '4 new · tap to review'),
    NewDashboardStatData(title: 'May 18', value: '5', meta: '2 late · 1 complaint'),
    NewDashboardStatData(title: 'May 17', value: '3', meta: '1 write-up warning'),
  ];

  final List<NewDashboardStatData> weekStats = const [
    NewDashboardStatData(title: 'This Week', value: '0m', meta: '↓ 7h vs last'),
    NewDashboardStatData(title: 'Last Week', value: '7h', meta: '1 completed shift'),
    NewDashboardStatData(title: 'Next Week', value: '16h', meta: '2 scheduled shifts'),
  ];

  final List<NewDashboardStatData> onTimeStats = const [
    NewDashboardStatData(title: 'On-Time', value: '71%', meta: '↓ 29% MoM', tag: 'MAY'),
    NewDashboardStatData(title: 'April', value: '100%', meta: '2/2 on time', tag: 'APR'),
    NewDashboardStatData(title: 'June', value: '—', meta: 'No shifts yet', tag: 'JUN'),
  ];

  NewDashboardStatData get warningStat => warningStats[warningStatIndex.value];
  NewDashboardStatData get weekStat => weekStats[weekStatIndex.value];
  NewDashboardStatData get onTimeStat => onTimeStats[onTimeStatIndex.value];

  @override
  void onInit() {
    super.onInit();
    _loadDummyData();
    _syncStats();
    _startIdleRing();
  }

  @override
  void onClose() {
    _timer?.cancel();
    reminderTitleCtrl.dispose();
    reminderNoteCtrl.dispose();
    complaintNoteCtrl.dispose();
    profileNameCtrl.dispose();
    profilePhoneCtrl.dispose();
    profileEmailCtrl.dispose();
    super.onClose();
  }

  void _loadDummyData() {
    shortcuts.assignAll(const [
      NewShortcutItem(id: 'clock', title: 'Clock In', iconKey: 'clock', colorKey: 'blue'),
      NewShortcutItem(id: 'issue', title: 'Report Issue', iconKey: 'warning', colorKey: 'amber'),
      NewShortcutItem(id: 'break', title: 'Start Break', iconKey: 'coffee', colorKey: 'amber'),
      NewShortcutItem(id: 'patrol', title: 'Patrol', iconKey: 'patrol', colorKey: 'purple'),
      NewShortcutItem(id: 'dar', title: 'DAR Log', iconKey: 'dar', colorKey: 'teal'),
      NewShortcutItem(id: 'incident', title: 'Incident Report', iconKey: 'incident', colorKey: 'red'),
    ]);
    allQuickActions.assignAll([
      ...shortcuts,
      const NewShortcutItem(id: 'parking', title: 'Parking Management', iconKey: 'parking', colorKey: 'slate'),
      const NewShortcutItem(id: 'relief', title: 'Relief', iconKey: 'people', colorKey: 'pink'),
      const NewShortcutItem(id: 'move', title: 'Move Pre/Post Inspection', iconKey: 'home', colorKey: 'green'),
      const NewShortcutItem(id: 'tasks', title: 'Tasks', iconKey: 'tasks', colorKey: 'blue', badge: '3'),
      const NewShortcutItem(id: 'manual', title: 'Site Manual', iconKey: 'manual', colorKey: 'purple'),
      const NewShortcutItem(id: 'firewatch', title: 'Firewatch', iconKey: 'fire', colorKey: 'red', enabled: false),
    ]);
    lateItems.assignAll(const [
      NewWarningItem(id: 'l1', title: 'Late Arrival', time: '5/1/2026, 9:05 PM', detail: 'Arrived 5 minutes after scheduled start.'),
      NewWarningItem(id: 'l2', title: 'Late Arrival', time: '5/2/2026, 9:08 PM', detail: 'Arrived 8 minutes after scheduled start.', unread: true),
    ]);
    writeUps.assignAll(const [
      NewWarningItem(id: 'w1', title: '1st Write-Up Warning', time: '5/1/2026, 9:05 PM', detail: 'Formal attendance warning.', acknowledged: true),
      NewWarningItem(id: 'w2', title: '2nd Write-Up Warning', time: '5/2/2026, 9:08 PM', detail: 'Second warning for repeated late arrival.', acknowledged: true),
      NewWarningItem(id: 'w3', title: '3rd Write-Up Warning', time: '5/3/2026, 9:10 PM', detail: 'Final warning requires acknowledgment.', unread: true),
    ]);
    complaints.assignAll(const [
      NewComplaintItem(id: 'c1', title: 'Resident reported delayed lobby response', site: 'BayCrest', severity: 'Medium', filedBy: 'Sarah Chen, Site Manager', filedAt: '5/3/2026, 4:12 PM', incidentDate: '5/2/2026, 11:14 PM', detail: 'Resident reported waiting at the front desk while lobby was unattended.', expectedAction: 'Notify relief or supervisor before leaving front desk.', unread: true),
      NewComplaintItem(id: 'c2', title: 'Visitor sign-in policy not followed', site: 'BayCrest', severity: 'Low', filedBy: 'David Park, Property Manager', filedAt: '4/28/2026, 9:45 AM', incidentDate: '4/27/2026, 8:22 PM', detail: 'Delivery contractor was allowed past lobby without visitor log.', expectedAction: 'All non-resident entries must complete visitor log.', unread: true),
      NewComplaintItem(id: 'c3', title: 'Tenant complaint — dismissive tone', site: 'Prism', severity: 'High', filedBy: 'Marcus Webb, Building Manager', filedAt: '4/22/2026, 2:30 PM', incidentDate: '4/21/2026, 6:45 PM', detail: 'Tenant reported confrontational tone during after-hours access request.', expectedAction: 'Maintain professional and courteous tone.', acknowledged: true, note: 'Reviewed after-hours access list.'),
    ]);
    reminders.assignAll(const [
      NewReminderItem(id: 'r1', title: 'Submit weekly report', dateText: 'Today', timeText: '7:30 PM', repeat: NewReminderRepeat.weekly, note: 'Upload before shift starts.'),
      NewReminderItem(id: 'r2', title: 'Check fire panel', dateText: 'Tomorrow', timeText: '9:15 PM', repeat: NewReminderRepeat.daily, fromManagement: true),
      NewReminderItem(id: 'r3', title: 'Uniform inspection', dateText: 'May 8', timeText: '8:30 PM', repeat: NewReminderRepeat.once, completed: true),
    ]);
    tasks.assignAll(const [
      NewTaskItem(id: 't1', title: 'Inspect east stairwell', detail: 'Confirm all emergency lights are active.', dueText: 'Today · 10 PM', priority: 'High'),
      NewTaskItem(id: 't2', title: 'Upload lobby report', detail: 'Attach photos and visitor log summary.', dueText: 'Today · 11 PM'),
      NewTaskItem(id: 't3', title: 'Review site manual update', detail: 'Read updated access control policy.', dueText: 'Tomorrow'),
    ]);
    notifications.assignAll(const [
      NewNotificationItem(id: 'n1', title: 'Shift starts in 1 hour', body: 'BayCrest lobby shift begins soon. Arrive on site before 9:00 PM and complete clock-in.', dateText: 'Today', timeText: '8:00 PM', type: 'Shift Reminder', source: 'System', site: 'BayCrest', shiftText: '9 PM – 5 AM', actionLabel: 'View Shift', iconKey: 'shift', colorKey: 'blue', unread: true),
      NewNotificationItem(id: 'n2', title: 'Reminder from Management', body: 'Check fire panel at the start of shift and add a note in the shift log.', dateText: 'Today', timeText: '6:15 PM', type: 'Reminder', source: 'Management', site: 'BayCrest', actionLabel: 'Open Reminder', iconKey: 'reminder', colorKey: 'amber', unread: true),
      NewNotificationItem(id: 'n3', title: 'New task assigned', body: 'Inspect east stairwell and confirm all emergency lights are active.', dateText: 'Today', timeText: '5:40 PM', type: 'Task', source: 'Dispatch', site: 'BayCrest', actionLabel: 'View Task', iconKey: 'task', colorKey: 'purple'),
      NewNotificationItem(id: 'n4', title: 'Complaint requires acknowledgment', body: 'A resident complaint was filed for delayed lobby response. Review and submit your response.', dateText: 'Yesterday', timeText: '4:12 PM', type: 'Complaint', source: 'Management', site: 'BayCrest', actionLabel: 'Review Complaint', iconKey: 'warning', colorKey: 'red', unread: true, critical: true),
      NewNotificationItem(id: 'n5', title: 'Dispatch message', body: 'Parking level B2 requires extra patrol after 10:00 PM.', dateText: 'Yesterday', timeText: '2:25 PM', type: 'Message', source: 'Dispatch', site: 'BayCrest', actionLabel: 'Open Messages', iconKey: 'message', colorKey: 'teal'),
    ]);
  }

  void _syncStats() {
    stats.assignAll([
      NewStatItem(title: warningStat.title, value: warningStat.value, meta: warningStat.meta, iconKey: 'warning', isWarning: true),
      NewStatItem(title: weekStat.title, value: weekStat.value, meta: weekStat.meta, iconKey: 'calendar'),
      NewStatItem(title: onTimeStat.title, value: onTimeStat.value, meta: onTimeStat.meta, iconKey: 'check'),
    ]);
  }

  void nextWarningStat() {
    warningStatIndex.value = (warningStatIndex.value + 1) % warningStats.length;
  }

  void resetWarningStat() {
    warningStatIndex.value = 0;
  }

  void nextWeekStat() {
    weekStatIndex.value = (weekStatIndex.value + 1) % weekStats.length;
  }

  void resetWeekStat() {
    weekStatIndex.value = 0;
  }

  void nextOnTimeStat() {
    onTimeStatIndex.value = (onTimeStatIndex.value + 1) % onTimeStats.length;
  }

  void resetOnTimeStat() {
    onTimeStatIndex.value = 0;
  }

  void _startIdleRing() {
    timerLabel.value = 'Shift Timer';
    ringInfoTitle.value = 'Upcoming Shift';
    ringInfoSubtitle.value = selectedSite.value;
  }

  void toggleTheme() {
    isDarkMode.value = !isDarkMode.value;
    Get.changeThemeMode(isDarkMode.value ? ThemeMode.dark : ThemeMode.light);
  }

  void openSideMenu() => sideMenuOpen.value = true;
  void closeSideMenu() => sideMenuOpen.value = false;
  void toggleCompliance() => complianceExpanded.toggle();
  void toggleShortcutEdit() => shortcutEditing.toggle();
  void toggleQuickActionEdit() => quickActionsEditing.toggle();

  void startShiftFlow() {
    if (status.value == NewOfficerStatus.standby) {
      _confirm('Start Shift', 'Clock in for $selectedSite now?', () {
        _startedAt = DateTime.now();
        status.value = NewOfficerStatus.onShift;
        timerLabel.value = 'Current Shift';
        ringInfoTitle.value = 'Current Shift';
        ringInfoSubtitle.value = selectedSite.value;
        arrivalText.value = 'On Time';
        _startTimer();
      });
      return;
    }
    _confirm('End Shift', 'Clock out and finish this shift?', () {
      status.value = NewOfficerStatus.standby;
      timerText.value = '00:00:00';
      _timer?.cancel();
      _workedBeforeBreak = 0;
      _startedAt = null;
      breakBadgeText.value = 'Break';
      _startIdleRing();
    }, danger: true);
  }

  void toggleBreak() {
    if (status.value == NewOfficerStatus.standby) {
      showInfoText('Break Unavailable', 'Start shift before taking a break.');
      return;
    }
    if (status.value == NewOfficerStatus.onShift) {
      _workedBeforeBreak = _elapsedSeconds;
      status.value = NewOfficerStatus.onBreak;
      timerLabel.value = 'Break Timer';
      breakBadgeText.value = 'On Break';
      _startedAt = DateTime.now();
      return;
    }
    status.value = NewOfficerStatus.onShift;
    timerLabel.value = 'Current Shift';
    breakBadgeText.value = 'Taken';
    _startedAt = DateTime.now().subtract(Duration(seconds: _workedBeforeBreak));
  }

  int get _elapsedSeconds {
    final started = _startedAt;
    if (started == null) return 0;
    return DateTime.now().difference(started).inSeconds;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      timerText.value = _formatDuration(_elapsedSeconds);
    });
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void handleShortcut(String id) {
    switch (id) {
      case 'clock':
        startShiftFlow();
        break;
      case 'break':
        toggleBreak();
        break;
      case 'tasks':
        openTasks();
        break;
      case 'issue':
        _openActionFlow('Report Issue', 'Issue reporting form UI is ready with photo, note, location, and severity placeholders.', Icons.flag_rounded, NewUi.warning);
        break;
      case 'patrol':
        _openActionFlow('Patrol', 'Patrol chooser UI is ready for round timer, QR patrol, tour checklist, route map, and camera flow.', Icons.location_on_rounded, NewUi.purple);
        break;
      case 'dar':
        _openActionFlow('DAR Log', 'Daily Activity Report UI is ready for notes, media attachments, and shift-linked entries.', Icons.description_rounded, NewUi.teal);
        break;
      case 'incident':
        _openActionFlow('Incident Report', 'Incident report UI is ready for priority flag, description, photos, and dispatch escalation.', Icons.report_rounded, NewUi.danger);
        break;
      case 'parking':
        _openActionFlow('Parking Management', 'Parking management UI is ready for vehicle lookup, violation logging, and permit checks.', Icons.local_parking_rounded, NewUi.textMutedLight);
        break;
      case 'relief':
        _openActionFlow('Relief Check', 'Reliever check UI is ready for contact options, shift handoff, and policy reminder.', Icons.groups_rounded, const Color(0xFFEC4899));
        break;
      case 'move':
        _openActionFlow('Move Inspection', 'Move pre/post inspection UI is ready for unit photos, notes, and signature placeholders.', Icons.home_work_rounded, NewUi.success);
        break;
      case 'manual':
        _openActionFlow('Site Manual', 'Site manual UI is ready for post orders, emergency procedures, and policy sections.', Icons.menu_book_rounded, NewUi.purple);
        break;
      case 'firewatch':
        _openActionFlow('Firewatch', 'Firewatch log UI is ready for round history, signature capture, and status tracking.', Icons.local_fire_department_rounded, NewUi.danger);
        break;
      default:
        _openActionFlow('Action', 'UI flow for this action is ready. Backend will be connected later.', Icons.apps_rounded, NewUi.accent);
    }
  }

  void setWarningTab(NewWarningTab tab) => warningTab.value = tab;
  void setReminderTab(NewReminderTab tab) => reminderTab.value = tab;
  void setReminderRepeat(NewReminderRepeat repeat) => selectedReminderRepeat.value = repeat;
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

  List<NewTaskItem> get filteredTasks => tasks.where((e) => taskOpenTab.value ? !e.completed : e.completed).toList();

  void saveReminder() {
    final title = reminderTitleCtrl.text.trim();
    if (title.isEmpty) {
      showInfoText('Missing Title', 'Please enter reminder title.');
      return;
    }
    reminders.insert(0, NewReminderItem(id: DateTime.now().millisecondsSinceEpoch.toString(), title: title, dateText: 'Today', timeText: '9:00 PM', repeat: selectedReminderRepeat.value, note: reminderNoteCtrl.text.trim(), critical: reminderCritical.value, autoSnooze: reminderAutoSnooze.value, showOnCalendar: reminderShowCalendar.value));
    reminderTitleCtrl.clear();
    reminderNoteCtrl.clear();
    Get.back();
  }

  void completeTask(NewTaskItem task) {
    final index = tasks.indexWhere((e) => e.id == task.id);
    if (index == -1) return;
    tasks[index] = task.copyWith(completed: true);
  }

  void markAllNotificationsRead() {
    notifications.assignAll(notifications.map((e) => e.copyWith(unread: false)).toList());
  }

  void clearNotifications() {
    notifications.clear();
  }

  void acknowledgeComplaint(NewComplaintItem item) {
    final index = complaints.indexWhere((e) => e.id == item.id);
    if (index == -1) return;
    complaints[index] = item.copyWith(unread: false, acknowledged: true, note: complaintNoteCtrl.text.trim());
    complaintNoteCtrl.clear();
    _syncStats();
    Get.back();
  }

  void openWarnings() => Get.dialog(NewWarningsDialog(controller: this));
  void openNotifications() => Get.to(() => const NewNotificationsScreen());
  void openReminders() => Get.dialog(NewRemindersDialog(controller: this));
  void openReminderEditor() => Get.dialog(NewReminderEditorDialog(controller: this));
  void openEditProfile() => Get.dialog(NewEditProfileDialog(controller: this));
  void openTasks() => Get.dialog(NewTasksDialog(controller: this));

  void openComplaint(NewComplaintItem complaint) {
    complaintNoteCtrl.text = complaint.note;
    Get.dialog(NewComplaintDialog(controller: this, complaint: complaint));
  }

  void saveProfile() {
    final name = profileNameCtrl.text.trim();
    if (name.isNotEmpty) officerName.value = name;
    Get.back();
  }

  void showInfoOnsite() => showInfoText('On-Site SCH', 'On-site schedule preview is ready.');
  void showInfoPatrol() => showInfoText('Patrol Officer SCH', 'Patrol officer schedule preview is ready.');
  void showInfoSettings() => showInfoText('Settings', 'Settings UI will be connected later.');
  void showInfoJobs() => showInfoText('Job Applications', 'Job applications preview.');
  void showInfoTraining() => showInfoText('Training & Onboarding', 'Training and onboarding preview.');
  void showInfoDispatch() => showInfoText('Contact Dispatch', 'Dispatch contact actions will be connected later.');

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

  void _confirm(String title, String body, VoidCallback onConfirm, {bool danger = false}) {
    Get.dialog(NewConfirmDialog(title: title, body: body, onConfirm: onConfirm, danger: danger));
  }

  void _openActionFlow(String title, String body, IconData icon, Color color) {
    Get.dialog(NewActionFlowDialog(title: title, body: body, icon: icon, color: color));
  }
}

class NewDashboardStatData {
  const NewDashboardStatData({required this.title, required this.value, required this.meta, this.tag});

  final String title;
  final String value;
  final String meta;
  final String? tag;
}
