// lib/Services/local_notification_service.dart
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get_storage/get_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _idShiftStart = 1001;
  static const int _idBreakEnd = 1002;
  static const int _idShiftEnd = 1003;

  static const String _channelId = 'shift_reminders';
  static const String _channelName = 'Shift reminders';

  bool _initialized = false;
  tz.Location? _sfLoc;

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    final TimezoneInfo tzInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzInfo.identifier));

    _sfLoc ??= tz.getLocation('America/Los_Angeles');

    // Debug timezone setup
    _log(
      'TZ_INIT',
      extra: {
        'localTZ': tz.local.name,
        'sfLoc': _sfLoc?.name,
        'deviceTZ': tzInfo.identifier,
      },
    );

    /// iOS init (NO actions / NO Open button)
    /// IMPORTANT: Set to false to prevent auto-requesting permissions on app start
    /// Permissions will be requested explicitly when needed (after login)
    final iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const androidInit = AndroidInitializationSettings('ic_stat_notify');

    final initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (resp) {
        _log(
          'NOTIFICATION_TAP',
          extra: {
            'id': resp.id,
            'actionId': resp.actionId,
            'payload': resp.payload,
          },
        );
      },
    );

    /// Android channel (HIGH importance for heads-up reminder)
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Notifications for shift and break reminders',
          importance: Importance.max,
        ),
      );
    }

    _initialized = true;
  }

  tz.TZDateTime _localTzFromSfWallClock(DateTime dt) {
    final sf = tz.TZDateTime(
      _sfLoc!,
      dt.year,
      dt.month,
      dt.day,
      dt.hour,
      dt.minute,
      dt.second,
      dt.millisecond,
      dt.microsecond,
    );
    return tz.TZDateTime.from(sf, tz.local);
  }

  /// IMPORTANT:
  /// - Android 13+ needs runtime notification permission
  /// - Android 12 and below: permission is typically "granted" by default
  /// - iOS: Uses native iOS notification API through flutter_local_notifications
  Future<bool> requestPermissionIfNeeded() async {
    await init();

    _log(
      'PERMISSION_REQUEST_STARTED',
      extra: {'platform': Platform.isIOS ? 'iOS' : 'Android'},
    );

    if (Platform.isIOS) {
      // Use iOS native notification permission request
      final iosPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();

      if (iosPlugin != null) {
        final granted = await iosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

        _log(
          'IOS_PERMISSION_REQUEST_RESULT',
          extra: {'granted': granted ?? false},
        );

        // Mark that we've asked for permission
        final box = GetStorage();
        box.write('askedForNotificationPermission', true);

        return granted ?? false;
      }

      _log(
        'IOS_PLUGIN_NULL',
        extra: {'error': 'Could not get iOS plugin implementation'},
      );
      return false;
    }

    // Android: use permission_handler
    final statusBefore = await Permission.notification.status;
    _log('PERMISSION_CHECK_BEFORE', extra: {'status': statusBefore.toString()});

    // permission_handler handles Android 13+ properly; below 13 returns granted
    final status = await Permission.notification.request();
    _log(
      'PERMISSION_REQUEST_RESULT',
      extra: {'status': status.toString(), 'isGranted': status.isGranted},
    );

    // Mark that we've asked for permission
    final box = GetStorage();
    box.write('askedForNotificationPermission', true);

    return status.isGranted;
  }

  Future<bool> isPermissionGranted() async {
    await init();

    if (Platform.isIOS) {
      // For iOS, use the native iOS plugin to check actual notification settings
      // This is more reliable than permission_handler which doesn't sync properly with iOS settings
      final iosPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();

      if (iosPlugin != null) {
        // Check notification settings from iOS
        // This doesn't trigger a permission dialog, just checks current state
        final settings = await iosPlugin.checkPermissions();

        final granted = settings?.isEnabled ?? false;

        _log(
          'IOS_PERMISSION_STATUS_CHECK',
          extra: {
            'method': 'ios_native_check',
            'isEnabled': settings?.isEnabled ?? false,
            'isGranted': granted,
          },
        );

        return granted;
      }

      // Fallback to permission_handler if iOS plugin is not available
      _log(
        'IOS_PLUGIN_NULL_FALLBACK',
        extra: {'error': 'iOS plugin not available, using permission_handler'},
      );

      final status = await Permission.notification.status;
      final granted =
          status.isGranted || status.isProvisional || status.isLimited;

      _log(
        'IOS_PERMISSION_FALLBACK_CHECK',
        extra: {
          'method': 'permission_handler_fallback',
          'status': status.toString(),
          'isGranted': granted,
        },
      );

      return granted;
    }

    // ✅ Android < 13 → always granted (no runtime permission)
    final androidInfo = await Permission.notification.status;
    _log(
      'PERMISSION_STATUS_CHECK',
      extra: {
        'platform': 'Android',
        'status': androidInfo.toString(),
        'isGranted': androidInfo.isGranted,
      },
    );
    // On Android <13 this returns granted by default
    return androidInfo.isGranted;
  }

  /// Android-only: battery optimization check (store-safe).
  /// Returns true if app is "unrestricted" / ignoring optimizations.
  Future<bool> isBatteryUnrestricted() async {
    if (!Platform.isAndroid) return true;
    final st = await Permission.ignoreBatteryOptimizations.status;
    _log('BATTERY_STATUS', extra: {'status': st.toString()});
    return st.isGranted;
  }

  /// Android-only: opens the system battery optimization screen.
  /// This is store-safe because it’s user-initiated.
  Future<bool> requestBatteryUnrestricted() async {
    if (!Platform.isAndroid) return true;
    final st = await Permission.ignoreBatteryOptimizations.request();
    _log('BATTERY_REQUEST', extra: {'status': st.toString()});
    return st.isGranted;
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id: id);
  }

  /// matches NotificationManager usage
  Future<void> cancelBreakReminder() async {
    await init();
    await _plugin.cancel(id: _idBreakEnd);
    _log('CANCEL_BREAK', extra: {'id': _idBreakEnd});
  }

  /// matches NotificationManager usage
  Future<void> cancelAllShiftRelated() async {
    await init();
    await _plugin.cancel(id: _idShiftStart);
    await _plugin.cancel(id: _idShiftEnd);
    _log(
      'CANCEL_SHIFT_RELATED',
      extra: {
        'ids': [_idShiftStart, _idShiftEnd],
      },
    );

    try {
      final box = GetStorage();
      box.remove('lastScheduledShiftStart');
      box.remove('lastScheduledShiftEnd');
      box.remove('lastScheduledShiftSig');
    } catch (_) {}
  }

  /// =============================
  /// SHIFT REMINDER SCHEDULING
  /// =============================

  Future<void> scheduleShiftReminders({
    required String siteName,
    required String shiftName,
    required DateTime shiftStart,
    required DateTime shiftEnd,
    int minutesBefore = 13,
  }) async {
    await init();

    final box = GetStorage();
    if (box.read('notificationsEnabled') != true) return;

    var s = shiftStart;
    var e = shiftEnd;

    if (e.isBefore(s)) {
      e = e.add(const Duration(days: 1));
    }

    final startNotify = _localTzFromSfWallClock(
      s.subtract(Duration(minutes: minutesBefore)),
    );

    final endNotify = _localTzFromSfWallClock(
      e.subtract(Duration(minutes: minutesBefore)),
    );

    final siteNameShort = _truncate(siteName, max: 30);

    await _scheduleIfFuture(
      id: _idShiftStart,
      title: 'Upcoming Shift at $siteNameShort',
      body: '$shiftName starts soon.',
      when: startNotify,
    );

    await _scheduleIfFuture(
      id: _idShiftEnd,
      title: 'Shift Ending Soon',
      body: '$shiftName at $siteNameShort will end soon.',
      when: endNotify,
    );
  }

  String _truncate(String text, {int max = 35}) {
    if (text.length <= max) return text;
    return '${text.substring(0, max)}...';
  }

  Future<void> scheduleBreakEndReminder({
    required DateTime breakStart,
    required int breakDurationSeconds,
    int minutesBefore = 13,
  }) async {
    await init();

    final box = GetStorage();
    if (box.read('notificationsEnabled') != true) return;
    if (breakDurationSeconds <= 0) return;

    await cancelBreakReminder();

    final breakEnd = breakStart.add(Duration(seconds: breakDurationSeconds));
    final notifyAt = breakEnd.subtract(Duration(minutes: minutesBefore));
    final notifyTz = _localTzFromSfWallClock(notifyAt);

    await _scheduleIfFuture(
      id: _idBreakEnd,
      title: 'Break Reminder',
      body: 'Your break ends in $minutesBefore minutes.',
      when: notifyTz,
    );
  }

  Future<void> _scheduleIfFuture({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
  }) async {
    final now = tz.TZDateTime.now(tz.local);

    _log(
      'SCHEDULE_ATTEMPT',
      extra: {
        'id': id,
        'now': now.toString(),
        'when': when.toString(),
        'isFuture': when.isAfter(now),
      },
    );

    if (!when.isAfter(now)) return;

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails: _details(),
      payload: 'SHIFT_REMINDER',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );

    final pending = await _plugin.pendingNotificationRequests();
    _log(
      'SCHEDULE_SET',
      extra: {
        'id': id,
        'when': when.toString(),
        'pendingCount': pending.length,
        'pendingIds': pending.map((e) => e.id).toList(),
      },
    );
  }

  /// =============================
  /// REMINDER STYLE DETAILS
  /// =============================

  NotificationDetails _details() {
    const android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Notifications for shift and break reminders',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.reminder,
      autoCancel: true,
      ongoing: false,
      showWhen: true,
      fullScreenIntent: false, // Store-safe
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      // ✅ Use 'active' for better simulator compatibility
      // timeSensitive requires special authorization and may be suppressed
      interruptionLevel: InterruptionLevel.active,
    );

    return const NotificationDetails(android: android, iOS: ios);
  }

  void _log(String action, {Map<String, dynamic>? extra}) {
    if (!kDebugMode) return;
    developer.log(
      {'action': action, 'extra': extra}.toString(),
      name: 'LocalNotificationService',
    );
  }
}
