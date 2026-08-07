import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import 'visit_media_draft_store.dart';
import 'visit_media_geo.dart';
import 'visit_patrol_context.dart';

enum VisitMediaType { photo, video }

class VisitBatchNote {
  const VisitBatchNote({
    this.enabled = false,
    this.textNote = '',
    this.voiceNotePath,
  });

  final bool enabled;
  final String textNote;
  final String? voiceNotePath;

  bool get hasTextNote => textNote.trim().isNotEmpty;
  bool get hasVoiceNote {
    final path = voiceNotePath;
    return path != null && path.trim().isNotEmpty;
  }

  bool get hasContent => hasTextNote || hasVoiceNote;

  VisitBatchNote copyWith({
    bool? enabled,
    String? textNote,
    String? voiceNotePath,
    bool clearVoiceNote = false,
  }) {
    return VisitBatchNote(
      enabled: enabled ?? this.enabled,
      textNote: textNote ?? this.textNote,
      voiceNotePath:
          clearVoiceNote ? null : (voiceNotePath ?? this.voiceNotePath),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'enabled': enabled,
      'textNote': textNote,
      'voiceNotePath': voiceNotePath,
    };
  }

  static VisitBatchNote fromJson(Map<String, dynamic>? json) {
    if (json == null) return const VisitBatchNote();
    return VisitBatchNote(
      enabled: json['enabled'] == true,
      textNote: (json['textNote'] as String?) ?? '',
      voiceNotePath: json['voiceNotePath'] as String?,
    );
  }

  Map<String, dynamic> toUploadMeta() {
    if (!enabled) {
      return <String, dynamic>{
        'needed': 'no',
        'text_note': '',
        'has_voice_note': false,
      };
    }
    return <String, dynamic>{
      'needed': 'yes',
      'text_note': hasTextNote ? textNote.trim() : '',
      'has_voice_note': hasVoiceNote,
    };
  }
}

class VisitMediaItem {
  const VisitMediaItem({
    required this.path,
    required this.type,
    this.textNote = '',
    this.voiceNotePath,
    this.capturedAt,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
  });

  final String path;
  final VisitMediaType type;
  final String textNote;
  final String? voiceNotePath;
  final DateTime? capturedAt;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;

  bool get isPhoto => type == VisitMediaType.photo;
  bool get isVideo => type == VisitMediaType.video;
  bool get hasTextNote => textNote.trim().isNotEmpty;
  bool get hasVoiceNote {
    final path = voiceNotePath;
    return path != null && path.trim().isNotEmpty;
  }

  bool get hasNotes => hasTextNote || hasVoiceNote;

  bool get hasStamp {
    return capturedAt != null || (latitude != null && longitude != null);
  }

  String get stampLabel {
    if (!hasStamp) return '';
    return VisitMediaGeo(
      capturedAt: capturedAt ?? DateTime.now(),
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
    ).stampLabel;
  }

  VisitMediaItem copyWith({
    String? path,
    VisitMediaType? type,
    String? textNote,
    String? voiceNotePath,
    bool clearVoiceNote = false,
    DateTime? capturedAt,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) {
    return VisitMediaItem(
      path: path ?? this.path,
      type: type ?? this.type,
      textNote: textNote ?? this.textNote,
      voiceNotePath:
          clearVoiceNote ? null : (voiceNotePath ?? this.voiceNotePath),
      capturedAt: capturedAt ?? this.capturedAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
    );
  }
}

class VisitVideoFlowController extends GetxController {
  final RxList<VisitMediaItem> mediaItems = <VisitMediaItem>[].obs;
  final Map<String, Future<Uint8List?>> _thumbnailFutures =
      <String, Future<Uint8List?>>{};
  final isDraftReady = false.obs;
  final draftSiteName = RxnString();
  final draftRegionName = RxnString();
  final patrolContext = Rxn<VisitPatrolContext>();
  final activeDraftKey = Rxn<VisitDraftKey>();
  final isUploading = false.obs;
  final batchNote = const VisitBatchNote().obs;

  final _store = VisitMediaDraftStore.instance;
  bool _restoring = false;
  Future<void>? _persistQueue;
  Future<void>? _restoreFuture;
  DateTime? _startedAt;

  DateTime? get draftStartedAt => _startedAt;

  String? get locationSubtitle =>
      patrolContext.value?.locationSubtitle ?? draftSiteName.value;

  @override
  void onInit() {
    super.onInit();
    _restoreFuture = _restoreDraft();
    unawaited(_restoreFuture!);
  }

  Future<void> _restoreDraft() async {
    _restoring = true;
    try {

      var snapshot = await _store.loadDraftSnapshot();
      if (!snapshot.hasItems) {
        final pending = await _store.listPendingDrafts();
        if (pending.isNotEmpty) {
          snapshot = pending.first;
          await _store.setActiveKey(snapshot.draftKey);
        }
      }
      _applySnapshotToState(snapshot);
    } finally {
      _restoring = false;
      isDraftReady.value = true;
    }
  }

  void _applySnapshotToState(VisitMediaDraftSnapshot snapshot) {
    mediaItems.assignAll(snapshot.items);
    _startedAt = snapshot.startedAt;
    activeDraftKey.value = snapshot.draftKey;
    batchNote.value = snapshot.batchNote;
    _applyContextToState(snapshot.context);
    if (draftSiteName.value == null || draftSiteName.value!.isEmpty) {
      draftSiteName.value = snapshot.displaySiteName;
    }
    if (draftRegionName.value == null || draftRegionName.value!.isEmpty) {
      draftRegionName.value = snapshot.context?.regionName;
    }
  }

  Future<void> ensureDraftLoaded() async {
    if (isDraftReady.value) return;
    final inFlight = _restoreFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    _restoreFuture = _restoreDraft();
    await _restoreFuture;
  }

  Future<void> resetForLogout() async {
    await _flushPersistQueue();
    _restoring = true;
    try {
      _thumbnailFutures.clear();
      mediaItems.clear();
      _startedAt = null;
      draftSiteName.value = null;
      draftRegionName.value = null;
      patrolContext.value = null;
      activeDraftKey.value = null;
      batchNote.value = const VisitBatchNote();
      isUploading.value = false;
      isDraftReady.value = false;
      _restoreFuture = null;
      _persistQueue = Future<void>.value();
    } finally {
      _restoring = false;
    }
  }

  Future<void> reloadForAccountChange() async {
    if (mediaItems.isNotEmpty || batchNote.value.hasContent) {
      await persistCurrentDraft();
    }
    await resetForLogout();
    _restoreFuture = _restoreDraft();
    await _restoreFuture;
  }

  Future<void> persistCurrentDraft() async {
    if (_restoring) return;
    if (mediaItems.isEmpty) return;
    await _persistDraft();
    await _flushPersistQueue();
  }

  Future<void> setBatchNotesEnabled(bool enabled) async {
    if (batchNote.value.enabled == enabled) return;
    batchNote.value = batchNote.value.copyWith(enabled: enabled);
    if (mediaItems.isNotEmpty) {
      await _persistDraft();
    }
  }

  Future<void> updateBatchTextNote(String textNote) async {
    final trimmed = textNote.trim();
    final previousVoice = batchNote.value.voiceNotePath;
    if (trimmed.isNotEmpty) {
      if (previousVoice != null && previousVoice.trim().isNotEmpty) {
        await _store.deleteQuietly(previousVoice);
      }
      batchNote.value = batchNote.value.copyWith(
        enabled: true,
        textNote: trimmed,
        clearVoiceNote: true,
      );
    } else {
      batchNote.value = batchNote.value.copyWith(textNote: '');
    }
    if (mediaItems.isNotEmpty) {
      await _persistDraft();
    }
  }

  Future<void> updateBatchVoiceNote(String? voiceNotePath) async {
    String? durableVoice = voiceNotePath;
    if (voiceNotePath != null && voiceNotePath.trim().isNotEmpty) {
      try {
        durableVoice = await _store.importVoiceFile(voiceNotePath);
      } catch (_) {
        durableVoice = voiceNotePath;
      }
    }

    final previous = batchNote.value.voiceNotePath;
    if (previous != null &&
        previous != durableVoice &&
        previous.trim().isNotEmpty) {
      await _store.deleteQuietly(previous);
    }

    if (durableVoice == null || durableVoice.trim().isEmpty) {
      batchNote.value = batchNote.value.copyWith(clearVoiceNote: true);
    } else {
      batchNote.value = batchNote.value.copyWith(
        enabled: true,
        textNote: '',
        voiceNotePath: durableVoice,
      );
    }
    if (mediaItems.isNotEmpty) {
      await _persistDraft();
    }
  }

  void _applyContextToState(VisitPatrolContext? context) {
    patrolContext.value = context;
    draftSiteName.value = context?.siteName ?? draftSiteName.value;
    draftRegionName.value = context?.regionName;
  }

  Future<void> _flushPersistQueue() async {
    final queue = _persistQueue;
    if (queue != null) await queue;
  }

  Future<void> activateDraft(VisitDraftKey key) async {
    await ensureDraftLoaded();
    await _flushPersistQueue();
    if (mediaItems.isNotEmpty) {
      await _persistDraft();
      await _flushPersistQueue();
    }

    _restoring = true;
    try {
      await _store.setActiveKey(key);
      final snapshot = await _store.loadDraftSnapshot(key: key);
      _thumbnailFutures.clear();
      _applySnapshotToState(snapshot);
    } finally {
      _restoring = false;
      isDraftReady.value = true;
    }
  }

  Future<List<VisitMediaDraftSnapshot>> listPendingDrafts() {
    return _store.listPendingDrafts();
  }

  Future<bool> applyBridgePatrolContext(Map<String, dynamic>? payload) async {
    await ensureDraftLoaded();
    final incoming = VisitPatrolContext.fromBridgePayload(payload);
    if (incoming == null) return false;

    final targetKey = VisitDraftKey.fromContext(incoming);
    final currentKey =
        activeDraftKey.value ?? VisitDraftKey.fromContext(patrolContext.value);

    await _flushPersistQueue();

    if (currentKey != targetKey && mediaItems.isNotEmpty) {
      await persistCurrentDraft();
    }

    final current = patrolContext.value;
    final merged = VisitPatrolContext(
      clientDraftId: current?.clientDraftId?.isNotEmpty == true
          ? current!.clientDraftId
          : (incoming.clientDraftId?.isNotEmpty == true
              ? incoming.clientDraftId
              : VisitPatrolContext.generateClientDraftId()),
      regionId: incoming.regionId ?? current?.regionId,
      siteId: incoming.siteId ?? current?.siteId,
      regionName: incoming.regionName ?? current?.regionName,
      siteName: incoming.siteName ?? current?.siteName,
      scheduleId: incoming.scheduleId ?? current?.scheduleId,
      requestId: incoming.requestId ?? current?.requestId,
    );

    if (currentKey == targetKey && mediaItems.isNotEmpty) {
      activeDraftKey.value = VisitDraftKey.fromContext(merged);
      _applyContextToState(merged);
      await _store.setActiveKey(targetKey);
      unawaited(persistCurrentDraft());
      final reopenedPending = mediaItems.isNotEmpty;
      debugPrint(
        '[VisitDraft] bridge open key=$targetKey '
        'reopenedPending=$reopenedPending items=${mediaItems.length} '
        'siteId=${merged.siteId} regionId=${merged.regionId} '
        'keptInMemory=true',
      );
      return reopenedPending;
    }

    _restoring = true;
    try {
      await _store.setActiveKey(targetKey);
      final snapshot = await _store.loadDraftSnapshot(key: targetKey);
      _thumbnailFutures.clear();
      _applySnapshotToState(snapshot);
    } finally {
      _restoring = false;
      isDraftReady.value = true;
    }

    activeDraftKey.value = VisitDraftKey.fromContext(merged);
    _applyContextToState(merged);

    final reopenedPending = mediaItems.isNotEmpty;
    debugPrint(
      '[VisitDraft] bridge open key=$targetKey '
      'reopenedPending=$reopenedPending items=${mediaItems.length} '
      'siteId=${merged.siteId} regionId=${merged.regionId}',
    );
    return reopenedPending;
  }

  void updateSiteName(String? name) {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    if (draftSiteName.value == trimmed &&
        patrolContext.value?.siteName == trimmed) {
      return;
    }
    draftSiteName.value = trimmed;
    final current = patrolContext.value;
    patrolContext.value = (current ?? const VisitPatrolContext()).copyWith(
      siteName: trimmed,
      clientDraftId: current?.clientDraftId?.isNotEmpty == true
          ? current!.clientDraftId
          : VisitPatrolContext.generateClientDraftId(),
    );
    if (mediaItems.isNotEmpty) {
      unawaited(_persistDraft());
    }
  }

  String ensureClientDraftId() {
    final current = patrolContext.value;
    final existing = current?.clientDraftId?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final id = VisitPatrolContext.generateClientDraftId();
    patrolContext.value = (current ?? const VisitPatrolContext()).copyWith(
      clientDraftId: id,
    );
    if (mediaItems.isNotEmpty) {
      unawaited(_persistDraft());
    }
    return id;
  }

  Map<String, dynamic> buildUploadMeta({DateTime? submittedAt}) {
    final draftId = ensureClientDraftId();
    final context = patrolContext.value;
    final started = (_startedAt ?? DateTime.now()).toUtc();
    final submitted = (submittedAt ?? DateTime.now()).toUtc();

    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < mediaItems.length; i++) {
      final item = mediaItems[i];
      items.add(<String, dynamic>{
        'client_index': i,
        'type': item.type.name,
        'text_note': item.textNote,
        'captured_at': item.capturedAt?.toUtc().toIso8601String(),
        'latitude': item.latitude,
        'longitude': item.longitude,
        'accuracy_meters': item.accuracyMeters,
        'has_voice_note': item.hasVoiceNote,
      });
    }

    final meta = <String, dynamic>{
      'client_draft_id': draftId,
      'started_at': started.toIso8601String(),
      'submitted_at': submitted.toIso8601String(),
      'items': items,
      'attention_needed': batchNote.value.toUploadMeta(),
    };
    final contextFields = context?.toUploadMetaFields();
    if (contextFields != null) {
      contextFields.remove('client_draft_id');
      meta.addAll(contextFields);
    }
    return meta;
  }

  Future<void> _persistDraft() async {
    if (_restoring) return;
    final snapshot = mediaItems.toList(growable: false);
    final startedAt = _startedAt;
    final siteName = draftSiteName.value;
    final context = patrolContext.value;
    final note = batchNote.value;
    final key =
        activeDraftKey.value ?? VisitDraftKey.fromContext(context);
    activeDraftKey.value = key;
    _persistQueue = (_persistQueue ?? Future<void>.value()).then((_) async {

      await _store.saveDraft(
        snapshot,
        startedAt: startedAt,
        siteName: siteName,
        context: context,
        key: key,
        batchNote: note,
      );
    });
    await _persistQueue;
  }

  Future<VisitMediaItem?> addVideo(String path, {VisitMediaGeo? geo}) {
    return addMediaItem(
      VisitMediaItem(
        path: path,
        type: VisitMediaType.video,
        capturedAt: geo?.capturedAt,
        latitude: geo?.latitude,
        longitude: geo?.longitude,
        accuracyMeters: geo?.accuracyMeters,
      ),
    );
  }

  Future<VisitMediaItem?> addPhoto(String path, {VisitMediaGeo? geo}) {
    return addMediaItem(
      VisitMediaItem(
        path: path,
        type: VisitMediaType.photo,
        capturedAt: geo?.capturedAt,
        latitude: geo?.latitude,
        longitude: geo?.longitude,
        accuracyMeters: geo?.accuracyMeters,
      ),
    );
  }

  Future<VisitMediaItem?> addMediaItem(
    VisitMediaItem item, {
    bool persistToDraftStore = true,
  }) async {
    if (item.path.trim().isEmpty) return null;

    String durablePath = item.path;
    if (persistToDraftStore) {
      try {
        durablePath = await _store.importMediaFile(
          sourcePath: item.path,
          type: item.type,
        );
      } catch (_) {
        if (!await File(item.path).exists()) return null;
      }
    } else if (!await File(item.path).exists()) {
      return null;
    }

    final durableItem = item.copyWith(path: durablePath);
    _startedAt ??= durableItem.capturedAt ?? DateTime.now();
    if (patrolContext.value?.clientDraftId == null ||
        patrolContext.value!.clientDraftId!.trim().isEmpty) {
      ensureClientDraftId();
    }
    final existing = mediaItems.indexWhere((e) => e.path == durablePath);
    if (existing >= 0) {
      mediaItems[existing] = durableItem;
    } else {
      mediaItems.add(durableItem);
    }
    await _persistDraft();
    return durableItem;
  }

  Future<VisitMediaItem?> registerCaptureDraft(VisitMediaItem item) {
    return addMediaItem(item, persistToDraftStore: false);
  }

  Future<VisitMediaItem?> finalizeCaptureDraft({
    required String previewPath,
    required VisitMediaType type,
    VisitMediaGeo? geo,
  }) async {
    final index = mediaItems.indexWhere((e) => e.path == previewPath);
    final existing = index >= 0 ? mediaItems[index] : null;

    String durablePath = previewPath;
    try {
      durablePath = await _store.importMediaFile(
        sourcePath: previewPath,
        type: type,
        deleteSource: false,
      );
    } catch (_) {
      if (!await File(previewPath).exists()) return existing;
    }

    final updated = (existing ??
            VisitMediaItem(
              path: durablePath,
              type: type,
            ))
        .copyWith(
          path: durablePath,
          capturedAt: geo?.capturedAt ?? existing?.capturedAt,
          latitude: geo?.latitude ?? existing?.latitude,
          longitude: geo?.longitude ?? existing?.longitude,
          accuracyMeters: geo?.accuracyMeters ?? existing?.accuracyMeters,
        );

    if (index >= 0) {
      mediaItems[index] = updated;
    } else {
      final durableIndex = mediaItems.indexWhere((e) => e.path == durablePath);
      if (durableIndex >= 0) {
        mediaItems[durableIndex] = updated;
      } else {
        mediaItems.add(updated);
      }
    }
    _startedAt ??= updated.capturedAt ?? DateTime.now();
    await _persistDraft();
    return updated;
  }

  Future<void> updateCaptureGeo({
    required String mediaPath,
    required VisitMediaGeo geo,
  }) async {
    final index = mediaItems.indexWhere((e) => e.path == mediaPath);
    if (index < 0) return;
    mediaItems[index] = mediaItems[index].copyWith(
      capturedAt: geo.capturedAt,
      latitude: geo.latitude,
      longitude: geo.longitude,
      accuracyMeters: geo.accuracyMeters,
    );
    await _persistDraft();
  }

  VisitMediaItem? findByPath(String path) {
    for (final item in mediaItems) {
      if (item.path == path) return item;
    }
    return null;
  }

  Future<Uint8List?> videoThumbnail(String videoPath) {
    return _thumbnailFutures.putIfAbsent(videoPath, () async {
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          final file = File(videoPath);
          if (!await file.exists()) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            continue;
          }

          const probeTimes = <int>[1000, 2000, 3000, 500, 0];
          for (final timeMs in probeTimes) {
            final bytes = await vt.VideoThumbnail.thumbnailData(
              video: videoPath,
              imageFormat: vt.ImageFormat.JPEG,
              timeMs: timeMs,
              maxWidth: 480,
              quality: 80,
            );
            if (bytes != null && bytes.isNotEmpty) return bytes;
          }
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      return null;
    });
  }

  Future<void> updateTextNote({
    required String mediaPath,
    required String textNote,
  }) async {
    final index = mediaItems.indexWhere((e) => e.path == mediaPath);
    if (index < 0) return;
    final trimmed = textNote.trim();
    if (trimmed.isNotEmpty) {
      final previousVoice = mediaItems[index].voiceNotePath;
      if (previousVoice != null && previousVoice.trim().isNotEmpty) {
        await _store.deleteQuietly(previousVoice);
      }
      mediaItems[index] = mediaItems[index].copyWith(
        textNote: trimmed,
        clearVoiceNote: true,
      );
      await _persistDraft();
      return;
    }
    mediaItems[index] = mediaItems[index].copyWith(textNote: '');
    await _persistDraft();
  }

  Future<void> updateVoiceNote({
    required String mediaPath,
    required String? voiceNotePath,
  }) async {
    final index = mediaItems.indexWhere((e) => e.path == mediaPath);
    if (index < 0) return;

    String? durableVoice = voiceNotePath;
    if (voiceNotePath != null && voiceNotePath.trim().isNotEmpty) {
      try {
        durableVoice = await _store.importVoiceFile(voiceNotePath);
      } catch (_) {
        durableVoice = voiceNotePath;
      }
    }

    final previous = mediaItems[index].voiceNotePath;
    if (previous != null &&
        previous != durableVoice &&
        previous.trim().isNotEmpty) {
      await _store.deleteQuietly(previous);
    }
    if (durableVoice == null) {
      mediaItems[index] = mediaItems[index].copyWith(clearVoiceNote: true);
      await _persistDraft();
      return;
    }
    mediaItems[index] = mediaItems[index].copyWith(
      voiceNotePath: durableVoice,
      textNote: '',
    );
    await _persistDraft();
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= mediaItems.length) return;
    final item = mediaItems[index];
    await _store.deleteQuietly(item.voiceNotePath);
    await _store.deleteQuietly(item.path);
    _thumbnailFutures.remove(item.path);
    mediaItems.removeAt(index);
    if (mediaItems.isEmpty) {
      _startedAt = null;
    }
    await _persistDraft();
  }

  Future<void> removeByPath(String path, {bool deleteMediaFile = false}) async {
    final index = mediaItems.indexWhere((e) => e.path == path);
    if (index < 0) return;
    final voicePath = mediaItems[index].voiceNotePath;
    await _store.deleteQuietly(voicePath);
    if (deleteMediaFile) {
      await _store.deleteQuietly(path);
    }
    _thumbnailFutures.remove(path);
    mediaItems.removeAt(index);
    if (mediaItems.isEmpty) {
      _startedAt = null;
    }
    await _persistDraft();
  }

  Future<void> clearAll({bool deleteFiles = true}) async {
    final key = activeDraftKey.value ??
        VisitDraftKey.fromContext(patrolContext.value);
    if (deleteFiles) {
      for (final item in mediaItems) {
        await _store.deleteQuietly(item.voiceNotePath);
        await _store.deleteQuietly(item.path);
      }
      await _store.deleteQuietly(batchNote.value.voiceNotePath);
      await _store.clearDraft(deleteFiles: true, key: key);
    } else {
      await _store.clearDraft(deleteFiles: false, key: key);
    }
    _thumbnailFutures.clear();
    mediaItems.clear();
    batchNote.value = const VisitBatchNote();
    _startedAt = null;
    draftSiteName.value = null;
    draftRegionName.value = null;
    patrolContext.value = null;

    activeDraftKey.value = key;
  }
}
