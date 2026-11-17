import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'Dashboard/theme/dashboard_design_tokens.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/controllers/connectivitycontroller.dart';
import 'package:smartnps360/src/screens/widgets/nointernetscreen.dart';
import 'Dashboard/new_dashboard_controller.dart';
import 'Widgets/new_app_header.dart';
import 'Widgets/new_bottom_bar.dart';
import 'Widgets/new_side_menu.dart';
import 'new_main_controller.dart';

class NewMainScreen extends StatelessWidget {
  const NewMainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(NewMainController());
    final dashboardController = Get.put(
      NewDashboardController(),
      permanent: true,
    );
    Future.microtask(dashboardController.healShortcuts);
    final connectivityController = Get.isRegistered<ConnectivityController>()
        ? Get.find<ConnectivityController>()
        : null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Obx(() {
        if (connectivityController != null &&
            !connectivityController.isConnected.value) {
          return NoInternetScreen(
            onRetry: () async => connectivityController.checkConnection(),
          );
        }

        return Scaffold(
          extendBody: true,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: DashboardDesign.of(context).pageGradient,
                  ),
                ),
              ),
              if (controller.pageIndex.value == 0 &&
                  controller.isAppHeaderVisible.value)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height:
                      DashboardMetrics.headerArtworkHeight +
                      MediaQuery.paddingOf(context).top,
                  child: ClipRect(
                    child: SvgPicture.asset(
                      DashboardDesign.of(context).headerAsset,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              Positioned.fill(
                child: Column(
                  children: [
                    if (controller.isAppHeaderVisible.value)
                      NewAppHeader(onMenuTap: dashboardController.openSideMenu),
                    Expanded(
                      child: controller.pages[controller.pageIndex.value],
                    ),
                  ],
                ),
              ),
              Obx(
                () => NewSideMenu(
                  open: dashboardController.sideMenuOpen.value,
                  onClose: dashboardController.closeSideMenu,
                ),
              ),
              Obx(
                () => controller.isBottomBarVisible.value
                    ? Align(
                        alignment: Alignment.bottomCenter,
                        child: NewBottomBar(controller: controller),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      }),
    );
  }
}
