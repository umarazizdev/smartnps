import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../app/app_navigator.dart';
import '../app/native_theme_controller.dart';
import '../webview/webview_shell.dart';
import 'unsupported_platform_screen.dart';

class SmartNpsApp extends StatelessWidget {
  const SmartNpsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeMode = NativeThemeController.instance.nativeThemeMode.value;
      return GetMaterialApp(
        title: 'SmartNPS360',
        debugShowCheckedModeBanner: false,
        navigatorKey: AppNavigator.key,
        themeMode: themeMode,
        theme: ThemeData(
          brightness: Brightness.light,
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF022A67),
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2563EB),
            brightness: Brightness.dark,
            surface: const Color(0xFF1A2332),
            primary: const Color(0xFF93C5FD),
          ),
          scaffoldBackgroundColor: const Color(0xFF0F1724),
          dialogTheme: const DialogThemeData(
            backgroundColor: Color(0xFF1A2332),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(22)),
            ),
          ),
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: Color(0xFF1A2332),
            modalBackgroundColor: Color(0xFF1A2332),
            surfaceTintColor: Colors.transparent,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFBFDBFE),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF111827),
            ),
          ),
        ),
        home: (kIsWeb || !(Platform.isAndroid || Platform.isIOS))
            ? const UnsupportedPlatformScreen()
            : const WebViewShell(),
      );
    });
  }
}
