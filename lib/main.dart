import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'src/app/smart_nps_app.dart';
import 'src/push/push_notification_service.dart';
import 'src/api/api_client.dart';
import 'src/location/mock_location_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  ApiClient.instance.ensureAuthInterceptorInstalled();
  await PushNotificationService.instance.init();
  MockLocationGuard.ensureBackgroundListenerInstalled();
  runApp(const SmartNpsApp());
}
