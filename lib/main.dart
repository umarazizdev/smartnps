import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app/smart_nps_app.dart';
import 'src/background/background_location_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  await BackgroundLocationService.configureAndStart();
  runApp(const SmartNpsApp());
}
