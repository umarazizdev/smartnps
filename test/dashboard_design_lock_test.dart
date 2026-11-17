import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/new_screens/Dashboard/new_dashboard_controller.dart';
import 'package:smartnps360/src/screens/new_screens/Dashboard/new_dashboard_screen.dart';
import 'package:smartnps360/src/screens/new_screens/Dashboard/theme/dashboard_design_tokens.dart';
import 'package:smartnps360/src/screens/new_screens/new_models.dart';
import 'package:smartnps360/src/screens/new_screens/Widgets/new_app_header.dart';
import 'package:smartnps360/src/screens/new_screens/Widgets/new_bottom_bar.dart';
import 'package:smartnps360/src/screens/new_screens/new_main_controller.dart';

// Isolated visual fixtures: no storage, timers, authentication or API calls.
class DesignFixture extends NewDashboardController {
  final fixtureUnread = 3.obs;
  @override
  int get unreadNotifications => fixtureUnread.value;
  @override
  // Deliberately suppress production initialization in this isolated fixture.
  // ignore: must_call_super
  void onInit() {}
}

class FixtureShell extends StatelessWidget {
  const FixtureShell({super.key});
  @override
  Widget build(BuildContext context) {
    final design = DashboardDesign.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: design.pageGradient),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 154,
          child: ClipRect(
            child: SvgPicture.asset(design.headerAsset, fit: BoxFit.cover),
          ),
        ),
        Column(
          children: [
            NewAppHeader(onMenuTap: () {}),
            const Expanded(child: NewDashboardScreen()),
          ],
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: NewBottomBar(controller: Get.find<NewMainController>()),
        ),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('PTSans')
      ..addFont(rootBundle.load('assets/fonts/pt-sans_regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/pt-sans_bold.ttf'));
    await loader.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final dark in [false, true]) {
    for (final state in [
      'upcoming',
      'late',
      'working',
      'workingLate',
      'break',
      'standby',
      'empty',
    ]) {
      testWidgets('${dark ? 'dark' : 'light'} $state has no layout errors', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Get.testMode = true;
        final c = DesignFixture();
        c.isDarkMode.value = dark;
        c.scheduledShiftStart = DateTime(2026, 11, 16, 21);
        c.scheduledShiftEnd = DateTime(2026, 11, 17, 5);
        c.timerText.value = '02:15:30';
        if (state == 'upcoming') c.timerText.value = '00:45:00';
        if (state == 'late') c.timerText.value = '00:15:07';
        if (state == 'standby') c.timerText.value = 'Stand By';
        c.timerLabel.value = 'CURRENT SHIFT';
        c.officerName.value = 'Hamid';
        c.warningCountValue.value = '8';
        c.warningMetaText.value = '4 new · tap to review';
        c.warningHasUnread.value = true;
        c.onTimeMeta.value = 'No shifts in NOV';
        c.hasAssignedShift.value = state != 'empty';
        if (['working', 'workingLate', 'break'].contains(state)) {
          c.status.value = state == 'break'
              ? NewOfficerStatus.onBreak
              : NewOfficerStatus.onShift;
          c.liveStatusText.value = state == 'break' ? 'On Break' : 'On Duty';
          if (state == 'break') {
            c.timerText.value = '00:12:00';
            c.timerLabel.value = 'BREAK REMAINING';
          }
          c.dialLiveEnd.value = .28;
          c.dialWork1End.value = .24;
          c.dialBreakEnd.value = state == 'break' ? .28 : .24;
        } else {
          c.timerLabel.value = state == 'late' ? 'LATE BY' : 'STARTS IN';
        }
        c.lateStartedStyle.value = state == 'late';
        if (state == 'workingLate') {
          c.arrivalStatus.value = NewArrivalStatus.late;
          c.arrivalText.value = 'Arrived 15 min late';
        }
        Get.put<NewDashboardController>(c, permanent: true);
        Get.put(NewMainController());
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
              fontFamily: 'PTSans',
            ),
            home: Scaffold(
              body: RepaintBoundary(
                key: key,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: DashboardDesign(dark).pageGradient,
                  ),
                  child: const FixtureShell(),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(() async {
          for (final asset in [
            'assets/images/npslogo_navy_exact.png',
            'assets/images/header_menu_outline_v4.png',
            'assets/images/header_sun_outline.png',
            'assets/images/header_moon_outline_v5.png',
            'assets/images/header_bell_outline_v6.png',
            'assets/home-icon-silhouette.png',
            'assets/home-outline.png',
            'assets/user.png',
            'assets/user-outline.png',
          ]) {
            await precacheImage(AssetImage(asset), key.currentContext!);
          }
        });
        await tester.pump();
        if (state == 'empty') {
          await tester.runAsync(
            () => precacheImage(
              AssetImage(DashboardDesign(dark).emptyAsset),
              key.currentContext!,
            ),
          );
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final screenshot = await boundary.toImage();
          final bytes = await screenshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final output = File(
            'docs/dashboard_design_lock/screenshots/${dark ? 'dark' : 'light'}_$state.png',
          );
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(bytes!.buffer.asUint8List());
          screenshot.dispose();
        });
        // Large text and a narrow phone must remain scrollable without overflow.
        tester.view.physicalSize = const Size(320, 700);
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: MaterialApp(
              theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.4)),
                child: child!,
              ),
              home: const Scaffold(body: FixtureShell()),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        Get.reset();
      });
    }
  }
}
