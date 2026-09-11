import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:smartnps360/src/api/visit_upload_api.dart';
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

class _FakeConnectivity extends Fake implements Connectivity {
  _FakeConnectivity(this.results);

  List<ConnectivityResult> results;
  final _controller =
      StreamControllerBridge<List<ConnectivityResult>>();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => results;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  void emit(List<ConnectivityResult> next) {
    results = next;
    _controller.add(next);
  }

  Future<void> dispose() => _controller.close();
}

class StreamControllerBridge<T> {
  final _inner = StreamController<T>.broadcast();

  Stream<T> get stream => _inner.stream;

  void add(T value) => _inner.add(value);

  Future<void> close() => _inner.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VisitUploadResult.isNetworkDioException', () {
    test('marks connection errors as network failures', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/visits'),
        type: DioExceptionType.connectionError,
        error: const SocketException('Failed host lookup'),
      );
      expect(VisitUploadResult.isNetworkDioException(error), isTrue);
    });

    test('marks timeouts as network failures', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/visits'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(VisitUploadResult.isNetworkDioException(error), isTrue);
    });

    test('does not mark bad responses as network failures', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/visits'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/visits'),
          statusCode: 422,
        ),
      );
      expect(VisitUploadResult.isNetworkDioException(error), isFalse);
    });
  });

  group('VisitUploadQueue', () {
    late Directory tempRoot;
    late _FakeConnectivity connectivity;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('nps_upload_queue_');
      PathProviderPlatform.instance = _FakePathProvider(tempRoot);
      VisitMediaDraftStore.instance.debugResetForTest();
      connectivity = _FakeConnectivity(const [ConnectivityResult.none]);
    });

    tearDown(() async {
      await connectivity.dispose();
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    Future<VisitDraftKey> _seedDraft() async {
      final key = const VisitDraftKey(regionId: 7, siteId: 11);
      final photos = Directory('${tempRoot.path}/photos')
        ..createSync(recursive: true);
      final mediaPath = '${photos.path}/shot.jpg';
      await File(mediaPath).writeAsBytes(List<int>.filled(32, 1));

      await VisitMediaDraftStore.instance.saveDraft(
        [
          VisitMediaItem(
            path: mediaPath,
            type: VisitMediaType.photo,
            capturedAt: DateTime.utc(2026, 9, 8, 1, 0),
            latitude: 1.1,
            longitude: 2.2,
          ),
        ],
        key: key,
        context: const VisitPatrolContext(
          regionId: 7,
          siteId: 11,
          siteName: 'Gate A',
          clientDraftId: 'draft-test-1',
        ),
        siteName: 'Gate A',
        startedAt: DateTime.utc(2026, 9, 8, 1, 0),
      );
      return key;
    }

    test('keeps offline failures queued and uploads when online', () async {
      final key = await _seedDraft();
      var attempts = 0;
      final queue = VisitUploadQueue.forTest(
        connectivity: connectivity,
        uploadRunner: (snapshot) async {
          attempts++;
          if (attempts == 1) {
            return const VisitUploadResult(
              success: false,
              isNetworkFailure: true,
              message: 'offline',
            );
          }
          return const VisitUploadResult(success: true, visitId: 99);
        },
      );

      await queue.enqueue(key);
      expect(queue.isQueued(key), isTrue);
      expect(attempts, 0);

      await queue.processPending();
      expect(queue.isQueued(key), isTrue);
      expect(attempts, 0);

      connectivity.emit(const [ConnectivityResult.wifi]);
      await queue.processPending();

      expect(attempts, 1);
      expect(queue.isQueued(key), isTrue);

      await queue.processPending();
      expect(attempts, 2);
      expect(queue.isQueued(key), isFalse);

      final remaining = await VisitMediaDraftStore.instance.loadDraftSnapshot(
        key: key,
      );
      expect(remaining.hasItems, isFalse);
    });

    test('removes from queue and reports non-network failures', () async {
      final key = await _seedDraft();
      VisitDraftKey? failedKey;
      connectivity.results = const [ConnectivityResult.mobile];

      final queue = VisitUploadQueue.forTest(
        connectivity: connectivity,
        uploadRunner: (_) async {
          return const VisitUploadResult(
            success: false,
            statusCode: 422,
            message: 'Outside site geofence',
            errors: {
              'items.0.latitude': ['outside_site_geofence'],
            },
          );
        },
      );
      queue.onNonNetworkFailure =
          ({
            required draftKey,
            required presentation,
            required snapshot,
          }) async {
            failedKey = draftKey;
          };

      await queue.enqueue(key);
      await queue.processPending();

      expect(queue.isQueued(key), isFalse);
      expect(failedKey, key);
      final remaining = await VisitMediaDraftStore.instance.loadDraftSnapshot(
        key: key,
      );
      expect(remaining.hasItems, isTrue);
      expect(remaining.lastUploadIssue, isNotNull);
      expect(remaining.lastUploadIssue!.title, 'Outside site geofence');

      final editable = await queue.listEditablePendingDrafts();
      expect(editable.any((e) => e.draftKey == key), isTrue);
      expect(
        editable.firstWhere((e) => e.draftKey == key).lastUploadIssue?.title,
        'Outside site geofence',
      );
    });

    test('hides queued drafts from editable pending list', () async {
      final key = await _seedDraft();
      final queue = VisitUploadQueue.forTest(
        connectivity: connectivity,
        uploadRunner: (_) async {
          return const VisitUploadResult(
            success: false,
            isNetworkFailure: true,
          );
        },
      );

      final before = await queue.listEditablePendingDrafts();
      expect(before.any((e) => e.draftKey == key), isTrue);

      await queue.enqueue(key);
      final after = await queue.listEditablePendingDrafts();
      expect(after.any((e) => e.draftKey == key), isFalse);
    });

    test('markInFlight hides draft and skips silent process until cleared',
        () async {
      final key = await _seedDraft();
      var attempts = 0;
      connectivity.results = const [ConnectivityResult.wifi];

      final queue = VisitUploadQueue.forTest(
        connectivity: connectivity,
        uploadRunner: (_) async {
          attempts++;
          return const VisitUploadResult(success: true, visitId: 1);
        },
      );

      await queue.markInFlight(key);
      expect(queue.isQueued(key), isTrue);
      final hidden = await queue.listEditablePendingDrafts();
      expect(hidden.any((e) => e.draftKey == key), isFalse);

      await queue.processPending();
      expect(attempts, 0);
      expect(queue.isQueued(key), isTrue);

      queue.clearInFlight(key);
      await queue.processPending();
      expect(attempts, 1);
      expect(queue.isQueued(key), isFalse);
    });
  });

  group('VisitUploadMeta', () {
    test('builds meta from snapshot with client draft id', () {
      final snapshot = VisitMediaDraftSnapshot(
        draftKey: const VisitDraftKey(regionId: 1, siteId: 2),
        startedAt: DateTime.utc(2026, 9, 8),
        context: const VisitPatrolContext(
          regionId: 1,
          siteId: 2,
          clientDraftId: 'abc',
        ),
        items: [
          VisitMediaItem(
            path: '/tmp/a.jpg',
            type: VisitMediaType.photo,
            capturedAt: DateTime.utc(2026, 9, 8),
            latitude: 3,
            longitude: 4,
          ),
        ],
      );

      final meta = VisitUploadMeta.buildFromSnapshot(snapshot);
      expect(meta['client_draft_id'], 'abc');
      expect(meta['site_id'], 2);
      expect(meta['region_id'], 1);
      expect((meta['items'] as List).length, 1);
    });
  });
}
