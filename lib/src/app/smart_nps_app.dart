import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../webview/webview_shell.dart';
import 'unsupported_platform_screen.dart';
import '../dev/location_test_screen.dart';

class SmartNpsApp extends StatelessWidget {
  const SmartNpsApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartNPS360',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF022A67),
      ),
      home: (kIsWeb || !(Platform.isAndroid || Platform.isIOS))
          ? const UnsupportedPlatformScreen()
          : const WebViewShell(),
      routes: {'/__dev/location': (_) => const LocationTestScreen()},
    );
  }
}
