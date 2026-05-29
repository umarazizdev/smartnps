import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'src/app/smart_nps_app.dart';
import 'src/background/background_location_permissions.dart';
import 'src/background/background_location_service.dart';
import 'src/push/push_notification_service.dart';
import 'src/api/api_client.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'src/widgets/mock_location_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  ApiClient.instance.ensureAuthInterceptorInstalled();
  await PushNotificationService.instance.init();
  final granted = await BackgroundLocationPermissions.ensureGranted();
  if (granted) {
    await BackgroundLocationService.configureAndStart();
  }

  DateTime? lastMockDialogAt;
  FlutterBackgroundService().on('mock_location').listen((event) {
    final now = DateTime.now();
    final last = lastMockDialogAt;
    if (last != null && now.difference(last) < const Duration(minutes: 2)) {
      return;
    }
    lastMockDialogAt = now;

    final ctx = SmartNpsApp.navigatorKey.currentContext;
    if (ctx == null) return;
    showDialog<void>(
      // ignore: use_build_context_synchronously
      context: ctx,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (context) => const MockLocationDialog(),
    );
  });
  runApp(const SmartNpsApp());
}
