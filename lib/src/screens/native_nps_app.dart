import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/app/app_navigator.dart';
import 'package:smartnps360/src/screens/app_storage.dart';
import 'package:smartnps360/src/screens/controllers/usercontroller.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/timer_controller.dart';
import 'package:smartnps360/src/screens/main_screens/VisitVideoScreen/visit_video_preview_screen.dart';
import 'package:smartnps360/src/screens/main_screens/VisitVideoScreen/visit_video_recorder_screen.dart';
import 'package:smartnps360/src/screens/splash/splashscreen.dart';
import 'package:smartnps360/src/screens/utilities/themedata.dart';

class NativeNpsApp extends StatelessWidget {
  const NativeNpsApp({super.key});

  static const _edgeToEdgeOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  );

  @override
  Widget build(BuildContext context) {
    final bool savedDark = box.read('isDarkMode') ?? false;
    final easyLoadingBuilder = EasyLoading.init();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _edgeToEdgeOverlay,
      child: GetMaterialApp(
        navigatorKey: AppNavigator.key,
        initialBinding: BindingsBuilder(() {
          Get.put(TimeController(), permanent: true);
          Get.put(UserController(), permanent: true);
        }),
        debugShowCheckedModeBanner: false,
        title: 'SmartNPS360',
        theme: appTheme,
        darkTheme: appDarkTheme,
        themeMode: savedDark ? ThemeMode.dark : ThemeMode.light,
        getPages: [
          GetPage(
            name: VisitVideoRecorderScreen.routeName,
            page: () => const VisitVideoRecorderScreen(),
          ),
          GetPage(
            name: VisitVideoPreviewScreen.routeName,
            page: () => const VisitVideoPreviewScreen(),
          ),
        ],
        home: SplashScreen(
          splashThemeMode: savedDark ? ThemeMode.dark : ThemeMode.light,
        ),
        builder: (context, child) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: _edgeToEdgeOverlay,
            child: easyLoadingBuilder(context, child),
          );
        },
      ),
    );
  }
}
