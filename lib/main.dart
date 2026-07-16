import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'firebase_options.dart';
import 'src/app/smart_nps_app.dart';
import 'src/push/push_notification_service.dart';
import 'src/api/api_client.dart';
import 'src/auth/auth_repository.dart';
import 'src/auth/auth_session_manager.dart';
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
  await AppVersionInfo.init();
  await AppUpgradeReconciler.reconcileIfNeeded();
  ApiClient.instance.ensureAuthInterceptorInstalled();
  AuthRepository.instance.onRefreshSessionExpired =
      AuthSessionManager.clearNativeSession;
  await AuthRepository.instance.warmAccessTokenCache();
  await PushNotificationService.instance.init();
  MockLocationGuard.ensureBackgroundListenerInstalled();
  runApp(const SmartNpsApp());
}

void _disableWebViewDebugLogging() {
  PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
  PlatformInAppBrowser.debugLoggingSettings.enabled = false;
  PlatformChromeSafariBrowser.debugLoggingSettings.enabled = false;
  PlatformWebAuthenticationSession.debugLoggingSettings.enabled = false;
  PlatformPullToRefreshController.debugLoggingSettings.enabled = false;
  PlatformFindInteractionController.debugLoggingSettings.enabled = false;
}
