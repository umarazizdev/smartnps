import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:smartnps360/src/log_visit/flow/visit_media_draft_store.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('nps_draft_');
    PathProviderPlatform.instance = _FakePathProvider(tempRoot);
    VisitMediaDraftStore.instance.debugResetForTest();
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('importMediaFile is idempotent for the same captureId', () async {
    final source = File('${tempRoot.path}/src.jpg');
    await source.writeAsBytes(const <int>[0xFF, 0xD8, 0xFF, 0xD9]);

    final store = VisitMediaDraftStore.instance;
    final first = await store.importMediaFile(
      sourcePath: source.path,
      type: VisitMediaType.photo,
      captureId: 'cap-test-1',
      deleteSource: false,
      key: const VisitDraftKey(regionId: 1, siteId: 1),
    );
    final second = await store.importMediaFile(
      sourcePath: source.path,
      type: VisitMediaType.photo,
      captureId: 'cap-test-1',
      deleteSource: false,
      key: const VisitDraftKey(regionId: 1, siteId: 1),
    );

    expect(first, second);
    expect(await File(first).exists(), isTrue);
    expect(await File(first).length(), greaterThan(0));
  });

  test('register + finalize same captureId yields one media item', () async {
    final flow = VisitVideoFlowController();
    final source = File('${tempRoot.path}/native.jpg');
    await source.writeAsBytes(const <int>[0xFF, 0xD8, 0xFF, 0xD9]);

    await flow.registerCaptureDraft(
      VisitMediaItem(
        path: source.path,
        type: VisitMediaType.photo,
        captureId: 'cap-dup-1',
        isPendingCapture: true,
      ),
    );
    await flow.registerCaptureDraft(
      VisitMediaItem(
        path: source.path,
        type: VisitMediaType.photo,
        captureId: 'cap-dup-1',
        isPendingCapture: true,
      ),
    );
    expect(flow.mediaItems.length, 1);

    final finalized = await flow.finalizeCaptureDraft(
      previewPath: source.path,
      type: VisitMediaType.photo,
      captureId: 'cap-dup-1',
      markAccepted: true,
    );
    expect(finalized, isNotNull);
    expect(flow.mediaItems.where((e) => e.captureId == 'cap-dup-1').length, 1);
    expect(flow.mediaItems.single.isPendingCapture, isFalse);

    await flow.rollbackCaptureDraft(
      captureId: 'cap-dup-1',
      previewPath: source.path,
      durablePath: finalized?.path,
    );
    expect(flow.mediaItems.where((e) => e.captureId == 'cap-dup-1'), isEmpty);
  });
}
