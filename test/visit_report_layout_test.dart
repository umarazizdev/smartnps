import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartnps360/src/log_visit/flow/visit_flow_kind.dart';
import 'package:smartnps360/src/log_visit/flow/visit_patrol_context.dart';
import 'package:smartnps360/src/log_visit/flow/visit_report_details.dart';
import 'package:smartnps360/src/log_visit/flow/visit_video_flow_controller.dart';
import 'package:smartnps360/src/log_visit/preview/visit_report_details_panel.dart';

class _PreviewFlow extends VisitVideoFlowController {
  @override
  Future<void> updateReportDetails(VisitReportDetails details) async {
    reportDetails.value = details;
  }
}

void main() {
  for (final kind in [
    VisitFlowKind.issueReport,
    VisitFlowKind.incidentReport,
  ]) {
    for (final dark in [false, true]) {
      testWidgets('${kind.name}: narrow layout with large text, dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final flow = _PreviewFlow();
        flow.patrolContext.value = VisitPatrolContext(
          regionId: 1,
          siteId: 1,
          visitType: kind.visitTypeValue,
        );
        flow.reportDetails.value = VisitReportDetails.defaultsFor(kind);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: VisitReportDetailsPanel(flow: flow, isDark: dark),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.enterText(find.byType(TextField).first, 'Gate inspection');
        await tester.pump();
        expect(flow.reportDetails.value.title, 'Gate inspection');
        final propertySwitch = find.byType(Switch).at(1);
        await tester.ensureVisible(propertySwitch);
        await tester.pumpAndSettle();
        await tester.tap(propertySwitch);
        await tester.pump();
        expect(flow.reportDetails.value.attentionToPropertyManagement, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
