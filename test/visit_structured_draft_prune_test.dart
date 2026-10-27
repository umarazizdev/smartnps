import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:smartnps360/src/log_visit/flow/visit_flow_kind.dart';
import 'package:smartnps360/src/log_visit/flow/visit_media_draft_store.dart';
import 'package:smartnps360/src/log_visit/flow/visit_patrol_context.dart';
import 'package:smartnps360/src/log_visit/flow/visit_report_details.dart';
import 'package:smartnps360/src/log_visit/flow/visit_upload_queue.dart';
import 'package:smartnps360/src/log_visit/flow/visit_video_flow_controller.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
}

void main() {
  late Directory tempRoot;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempRoot = await Directory.systemTemp.createTemp('nps_structured_draft_');
    PathProviderPlatform.instance = _FakePathProvider(tempRoot);
    VisitMediaDraftStore.instance.debugResetForTest();
    VisitUploadQueue.instance.debugResetForTest();
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('report context alone is not resume content', () {
    const snapshot = VisitMediaDraftSnapshot(
      items: [],
      draftKey: VisitDraftKey(
        regionId: 1,
        siteId: 2,
        flowKind: VisitFlowKind.issueReport,
      ),
      context: VisitPatrolContext(
        regionId: 1,
        siteId: 2,
        visitType: VisitFlowKind.issueReportVisitType,
        reportContextId: 'ctx-only',
        siteName: 'Bilal Dairy Farm',
        regionName: 'TESTING REGION',
      ),
      reportDetails: VisitReportDetails(category: 'Suspicious Activity'),
    );

    expect(snapshot.hasResumeContent, isFalse);
  });

  test('officer form input makes structured draft resumable', () {
    const snapshot = VisitMediaDraftSnapshot(
      items: [],
      draftKey: VisitDraftKey(
        regionId: 1,
        siteId: 2,
        flowKind: VisitFlowKind.issueReport,
      ),
      context: VisitPatrolContext(
        regionId: 1,
        siteId: 2,
        visitType: VisitFlowKind.issueReportVisitType,
        reportContextId: 'ctx-with-title',
      ),
      reportDetails: VisitReportDetails(
        title: 'Broken gate',
        category: 'Suspicious Activity',
      ),
    );

    expect(snapshot.hasResumeContent, isTrue);
  });

  test('open/close with report context and no officer input leaves no draft',
      () async {
    final flow = VisitVideoFlowController();
    flow.isDraftReady.value = true;

    final reopened = await flow.applyBridgePatrolContext({
      'region_id': 42,
      'site_id': 659,
      'site_name': 'Bilal Dairy Farm',
      'region_name': 'TESTING REGION',
      'visit_type': VisitFlowKind.issueReportVisitType,
      'report_context_id': 'issued-on-open',
    });
    expect(reopened, isFalse);
    expect(flow.patrolContext.value?.hasReportContext, isTrue);
    expect(flow.reportDetails.value.hasUserContent, isFalse);

    await flow.persistCurrentDraft();

    final pending = await VisitMediaDraftStore.instance.listPendingDrafts();
    expect(pending, isEmpty);
    expect(
      await VisitMediaDraftStore.instance.hasDraft(
        key: VisitDraftKey(
          regionId: 42,
          siteId: 659,
          flowKind: VisitFlowKind.issueReport,
        ),
      ),
      isFalse,
    );
  });

  test('saving officer input keeps structured draft after close persist',
      () async {
    final flow = VisitVideoFlowController();
    flow.isDraftReady.value = true;

    await flow.applyBridgePatrolContext({
      'region_id': 42,
      'site_id': 659,
      'site_name': 'Bilal Dairy Farm',
      'region_name': 'TESTING REGION',
      'visit_type': VisitFlowKind.issueReportVisitType,
      'report_context_id': 'issued-on-open',
    });

    await flow.updateReportDetails(
      const VisitReportDetails(
        title: 'Gate issue',
        category: 'Suspicious Activity',
        details: 'Latch broken',
      ),
    );

    final pending = await VisitMediaDraftStore.instance.listPendingDrafts();
    expect(pending, hasLength(1));
    expect(pending.first.reportDetails.title, 'Gate issue');
    expect(pending.first.hasResumeContent, isTrue);
  });

  test('clearing officer input removes structured draft', () async {
    final flow = VisitVideoFlowController();
    flow.isDraftReady.value = true;

    await flow.applyBridgePatrolContext({
      'region_id': 42,
      'site_id': 659,
      'visit_type': VisitFlowKind.issueReportVisitType,
      'report_context_id': 'issued-on-open',
    });

    await flow.updateReportDetails(
      const VisitReportDetails(
        title: 'Gate issue',
        category: 'Suspicious Activity',
      ),
    );
    expect(await VisitMediaDraftStore.instance.listPendingDrafts(), hasLength(1));

    await flow.updateReportDetails(
      VisitReportDetails.defaultsFor(VisitFlowKind.issueReport),
    );

    expect(await VisitMediaDraftStore.instance.listPendingDrafts(), isEmpty);
    expect(flow.patrolContext.value?.hasReportContext, isTrue);
  });
}
