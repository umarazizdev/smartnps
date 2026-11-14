import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/main_screens/DARScreen/darscreen.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/dashboardscreen.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/timer_controller.dart';
import 'package:smartnps360/src/screens/main_screens/HelpScreen/helpscreen.dart';
import 'package:smartnps360/src/screens/main_screens/ProfileScreen/profilescreen.dart';
import 'package:smartnps360/src/screens/main_screens/TimeSheetScreen/timesheetscreen.dart';

class MainController extends GetxController implements WidgetsBindingObserver {
  final RxInt pageIndex = 0.obs;
  final RxBool isBottomBarVisible = true.obs;

  final pages = const [
    DashBoardScreen(),
    TimesheetScreen(),
    DARScreen(),
    HelpScreen(),
    ProfileScreen(),
  ];

  void changePage(int index) {
    pageIndex.value = index;
  }

  void hideBottomBar() {
    isBottomBarVisible.value = false;
  }

  void showBottomBar() {
    isBottomBarVisible.value = true;
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      try {
        if (Get.isRegistered<TimeController>()) {
          Get.find<TimeController>().refreshServerSession(
            showShimmer: false,
            blockUI: false,
            suppressScopeLoading: true,
          );
        }
      } catch (_) {}
    }
  }

  // -------------------------
  // Safe no-op implementations
  // -------------------------

  @override
  void didChangeAccessibilityFeatures() {}

  @override
  void didChangeLocales(List<Locale>? locales) {}

  @override
  void didChangeMetrics() {}

  @override
  void didChangePlatformBrightness() {}

  @override
  void didChangeTextScaleFactor() {}

  @override
  void didChangeViewFocus(ViewFocusEvent event) {}

  @override
  void didHaveMemoryPressure() {}

  // -------------------------
  // Navigation / Router
  // -------------------------

  @override
  Future<bool> didPopRoute() async {
    // Return false to let framework handle it
    return false;
  }

  @override
  Future<bool> didPushRoute(String route) async {
    return false;
  }

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    return false;
  }

  // -------------------------
  // App exit
  // -------------------------

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    // Allow system to handle normally
    return AppExitResponse.exit;
  }

  // -------------------------
  // Android Predictive Back
  // -------------------------

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    // Return false to allow system to control gesture
    return false;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {}

  @override
  void handleCommitBackGesture() {}

  @override
  void handleCancelBackGesture() {}

  @override
  void handleStatusBarTap() {}
}
