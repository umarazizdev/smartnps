import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartnps360/src/widgets/sheets/app_bottom_sheet_motion.dart';

void main() {
  test('exposes iOS-style open and close motion values', () {
    expect(
      AppBottomSheetMotion.openDuration,
      const Duration(milliseconds: 350),
    );
    expect(
      AppBottomSheetMotion.closeDuration,
      const Duration(milliseconds: 250),
    );
    expect(AppBottomSheetMotion.openCurve, Curves.easeOutCubic);
    expect(AppBottomSheetMotion.closeCurve, Curves.easeInCubic);
    expect(AppBottomSheetMotion.scrimMaxOpacity, 0.45);
    expect(
      AppBottomSheetMotion.animationStyle.duration,
      AppBottomSheetMotion.openDuration,
    );
    expect(
      AppBottomSheetMotion.animationStyle.reverseDuration,
      AppBottomSheetMotion.closeDuration,
    );
  });

  testWidgets('disables modal animation when reduced motion is on', (
    tester,
  ) async {
    late AnimationStyle style;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            style = AppBottomSheetMotion.animationStyleFor(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(style.duration, Duration.zero);
    expect(style.reverseDuration, Duration.zero);
  });

  testWidgets('embedded sheet slides up without delaying child build', (
    tester,
  ) async {
    var built = false;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppEmbeddedBottomSheetFrame(
            child: SizedBox(height: 120, child: Text('Sheet body')),
          ),
        ),
      ),
    );
    built = tester.any(find.text('Sheet body'));
    expect(built, isTrue);
    await tester.pump(AppBottomSheetMotion.openDuration);
    expect(find.text('Sheet body'), findsOneWidget);
  });
}
