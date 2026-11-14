import 'dart:ui';
import 'package:cupertino_native/cupertino_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/controllers/connectivitycontroller.dart';
import 'package:smartnps360/src/screens/main_screens/main_controller.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/widgets/nointernetscreen.dart';

class _BottomTabData {
  const _BottomTabData({
    required this.symbolName,
    required this.activeIcon,
    required this.inactiveIcon,
    required this.label,
    required this.index,
  });

  final String symbolName;
  final String activeIcon;
  final String inactiveIcon;
  final String label;
  final int index;
}

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  static const List<_BottomTabData> _tabs = [
    _BottomTabData(
      symbolName: 'house.fill',
      activeIcon: 'assets/Icons/postFil.png',
      inactiveIcon: 'assets/Icons/postFilFill.png',
      label: 'Dashboard',
      index: 0,
    ),
    _BottomTabData(
      symbolName: 'calendar',
      activeIcon: 'assets/Icons/schedule.png',
      inactiveIcon: 'assets/Icons/calendar_outline.png',
      label: 'TimeSheet',
      index: 1,
    ),
    _BottomTabData(
      symbolName: 'doc.text.image.fill',
      activeIcon: 'assets/Icons/reports_outline.png',
      inactiveIcon: 'assets/Icons/reports.png',
      label: 'DAR',
      index: 2,
    ),
    // _BottomTabData(
    //   symbolName: 'questionmark.circle.fill',
    //   activeIcon: 'assets/Icons/help.png',
    //   inactiveIcon: 'assets/Icons/help_outline.png',
    //   label: 'Help',
    //   index: 3,
    // ),
    _BottomTabData(
      symbolName: 'person.crop.circle.fill',
      activeIcon: 'assets/Icons/profile.png',
      inactiveIcon: 'assets/Icons/avatar.png',
      label: 'Profile',
      index: 4,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(MainController());
    final connectivityController = Get.find<ConnectivityController>();

    return Obx(() {
      // Show no internet screen if not connected
      if (!connectivityController.isConnected.value) {
        return NoInternetScreen(
          onRetry: () async {
            await connectivityController.checkConnection();
          },
        );
      }

      // Show main screen with bottom navigation
      return Scaffold(
        extendBody: true,
        // floatingActionButton: controller.isBottomBarVisible.value
        //     ? _FrostedHelpFab(
        //         onTap: () => Get.to(() => const HelpScreen(showBack: true)),
        //       )
        //     : null,
        // floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        body: Stack(
          children: [
            Positioned.fill(
              child: controller.pages[controller.pageIndex.value],
            ),
            if (controller.isBottomBarVisible.value)
              Align(
                alignment: Alignment.bottomCenter,
                child: _buildMyNavBar(context, controller),
              ),
          ],
        ),
      );
    });
  }

  Widget _buildMyNavBar(BuildContext context, MainController controller) {
    final isApplePlatform =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    return isApplePlatform
        ? _buildNativeNavBar(context, controller)
        : _buildClassicNavBar(context, controller);
  }

  // iOS / macOS native bottom bar is untouched.
  Widget _buildNativeNavBar(BuildContext context, MainController controller) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final selectedTabPosition = _tabs.indexWhere(
      (tab) => tab.index == controller.pageIndex.value,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomInset > 0 ? 6 : 10),
      child: CNTabBar(
        items: _tabs
            .map(
              (tab) => CNTabBarItem(
                label: tab.label,
                icon: CNSymbol(tab.symbolName),
              ),
            )
            .toList(),
        currentIndex: selectedTabPosition >= 0 ? selectedTabPosition : 0,
        tint: cPrimary,
        height: 85,
        onTap: (tabPosition) => controller.changePage(_tabs[tabPosition].index),
      ),
    );
  }

  // Android / classic bottom bar only updated.
  Widget _buildClassicNavBar(BuildContext context, MainController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        0,
        18,
        bottomInset > 0 ? bottomInset + 6 : 10,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            height: 74,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: isDark
                  ? cDarkCardColor.withAlpha(230)
                  : Colors.white.withAlpha(246),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isDark
                    ? cDarkBorderColor.withAlpha(115)
                    : const Color(0xFFE5EAF1),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 85 : 18),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: _tabs.map((tab) {
                final isActive = controller.pageIndex.value == tab.index;
                final activeColor = cPrimary;
                final inactiveColor = isDark
                    ? Colors.white.withAlpha(145)
                    : const Color(0xFF8B93A3);

                return Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    overlayColor: const WidgetStatePropertyAll(cTransparent),
                    onTap: () => controller.changePage(tab.index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 190),
                      curve: Curves.easeOutCubic,
                      height: 58,
                      decoration: BoxDecoration(
                        color: isActive
                            ? cPrimary.withAlpha(isDark ? 32 : 18)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedScale(
                            scale: isActive ? 1.04 : 1,
                            duration: const Duration(milliseconds: 170),
                            child: Image.asset(
                              isActive ? tab.activeIcon : tab.inactiveIcon,
                              color: isActive ? activeColor : inactiveColor,
                              height: isActive ? 24 : 23,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tab.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: isActive ? activeColor : inactiveColor,
                                  fontSize: 11,
                                  fontWeight: isActive
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  height: 1,
                                  letterSpacing: -0.1,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
