import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smartnps360/src/dispatch/dispatch_request_controller.dart';
import 'package:smartnps360/src/dispatch/dispatch_request_data.dart';
import 'package:smartnps360/src/dispatch/dispatch_request_screen.dart';
import 'package:smartnps360/src/dispatch/dispatch_response_panel.dart';
import 'package:smartnps360/src/dispatch/dispatch_route_map.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await Get.deleteAll(force: true);
  });

  Widget harness({
    ThemeMode themeMode = ThemeMode.light,
    int seconds = 30,
  }) {
    return GetMaterialApp(
      themeMode: themeMode,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: DispatchRequestScreen(
        request: DispatchRequestData(
          address: 'Horizon Plaza',
          city: 'Bahawalpur',
          summary:
              'Suspicious person near the parking entrance. Check the area and report your findings to dispatch.',
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

  Future<void> settlePreview(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('vivo dispatch preview layout stays on screen', (tester) async {
    await tester.pumpWidget(harness());
    await settlePreview(tester);

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (final label in [
      'Accept response',
      'Decline',
      'Incident Summary',
      'Route to the site',
      'Response requested',
      'Estimated arrival',
      'Distance to site',
    ]) {
      final finder = find.text(label);
      expect(finder, findsOneWidget, reason: label);
      final rect = tester.getRect(finder);
      expect(rect.left, greaterThanOrEqualTo(-1));
      expect(rect.right, lessThanOrEqualTo(screen.width + 1));
      expect(rect.bottom, lessThanOrEqualTo(screen.height + 1));
    }

    expect(find.byType(DispatchRouteMap), findsOneWidget);
    expect(
      find.textContaining('Horizon Plaza', findRichText: true),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('vivo decline validates then submits text reason', (tester) async {
    await tester.pumpWidget(harness());
    await settlePreview(tester);

    await tester.ensureVisible(find.text('Decline'));
    await tester.tap(find.text('Decline'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('DECLINE DISPATCH REQUEST'), findsOneWidget);
    expect(find.text('Why are you declining?'), findsOneWidget);
    expect(find.text('Confirm decline'), findsOneWidget);
    expect(find.text('Text note'), findsOneWidget);
    expect(find.text('Voice note'), findsOneWidget);

    await tester.tap(find.text('Confirm decline'));
    await tester.pump();
    expect(
      find.text('Please add a text note or record a voice note.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byType(TextField),
      'I cannot leave my current site.',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(
      find.text('Please add a text note or record a voice note.'),
      findsNothing,
    );

    await tester.tap(find.text('Confirm decline'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Decline reason submitted to dispatch.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vivo expire sheet appears after countdown', (tester) async {
    await tester.pumpWidget(harness(themeMode: ThemeMode.dark, seconds: 2));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('You missed a dispatch request'), findsOneWidget);
    expect(find.text('Accept response'), findsNothing);
    expect(find.text('Submit explanation to dispatch'), findsOneWidget);

    await tester.tap(find.text('Submit explanation to dispatch'));
    await tester.pump();
    expect(
      find.text('Please add a text note or record a voice note.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byType(TextField),
      'I was assisting another officer.',
    );
    await tester.tap(find.text('Submit explanation to dispatch'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Explanation submitted to dispatch.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vivo accept marks request accepted in GetX controller', (
    tester,
  ) async {
    await tester.pumpWidget(harness(seconds: 25));
    await settlePreview(tester);

    expect(
      Get.isRegistered<DispatchRequestController>(
        tag: DispatchRequestController.tag,
      ),
      isTrue,
    );
    final controller = Get.find<DispatchRequestController>(
      tag: DispatchRequestController.tag,
    );
    expect(controller.accepted.value, isFalse);
    expect(controller.declining.value, isFalse);

    await tester.ensureVisible(find.text('Accept response'));
    await tester.tap(find.text('Accept response'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(controller.accepted.value, isTrue);
    expect(controller.openingNavigation.value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vivo expand opens fullscreen map with response actions', (
    tester,
  ) async {
    await tester.pumpWidget(harness(seconds: 28));
    await settlePreview(tester);

    final expand = find.byTooltip('Open full map');
    expect(expand, findsOneWidget);
    await tester.tap(expand);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(DispatchResponsePanel), findsWidgets);
    expect(find.text('Accept response'), findsWidgets);
    expect(find.text('Decline'), findsWidgets);
    expect(tester.takeException(), isNull);

    final close = find.byTooltip('Close map');
    if (close.evaluate().isNotEmpty) {
      await tester.tap(close);
      await tester.pump(const Duration(milliseconds: 500));
    } else {
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
      navigator.pop();
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(find.byTooltip('Open full map'), findsOneWidget);

    final controller = Get.find<DispatchRequestController>(
      tag: DispatchRequestController.tag,
    );
    await controller.decline();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Why are you declining?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
