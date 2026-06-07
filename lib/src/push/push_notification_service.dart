import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/api_client.dart';
import '../auth/auth_repository.dart';
import '../utilities/app_config.dart';

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  String? _lastFcmToken;
  bool _firebaseMessagingInitialized = false;
  bool _permissionRequestStarted = false;
  String? _cachedDeviceId;
  String? _cachedAppVersion;

  static const String _androidChannelId = 'smartnps360_default';
  static const String _androidChannelName = 'SmartNPS360';
  static const String _androidChannelDescription = 'SmartNPS360 notifications';

  String? get lastFcmToken => _lastFcmToken;

  Future<void> init() async {
    await _initLocalNotifications();
    await _initFirebaseMessaging();
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _local.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (details) {
        debugPrint(
          '[SmartNPS360][Push] notification tapped payload=${details.payload}',
        );
      },
    );

    final android = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
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
    if (_firebaseMessagingInitialized) return;
    _firebaseMessagingInitialized = true;

    final messaging = FirebaseMessaging.instance;

    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

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
      debugPrint(
        '[SmartNPS360][Push] onMessageOpenedApp id=${message.messageId}',
      );
    });

    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      debugPrint('[SmartNPS360][Push] initialMessage id=${initial.messageId}');
    }
  }

  Future<void> requestPermissionAfterLogin() async {
    if (_permissionRequestStarted) {
      await _maybeUploadToken();
      return;
    }
    _permissionRequestStarted = true;

    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint(
      '[SmartNPS360][Push] permission=${settings.authorizationStatus}',
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }

    try {
      final token = await messaging.getToken();
      _lastFcmToken = token;
      debugPrint('[SmartNPS360][Push] fcmToken=$token');
      await _maybeUploadToken();
    } catch (e) {
      debugPrint('[SmartNPS360][Push] getToken failed: $e');
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

    await uploadPushToken();
  }

  Future<void> uploadPushToken() async {
    final token = _lastFcmToken;
    if (token == null || token.isEmpty) {
      debugPrint('[SmartNPS360][Push] skip upload (no FCM token)');
      return;
    }

    ApiClient.instance.ensureAuthInterceptorInstalled();
    final payload = await _buildPushTokenPayload(pushToken: token);
    final uri = Uri.parse(AppConfig.pushTokenUrl);

    try {
      if (kDebugMode) {
        debugPrint('[SmartNPS360][Push] POST $uri body=$payload');
      }
      final response = await ApiClient.instance.dio.postUri(
        uri,
        data: payload,
        options: _jsonOptions(),
      );
      if (kDebugMode) {
        debugPrint(
          '[SmartNPS360][Push] upload ok status=${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[SmartNPS360][Push] upload failed: $e');
    }
  }

  Future<void> deletePushToken() async {
    final token = _lastFcmToken;
    if (token == null || token.isEmpty) {
      debugPrint('[SmartNPS360][Push] skip delete (no FCM token)');
      return;
    }

    final accessToken = await AuthRepository.instance.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      debugPrint('[SmartNPS360][Push] skip delete (no accessToken)');
      return;
    }

    ApiClient.instance.ensureAuthInterceptorInstalled();
    final payload = await _buildPushTokenPayload(pushToken: token);
    final uri = Uri.parse(AppConfig.pushTokenUrl);

    try {
      if (kDebugMode) {
        debugPrint('[SmartNPS360][Push] DELETE $uri body=$payload');
      }
      final response = await ApiClient.instance.dio.deleteUri(
        uri,
        data: payload,
        options: _jsonOptions(),
      );
      if (kDebugMode) {
        debugPrint(
          '[SmartNPS360][Push] delete ok status=${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[SmartNPS360][Push] delete failed: $e');
    }
  }

  Future<Map<String, dynamic>> _buildPushTokenPayload({
    required String pushToken,
  }) async {
    return {
      'platform': _platformName(),
      'device_id': await _deviceId(),
      'push_token': pushToken,
      'app_version': await _appVersion(),
    };
  }

  String _platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return Platform.operatingSystem;
  }

  Future<String> _deviceId() async {
    final cached = _cachedDeviceId;
    if (cached != null && cached.isNotEmpty) return cached;

    final info = DeviceInfoPlugin();
    String id;
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      final brand = _slug(a.brand);
      final model = _slug(a.model);
      id = '$brand-$model-${a.id}';
    } else if (Platform.isIOS) {
      final i = await info.iosInfo;
      id = 'ios-${i.identifierForVendor ?? _slug(i.utsname.machine)}';
    } else {
      id = Platform.operatingSystem;
    }

    _cachedDeviceId = id;
    return id;
  }

  Future<String> _appVersion() async {
    final cached = _cachedAppVersion;
    if (cached != null && cached.isNotEmpty) return cached;

    final info = await PackageInfo.fromPlatform();
    _cachedAppVersion = info.version;
    return info.version;
  }

  String _slug(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  Options _jsonOptions() {
    return Options(
      headers: const {'Accept': 'application/json'},
      contentType: Headers.jsonContentType,
      sendTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
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
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
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
