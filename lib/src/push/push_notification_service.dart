import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/api_client.dart';
import '../auth/auth_repository.dart';

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  String? _lastFcmToken;

  static const String _androidChannelId = 'smartnps360_default';
  static const String _androidChannelName = 'SmartNPS360';
  static const String _androidChannelDescription = 'SmartNPS360 notifications';

  Future<void> init() async {
    await _initLocalNotifications();
    await _initFirebaseMessaging();
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings =
        InitializationSettings(android: androidInit, iOS: iosInit);

    await _local.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (details) {
        debugPrint(
          '[SmartNPS360][Push] notification tapped payload=${details.payload}',
        );
      },
    );

    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _androidChannelId,
          _androidChannelName,
          description: _androidChannelDescription,
          importance: Importance.high,
        ),
      );
    }
  }

  Future<void> _initFirebaseMessaging() async {
    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('[SmartNPS360][Push] permission=${settings.authorizationStatus}');

    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    try {
      final token = await messaging.getToken();
      _lastFcmToken = token;
      debugPrint('[SmartNPS360][Push] fcmToken=$token');
      await _maybeUploadToken();
    } catch (e) {
      debugPrint('[SmartNPS360][Push] getToken failed: $e');
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((t) {
      _lastFcmToken = t;
      debugPrint('[SmartNPS360][Push] onTokenRefresh fcmToken=$t');
      _maybeUploadToken();
    });

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((message) async {
      debugPrint('[SmartNPS360][Push] onMessage id=${message.messageId}');
      await _showLocalFromRemoteMessage(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('[SmartNPS360][Push] onMessageOpenedApp id=${message.messageId}');
    });

    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      debugPrint('[SmartNPS360][Push] initialMessage id=${initial.messageId}');
    }
  }

  Future<void> _maybeUploadToken() async {
    final token = _lastFcmToken;
    if (token == null || token.isEmpty) return;

    final accessToken = await AuthRepository.instance.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      debugPrint('[SmartNPS360][Push] skip upload (no accessToken yet)');
      return;
    }

    // TODO: call your backend: POST /api/push/register with fcmToken + device info.
    // ApiClient already injects Authorization: Bearer <accessToken>.
    ApiClient.instance.ensureAuthInterceptorInstalled();
    debugPrint(
      '[SmartNPS360][Push] ready to upload token (accessToken present)',
    );
  }

  Future<void> _showLocalFromRemoteMessage(RemoteMessage message) async {
    final n = message.notification;
    final title = n?.title ?? 'SmartNPS360';
    final body = n?.body ?? '';
    final payload = jsonEncode({
      'messageId': message.messageId,
      'data': message.data,
    });

    final androidDetails = AndroidNotificationDetails(
      _androidChannelId,
      _androidChannelName,
      channelDescription: _androidChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();

    await _local.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails:
          NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[SmartNPS360][Push] background message id=${message.messageId}');
  // In background/terminated, OS displays notification when payload includes "notification".
  // If you want local-notifications for data-only messages, initialize FlutterLocalNotifications here later.
}
