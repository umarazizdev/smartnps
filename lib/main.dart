import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'firebase_options.dart';
import 'src/app/smart_nps_app.dart';
import 'src/background/location/android_duty_location_health.dart';
import 'src/background/location/background_location_service.dart';
import 'src/push/notifications/push_notification_service.dart';
import 'src/api/api_client.dart';
import 'src/auth/auth_repository.dart';
import 'src/debug/debug_env_config.dart';
import 'src/location/mock_location_guard.dart';
import 'src/utilities/app_upgrade_reconciler.dart';
import 'src/utilities/app_version_info.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _disableWebViewDebugLogging();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _initCrashlytics();
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await DebugEnvConfig.instance.init();
  }
  await AppVersionInfo.init();
  await AppUpgradeReconciler.reconcileIfNeeded();
  ApiClient.instance.ensureAuthInterceptorInstalled();
  unawaited(AuthRepository.instance.warmAccessTokenCache());
  unawaited(_initPostUiServices());
  runApp(const SmartNpsApp());
}

Future<void> _initCrashlytics() async {
  try {
    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);

      if (kDebugMode) {
        FlutterError.presentError(errorDetails);
      }
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);

      return !kDebugMode;
    };

    if (kDebugMode) {

      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      await FirebaseCrashlytics.instance.sendUnsentReports();
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
    } else {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    }
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
