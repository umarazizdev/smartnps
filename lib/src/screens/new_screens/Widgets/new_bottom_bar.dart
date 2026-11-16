import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/utilities/app_config.dart';
import 'package:smartnps360/src/widgets/chrome/platform_bottom_bar.dart';
import '../new_main_controller.dart';

class NewBottomBar extends StatelessWidget {
  const NewBottomBar({super.key, required this.controller});

  final NewMainController controller;

  static const List<PlatformBottomTab> _tabs = [
    PlatformBottomTab(
      label: 'Dashboard',
      index: 0,
      iosSymbolName: 'house.fill',
      activeAssetIcon: 'assets/home-icon-silhouette.png',
      inactiveAssetIcon: 'assets/home-outline.png',
      materialIcon: Icons.home_rounded,
    ),
    PlatformBottomTab(
      label: 'Calendar',
      index: 1,
      iosSymbolName: 'calendar',
      useCalendarClockIcon: true,
      materialIcon: Icons.calendar_month_rounded,
    ),
    PlatformBottomTab(
      label: 'Messages',
      index: 2,
      iosSymbolName: 'bubble.left',
      useThinChatIcon: true,
      materialIcon: Icons.chat_bubble_outline_rounded,
    ),
    PlatformBottomTab(
      label: 'Timesheet',
      index: 3,
      iosSymbolName: 'calendar',
      useTimesheetIcon: true,
      materialIcon: Icons.calendar_month_outlined,
    ),
    PlatformBottomTab(
      label: 'Profile',
      index: 4,
      iosSymbolName: 'person.crop.circle.fill',
      activeAssetIcon: 'assets/user.png',
      inactiveAssetIcon: 'assets/user-outline.png',
      materialIcon: Icons.account_circle_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Obx(
      () => PlatformBottomBar(
        tabs: _tabs,
        currentIndex: controller.pageIndex.value,
        tint: const Color(AppConfig.cBottomBarActive),
        surface: const Color(AppConfig.cSurface),
        darkSurface: const Color(AppConfig.cDarkCardColor),
        isDark: isDark,
        heightIOS: 85,
        onTap: controller.changePage,
      ),
    );
  }
}
