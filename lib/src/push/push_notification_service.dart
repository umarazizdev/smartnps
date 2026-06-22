import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../firebase_options.dart';
import '../api/api_client.dart';
import '../auth/auth_repository.dart';
import '../auth/auth_state.dart';
import '../utilities/app_config.dart';
import '../utilities/app_version_info.dart';
import '../utilities/permission_settings_helper.dart';

const String kPushAndroidChannelId = 'smartnps360_default';
const String kPushAndroidChannelName = 'SmartNPS360';
const String kPushAndroidChannelDescription = 'SmartNPS360 notifications';

Future<void> ensurePushLocalNotificationsReady(
  FlutterLocalNotificationsPlugin plugin,
) async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  await plugin.initialize(
    settings: const InitializationSettings(android: androidInit, iOS: iosInit),
  );

  final android = plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (android != null) {
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        kPushAndroidChannelId,
        kPushAndroidChannelName,
        description: kPushAndroidChannelDescription,
        importance: Importance.high,
      ),
    );
  }
}

Future<void> showPushLocalNotification({
  required FlutterLocalNotificationsPlugin plugin,
  required String title,
  required String body,
  required Map<String, dynamic> data,
  String? messageId,
}) async {
  final payload = jsonEncode({'messageId': messageId, 'data': data});

  final androidDetails = AndroidNotificationDetails(
    kPushAndroidChannelId,
    kPushAndroidChannelName,
    channelDescription: kPushAndroidChannelDescription,
    importance: Importance.high,
    priority: Priority.high,
  );
  const iosDetails = DarwinNotificationDetails();

  await plugin.show(
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

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint(
    '[SmartNPS360][Push] background message id=${message.messageId} '
    'notification=${message.notification?.title} data=${message.data}',
  );

  // Messages with a notification payload are displayed by the OS when killed.
  if (message.notification != null) {
    return;
  }

  final data = message.data;
  final title = (data['title'] ?? data['notification_title'] ?? 'SmartNPS360')
      .toString();
  final body =
      (data['body'] ??
              data['message'] ??
              data['notification_body'] ??
              data['text'] ??
              '')
          .toString();
  if (body.trim().isEmpty) {
    return;
  }

  final plugin = FlutterLocalNotificationsPlugin();
  await ensurePushLocalNotificationsReady(plugin);
  await showPushLocalNotification(
    plugin: plugin,
    title: title,
    body: body,
    data: Map<String, dynamic>.from(data),
    messageId: message.messageId,
  );
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static const _storage = FlutterSecureStorage();
  static const _kPushEnabledKey = 'push.notifications_enabled';

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  String? _lastFcmToken;
  bool? _pushNotificationsEnabled;
  bool _firebaseMessagingInitialized = false;
  bool _permissionPromptAttempted = false;
  Future<void>? _permissionPromptFuture;
  bool _iosPendingTokenUpload = false;
  bool _notificationSettingsPromptShown = false;
  String? _iosSessionCookieHeader;
  String? _iosXsrfToken;
  String? _cachedDeviceId;

  /// When this returns true, notification permission prompts are deferred
  /// (e.g. while the login screen is visible).
  bool Function()? _deferPermissionPromptWhile;

  void setDeferPermissionPromptWhile(bool Function()? checker) {
    _deferPermissionPromptWhile = checker;
  }

  bool get _shouldDeferPermissionPrompt =>
      _deferPermissionPromptWhile?.call() ?? false;

  void setIosSessionAuth({String? cookieHeader, String? xsrfToken}) {
    _iosSessionCookieHeader = cookieHeader;
    _iosXsrfToken = xsrfToken;
  }

  Future<bool> Function(Map<String, dynamic> payload)? _iosWebPushUpload;
  Future<bool> Function(Map<String, dynamic> payload)? _iosWebPushDelete;

  void setIosWebPushUploadHandler(
    Future<bool> Function(Map<String, dynamic> payload)? handler,
  ) {
    _iosWebPushUpload = handler;
  }

  void setIosWebPushDeleteHandler(
    Future<bool> Function(Map<String, dynamic> payload)? handler,
  ) {
    _iosWebPushDelete = handler;
  }

  String? get lastFcmToken => _lastFcmToken;

  bool get pushNotificationsEnabled => _pushNotificationsEnabled ?? true;

  void Function(String url)? _onNotificationTap;
  String? _pendingNotificationUrl;

  void setOnNotificationTap(void Function(String url)? handler) {
    _onNotificationTap = handler;
    final pending = _pendingNotificationUrl;
    if (handler != null && pending != null) {
      _pendingNotificationUrl = null;
      handler(pending);
    }
  }

  Future<void> init() async {
    await _loadPushEnabledPreference();
    await _initLocalNotifications();
    await _initFirebaseMessaging();
  }

  Future<void> _loadPushEnabledPreference() async {
    final stored = await _storage.read(key: _kPushEnabledKey);
    _pushNotificationsEnabled = stored != '0';
  }

  Future<void> _persistPushEnabledPreference(bool enabled) async {
    _pushNotificationsEnabled = enabled;
    await _storage.write(key: _kPushEnabledKey, value: enabled ? '1' : '0');
  }

  Future<Map<String, dynamic>> getNotificationStatus() async {
    return {
      'ok': true,
      'enabled': pushNotificationsEnabled,
      'hasToken': _lastFcmToken != null && _lastFcmToken!.isNotEmpty,
      'permissionGranted': await _hasNotificationPermission(),
    };
  }

  Future<Map<String, dynamic>> setNotificationsEnabled(bool enabled) async {
    if (enabled == pushNotificationsEnabled) {
      return {
        'ok': true,
        'enabled': enabled,
        'unchanged': true,
        ...(await getNotificationStatus()),
      };
    }

    await _persistPushEnabledPreference(enabled);
    if (!enabled) {
      await disablePushNotifications();
      return {
        'ok': true,
        'enabled': false,
        'hasToken': false,
        'permissionGranted': await _hasNotificationPermission(),
      };
    }

    await enablePushNotifications();
    return await getNotificationStatus();
  }

  Future<void> enablePushNotifications() async {
    await _ensureNotificationPermission();
    await _refreshFcmToken(uploadIfAuthenticated: true);
    if (Platform.isIOS) {
      await _iosRetryFcmTokenAndUpload();
    }
  }

  Future<void> disablePushNotifications() async {
    await deletePushToken();
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('[SmartNPS360][Push] deleteToken failed: $e');
    }
    _lastFcmToken = null;
    _iosPendingTokenUpload = false;
  }

  /// Waits until the notification permission flow finishes (system dialog included).
  ///
  /// Duty/location prompts should call this first so dialogs never stack.
  Future<void> waitForPermissionPromptCompleted({
    bool promptIfNeeded = false,
  }) async {
    if (_permissionPromptFuture != null) {
      await _permissionPromptFuture!;
      return;
    }
    if (_permissionPromptAttempted) return;
    if (!promptIfNeeded) return;
    await requestPermissionAfterAuth();
  }

  /// Prompts for notification permission after login or sign-up (once per app session).
  Future<void> requestPermissionAfterAuth() async {
    if (!pushNotificationsEnabled) {
      debugPrint(
        '[SmartNPS360][Push] skip permission prompt (disabled by user)',
      );
      return;
    }
    if (_shouldDeferPermissionPrompt) {
      debugPrint(
        '[SmartNPS360][Push] deferring notification permission (auth route)',
      );
      return;
    }
    if (_permissionPromptFuture != null) {
      return _permissionPromptFuture!;
    }

    if (_permissionPromptAttempted) {
      await _refreshFcmToken(uploadIfAuthenticated: true);
      return;
    }

    final future = _requestPermissionAfterAuthImpl();
    _permissionPromptFuture = future;
    try {
      await future;
    } finally {
      if (identical(_permissionPromptFuture, future)) {
        _permissionPromptFuture = null;
      }
    }
  }

  Future<void> _requestPermissionAfterAuthImpl() async {
    if (_permissionPromptAttempted) {
      await _refreshFcmToken(uploadIfAuthenticated: true);
      return;
    }
    _permissionPromptAttempted = true;

    // Brief delay so dashboard/navigation finishes before the system dialog.
    await Future<void>.delayed(const Duration(seconds: 1));

    debugPrint(
      '[SmartNPS360][Push] requesting notification permission (after auth)',
    );
    await _ensureNotificationPermission();
    await _refreshFcmToken(uploadIfAuthenticated: true);
    if (Platform.isIOS) {
      await _iosRetryFcmTokenAndUpload();
    }
  }

  /// Requests permission (if needed) and uploads the FCM token after auth.
  Future<void> syncPushTokenAfterLogin() async {
    if (!pushNotificationsEnabled) {
      debugPrint('[SmartNPS360][Push] skip push sync (disabled by user)');
      return;
    }
    if (_shouldDeferPermissionPrompt) {
      debugPrint(
        '[SmartNPS360][Push] deferring push sync until post-login route',
      );
      return;
    }
    if (!_permissionPromptAttempted) {
      await requestPermissionAfterAuth();
      return;
    }
    await _refreshFcmToken(uploadIfAuthenticated: true);
    if (Platform.isIOS && _iosPendingTokenUpload) {
      await _maybeUploadToken();
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      ),
      onDidReceiveNotificationResponse: (details) {
        debugPrint(
          '[SmartNPS360][Push] notification tapped payload=${details.payload}',
        );
        _handleLocalNotificationTap(details.payload);
      },
    );

    final android = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          kPushAndroidChannelId,
          kPushAndroidChannelName,
          description: kPushAndroidChannelDescription,
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
      if (!pushNotificationsEnabled) {
        debugPrint(
          '[SmartNPS360][Push] ignore onTokenRefresh (disabled by user)',
        );
        return;
      }
      _lastFcmToken = t;
      debugPrint('[SmartNPS360][Push] onTokenRefresh fcmToken=$t');
      _maybeUploadToken();
    });

    FirebaseMessaging.onMessage.listen((message) async {
      if (!pushNotificationsEnabled) return;
      debugPrint('[SmartNPS360][Push] onMessage id=${message.messageId}');
      await _showLocalFromRemoteMessage(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint(
        '[SmartNPS360][Push] onMessageOpenedApp id=${message.messageId}',
      );
      _handleRemoteMessageTap(message);
    });

    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      debugPrint('[SmartNPS360][Push] initialMessage id=${initial.messageId}');
      _handleRemoteMessageTap(initial);
    }
  }

  Future<bool> _hasNotificationPermission() async {
    if (Platform.isAndroid) {
      return (await Permission.notification.status).isGranted;
    }
    if (Platform.isIOS) {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    }
    return true;
  }

  Future<bool> _ensureNotificationPermission() async {
    if (Platform.isAndroid) {
      return _ensureAndroidNotificationPermission();
    }
    if (Platform.isIOS) {
      return _ensureIosNotificationPermission();
    }
    return true;
  }

  Future<bool> _ensureAndroidNotificationPermission() async {
    if (!Platform.isAndroid) return true;

    final current = await Permission.notification.status;
    if (current.isGranted) {
      debugPrint(
        '[SmartNPS360][Push] android notification permission=already granted',
      );
      return true;
    }

    final android = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      if (granted == true) {
        debugPrint(
          '[SmartNPS360][Push] android notification permission=granted',
        );
        return true;
      }
    }

    final status = await Permission.notification.request();
    debugPrint('[SmartNPS360][Push] android notification permission=$status');
    if (!status.isGranted &&
        PermissionSettingsHelper.shouldOpenSettings(status) &&
        !_notificationSettingsPromptShown) {
      _notificationSettingsPromptShown = true;
      await PermissionSettingsHelper.promptOpenSettings(
        title: 'Notifications disabled',
        message:
            'Please enable notifications for SmartNPS360 to receive important '
            'shift updates.',
        dialogKey: 'push_notification',
      );
    }
    return status.isGranted;
  }

  Future<bool> _ensureIosNotificationPermission() async {
    if (!Platform.isIOS) return true;

    final messaging = FirebaseMessaging.instance;
    final current = await messaging.getNotificationSettings();
    if (current.authorizationStatus == AuthorizationStatus.authorized ||
        current.authorizationStatus == AuthorizationStatus.provisional) {
      debugPrint('[SmartNPS360][Push] ios permission=already granted');
      return true;
    }

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint(
      '[SmartNPS360][Push] ios permission=${settings.authorizationStatus}',
    );
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!granted && !_notificationSettingsPromptShown) {
      _notificationSettingsPromptShown = true;
      await PermissionSettingsHelper.promptOpenSettings(
        title: 'Notifications disabled',
        message:
            'Please enable notifications for SmartNPS360 to receive important '
            'shift updates.',
        dialogKey: 'push_notification',
      );
    }
    return granted;
  }

  Future<void> _refreshFcmToken({required bool uploadIfAuthenticated}) async {
    if (!pushNotificationsEnabled) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      _lastFcmToken = token;
      debugPrint('[SmartNPS360][Push] fcmToken=$token');
      if (uploadIfAuthenticated) {
        await _maybeUploadToken();
      }
    } catch (e) {
      debugPrint('[SmartNPS360][Push] getToken failed: $e');
    }
  }

  Future<String?> _resolveAccessToken() async {
    final stored = await AuthRepository.instance.getAccessToken();
    if (stored != null && stored.isNotEmpty) return stored;

    if (!Platform.isIOS) return null;

    final session = AuthState.instance.session.value;
    if (session == null) return null;

    final token =
        (session['accessToken'] ??
                session['access_token'] ??
                session['token'] ??
                session['jwt'])
            ?.toString();
    if (token == null || token.isEmpty) return null;

    await AuthRepository.instance.saveAccessToken(token);
    return token;
  }

  Future<void> _iosRetryFcmTokenAndUpload() async {
    if (!Platform.isIOS) return;

    const delays = <Duration>[
      Duration(milliseconds: 600),
      Duration(seconds: 2),
    ];
    for (final delay in delays) {
      await Future<void>.delayed(delay);
      await _refreshFcmToken(uploadIfAuthenticated: true);
      final accessToken = await _resolveAccessToken();
      if (accessToken != null &&
          accessToken.isNotEmpty &&
          _lastFcmToken != null &&
          !_iosPendingTokenUpload) {
        return;
      }
    }
  }

  Future<void> _maybeUploadToken() async {
    if (!pushNotificationsEnabled) {
      debugPrint('[SmartNPS360][Push] skip upload (disabled by user)');
      return;
    }
    final token = _lastFcmToken;
    if (token == null || token.isEmpty) return;

    final payload = await _buildPushTokenPayload(pushToken: token);
    final accessToken = await _resolveAccessToken();
    if (accessToken != null && accessToken.isNotEmpty) {
      _iosPendingTokenUpload = false;
      await uploadPushToken();
      return;
    }

    if (Platform.isIOS) {
      final webUpload = _iosWebPushUpload;
      if (webUpload != null) {
        debugPrint('[SmartNPS360][Push] ios upload via web session fetch');
        final uploaded = await webUpload(payload);
        if (uploaded) {
          _iosPendingTokenUpload = false;
          return;
        }
      }

      if (_iosSessionCookieHeader != null &&
          _iosSessionCookieHeader!.isNotEmpty) {
        final uploaded = await uploadPushToken(useSessionCookies: true);
        if (uploaded) {
          _iosPendingTokenUpload = false;
          return;
        }
      }

      _iosPendingTokenUpload = true;
      debugPrint(
        '[SmartNPS360][Push] ios upload failed (API requires bearer token)',
      );
      return;
    }

    debugPrint('[SmartNPS360][Push] skip upload (no accessToken yet)');
  }

  Future<bool> uploadPushToken({bool useSessionCookies = false}) async {
    final token = _lastFcmToken;
    if (token == null || token.isEmpty) {
      debugPrint('[SmartNPS360][Push] skip upload (no FCM token)');
      return false;
    }

    ApiClient.instance.ensureAuthInterceptorInstalled();
    final payload = await _buildPushTokenPayload(pushToken: token);
    final uri = Uri.parse(AppConfig.pushTokenUrl);

    try {
      if (kDebugMode) {
        debugPrint(
          '[SmartNPS360][Push] POST $uri body=$payload '
          'auth=${useSessionCookies ? 'session-cookies' : 'bearer'}',
        );
      }
      final response = await ApiClient.instance.dio.postUri(
        uri,
        data: payload,
        options: _jsonOptions(useSessionCookies: useSessionCookies),
      );
      if (kDebugMode) {
        debugPrint(
          '[SmartNPS360][Push] upload ok status=${response.statusCode}',
        );
      }
      return response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
    } catch (e) {
      debugPrint('[SmartNPS360][Push] upload failed: $e');
      return false;
    }
  }

  Future<bool> deletePushToken() async {
    final token = _lastFcmToken;
    if (token == null || token.isEmpty) {
      debugPrint('[SmartNPS360][Push] skip delete (no FCM token)');
      return true;
    }

    final payload = await _buildPushTokenPayload(pushToken: token);
    var deleted = false;

    final accessToken = await _resolveAccessToken();
    if (accessToken != null && accessToken.isNotEmpty) {
      deleted = await _deletePushTokenViaApi(
        payload: payload,
        useSessionCookies: false,
      );
    }

    if (!deleted && Platform.isIOS) {
      final webDelete = _iosWebPushDelete;
      if (webDelete != null) {
        debugPrint('[SmartNPS360][Push] ios delete via web session fetch');
        deleted = await webDelete(payload);
      }

      if (!deleted &&
          _iosSessionCookieHeader != null &&
          _iosSessionCookieHeader!.isNotEmpty) {
        deleted = await _deletePushTokenViaApi(
          payload: payload,
          useSessionCookies: true,
        );
      }
    }

    if (!deleted) {
      debugPrint('[SmartNPS360][Push] delete failed or skipped (no auth)');
    }
    return deleted;
  }

  Future<bool> _deletePushTokenViaApi({
    required Map<String, dynamic> payload,
    required bool useSessionCookies,
  }) async {
    ApiClient.instance.ensureAuthInterceptorInstalled();
    final uri = Uri.parse(AppConfig.pushTokenUrl);

    try {
      if (kDebugMode) {
        debugPrint(
          '[SmartNPS360][Push] DELETE $uri body=$payload '
          'auth=${useSessionCookies ? 'session-cookies' : 'bearer'}',
        );
      }
      final response = await ApiClient.instance.dio.deleteUri(
        uri,
        data: payload,
        options: _jsonOptions(useSessionCookies: useSessionCookies),
      );
      final ok = response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
      if (kDebugMode) {
        debugPrint(
          '[SmartNPS360][Push] delete ok status=${response.statusCode}',
        );
      }
      return ok;
    } catch (e) {
      debugPrint('[SmartNPS360][Push] delete failed: $e');
      return false;
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

  Future<String> _appVersion() async => AppVersionInfo.version;

  String _slug(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  Options _jsonOptions({bool useSessionCookies = false}) {
    final headers = <String, dynamic>{'Accept': 'application/json'};
    if (useSessionCookies) {
      final cookieHeader = _iosSessionCookieHeader;
      if (cookieHeader != null && cookieHeader.isNotEmpty) {
        headers['Cookie'] = cookieHeader;
      }
      final xsrf = _iosXsrfToken;
      if (xsrf != null && xsrf.isNotEmpty) {
        headers['X-XSRF-TOKEN'] = xsrf;
      }
      headers['X-Requested-With'] = 'XMLHttpRequest';
      headers['Referer'] = AppConfig.initialUrl;
      headers['Origin'] = AppConfig.initialUrl.replaceAll(RegExp(r'/$'), '');
    }
    return Options(
      headers: headers,
      contentType: Headers.jsonContentType,
      sendTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
    );
  }

  void _handleLocalNotificationTap(String? payload) {
    if (payload == null || payload.trim().isEmpty) {
      _dispatchNotificationTap(AppConfig.defaultPushUrl);
      return;
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        final data = decoded['data'];
        if (data is Map) {
          _dispatchNotificationTap(
            resolveNotificationUrl(Map<String, dynamic>.from(data)),
          );
          return;
        }
      }
    } catch (e) {
      debugPrint('[SmartNPS360][Push] invalid tap payload: $e');
    }

    _dispatchNotificationTap(AppConfig.defaultPushUrl);
  }

  void _handleRemoteMessageTap(RemoteMessage message) {
    _dispatchNotificationTap(resolveNotificationUrl(message.data));
  }

  void _dispatchNotificationTap(String url) {
    final normalized = normalizeNotificationUrl(url);
    debugPrint('[SmartNPS360][Push] open url=$normalized');
    final handler = _onNotificationTap;
    if (handler != null) {
      handler(normalized);
      return;
    }
    _pendingNotificationUrl = normalized;
  }

  static String resolveNotificationUrl(Map<String, dynamic> data) {
    final url = data['url']?.toString().trim();
    if (url != null && url.isNotEmpty) {
      return normalizeNotificationUrl(url);
    }

    final path = data['path']?.toString().trim();
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        return normalizeNotificationUrl(path);
      }
      final normalizedPath = path.startsWith('/') ? path : '/$path';
      final base = AppConfig.initialUrl.endsWith('/')
          ? AppConfig.initialUrl.substring(0, AppConfig.initialUrl.length - 1)
          : AppConfig.initialUrl;
      return normalizeNotificationUrl('$base$normalizedPath');
    }

    return AppConfig.defaultPushUrl;
  }

  static String normalizeNotificationUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) {
      return AppConfig.defaultPushUrl;
    }
    if (!AppConfig.isAllowedHost(uri.host)) {
      return AppConfig.defaultPushUrl;
    }
    return uri.toString();
  }

  Future<void> _showLocalFromRemoteMessage(RemoteMessage message) async {
    final n = message.notification;
    final data = message.data;
    final title =
        n?.title ??
        data['title']?.toString() ??
        data['notification_title']?.toString() ??
        'SmartNPS360';
    final body =
        n?.body ??
        data['body']?.toString() ??
        data['message']?.toString() ??
        data['notification_body']?.toString() ??
        '';

    await showPushLocalNotification(
      plugin: _local,
      title: title,
      body: body,
      data: Map<String, dynamic>.from(data),
      messageId: message.messageId,
    );
  }
}
