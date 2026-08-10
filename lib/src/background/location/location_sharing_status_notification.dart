import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum LocationSharingStopReason {
  shiftEnded,
  signedOut,
}

class LocationSharingStatusNotification {
  LocationSharingStatusNotification._();

  static const int sharingNotificationId = 9911;
  static const int stoppedNotificationId = 9912;

  static const String iosAppTitle = 'SmartNPS360';
  static const String androidSharingTitle = 'On Duty • Location Active';
  static const String androidSharingBody =
      'Your live location is being shared while you are on duty.';
  static const String androidStoppedTitle = 'Off Duty • Location Stopped';
  static const String androidSignedOutTitle =
      'Session Expired • Location Stopped';
  static const String androidShiftEndedBody =
      'Your live location is no longer being shared. You are off duty.';
  static const String androidSignedOutBody =
      'Your session has expired, and live location sharing has stopped.';

  static const String sharingBody =
      'You are on duty. Your live location is being shared.';
  static const String shiftEndedBody =
      'You are off duty. Your live location is no longer being shared.';
  static const String signedOutBody =
      'Your session has expired. Live location sharing has stopped.';

  static const String title = iosAppTitle;

  static const String _androidStoppedChannelId =
      'smartnps360_location_status';
  static const String _androidStoppedChannelName = 'Location status';
  static const String _androidStoppedChannelDescription =
      'Quiet updates when location sharing starts or stops';

  static FlutterLocalNotificationsPlugin? _plugin;
  static bool _sharingShown = false;

  static String sharingTitleForPlatform() {
    return Platform.isAndroid ? androidSharingTitle : iosAppTitle;
  }

  static String sharingBodyForPlatform() {
    return Platform.isAndroid ? androidSharingBody : sharingBody;
  }

  static String titleFor(LocationSharingStopReason reason) {
    if (Platform.isIOS) return iosAppTitle;
    switch (reason) {
      case LocationSharingStopReason.shiftEnded:
        return androidStoppedTitle;
      case LocationSharingStopReason.signedOut:
        return androidSignedOutTitle;
    }
  }

  static String bodyFor(LocationSharingStopReason reason) {
    if (Platform.isAndroid) {
      switch (reason) {
        case LocationSharingStopReason.shiftEnded:
          return androidShiftEndedBody;
        case LocationSharingStopReason.signedOut:
          return androidSignedOutBody;
      }
    }
    switch (reason) {
      case LocationSharingStopReason.shiftEnded:
        return shiftEndedBody;
      case LocationSharingStopReason.signedOut:
        return signedOutBody;
    }
  }

  static LocationSharingStopReason? reasonFromWire(Object? raw) {
    final value = raw?.toString();
    switch (value) {
      case 'shift_ended':
        return LocationSharingStopReason.shiftEnded;
      case 'signed_out':
        return LocationSharingStopReason.signedOut;
      default:
        return null;
    }
  }

  static String reasonToWire(LocationSharingStopReason reason) {
    switch (reason) {
      case LocationSharingStopReason.shiftEnded:
        return 'shift_ended';
      case LocationSharingStopReason.signedOut:
        return 'signed_out';
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
        ),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    if (Platform.isAndroid) {
      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _androidStoppedChannelId,
          _androidStoppedChannelName,
          description: _androidStoppedChannelDescription,
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        ),
      );
    }

    return plugin;
  }

  static const NotificationDetails _sharingDetails = NotificationDetails(
    iOS: DarwinNotificationDetails(
      presentAlert: false,
      presentBanner: false,
      presentList: true,
      presentBadge: false,
      presentSound: false,
      threadIdentifier: 'smartnps360_location',
      interruptionLevel: InterruptionLevel.passive,
    ),
  );

  static const NotificationDetails _stoppedDetails = NotificationDetails(
    iOS: DarwinNotificationDetails(
      presentAlert: false,
      presentBanner: false,
      presentList: true,
      presentBadge: false,
      presentSound: false,
      threadIdentifier: 'smartnps360_location',
      interruptionLevel: InterruptionLevel.passive,
    ),
    android: AndroidNotificationDetails(
      _androidStoppedChannelId,
      _androidStoppedChannelName,
      channelDescription: _androidStoppedChannelDescription,
      importance: Importance.low,
      priority: Priority.low,
      playSound: false,
      enableVibration: false,
      silent: true,
      ongoing: false,
      autoCancel: true,
      channelShowBadge: false,
    ),
  );

  static Future<void> showSharing() async {
    if (!Platform.isIOS || _sharingShown) return;

    final plugin = await _ensurePlugin();

    await plugin.cancel(id: stoppedNotificationId);

    await plugin.show(
      id: sharingNotificationId,
      title: sharingTitleForPlatform(),
      body: sharingBodyForPlatform(),
      notificationDetails: _sharingDetails,
    );
    _sharingShown = true;

    if (kDebugMode) {
      debugPrint('[LocationSharingStatusNotification] sharing shown');
    }
  }

  static Future<void> dismissSharing() async {
    if (!Platform.isIOS) return;
    if (!_sharingShown && _plugin == null) return;

    final plugin = _plugin ?? await _ensurePlugin();
    await plugin.cancel(id: sharingNotificationId);
    _sharingShown = false;

    if (kDebugMode) {
      debugPrint('[LocationSharingStatusNotification] sharing dismissed');
    }
  }

  static Future<void> showStopped({
    required LocationSharingStopReason reason,
  }) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;

    final plugin = await _ensurePlugin();

    if (Platform.isIOS) {
      await plugin.cancel(id: sharingNotificationId);
      _sharingShown = false;
    }

    await plugin.show(
      id: stoppedNotificationId,
      title: titleFor(reason),
      body: bodyFor(reason),
      notificationDetails: _stoppedDetails,
    );

    if (kDebugMode) {
      debugPrint(
        '[LocationSharingStatusNotification] stopped shown reason=$reason',
      );
    }
  }

  static Future<void> clearStopped() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;

    final plugin = await _ensurePlugin();
    await plugin.cancel(id: stoppedNotificationId);

    if (kDebugMode) {
      debugPrint('[LocationSharingStatusNotification] stopped cleared');
    }
  }
}
