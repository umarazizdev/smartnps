import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartnps360/src/dispatch/dispatch_request_screen.dart';
import 'package:smartnps360/src/widgets/sheets/app_bottom_sheet_motion.dart';

void main() {
  Widget app({ThemeMode themeMode = ThemeMode.light, int seconds = 30}) {
    return MaterialApp(
      themeMode: themeMode,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: DispatchRequestScreen(
        request: DispatchRequestData(
          address: 'Horizon Plaza',
          city: '',
          summary: 'Suspicious person near the parking entrance.',
          score: 97,
          arrivalMinutes: 9,
          distanceMiles: 1.8,
          siteLatitude: 28.477741852243042,
          siteLongitude: 70.40424054232736,
          responseSeconds: seconds,
        ),
      ),
    );
  }

  testWidgets('shows dispatch details without layout errors', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pump(AppBottomSheetMotion.openDuration);

    expect(find.text('Response requested'), findsOneWidget);
    expect(
      find.textContaining('Horizon Plaza', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Accept response'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('countdown is visible during entrance animation', (tester) async {
    await tester.pumpWidget(app(seconds: 30));
    expect(find.text('00:30'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('00:'), findsWidgets);
  });

  testWidgets('shows missed response dialog when timer expires', (
    tester,
  ) async {
    await tester.pumpWidget(app(themeMode: ThemeMode.dark, seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(AppBottomSheetMotion.openDuration);

    expect(find.text('You missed a dispatch request'), findsOneWidget);
    expect(find.text('Accept response'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
