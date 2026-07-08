import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'src/app/smart_nps_app.dart';
import 'src/push/push_notification_service.dart';
import 'src/api/api_client.dart';
import 'src/auth/auth_repository.dart';
import 'src/auth/auth_session_manager.dart';
import 'src/location/mock_location_guard.dart';
import 'src/utilities/app_version_info.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AppVersionInfo.init();
  ApiClient.instance.ensureAuthInterceptorInstalled();
  AuthRepository.instance.onRefreshSessionExpired =
      AuthSessionManager.clearNativeSession;
  await AuthRepository.instance.warmAccessTokenCache();
  await PushNotificationService.instance.init();
  MockLocationGuard.ensureBackgroundListenerInstalled();
  runApp(const SmartNpsApp());
}
