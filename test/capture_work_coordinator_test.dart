import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:smartnps360/src/log_visit/flow/capture_work_coordinator.dart';
import 'package:smartnps360/src/log_visit/flow/visit_gps_session.dart';
import 'package:smartnps360/src/log_visit/flow/visit_media_draft_store.dart';
import 'package:smartnps360/src/log_visit/flow/visit_media_geo.dart';
import 'package:smartnps360/src/log_visit/flow/visit_video_flow_controller.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
}

Position _position({
  required DateTime timestamp,
  double lat = 1.0,
  double lon = 2.0,
  double accuracy = 8,
}) {
  return Position(
    longitude: lon,
    latitude: lat,
    timestamp: timestamp,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VisitGpsSession capture-time validity', () {
    test('isAcceptableForCapture uses captureTime age window', () {
      final captureAt = DateTime.utc(2026, 9, 6, 12, 0, 0);
      final fresh = _position(
        timestamp: captureAt.subtract(const Duration(seconds: 10)),
      );
      final stale = _position(
        timestamp: captureAt.subtract(const Duration(seconds: 45)),
      );

      expect(VisitGpsSession.isAcceptableForCapture(fresh, captureAt), isTrue);
      expect(VisitGpsSession.isAcceptableForCapture(stale, captureAt), isFalse);
    });

    test('fix slightly after capture within maxAcceptAge is acceptable', () {
      final captureAt = DateTime.utc(2026, 9, 6, 12, 0, 0);
      final after = _position(
        timestamp: captureAt.add(const Duration(seconds: 5)),
      );
      expect(VisitGpsSession.isAcceptableForCapture(after, captureAt), isTrue);
    });
  });

  group('CaptureWorkCoordinator', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('nps_coord_');
      PathProviderPlatform.instance = _FakePathProvider(tempRoot);
      VisitMediaDraftStore.instance.debugResetForTest();
      CaptureWorkCoordinator.active?.disposeSession(reason: 'testSetup');
    });

    tearDown(() async {
      CaptureWorkCoordinator.active?.disposeSession(reason: 'testTeardown');
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('beginSession replaces previous active coordinator', () {
      final a = CaptureWorkCoordinator.beginSession(
        expectedType: VisitMediaType.photo,
      );
      final b = CaptureWorkCoordinator.beginSession(
        expectedType: VisitMediaType.photo,
      );
      expect(identical(CaptureWorkCoordinator.active, b), isTrue);
      expect(a.isDisposed, isTrue);
      expect(b.isDisposed, isFalse);
    });

    test('bindNativeResult snapshots geo without coords when no fix', () {
      final coordinator = CaptureWorkCoordinator.beginSession(
        expectedType: VisitMediaType.photo,
      );
      final capturedAt = DateTime.now();
      final geo = coordinator.bindNativeResult(
        captureId: 'cap-a',
        capturedAt: capturedAt,
        mediaType: VisitMediaType.photo,
      );
      expect(geo.capturedAt, capturedAt);
      expect(geo.hasCoordinates, isFalse);
      expect(coordinator.captureId, 'cap-a');
      expect(coordinator.gpsContinueFuture, isNotNull);
    });

    test('prepareRetake clears capture-scoped state', () {
      final coordinator = CaptureWorkCoordinator.beginSession(
        expectedType: VisitMediaType.photo,
      );
      coordinator.bindNativeResult(
        captureId: 'cap-a',
        capturedAt: DateTime.now(),
        mediaType: VisitMediaType.photo,
      );
      final genBefore = coordinator.generation;
      coordinator.prepareRetake();
      expect(coordinator.captureId, isNull);
      expect(coordinator.generation, greaterThan(genBefore));
      expect(coordinator.isDisposed, isFalse);

      final geoB = coordinator.bindNativeResult(
        captureId: 'cap-b',
        capturedAt: DateTime.now(),
        mediaType: VisitMediaType.photo,
      );
      expect(coordinator.captureId, 'cap-b');
      expect(geoB.capturedAt, isNotNull);
    });

    test('cancelCapture then disposeSession clears active', () {
      final coordinator = CaptureWorkCoordinator.beginSession(
        expectedType: VisitMediaType.photo,
      );
      coordinator.bindNativeResult(
        captureId: 'cap-close',
        capturedAt: DateTime.now(),
        mediaType: VisitMediaType.photo,
      );
      coordinator.cancelCapture(reason: 'close');
      coordinator.disposeSession(reason: 'close');
      expect(coordinator.isDisposed, isTrue);
      expect(CaptureWorkCoordinator.active, isNull);
    });

    test('warm durable ready before Use Photo wait', () async {
      final flow = VisitVideoFlowController();
      final source = File('${tempRoot.path}/native.jpg');
      await source.writeAsBytes(const <int>[0xFF, 0xD8, 0xFF, 0xD9]);

      await flow.registerCaptureDraft(
        VisitMediaItem(
          path: source.path,
          type: VisitMediaType.photo,
          captureId: 'cap-warm-1',
          isPendingCapture: true,
        ),
      );

      final coordinator = CaptureWorkCoordinator.beginSession(
        expectedType: VisitMediaType.photo,
      );
      final geo = VisitMediaGeo(capturedAt: DateTime.now());
      coordinator.bindNativeResult(
        captureId: 'cap-warm-1',
        capturedAt: geo.capturedAt,
        mediaType: VisitMediaType.photo,
      );

      // Simulate post-first-frame durable import ownership.
      final warmFuture = flow.finalizeCaptureDraft(
        previewPath: source.path,
        type: VisitMediaType.photo,
        captureId: 'cap-warm-1',
        geo: geo,
        markAccepted: false,
      );
      coordinator.attachWarmPersist(warmFuture);
      final durable = await warmFuture;
      expect(durable, isNotNull);
      expect(
        VisitMediaDraftStore.instance.isManagedPath(durable!.path),
        isTrue,
      );

      final waited = await coordinator.waitForAcceptRequirements(
        gpsRequired: false,
        currentGeo: geo,
      );
      expect(waited.durable?.path, durable.path);
      expect(waited.durableWasReady, isTrue);

      final accepted = await flow.acceptWarmCapture(
        captureId: 'cap-warm-1',
        previewPath: source.path,
        geo: geo,
        assumeFileReady: true,
      );
      expect(accepted, isNotNull);
      expect(accepted!.isPendingCapture, isFalse);
      expect(
        flow.mediaItems.where((e) => e.captureId == 'cap-warm-1').length,
        1,
      );
      expect(await File(accepted.path).exists(), isTrue);
    });

    test('Use Photo before durable completes awaits warm future', () async {
      final flow = VisitVideoFlowController();
      final source = File('${tempRoot.path}/native2.jpg');
      await source.writeAsBytes(const <int>[0xFF, 0xD8, 0xFF, 0xD9]);

      await flow.registerCaptureDraft(
        VisitMediaItem(
          path: source.path,
          type: VisitMediaType.photo,
          captureId: 'cap-slow-1',
          isPendingCapture: true,
        ),
      );

      final coordinator = CaptureWorkCoordinator.beginSession(
        expectedType: VisitMediaType.photo,
      );
      final geo = VisitMediaGeo(capturedAt: DateTime.now());
      coordinator.bindNativeResult(
        captureId: 'cap-slow-1',
        capturedAt: geo.capturedAt,
        mediaType: VisitMediaType.photo,
      );

      coordinator.attachWarmPersist(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return flow.finalizeCaptureDraft(
          previewPath: source.path,
          type: VisitMediaType.photo,
          captureId: 'cap-slow-1',
          geo: geo,
          markAccepted: false,
        );
      }());

      expect(coordinator.isWarmPersistCompleted, isFalse);
      final waited = await coordinator.waitForAcceptRequirements(
        gpsRequired: false,
        currentGeo: geo,
      );
      expect(waited.durable, isNotNull);
      expect(waited.durableWasReady, isFalse);
      expect(await File(waited.durable!.path).exists(), isTrue);
    });

    test('two captures with distinct captureIds', () async {
      final flow = VisitVideoFlowController();
      for (final id in ['cap-1', 'cap-2']) {
        final source = File('${tempRoot.path}/$id.jpg');
        await source.writeAsBytes(const <int>[0xFF, 0xD8, 0xFF, 0xD9]);
        await flow.registerCaptureDraft(
          VisitMediaItem(
            path: source.path,
            type: VisitMediaType.photo,
            captureId: id,
            isPendingCapture: true,
          ),
        );
        final item = await flow.finalizeCaptureDraft(
          previewPath: source.path,
          type: VisitMediaType.photo,
          captureId: id,
          markAccepted: true,
        );
        expect(item?.captureId, id);
        expect(await File(item!.path).exists(), isTrue);
      }
      expect(flow.mediaItems.length, 2);
      expect(flow.mediaItems.map((e) => e.captureId).toSet(), {
        'cap-1',
        'cap-2',
      });
    });

    test('rollback during background work leaves no finalized row', () async {
      final flow = VisitVideoFlowController();
      final source = File('${tempRoot.path}/native3.jpg');
      await source.writeAsBytes(const <int>[0xFF, 0xD8, 0xFF, 0xD9]);

      await flow.registerCaptureDraft(
        VisitMediaItem(
          path: source.path,
          type: VisitMediaType.photo,
          captureId: 'cap-rollback',
          isPendingCapture: true,
        ),
      );

      final coordinator = CaptureWorkCoordinator.beginSession(
        expectedType: VisitMediaType.photo,
      );
      coordinator.bindNativeResult(
        captureId: 'cap-rollback',
        capturedAt: DateTime.now(),
        mediaType: VisitMediaType.photo,
      );

      final warm = flow.finalizeCaptureDraft(
        previewPath: source.path,
        type: VisitMediaType.photo,
        captureId: 'cap-rollback',
        markAccepted: false,
      );
      coordinator.attachWarmPersist(warm);
      final durable = await warm;
      coordinator.cancelCapture(reason: 'close');
      await flow.rollbackCaptureDraft(
        captureId: 'cap-rollback',
        previewPath: source.path,
        durablePath: durable?.path,
      );

      expect(
        flow.mediaItems.where((e) => e.captureId == 'cap-rollback'),
        isEmpty,
      );
      if (durable != null) {
        expect(await File(durable.path).exists(), isFalse);
      }
    });

    test('double acceptWarmCapture does not duplicate captureId', () async {
      final flow = VisitVideoFlowController();
      final source = File('${tempRoot.path}/native4.jpg');
      await source.writeAsBytes(const <int>[0xFF, 0xD8, 0xFF, 0xD9]);

      await flow.registerCaptureDraft(
        VisitMediaItem(
          path: source.path,
          type: VisitMediaType.photo,
          captureId: 'cap-double',
          isPendingCapture: true,
        ),
      );
      final durable = await flow.finalizeCaptureDraft(
        previewPath: source.path,
        type: VisitMediaType.photo,
        captureId: 'cap-double',
        markAccepted: false,
      );
      expect(durable, isNotNull);

      final a = await flow.acceptWarmCapture(
        captureId: 'cap-double',
        previewPath: source.path,
        assumeFileReady: true,
      );
      final b = await flow.acceptWarmCapture(
        captureId: 'cap-double',
        previewPath: source.path,
        assumeFileReady: true,
      );
      expect(a?.path, b?.path);
      expect(
        flow.mediaItems.where((e) => e.captureId == 'cap-double').length,
        1,
      );
      expect(flow.mediaItems.single.isPendingCapture, isFalse);
      expect(await File(flow.mediaItems.single.path).exists(), isTrue);
    });

    test('prewarmCaptureContext creates media directory', () async {
      final key = const VisitDraftKey(regionId: 9, siteId: 3);
      await VisitMediaDraftStore.instance.prewarmCaptureContext(
        key: key,
        type: VisitMediaType.photo,
      );
      final root = Directory('${tempRoot.path}/visit_media_draft');
      expect(await root.exists(), isTrue, reason: 'draft root under docs');
      final dir = Directory('${root.path}/${key.folderName}/photos');
      expect(
        await dir.exists(),
        isTrue,
        reason:
            'expected ${dir.path}; root children=${root.existsSync() ? root.listSync().map((e) => e.path).toList() : const <String>[]}',
      );
    });
  });
}
