import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'firebase_options.dart';
import 'src/api/api_client.dart';
import 'src/auth/auth_repository.dart';
import 'src/background/location/android_duty_location_health.dart';
import 'src/background/location/background_location_service.dart';
import 'src/crashlytics/crashlytics_identity.dart';
import 'src/crashlytics/crashlytics_reporter.dart';
import 'src/debug/debug_env_access_service.dart';
import 'src/debug/debug_env_config.dart';
import 'src/location/mock_location_guard.dart';
import 'src/push/notifications/push_notification_service.dart';
import 'src/screens/app_storage.dart';
import 'src/screens/controllers/connectivitycontroller.dart';
import 'src/screens/native_auth_session.dart';
import 'src/screens/native_nps_app.dart';
import 'src/screens/utilities/const.dart';
import 'src/utilities/app_upgrade_reconciler.dart';
import 'src/utilities/app_version_info.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _disableWebViewDebugLogging();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    ),
  );
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _initCrashlytics();
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await DebugEnvConfig.instance.init();
    unawaited(DebugEnvAccessService.instance.ensureReady());
  }
  await AppVersionInfo.init();
  await AppUpgradeReconciler.reconcileIfNeeded();
  await GetStorage.init();
  box.remove('notificationPermissionAsked');
  await AuthRepository.instance.warmAccessTokenCache();
  await NativeAuthSession.instance.hydrate();
  Get.put(ConnectivityController(), permanent: true);
  _configureEasyLoading();
  ApiClient.instance.ensureAuthInterceptorInstalled();
  unawaited(CrashlyticsIdentity.syncFromStoredSession());
  unawaited(_initPostUiServices());
  runApp(const NativeNpsApp());
}

void _configureEasyLoading() {
  EasyLoading.instance
    ..displayDuration = const Duration(milliseconds: 2000)
    ..indicatorType = EasyLoadingIndicatorType.fadingCircle
    ..loadingStyle = EasyLoadingStyle.custom
    ..indicatorSize = 45.0
    ..radius = 10.0
    ..progressColor = Colors.white
    ..backgroundColor = cOrange
    ..indicatorColor = Colors.white
    ..textColor = Colors.white
    ..maskColor = Colors.blue.withAlpha(128)
    ..userInteractions = true
    ..dismissOnTap = false;
}

Future<void> _initCrashlytics() async {
  try {
    await CrashlyticsReporter.init();
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[SmartNPS360] Crashlytics init failed: $e\n$st');
    }
  }
}

Future<void> _initPostUiServices() async {
  try {
    await PushNotificationService.instance.init();
    MockLocationGuard.ensureBackgroundListenerInstalled();
    if (Platform.isAndroid) {
      AndroidDutyLocationHealth.ensureListenerInstalled();
      unawaited(BackgroundLocationService.ensureConfigured());
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[SmartNPS360] post-UI service init failed: $e');
    }
  }
}

void _disableWebViewDebugLogging() {
  PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
  PlatformInAppBrowser.debugLoggingSettings.enabled = false;
  PlatformChromeSafariBrowser.debugLoggingSettings.enabled = false;
  PlatformWebAuthenticationSession.debugLoggingSettings.enabled = false;
  PlatformPullToRefreshController.debugLoggingSettings.enabled = false;
  PlatformFindInteractionController.debugLoggingSettings.enabled = false;
}
