import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../../api/visit_upload_api.dart';
import 'visit_gps_session.dart';
import 'visit_media_draft_store.dart';
import 'visit_upload_failure.dart';
import 'visit_video_flow_controller.dart';

typedef VisitQueuedUploadRunner =
    Future<VisitUploadResult> Function(VisitMediaDraftSnapshot snapshot);

typedef VisitQueuedUploadFailureHandler =
    Future<void> Function({
      required VisitDraftKey draftKey,
      required VisitUploadFailurePresentation presentation,
      required VisitMediaDraftSnapshot snapshot,
    });

typedef VisitQueuedUploadSuccessHandler = Future<void> Function();

class VisitUploadQueue {
  VisitUploadQueue._({
    Connectivity? connectivity,
    VisitMediaDraftStore? store,
  }) : _connectivity = connectivity ?? Connectivity(),
       _store = store ?? VisitMediaDraftStore.instance;

  static final VisitUploadQueue instance = VisitUploadQueue._();

  @visibleForTesting
  factory VisitUploadQueue.forTest({
    Connectivity? connectivity,
    VisitMediaDraftStore? store,
    VisitQueuedUploadRunner? uploadRunner,
  }) {
    final queue = VisitUploadQueue._(
      connectivity: connectivity,
      store: store,
    );
    queue._uploadRunner = uploadRunner;
    return queue;
  }

  static const _queueFileName = 'visit_upload_queue.json';
  static const _rootFolder = 'visit_upload_queue';

  final Connectivity _connectivity;
  final VisitMediaDraftStore _store;
  VisitQueuedUploadRunner? _uploadRunner;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Future<void>? _processFuture;
  bool _started = false;
  File? _queueFile;
  final LinkedHashSet<String> _queuedKeys = LinkedHashSet<String>();

  String? _activeUploadFolderName;

  VisitQueuedUploadFailureHandler? onNonNetworkFailure;
  VisitQueuedUploadSuccessHandler? onUploadSucceeded;
  VoidCallback? onQueueChanged;

  @visibleForTesting
  void debugResetForTest({VisitQueuedUploadRunner? uploadRunner}) {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _started = false;
    _processFuture = null;
    _queueFile = null;
    _queuedKeys.clear();
    _activeUploadFolderName = null;
    _uploadRunner = uploadRunner;
    onNonNetworkFailure = null;
    onUploadSucceeded = null;
    onQueueChanged = null;
  }

  Set<String> get queuedFolderNames => Set<String>.unmodifiable(_queuedKeys);

  bool isQueued(VisitDraftKey key) => _queuedKeys.contains(key.folderName);

  Future<void> ensureStarted() async {
    await _loadQueue();
    if (_started) {
      unawaited(processPending());
      return;
    }
    _started = true;
    _connectivitySub ??= _connectivity.onConnectivityChanged.listen((results) {
      if (!_hasNetworkInterface(results)) return;
      unawaited(processPending());
    });
    unawaited(processPending());
  }

  Future<void> markInFlight(VisitDraftKey key) async {
    await _loadQueue();
    final name = key.folderName;
    _activeUploadFolderName = name;
    if (_queuedKeys.add(name)) {
      await _persistQueue();
      if (kDebugMode) {
        debugPrint('[VisitUploadQueue] marked in-flight draft=$name');
      }
      onQueueChanged?.call();
    }
  }

  void clearInFlight(VisitDraftKey key) {
    if (_activeUploadFolderName == key.folderName) {
      _activeUploadFolderName = null;
    }
  }

  Future<void> enqueue(VisitDraftKey key) async {
    await _loadQueue();
    clearInFlight(key);
    final name = key.folderName;
    if (_queuedKeys.add(name)) {
      await _persistQueue();
      if (kDebugMode) {
        debugPrint('[VisitUploadQueue] enqueued draft=$name');
      }
      onQueueChanged?.call();
    }
    unawaited(processPending());
  }

  Future<void> remove(VisitDraftKey key) async {
    await _loadQueue();
    clearInFlight(key);
    if (_queuedKeys.remove(key.folderName)) {
      await _persistQueue();
      onQueueChanged?.call();
    }
  }

  Future<List<VisitMediaDraftSnapshot>> listEditablePendingDrafts() async {
    await _loadQueue();
    final pending = await _store.listPendingDrafts();
    return pending
        .where((draft) => !_queuedKeys.contains(draft.draftKey.folderName))
        .toList(growable: false);
  }

  Future<void> processPending() async {
    final existing = _processFuture;
    if (existing != null) {
      await existing;
      return;
    }
    final run = _processPendingLocked();
    _processFuture = run;
    try {
      await run;
    } finally {
      if (identical(_processFuture, run)) {
        _processFuture = null;
      }
    }
  }

  Future<void> _processPendingLocked() async {
    await _loadQueue();
    if (_queuedKeys.isEmpty) return;

    final online = await _isOnline();
    if (!online) {
      if (kDebugMode) {
        debugPrint(
          '[VisitUploadQueue] skip process; offline queued=${_queuedKeys.length}',
        );
      }
      return;
    }

    final keys = _queuedKeys.toList(growable: false);
    for (final folderName in keys) {
      final key = VisitDraftKey.tryParse(folderName);
      if (key == null) {
        _queuedKeys.remove(folderName);
        await _persistQueue();
        continue;
      }

      final stillOnline = await _isOnline();
      if (!stillOnline) return;

      if (_activeUploadFolderName == folderName) {
        if (kDebugMode) {
          debugPrint(
            '[VisitUploadQueue] skip process; in-flight draft=$folderName',
          );
        }
        continue;
      }

      final snapshot = await _store.loadDraftSnapshot(key: key);
      if (!snapshot.hasItems) {
        _queuedKeys.remove(folderName);
        await _persistQueue();
        continue;
      }

      if (kDebugMode) {
        debugPrint(
          '[VisitUploadQueue] silent upload start draft=$folderName '
          'items=${snapshot.items.length}',
        );
      }

      final flow = _ensureFlowController();
      _beginUploadBanner(flow, itemCount: snapshot.items.length);

      VisitUploadResult result;
      try {
        result = await _runUpload(
          snapshot,
          onProgress: (current, total) {
            flow.uploadProgressCurrent.value = current;
            flow.uploadProgressTotal.value = total;
          },
        );
      } catch (error, stack) {
        if (kDebugMode) {
          debugPrint('[VisitUploadQueue] unexpected error=$error');
          debugPrint('[VisitUploadQueue] stack=$stack');
        }

        if (_isTransportNetworkError(error)) {
          _clearUploadBanner(flow);
          return;
        }
        _clearUploadBanner(flow);
        await _handleNonNetworkFailure(
          key: key,
          snapshot: snapshot,
          presentation: VisitUploadFailure.presentUnexpected(error),
        );
        continue;
      }

      if (result.success) {
        _clearUploadBanner(flow);
        await _handleSuccess(key: key, snapshot: snapshot);
        continue;
      }

      if (result.isNetworkFailure) {
        _clearUploadBanner(flow);
        if (kDebugMode) {
          debugPrint(
            '[VisitUploadQueue] network fail; keep queued draft=$folderName',
          );
        }
        return;
      }

      _clearUploadBanner(flow);
      await _handleNonNetworkFailure(
        key: key,
        snapshot: snapshot,
        presentation: VisitUploadFailure.present(
          result: result,
          mediaItems: snapshot.items,
          checkpoints: snapshot.context?.checkpoints ?? const [],
        ),
      );
    }
  }

  Future<VisitUploadResult> _runUpload(
    VisitMediaDraftSnapshot snapshot, {
    void Function(int current, int total)? onProgress,
  }) async {
    final runner = _uploadRunner;
    if (runner != null) return runner(snapshot);

    final meta = await VisitUploadMeta.buildFromSnapshot(snapshot);
    return VisitUploadApi.instance.uploadVisit(
      meta: meta,
      items: snapshot.items,
      batchVoicePath: snapshot.batchNote.voiceNotePath,
      generalVoicePath: snapshot.generalNote.voiceNotePath,
      uploadUrl: snapshot.context?.uploadUrl,
      onProgress: onProgress,
    );
  }

  VisitVideoFlowController _ensureFlowController() {
    if (Get.isRegistered<VisitVideoFlowController>()) {
      return Get.find<VisitVideoFlowController>();
    }
    return Get.put(VisitVideoFlowController(), permanent: true);
  }

  void _beginUploadBanner(
    VisitVideoFlowController flow, {
    required int itemCount,
  }) {
    flow.isUploading.value = true;
    flow.isQueueUploading.value = true;
    flow.uploadProgressCurrent.value = 0;
    flow.uploadProgressTotal.value = itemCount;
  }

  void _clearUploadBanner(VisitVideoFlowController flow) {
    flow.isUploading.value = false;
    flow.isQueueUploading.value = false;
    flow.uploadProgressCurrent.value = 0;
    flow.uploadProgressTotal.value = 0;
    flow.uploadLocationLabel.value = '';
  }

  Future<void> _handleSuccess({
    required VisitDraftKey key,
    required VisitMediaDraftSnapshot snapshot,
  }) async {
    _queuedKeys.remove(key.folderName);
    await _persistQueue();
    onQueueChanged?.call();

    if (Get.isRegistered<VisitVideoFlowController>()) {
      final flow = Get.find<VisitVideoFlowController>();
      final active =
          flow.activeDraftKey.value ??
          VisitDraftKey.fromContext(flow.patrolContext.value);
      if (active == key ||
          (flow.mediaItems.isNotEmpty &&
              VisitDraftKey.fromContext(flow.patrolContext.value) == key)) {
        await flow.clearAll(deleteFiles: true);
      } else {
        await _store.clearDraft(deleteFiles: true, key: key);
      }
    } else {
      await _store.clearDraft(deleteFiles: true, key: key);
    }

    unawaited(VisitGpsSession.instance.stop());

    if (kDebugMode) {
      debugPrint('[VisitUploadQueue] upload success draft=${key.folderName}');
    }

    final successHandler = onUploadSucceeded;
    if (successHandler != null) {
      await successHandler();
    }
  }

  Future<void> _handleNonNetworkFailure({
    required VisitDraftKey key,
    required VisitMediaDraftSnapshot snapshot,
    required VisitUploadFailurePresentation presentation,
  }) async {
    await remove(key);

    final flow = _ensureFlowController();
    await flow.activateDraft(key);
    await flow.recordLastUploadIssue(presentation.toDraftIssue());

    if (kDebugMode) {
      debugPrint(
        '[VisitUploadQueue] released to editable after non-network '
        'draft=${key.folderName}',
      );
    }

    final handler = onNonNetworkFailure;
    if (handler != null) {
      await handler(
        draftKey: key,
        presentation: presentation,
        snapshot: snapshot,
      );
    }
  }

  Future<bool> _isOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return _hasNetworkInterface(results);
    } catch (_) {

      return true;
    }
  }

  static bool _hasNetworkInterface(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  static bool _isTransportNetworkError(Object error) {
    if (error is SocketException || error is HttpException) return true;
    if (error is DioException) {
      return VisitUploadResult.isNetworkDioException(error);
    }
    return false;
  }

  Future<void> _loadQueue() async {
    final file = await _ensureQueueFile();
    if (!await file.exists()) return;
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final list = decoded['draftKeys'];
      if (list is! List) return;
      _queuedKeys
        ..clear()
        ..addAll(
          list
              .map((e) => e?.toString().trim() ?? '')
              .where((e) => e.isNotEmpty),
        );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VisitUploadQueue] load failed: $e');
      }
    }
  }

  Future<void> _persistQueue() async {
    final file = await _ensureQueueFile();
    final payload = <String, dynamic>{
      'version': 1,
      'updatedAt': DateTime.now().toIso8601String(),
      'draftKeys': _queuedKeys.toList(growable: false),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<File> _ensureQueueFile() async {
    final existing = _queueFile;
    if (existing != null) return existing;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_rootFolder');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$_queueFileName');
    _queueFile = file;
    return file;
  }
}
