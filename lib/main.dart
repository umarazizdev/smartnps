import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app/smart_nps_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  runApp(const SmartNpsApp());
}
