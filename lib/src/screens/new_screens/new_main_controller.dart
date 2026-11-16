import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'Calendar/new_calendar_screen.dart';
import 'Dashboard/new_dashboard_screen.dart';
import 'Messages/new_messages_screen.dart';
import 'Profile/new_profile_screen.dart';
import 'ShiftLog/new_shift_log_screen.dart';
import 'Timesheet/new_timesheet_screen.dart';
import 'Widgets/new_quick_actions_overlay.dart';

class NewMainController extends GetxController {
  final pageIndex = 0.obs;
  final isBottomBarVisible = true.obs;
  final isAppHeaderVisible = true.obs;
  final quickActionsOpen = false.obs;

  final pages = const <Widget>[
    NewDashboardScreen(),
    NewCalendarScreen(),
    NewMessagesScreen(),
    NewTimesheetScreen(),
    NewProfileScreen(),
  ];

  void changePage(int index) {
    if (index < 0 || index >= pages.length) return;
    closeQuickActions();
    pageIndex.value = index;
  }

  Future<void> toggleQuickActions() async {
    if (quickActionsOpen.value && Get.isDialogOpen == true) {
      closeQuickActions();
      return;
    }
    quickActionsOpen.value = false;
    await NewQuickActionsDialog.show();
  }

  void closeQuickActions() {
    if (Get.isDialogOpen == true) {
      NewQuickActionsDialog.dismiss();
    }
    quickActionsOpen.value = false;
  }

  void openShiftLog() {
    closeQuickActions();
    Get.to(
      () => const NewShiftLogScreen(),
      transition: Transition.cupertino,
      duration: const Duration(milliseconds: 280),
    );
  }

  void hideBottomBar() {
    isBottomBarVisible.value = false;
  }

  void showBottomBar() {
    isBottomBarVisible.value = true;
  }

  void enterFocusedView() {
    isAppHeaderVisible.value = false;
    isBottomBarVisible.value = false;
  }

  void leaveFocusedView() {
    isAppHeaderVisible.value = true;
    isBottomBarVisible.value = true;
  }
}
