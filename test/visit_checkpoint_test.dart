import 'package:flutter_test/flutter_test.dart';
import 'package:smartnps360/src/log_visit/flow/visit_checkpoint.dart';
import 'package:smartnps360/src/log_visit/flow/visit_patrol_context.dart';
import 'package:smartnps360/src/log_visit/flow/visit_video_flow_controller.dart';

void main() {
  test('VisitCheckpoint parses bridge aliases and sorts by sort_order', () {
    final list = VisitCheckpoint.listFromJson([
      {
        'id': 502,
        'name': 'Back Gate',
        'sort_order': 2,
        'latitude': 31.52,
        'longitude': 74.35,
        'radius_meters': 50,
      },
      {
        'site_checkpoint_id': 501,
        'name': 'Main Gate',
        'description': 'Photograph the lock',
        'photo_url': 'https://example.com/gate.jpg',
        'sort_order': 1,
        'is_active': true,
      },
      {
        'checkpoint_id': 503,
        'name': 'Inactive',
        'is_active': false,
      },
    ]);

    expect(list.length, 2);
    expect(list.first.id, 501);
    expect(list.first.name, 'Main Gate');
    expect(list.first.hasReferencePhoto, isTrue);
    expect(list.last.id, 502);
  });

  test('VisitPatrolContext from bridge payload includes window + checkpoints', () {
    final ctx = VisitPatrolContext.fromBridgePayload({
      'action': 'open_patrol_draft',
      'region_id': 7,
      'site_id': 123,
      'region_name': 'Lahore North',
      'site_name': 'Gate A',
      'site_patrol_window_id': 44,
      'schedule_id': null,
      'api_upload_url': 'https://example.com/api/visits',
      'checkpoints': [
        {
          'site_checkpoint_id': 501,
          'name': 'Main Gate',
          'sort_order': 1,
        },
      ],
      'site': {'id': 123, 'name': 'Gate A', 'latitude': 31.5, 'longitude': 74.3},
      'region': {'id': 7, 'name': 'Lahore North'},
    });

    expect(ctx, isNotNull);
    expect(ctx!.siteId, 123);
    expect(ctx.regionId, 7);
    expect(ctx.sitePatrolWindowId, 44);
    expect(ctx.siteLatitude, 31.5);
    expect(ctx.uploadUrl, 'https://example.com/api/visits');
    expect(ctx.checkpoints.length, 1);
    expect(ctx.toUploadMetaFields()['site_patrol_window_id'], 44);
  });

  test('buildUploadMeta includes completed checkpoints with photo_client_index', () async {
    final flow = VisitVideoFlowController();
    flow.patrolContext.value = const VisitPatrolContext(
      clientDraftId: 'draft-1',
      regionId: 7,
      siteId: 123,
      regionName: 'Lahore North',
      siteName: 'Gate A',
      sitePatrolWindowId: 44,
      checkpoints: [
        VisitCheckpoint(id: 501, name: 'Main Gate', latitude: 31.52, longitude: 74.35),
      ],
    );
    flow.mediaItems
      ..clear()
      ..addAll([
      VisitMediaItem(
        path: '/tmp/photo0.jpg',
        type: VisitMediaType.photo,
        textNote: 'Gate secure',
        capturedAt: DateTime.utc(2026, 8, 2, 8, 10),
        latitude: 31.52051,
        longitude: 74.35891,
        accuracyMeters: 6,
        siteCheckpointId: 501,
      ),
      VisitMediaItem(
        path: '/tmp/extra.jpg',
        type: VisitMediaType.photo,
        capturedAt: DateTime.utc(2026, 8, 2, 8, 12),
        latitude: 31.52,
        longitude: 74.35,
      ),
    ]);

    final meta = flow.buildUploadMeta(
      submittedAt: DateTime.utc(2026, 8, 2, 8, 15),
    );

    expect(meta['site_patrol_window_id'], 44);
    expect(meta['items'], hasLength(2));
    expect(meta['checkpoints'], hasLength(1));
    final checkpoint = (meta['checkpoints'] as List).first as Map;
    expect(checkpoint['site_checkpoint_id'], 501);
    expect(checkpoint['status'], 'completed');
    expect(checkpoint['photo_client_index'], 0);
    expect(checkpoint['notes'], 'Gate secure');
    expect(flow.isCheckpointCompleted(501), isTrue);
    expect(flow.additionalMediaItems, hasLength(1));
  });

  test('resolves relative photo_path against upload origin', () {
    final checkpoint = VisitCheckpoint.fromJson(
      {
        'site_checkpoint_id': 501,
        'name': 'Main Gate',
        'photo_path': 'checkpoints/main-gate.jpg',
      },
      baseUrl: 'https://smartnps360.com/api/visits',
    );

    expect(
      checkpoint!.photoUrl,
      'https://smartnps360.com/storage/checkpoints/main-gate.jpg',
    );
    expect(checkpoint.hasReferencePhoto, isTrue);
  });
}
