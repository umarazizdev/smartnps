import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:smartnps360/src/log_visit/flow/visit_checkpoint.dart';
import 'package:smartnps360/src/log_visit/flow/visit_media_draft_store.dart';
import 'package:smartnps360/src/log_visit/flow/visit_patrol_context.dart';
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
  group('VisitPatrolContext.overlayFromBridge', () {
    const baseline = VisitPatrolContext(
      clientDraftId: 'draft-1',
      regionId: 7,
      siteId: 11,
      regionName: 'Old Region',
      siteName: 'Old Site',
      scheduleId: 100,
      uploadUrl: 'https://example.com/old',
      checkpoints: [
        VisitCheckpoint(id: 1, name: 'Gate'),
        VisitCheckpoint(id: 2, name: 'Lobby'),
        VisitCheckpoint(id: 3, name: 'Roof'),
      ],
    );

    test('adds checkpoints when payload sends a longer list', () {
      final incoming = VisitPatrolContext.fromBridgePayload({
        'region_id': 7,
        'site_id': 11,
        'site_name': 'Old Site',
        'checkpoints': [
          {'site_checkpoint_id': 1, 'name': 'Gate'},
          {'site_checkpoint_id': 2, 'name': 'Lobby'},
          {'site_checkpoint_id': 3, 'name': 'Roof'},
          {'site_checkpoint_id': 4, 'name': 'Parking'},
          {'site_checkpoint_id': 5, 'name': 'Dock'},
        ],
      })!;

      final merged = VisitPatrolContext.overlayFromBridge(
        baseline: baseline,
        incoming: incoming,
        payload: {
          'region_id': 7,
          'site_id': 11,
          'checkpoints': incoming.checkpoints.map((e) => e.toJson()).toList(),
        },
        sameSite: true,
      );

      expect(merged.checkpoints.map((e) => e.id), [1, 2, 3, 4, 5]);
      expect(merged.siteName, 'Old Site');
    });

    test('removes checkpoints when payload sends a shorter list', () {
      final payload = <String, dynamic>{
        'region_id': 7,
        'site_id': 11,
        'checkpoints': [
          {'site_checkpoint_id': 1, 'name': 'Gate'},
          {'site_checkpoint_id': 3, 'name': 'Roof'},
        ],
      };
      final incoming = VisitPatrolContext.fromBridgePayload(payload)!;

      final merged = VisitPatrolContext.overlayFromBridge(
        baseline: baseline,
        incoming: incoming,
        payload: payload,
        sameSite: true,
      );

      expect(merged.checkpoints.map((e) => e.id), [1, 3]);
    });

    test('clears checkpoints when payload sends an explicit empty list', () {
      final payload = <String, dynamic>{
        'region_id': 7,
        'site_id': 11,
        'checkpoints': <Map<String, dynamic>>[],
      };
      final incoming = VisitPatrolContext.fromBridgePayload(payload)!;

      final merged = VisitPatrolContext.overlayFromBridge(
        baseline: baseline,
        incoming: incoming,
        payload: payload,
        sameSite: true,
      );

      expect(merged.checkpoints, isEmpty);
    });

    test('clears checkpoints when payload omits the key', () {
      final payload = <String, dynamic>{
        'region_id': 7,
        'site_id': 11,
        'site_name': 'Renamed Site',
      };
      final incoming = VisitPatrolContext.fromBridgePayload(payload)!;

      final merged = VisitPatrolContext.overlayFromBridge(
        baseline: baseline,
        incoming: incoming,
        payload: payload,
        sameSite: true,
      );

      expect(merged.checkpoints, isEmpty);
      expect(merged.siteName, 'Renamed Site');
      expect(merged.regionName, 'Old Region');
    });

    test('updates scalar context from payload while same-site', () {
      final payload = <String, dynamic>{
        'region_id': 7,
        'site_id': 11,
        'site_name': 'New Site',
        'region_name': 'New Region',
        'upload_url': 'https://example.com/new',
        'minimum_photos': 4,
        'checkpoints': [
          {'site_checkpoint_id': 1, 'name': 'Gate'},
          {'site_checkpoint_id': 2, 'name': 'Lobby'},
          {'site_checkpoint_id': 3, 'name': 'Roof'},
        ],
      };
      final incoming = VisitPatrolContext.fromBridgePayload(payload)!;

      final merged = VisitPatrolContext.overlayFromBridge(
        baseline: baseline,
        incoming: incoming,
        payload: payload,
        sameSite: true,
      );

      expect(merged.siteName, 'New Site');
      expect(merged.regionName, 'New Region');
      expect(merged.uploadUrl, 'https://example.com/new');
      expect(merged.minimumPhotos, 4);
      expect(merged.checkpoints.length, 3);
    });

    test('does not keep baseline checkpoints when switching sites', () {
      final payload = <String, dynamic>{
        'region_id': 7,
        'site_id': 99,
        'site_name': 'Other Site',
      };
      final incoming = VisitPatrolContext.fromBridgePayload(payload)!;

      final merged = VisitPatrolContext.overlayFromBridge(
        baseline: baseline,
        incoming: incoming,
        payload: payload,
        sameSite: false,
      );

      expect(merged.siteId, 99);
      expect(merged.siteName, 'Other Site');
      expect(merged.checkpoints, isEmpty);
      expect(merged.scheduleId, isNull);
    });
  });

  group('VisitVideoFlowController.applyBridgePatrolContext', () {
    late Directory tempRoot;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempRoot = await Directory.systemTemp.createTemp('nps_bridge_overlay_');
      PathProviderPlatform.instance = _FakePathProvider(tempRoot);
      VisitMediaDraftStore.instance.debugResetForTest();
      VisitUploadQueue.instance.debugResetForTest();
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('reopen overlays payload onto existing draft without user edits',
        () async {
      final flow = VisitVideoFlowController();
      flow.isDraftReady.value = true;

      await flow.applyBridgePatrolContext({
        'region_id': 7,
        'site_id': 11,
        'site_name': 'Gate A',
        'region_name': 'North',
        'checkpoints': [
          {'site_checkpoint_id': 1, 'name': 'Gate'},
          {'site_checkpoint_id': 2, 'name': 'Lobby'},
        ],
      });
      expect(flow.checkpoints.map((e) => e.id), [1, 2]);
      expect(flow.draftSiteName.value, 'Gate A');

      await flow.applyBridgePatrolContext({
        'region_id': 7,
        'site_id': 11,
        'site_name': 'Gate A West',
        'region_name': 'North',
        'checkpoints': [
          {'site_checkpoint_id': 1, 'name': 'Gate'},
          {'site_checkpoint_id': 2, 'name': 'Lobby'},
          {'site_checkpoint_id': 3, 'name': 'Roof'},
        ],
      });
      expect(flow.checkpoints.map((e) => e.id), [1, 2, 3]);
      expect(flow.patrolContext.value?.siteName, 'Gate A West');
      expect(flow.draftSiteName.value, 'Gate A West');

      await flow.applyBridgePatrolContext({
        'region_id': 7,
        'site_id': 11,
        'site_name': 'Gate A West',
        'checkpoints': [
          {'site_checkpoint_id': 1, 'name': 'Gate'},
          {'site_checkpoint_id': 3, 'name': 'Roof'},
        ],
      });
      expect(flow.checkpoints.map((e) => e.id), [1, 3]);

      await flow.applyBridgePatrolContext({
        'region_id': 7,
        'site_id': 11,
        'checkpoints': <Map<String, dynamic>>[],
      });
      expect(flow.checkpoints, isEmpty);

      await flow.applyBridgePatrolContext({
        'region_id': 7,
        'site_id': 11,
        'site_name': 'Gate A West',
        'checkpoints': [
          {'site_checkpoint_id': 1, 'name': 'Gate'},
          {'site_checkpoint_id': 2, 'name': 'Lobby'},
        ],
      });
      expect(flow.checkpoints.map((e) => e.id), [1, 2]);

      await flow.applyBridgePatrolContext({
        'region_id': 7,
        'site_id': 11,
        'site_name': 'Gate A West',
      });
      expect(flow.checkpoints, isEmpty);
      expect(flow.patrolContext.value?.siteName, 'Gate A West');
    });
  });
}
