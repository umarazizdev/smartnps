import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../duty/duty_status_snapshot.dart';

enum BackgroundLocationIssue {
  gpsStopped,
  gpsNotUpdating,
  signedOut,
}

/// Alerts the officer when on-duty background GPS fails unexpectedly.
/// Does not fire for normal clock-out / off_duty stops.
class BackgroundLocationIssueNotification {
  BackgroundLocationIssueNotification._();

  static const int notificationId = 9913;
  static const Duration cooldown = Duration(minutes: 15);

  static const String _channelId = 'smartnps360_location_issue';
  static const String _channelName = 'Location issues';
  static const String _channelDescription =
      'Alerts when live location tracking stops while you are on duty';

  static const String dispatchHint =
      'Contact dispatch and tell them your live location stopped.';

  static FlutterLocalNotificationsPlugin? _plugin;
  static DateTime? _lastShownAt;

  static String titleFor(BackgroundLocationIssue issue) {
    switch (issue) {
      case BackgroundLocationIssue.gpsStopped:
        return 'Location stopped';
      case BackgroundLocationIssue.gpsNotUpdating:
        return 'Location not updating';
      case BackgroundLocationIssue.signedOut:
        return 'Location stopped';
    }
  }

  static String whyFor(BackgroundLocationIssue issue) {
    switch (issue) {
      case BackgroundLocationIssue.gpsStopped:
        return 'Your live location stopped. The phone is not getting GPS while you are on duty.';
      case BackgroundLocationIssue.gpsNotUpdating:
        return 'Your live location stopped updating while you are on duty.';
      case BackgroundLocationIssue.signedOut:
        return 'Your live location stopped because you were signed out.';
    }
  }

  static String bodyFor(BackgroundLocationIssue issue) {
    return '${whyFor(issue)} $dispatchHint';
  }

  static Future<void> showIfOnDuty({
    required BackgroundLocationIssue issue,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      if (!await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) {
        return;
      }
      final last = _lastShownAt;
      if (last != null && DateTime.now().difference(last) < cooldown) {
        return;
      }

      final plugin = await _ensurePlugin();
      final title = titleFor(issue);
      final body = bodyFor(issue);
      await plugin.show(
        id: notificationId,
        title: title,
        body: body,
        notificationDetails: _detailsFor(body),
      );
      _lastShownAt = DateTime.now();
      if (kDebugMode) {
        debugPrint(
          '[DutyLocation] issue notification shown: $title | $body',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DutyLocation] issue notification failed: $e');
      }
    }
  }

  static Future<FlutterLocalNotificationsPlugin> _ensurePlugin() async {
    WidgetsFlutterBinding.ensureInitialized();
    final plugin = _plugin ??= FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          defaultPresentAlert: true,
          defaultPresentBadge: false,
          defaultPresentSound: true,
          defaultPresentBanner: true,
          defaultPresentList: true,
        ),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    if (Platform.isAndroid) {
      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );
    }
    return plugin;
  }

  static NotificationDetails _detailsFor(String body) {
    return NotificationDetails(
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentBadge: false,
        presentSound: true,
        threadIdentifier: 'smartnps360_location_issue',
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        ongoing: false,
        autoCancel: true,
        channelShowBadge: true,
        styleInformation: BigTextStyleInformation(body),
      ),
    );
  }
}
