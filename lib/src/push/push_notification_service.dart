import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../firebase_options.dart';
import '../api/api_client.dart';
import '../auth/auth_repository.dart';
import '../auth/auth_state.dart';
import '../permissions/native_permission_status_service.dart';
import '../permissions/os_notification_permission.dart';
import '../permissions/required_permissions_gate.dart';
import 'officer_announcement_coordinator.dart';
import 'officer_announcement_push.dart';
import 'push_notification_preferences.dart';
import '../utilities/app_config.dart';
import '../utilities/app_version_info.dart';
import '../utilities/overlay_prompt_guard.dart';
import '../utilities/permission_settings_helper.dart';

const String kPushAndroidChannelId = 'smartnps360_default';
const String kPushAndroidChannelName = 'SmartNPS360';
const String kPushAndroidChannelDescription = 'SmartNPS360 notifications';
const String kPushIosSoundFile = 'alert_sound.caf';

const DarwinNotificationDetails kPushIosNotificationDetails =
    DarwinNotificationDetails(
      presentSound: true,
      presentBanner: true,
      presentList: true,
      sound: kPushIosSoundFile,
    );

const DarwinInitializationSettings kPushIosInitializationSettings =
    DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      defaultPresentSound: true,
      defaultPresentBanner: true,
      defaultPresentList: true,
    );

void debugPrintRemoteMessagePayload(String source, RemoteMessage message) {
  final notification = message.notification;
  debugPrint(
    '[SmartNPS360][Push][$source] messageId=${message.messageId} '
    'hasNotification=${notification != null} dataKeys=${message.data.length}',
  );
}

Future<void> ensurePushLocalNotificationsReady(
  FlutterLocalNotificationsPlugin plugin,
) async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(
    settings: const InitializationSettings(
      android: androidInit,
      iOS: kPushIosInitializationSettings,
    ),
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
        sound: RawResourceAndroidNotificationSound('alert_sound'),
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
    sound: RawResourceAndroidNotificationSound('alert_sound'),
  );
  const iosDetails = kPushIosNotificationDetails;

  debugPrint(
    '[SmartNPS360][Push] showing local notification sound=$kPushIosSoundFile '
    'title=$title',
  );

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

  debugPrintRemoteMessagePayload('background', message);

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

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  String? _lastFcmToken;
  String? _lastUploadedPushTokenFingerprint;
  String? _pushTokenUploadInFlightFingerprint;
  Future<bool>? _pushTokenUploadInFlight;
  bool? _pushNotificationsEnabled;
  bool _firebaseMessagingInitialized = false;
  bool _permissionPromptAttempted = false;
  Future<void>? _permissionPromptFuture;
  bool _iosPendingTokenUpload = false;
  bool _notificationSettingsPromptShown = false;
  String? _iosSessionCookieHeader;
  String? _iosXsrfToken;
  String? _cachedDeviceId;

  bool Function()? _deferPermissionPromptWhile;

  VoidCallback? _onPushPreferenceChanged;

  void setDeferPermissionPromptWhile(bool Function()? checker) {
    _deferPermissionPromptWhile = checker;
  }

  void setOnPushPreferenceChanged(VoidCallback? callback) {
    _onPushPreferenceChanged = callback;
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
  bool _initialMessageHandled = false;

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
    _pushNotificationsEnabled = await PushNotificationPreferences.readEnabled();
  }

  Future<void> _persistPushEnabledPreference(bool enabled) async {
    _pushNotificationsEnabled = enabled;
    await PushNotificationPreferences.writeEnabled(enabled);
  }

  Future<Map<String, dynamic>> getNotificationStatus() async {
    await _loadPushEnabledPreference();
    final permissionGranted = await _hasNotificationPermission();
    final hasToken = _lastFcmToken != null && _lastFcmToken!.isNotEmpty;
    return {
      'ok': true,
      'enabled': pushNotificationsEnabled,
      'permissionGranted': permissionGranted,
      'hasToken': hasToken,
    };
  }

  Future<Map<String, dynamic>> setNotificationsEnabled(bool enabled) async {
    final previous = pushNotificationsEnabled;
    if (enabled == previous) {
      return {
        'ok': true,
        'unchanged': true,
        ...(await getNotificationStatus()),
      };
    }

    await _persistPushEnabledPreference(enabled);
    if (!enabled) {
      await disablePushNotifications();
    } else {
      await enablePushNotifications();
    }

    _onPushPreferenceChanged?.call();

    final status = await getNotificationStatus();
    await syncPushStateToPermissionApi();
    return status;
  }

  Future<void> syncPushStateToPermissionApi() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (!await AuthRepository.instance.isOfficerLoggedIn()) return;

    await _loadPushEnabledPreference();
    await NativePermissionStatusService.instance.uploadPushToggle(
      enabled: pushNotificationsEnabled,
    );
  }

  Future<Map<String, dynamic>> reconcileOnAppResume() async {
    await _loadPushEnabledPreference();

    if (pushNotificationsEnabled) {
      final permissionGranted = await _hasNotificationPermission();
      if (permissionGranted) {
        await _refreshFcmToken(uploadIfAuthenticated: true);
        if (Platform.isIOS) {
          await _iosRetryFcmTokenAndUpload();
        } else if (_lastFcmToken != null && _lastFcmToken!.isNotEmpty) {
          await _maybeUploadToken();
        }
      }
    }

    return getNotificationStatus();
  }

  Future<void> enablePushNotifications() async {
    final granted = await _ensureNotificationPermission();
    if (!granted) {
      debugPrint('[SmartNPS360][Push] enable skipped (permission not granted)');
      return;
    }
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

    await _local.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: kPushIosInitializationSettings,
      ),
      onDidReceiveNotificationResponse: (details) {
        debugPrint(
          '[SmartNPS360][Push] notification tapped payloadPresent=${details.payload != null}',
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
          sound: RawResourceAndroidNotificationSound('alert_sound'),
        ),
      );
    }
  }

  Future<void> _initFirebaseMessaging() async {
    if (_firebaseMessagingInitialized) return;
    _firebaseMessagingInitialized = true;

    final messaging = FirebaseMessaging.instance;

    if (Platform.isIOS) {
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );
    } else {
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

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
      debugPrintRemoteMessagePayload('foreground', message);
      if (!pushNotificationsEnabled) return;
      await _showLocalFromRemoteMessage(message);
      _handleForegroundAnnouncement(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrintRemoteMessagePayload('openedApp', message);
      _handleRemoteMessageOpened(message, source: 'opened-app');
    });

    if (!_initialMessageHandled) {
      _initialMessageHandled = true;
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        debugPrintRemoteMessagePayload('initialMessage', initial);
        _handleRemoteMessageOpened(initial, source: 'cold-launch');
      }
    }

    debugPrint('[SmartNPS360][Push] Firebase messaging listeners ready');
  }

  Future<bool> _hasNotificationPermission() async {
    return OsNotificationPermission.isGranted();
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

    final status = await OverlayPromptGuard.runDuringOsPermissionPrompt(
      Permission.notification.request,
    );
    debugPrint('[SmartNPS360][Push] android notification permission=$status');
    if (!status.isGranted &&
        PermissionSettingsHelper.shouldOpenSettings(status) &&
        !_notificationSettingsPromptShown &&
        !_isRequiredPermissionsBlockerActive) {
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

    final settings = await OverlayPromptGuard.runDuringOsPermissionPrompt(
      () => messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      ),
    );
    debugPrint(
      '[SmartNPS360][Push] ios permission=${settings.authorizationStatus}',
    );
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!granted &&
        !_notificationSettingsPromptShown &&
        !_isRequiredPermissionsBlockerActive) {
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

  bool get _isRequiredPermissionsBlockerActive =>
      RequiredPermissionsGate.shouldSuppressCompetingDialogs;

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
    final stored = await AuthRepository.instance.ensureValidAccessToken();
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
    final fingerprint = _pushTokenUploadFingerprint(
      payload,
      useSessionCookies: useSessionCookies,
    );

    if (fingerprint == _lastUploadedPushTokenFingerprint) {
      if (kDebugMode) {
        debugPrint('[SmartNPS360][Push] skip upload (unchanged token)');
      }
      return true;
    }

    final inFlight = _pushTokenUploadInFlight;
    if (inFlight != null &&
        fingerprint == _pushTokenUploadInFlightFingerprint) {
      if (kDebugMode) {
        debugPrint('[SmartNPS360][Push] join upload (unchanged token)');
      }
      return inFlight;
    }

    final task = _uploadPushTokenNow(
      uri: uri,
      payload: payload,
      useSessionCookies: useSessionCookies,
      fingerprint: fingerprint,
    );
    _pushTokenUploadInFlight = task;
    _pushTokenUploadInFlightFingerprint = fingerprint;
    try {
      return await task;
    } finally {
      if (identical(_pushTokenUploadInFlight, task)) {
        _pushTokenUploadInFlight = null;
        _pushTokenUploadInFlightFingerprint = null;
      }
    }
  }

  String _pushTokenUploadFingerprint(
    Map<String, dynamic> payload, {
    required bool useSessionCookies,
  }) {
    return jsonEncode({
      'auth': useSessionCookies ? 'session-cookies' : 'bearer',
      'payload': payload,
    });
  }

  Future<bool> _uploadPushTokenNow({
    required Uri uri,
    required Map<String, dynamic> payload,
    required bool useSessionCookies,
    required String fingerprint,
  }) async {
    try {
      final response = await ApiClient.instance.dio.postUri(
        uri,
        data: payload,
        options: _jsonOptions(useSessionCookies: useSessionCookies),
      );
      final ok =
          response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
      if (ok) {
        _lastUploadedPushTokenFingerprint = fingerprint;
      }
      return ok;
    } catch (_) {
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
    } else {
      _lastUploadedPushTokenFingerprint = null;
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
      final response = await ApiClient.instance.dio.deleteUri(
        uri,
        data: payload,
        options: _jsonOptions(useSessionCookies: useSessionCookies),
      );
      final ok =
          response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
      return ok;
    } catch (_) {
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
      'build': AppVersionInfo.buildNumber,
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
          final map = Map<String, dynamic>.from(data);
          if (_consumeAnnouncementOpen(map, source: 'local-tap')) {
            return;
          }
          _dispatchNotificationTap(resolveNotificationUrl(map));
          return;
        }
      }
    } catch (e) {
      debugPrint('[SmartNPS360][Push] invalid tap payload: $e');
    }

    _dispatchNotificationTap(AppConfig.defaultPushUrl);
  }

  void _handleRemoteMessageOpened(
    RemoteMessage message, {
    required String source,
  }) {
    final data = Map<String, dynamic>.from(message.data);
    if (_consumeAnnouncementOpen(data, source: source)) {
      return;
    }
    _dispatchNotificationTap(resolveNotificationUrl(data));
  }

  void _handleForegroundAnnouncement(RemoteMessage message) {
    final announcement = OfficerAnnouncementPush.tryParse(
      Map<String, dynamic>.from(message.data),
    );
    if (announcement == null) return;
    OfficerAnnouncementCoordinator.instance.onForeground(announcement);
  }

  bool _consumeAnnouncementOpen(
    Map<String, dynamic> data, {
    required String source,
  }) {
    final announcement = OfficerAnnouncementPush.tryParse(data);
    if (announcement == null) return false;
    OfficerAnnouncementCoordinator.instance.onOpened(
      announcement,
      source: source,
    );
    return true;
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
