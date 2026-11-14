import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'Dashboard/new_dashboard_screen.dart';
import 'Calendar/new_calendar_screen.dart';
import 'ShiftLog/new_shift_log_screen.dart';
import 'Messages/new_messages_screen.dart';
import 'Profile/new_profile_screen.dart';

class NewMainController extends GetxController {
  final pageIndex = 0.obs;
  final isBottomBarVisible = true.obs;

  final pages = const <Widget>[
    NewDashboardScreen(),
    NewCalendarScreen(),
    NewShiftLogScreen(),
    NewMessagesScreen(),
    NewProfileScreen(),
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
}
