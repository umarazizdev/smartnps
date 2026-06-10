import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Persistent, silent iOS notification shown while live location is shared.
class IosBackgroundLocationNotification {
  IosBackgroundLocationNotification._();

  static const int notificationId = 9911;
  static const String title = 'SmartNPS360';
  static const String body = 'Sharing live location';

  static FlutterLocalNotificationsPlugin? _plugin;
  static bool _shown = false;

  static Future<void> show() async {
    if (!Platform.isIOS || _shown) return;

    WidgetsFlutterBinding.ensureInitialized();

    final plugin = _plugin ??= FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );

    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: false,
        presentSound: false,
        threadIdentifier: 'smartnps360_location',
        interruptionLevel: InterruptionLevel.passive,
      ),
    );

    await plugin.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: details,
    );
    _shown = true;

    if (kDebugMode) {
      debugPrint('[IosBackgroundLocationNotification] shown');
    }
  }

  static Future<void> dismiss() async {
    if (!Platform.isIOS || !_shown) return;

    await _plugin?.cancel(id: notificationId);
    _shown = false;

    if (kDebugMode) {
      debugPrint('[IosBackgroundLocationNotification] dismissed');
    }
  }
}
