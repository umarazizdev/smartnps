import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import 'package:geolocator/geolocator.dart';

import '../../utilities/app_debug_log.dart';
import 'cam_perf.dart';
import 'visit_checkpoint.dart';
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
      voiceNotePath: clearVoiceNote
          ? null
          : (voiceNotePath ?? this.voiceNotePath),
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

  Map<String, dynamic> toGeneralUploadMeta() {
    if (!enabled) {
      return <String, dynamic>{
        'enabled': 'no',
        'text_note': '',
        'has_voice_note': false,
      };
    }
    return <String, dynamic>{
      'enabled': 'yes',
      'text_note': hasTextNote ? textNote.trim() : '',
      'has_voice_note': hasVoiceNote,
    };
  }
}

class VisitMediaItem {
  const VisitMediaItem({
    required this.path,
    required this.type,
    this.captureId,
    this.textNote = '',
    this.voiceNotePath,
    this.capturedAt,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.siteCheckpointId,
    this.attentionNeeded = false,
    this.isPendingCapture = false,
  });

  final String path;
  final VisitMediaType type;

  /// Stable identity for one native capture (survives import path changes).
  final String? captureId;
  final String textNote;
  final String? voiceNotePath;
  final DateTime? capturedAt;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final int? siteCheckpointId;
  final bool attentionNeeded;

  /// True while CaptureReview owns this capture before Use Photo commits it.
  final bool isPendingCapture;

  bool get isPhoto => type == VisitMediaType.photo;
  bool get isVideo => type == VisitMediaType.video;
  bool get hasTextNote => textNote.trim().isNotEmpty;
  bool get hasVoiceNote {
    final path = voiceNotePath;
    return path != null && path.trim().isNotEmpty;
  }

  bool get hasNotes => hasTextNote || hasVoiceNote;
  bool get isCheckpointMedia => siteCheckpointId != null;
  bool get isAdditionalMedia => siteCheckpointId == null;

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
    String? captureId,
    String? textNote,
    String? voiceNotePath,
    bool clearVoiceNote = false,
    DateTime? capturedAt,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    int? siteCheckpointId,
    bool clearSiteCheckpointId = false,
    bool? attentionNeeded,
    bool? isPendingCapture,
  }) {
    return VisitMediaItem(
      path: path ?? this.path,
      type: type ?? this.type,
      captureId: captureId ?? this.captureId,
      textNote: textNote ?? this.textNote,
      voiceNotePath: clearVoiceNote
          ? null
          : (voiceNotePath ?? this.voiceNotePath),
      capturedAt: capturedAt ?? this.capturedAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      siteCheckpointId: clearSiteCheckpointId
          ? null
          : (siteCheckpointId ?? this.siteCheckpointId),
      attentionNeeded: attentionNeeded ?? this.attentionNeeded,
      isPendingCapture: isPendingCapture ?? this.isPendingCapture,
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
  final generalNote = const VisitBatchNote().obs;
  final activeCheckpointId = RxnInt();

  final _store = VisitMediaDraftStore.instance;
  bool _restoring = false;
  Future<void>? _persistQueue;
  Future<void>? _restoreFuture;
  DateTime? _startedAt;

  /// In-flight durable imports keyed by captureId (or preview path fallback).
  final Map<String, Future<VisitMediaItem?>> _finalizeInFlight =
      <String, Future<VisitMediaItem?>>{};

  DateTime? get draftStartedAt => _startedAt;

  String? get locationSubtitle =>
      patrolContext.value?.locationSubtitle ?? draftSiteName.value;

  List<VisitCheckpoint> get checkpoints =>
      patrolContext.value?.checkpoints ?? const <VisitCheckpoint>[];

  List<VisitMediaItem> get additionalMediaItems => mediaItems
      .where((e) => e.isAdditionalMedia && !e.isPendingCapture)
      .toList(growable: false);

  /// Draft UI should never render in-flight CaptureReview rows.
  List<VisitMediaItem> get visibleMediaItems =>
      mediaItems.where((e) => !e.isPendingCapture).toList(growable: false);

  List<VisitMediaItem> mediaForCheckpoint(int checkpointId) {
    return mediaItems
        .where((e) => e.siteCheckpointId == checkpointId && !e.isPendingCapture)
        .toList(growable: false);
  }

  bool isCheckpointCompleted(int checkpointId) {
    return mediaForCheckpoint(checkpointId).any((e) => e.isPhoto);
  }

  int get completedCheckpointCount =>
      checkpoints.where((e) => isCheckpointCompleted(e.id)).length;

  int get pendingCheckpointCount =>
      checkpoints.length - completedCheckpointCount;

  bool get hasIncompleteCheckpoints => pendingCheckpointCount > 0;

  void beginCheckpointCapture(int checkpointId) {
    activeCheckpointId.value = checkpointId;
  }

  void endCheckpointCapture() {
    activeCheckpointId.value = null;
  }

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
    generalNote.value = snapshot.generalNote;
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
      generalNote.value = const VisitBatchNote();
      activeCheckpointId.value = null;
      isUploading.value = false;
      isDraftReady.value = false;
      _restoreFuture = null;
      _persistQueue = Future<void>.value();
    } finally {
      _restoring = false;
    }
  }

  Future<void> reloadForAccountChange() async {
    if (mediaItems.isNotEmpty ||
        batchNote.value.hasContent ||
        generalNote.value.hasContent) {
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

  Future<void> setGeneralNotesEnabled(bool enabled) async {
    if (generalNote.value.enabled == enabled) return;
    generalNote.value = generalNote.value.copyWith(enabled: enabled);
    if (mediaItems.isNotEmpty) {
      await _persistDraft();
    }
  }

  Future<void> updateBatchTextNote(String textNote) async {
    await _updateToggleNoteText(current: batchNote, textNote: textNote);
  }

  Future<void> updateGeneralTextNote(String textNote) async {
    await _updateToggleNoteText(current: generalNote, textNote: textNote);
  }

  Future<void> updateBatchVoiceNote(String? voiceNotePath) async {
    await _updateToggleNoteVoice(
      current: batchNote,
      voiceNotePath: voiceNotePath,
    );
  }

  Future<void> updateGeneralVoiceNote(String? voiceNotePath) async {
    await _updateToggleNoteVoice(
      current: generalNote,
      voiceNotePath: voiceNotePath,
    );
  }

  Future<void> _updateToggleNoteText({
    required Rx<VisitBatchNote> current,
    required String textNote,
  }) async {
    final trimmed = textNote.trim();
    final previousVoice = current.value.voiceNotePath;
    if (trimmed.isNotEmpty) {
      if (previousVoice != null && previousVoice.trim().isNotEmpty) {
        await _store.deleteQuietly(previousVoice);
      }
      current.value = current.value.copyWith(
        enabled: true,
        textNote: trimmed,
        clearVoiceNote: true,
      );
    } else {
      current.value = current.value.copyWith(textNote: '');
    }
    if (mediaItems.isNotEmpty) {
      await _persistDraft();
    }
  }

  Future<void> _updateToggleNoteVoice({
    required Rx<VisitBatchNote> current,
    required String? voiceNotePath,
  }) async {
    String? durableVoice = voiceNotePath;
    if (voiceNotePath != null && voiceNotePath.trim().isNotEmpty) {
      try {
        durableVoice = await _store.importVoiceFile(voiceNotePath);
      } catch (_) {
        durableVoice = voiceNotePath;
      }
    }

    final previous = current.value.voiceNotePath;
    if (previous != null &&
        previous != durableVoice &&
        previous.trim().isNotEmpty) {
      await _store.deleteQuietly(previous);
    }

    if (durableVoice == null || durableVoice.trim().isEmpty) {
      current.value = current.value.copyWith(clearVoiceNote: true);
    } else {
      current.value = current.value.copyWith(
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
    final sameSite = currentKey == targetKey;
    // Only keep prior checkpoints when reopening the same site without a
    // fresh list. Switching sites (or an explicit empty list) restores the
    // classic media-only log visit UI.
    final incomingHasCheckpointList =
        payload != null &&
        (payload.containsKey('checkpoints') ||
            payload.containsKey('checkpoint_count'));
    final List<VisitCheckpoint> mergedCheckpoints;
    if (incoming.checkpoints.isNotEmpty) {
      mergedCheckpoints = incoming.checkpoints;
    } else if (incomingHasCheckpointList) {
      mergedCheckpoints = const <VisitCheckpoint>[];
    } else if (sameSite) {
      mergedCheckpoints = current?.checkpoints ?? const <VisitCheckpoint>[];
    } else {
      mergedCheckpoints = const <VisitCheckpoint>[];
    }
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
      sitePatrolWindowId:
          incoming.sitePatrolWindowId ?? current?.sitePatrolWindowId,
      requestId: incoming.requestId ?? current?.requestId,
      siteLatitude: incoming.siteLatitude ?? current?.siteLatitude,
      siteLongitude: incoming.siteLongitude ?? current?.siteLongitude,
      uploadUrl: incoming.uploadUrl ?? current?.uploadUrl,
      checkpoints: mergedCheckpoints,
    );

    if (currentKey == targetKey && mediaItems.isNotEmpty) {
      activeDraftKey.value = VisitDraftKey.fromContext(merged);
      _applyContextToState(merged);
      await _store.setActiveKey(targetKey);
      unawaited(persistCurrentDraft());
      final reopenedPending = mediaItems.isNotEmpty;
      patrolLogDebugLog(
        '[VisitDraft] bridge open key=$targetKey '
        'reopenedPending=$reopenedPending items=${mediaItems.length} '
        'siteId=${merged.siteId} regionId=${merged.regionId} '
        'checkpoints=${merged.checkpoints.length} '
        'photos=${merged.checkpoints.where((e) => e.hasReferencePhoto).length} '
        'photoUrls=${merged.checkpoints.map((e) => e.photoUrl).toList()} '
        'keptInMemory=true payload=$payload',
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
    patrolLogDebugLog(
      '[VisitDraft] bridge open key=$targetKey '
      'reopenedPending=$reopenedPending items=${mediaItems.length} '
      'siteId=${merged.siteId} regionId=${merged.regionId} '
      'checkpoints=${merged.checkpoints.length} '
      'photos=${merged.checkpoints.where((e) => e.hasReferencePhoto).length} '
      'photoUrls=${merged.checkpoints.map((e) => e.photoUrl).toList()} '
      'payload=$payload',
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
        'attention_needed': item.attentionNeeded ? 'yes' : 'no',
      });
    }

    final checkpointsMeta = <Map<String, dynamic>>[];
    final definedCheckpoints =
        context?.checkpoints ?? const <VisitCheckpoint>[];
    for (final checkpoint in definedCheckpoints) {
      final linked = mediaForCheckpoint(checkpoint.id);
      final photoIndex = mediaItems.indexWhere(
        (e) => e.siteCheckpointId == checkpoint.id && e.isPhoto,
      );
      if (photoIndex < 0) continue;

      final photo = mediaItems[photoIndex];
      final notesItem = linked.firstWhere(
        (e) => e.hasTextNote,
        orElse: () => photo,
      );
      double? distanceMeters;
      if (checkpoint.hasCoordinates &&
          photo.latitude != null &&
          photo.longitude != null) {
        distanceMeters = Geolocator.distanceBetween(
          checkpoint.latitude!,
          checkpoint.longitude!,
          photo.latitude!,
          photo.longitude!,
        );
      }

      checkpointsMeta.add(<String, dynamic>{
        'site_checkpoint_id': checkpoint.id,
        'status': 'completed',
        'checked_at': (photo.capturedAt ?? submitted).toUtc().toIso8601String(),
        'latitude': photo.latitude,
        'longitude': photo.longitude,
        'accuracy_meters': photo.accuracyMeters,
        if (distanceMeters != null)
          'distance_meters': double.parse(distanceMeters.toStringAsFixed(1)),
        'notes': notesItem.textNote.trim(),
        'photo_client_index': photoIndex,
      });
    }

    final meta = <String, dynamic>{
      'client_draft_id': draftId,
      'started_at': started.toIso8601String(),
      'submitted_at': submitted.toIso8601String(),
      'items': items,
      'attention_needed': batchNote.value.toUploadMeta(),
      'general_note': generalNote.value.toGeneralUploadMeta(),
      if (checkpointsMeta.isNotEmpty) 'checkpoints': checkpointsMeta,
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
    CamPerf.stage(
      null,
      'PERSIST_QUEUE_WAIT_START',
      detail: 'items=${mediaItems.length}',
      usePhotoClock: true,
    );
    final snapshot = mediaItems.toList(growable: false);
    final startedAt = _startedAt;
    final siteName = draftSiteName.value;
    final context = patrolContext.value;
    final note = batchNote.value;
    final general = generalNote.value;
    final key = activeDraftKey.value ?? VisitDraftKey.fromContext(context);
    if (activeDraftKey.value != key) {
      activeDraftKey.value = key;
    }
    _persistQueue = (_persistQueue ?? Future<void>.value()).then((_) async {
      CamPerf.stage(null, 'PERSIST_QUEUE_WAIT_END', usePhotoClock: true);
      await _store.saveDraft(
        snapshot,
        startedAt: startedAt,
        siteName: siteName,
        context: context,
        key: key,
        batchNote: note,
        generalNote: general,
      );
    });
    await _persistQueue;
  }

  /// Persist [snapshot] without first mutating [mediaItems] (avoids Obx rebuild
  /// storms during Use Photo before Review has popped).
  Future<void> _persistDraftSnapshot(List<VisitMediaItem> snapshot) async {
    if (_restoring) return;
    CamPerf.stage(
      null,
      'PERSIST_QUEUE_WAIT_START',
      detail: 'snapshotItems=${snapshot.length}',
      usePhotoClock: true,
    );
    final startedAt = _startedAt;
    final siteName = draftSiteName.value;
    final context = patrolContext.value;
    final note = batchNote.value;
    final general = generalNote.value;
    final key = activeDraftKey.value ?? VisitDraftKey.fromContext(context);
    if (activeDraftKey.value != key) {
      activeDraftKey.value = key;
    }
    _persistQueue = (_persistQueue ?? Future<void>.value()).then((_) async {
      CamPerf.stage(null, 'PERSIST_QUEUE_WAIT_END', usePhotoClock: true);
      await _store.saveDraft(
        snapshot,
        startedAt: startedAt,
        siteName: siteName,
        context: context,
        key: key,
        batchNote: note,
        generalNote: general,
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

    final captureKey = item.captureId?.trim();
    if (captureKey != null && captureKey.isNotEmpty) {
      final existingById = findByCaptureId(captureKey);
      if (existingById != null && persistToDraftStore == false) {
        _txnLog('DUPLICATE_IGNORED id=$captureKey path=${existingById.path}');
        return existingById;
      }
    }

    String durablePath = item.path;
    if (persistToDraftStore) {
      try {
        durablePath = await _store.importMediaFile(
          sourcePath: item.path,
          type: item.type,
          captureId: item.captureId,
        );
      } catch (_) {
        if (!await File(item.path).exists()) return null;
      }
    } else if (!await File(item.path).exists()) {
      return null;
    }

    final durableItem = item.copyWith(
      path: durablePath,
      siteCheckpointId: item.siteCheckpointId ?? activeCheckpointId.value,
    );
    _startedAt ??= durableItem.capturedAt ?? DateTime.now();
    if (patrolContext.value?.clientDraftId == null ||
        patrolContext.value!.clientDraftId!.trim().isEmpty) {
      ensureClientDraftId();
    }
    _upsertMediaItem(durableItem);
    await _persistDraft();
    return durableItem;
  }

  Future<VisitMediaItem?> registerCaptureDraft(VisitMediaItem item) {
    final id = item.captureId?.trim();
    CamPerf.stage(id, 'REGISTER_CAPTURE_DRAFT_START');
    if (id != null && id.isNotEmpty) {
      final existing = findByCaptureId(id);
      if (existing != null) {
        _txnLog('DUPLICATE_IGNORED id=$id (register)');
        CamPerf.stage(
          id,
          'REGISTER_CAPTURE_DRAFT_END',
          detail: 'duplicateIgnored',
        );
        return Future.value(existing);
      }
    }
    _txnLog('CREATED id=${item.captureId} path=${item.path} pending=true');
    return addMediaItem(
      item.copyWith(isPendingCapture: true),
      persistToDraftStore: false,
    ).then((value) {
      CamPerf.stage(id, 'REGISTER_CAPTURE_DRAFT_END');
      return value;
    });
  }

  Future<VisitMediaItem?> finalizeCaptureDraft({
    required String previewPath,
    required VisitMediaType type,
    VisitMediaGeo? geo,
    String? captureId,
    bool markAccepted = false,
  }) async {
    final key = (captureId != null && captureId.trim().isNotEmpty)
        ? captureId.trim()
        : previewPath;
    CamPerf.stage(
      key,
      'FINALIZE_CAPTURE_DRAFT_START',
      detail: 'markAccepted=$markAccepted mediaType=${type.name}',
      usePhotoClock: true,
    );
    final existingFlight = _finalizeInFlight[key];
    CamPerf.stage(
      key,
      'FINALIZE_INFLIGHT_FOUND',
      detail: 'value=${existingFlight != null}',
      usePhotoClock: true,
    );
    if (existingFlight != null) {
      _txnLog('DUPLICATE_IGNORED id=$key (finalize in-flight)');
      CamPerf.stage(key, 'FINALIZE_AWAIT_INFLIGHT_START', usePhotoClock: true);
      final existing = await existingFlight;
      CamPerf.stage(
        key,
        'FINALIZE_AWAIT_INFLIGHT_END',
        detail: 'pending=${existing?.isPendingCapture}',
        usePhotoClock: true,
      );
      if (existing != null && markAccepted && existing.isPendingCapture) {
        return _markAccepted(existing, geo: geo);
      }
      if (existing != null && markAccepted && !existing.isPendingCapture) {
        CamPerf.stage(key, 'FINALIZE_ALREADY_ACCEPTED', usePhotoClock: true);
        if (geo != null) {
          await updateCaptureGeo(
            mediaPath: existing.path,
            geo: geo,
            captureId: existing.captureId,
          );
        }
        return existing;
      }
      CamPerf.stage(
        key,
        'FINALIZE_CAPTURE_DRAFT_END',
        detail: 'awaitedInflight',
        usePhotoClock: true,
      );
      return existing;
    }

    final future = _finalizeCaptureDraftLocked(
      previewPath: previewPath,
      type: type,
      geo: geo,
      captureId: captureId,
      markAccepted: markAccepted,
    );
    _finalizeInFlight[key] = future;
    try {
      final result = await future;
      CamPerf.stage(key, 'FINALIZE_CAPTURE_DRAFT_END', usePhotoClock: true);
      return result;
    } finally {
      if (identical(_finalizeInFlight[key], future)) {
        _finalizeInFlight.remove(key);
      }
    }
  }

  Future<VisitMediaItem?> _finalizeCaptureDraftLocked({
    required String previewPath,
    required VisitMediaType type,
    VisitMediaGeo? geo,
    String? captureId,
    bool markAccepted = false,
  }) async {
    final id = captureId?.trim();
    final index = _indexForCapture(captureId: id, path: previewPath);
    final existing = index >= 0 ? mediaItems[index] : null;

    if (existing != null &&
        _store.isManagedPath(existing.path) &&
        await _fileReady(existing.path)) {
      _txnLog('FINALIZE_COMPLETE id=$id media reused path=${existing.path}');
      CamPerf.stage(
        id,
        'FINALIZE_REUSE_DURABLE',
        detail: 'path=${existing.path} markAccepted=$markAccepted',
        usePhotoClock: true,
      );
      if (markAccepted) {
        return _markAccepted(existing, geo: geo);
      }
      final reused = existing.copyWith(
        capturedAt: geo?.capturedAt ?? existing.capturedAt,
        latitude: geo?.latitude ?? existing.latitude,
        longitude: geo?.longitude ?? existing.longitude,
        accuracyMeters: geo?.accuracyMeters ?? existing.accuracyMeters,
        isPendingCapture: existing.isPendingCapture,
      );
      CamPerf.stage(id, 'MEDIA_ITEM_UPSERT_START', usePhotoClock: true);
      if (index >= 0) mediaItems[index] = reused;
      CamPerf.stage(id, 'MEDIA_ITEM_UPSERT_END', usePhotoClock: true);
      _removeGhostPaths(
        keepCaptureId: reused.captureId,
        removePath: previewPath,
        keepPath: reused.path,
      );
      await _persistDraft();
      return reused;
    }

    _txnLog('IMPORT_START id=$id path=$previewPath');
    String durablePath = previewPath;
    try {
      durablePath = await _store.importMediaFile(
        sourcePath: previewPath,
        type: type,
        captureId: id ?? existing?.captureId,
        deleteSource: false,
      );
      _txnLog('IMPORT_DEST id=$id path=$durablePath');
    } catch (error) {
      _txnLog('IMPORT_FAILED id=$id error=$error');
      if (!await File(previewPath).exists()) return existing;
      rethrow;
    }

    if (!await _fileReady(durablePath)) {
      _txnLog('IMPORT_FAILED id=$id empty or missing dest=$durablePath');
      await _store.deleteQuietly(durablePath);
      throw StateError('Durable media import failed for $previewPath');
    }
    _txnLog('IMPORT_COMPLETE id=$id bytes=${await File(durablePath).length()}');

    final updated =
        (existing ??
                VisitMediaItem(path: durablePath, type: type, captureId: id))
            .copyWith(
              path: durablePath,
              captureId: id ?? existing?.captureId,
              capturedAt: geo?.capturedAt ?? existing?.capturedAt,
              latitude: geo?.latitude ?? existing?.latitude,
              longitude: geo?.longitude ?? existing?.longitude,
              accuracyMeters: geo?.accuracyMeters ?? existing?.accuracyMeters,
              siteCheckpointId:
                  existing?.siteCheckpointId ?? activeCheckpointId.value,
              isPendingCapture: markAccepted
                  ? false
                  : (existing?.isPendingCapture ?? true),
            );

    _txnLog(
      'FINALIZE_${markAccepted ? "COMPLETE" : "READY"} id=$id path=$durablePath',
    );
    CamPerf.stage(id, 'MEDIA_ITEM_UPSERT_START', usePhotoClock: true);
    _upsertMediaItem(updated);
    CamPerf.stage(id, 'MEDIA_ITEM_UPSERT_END', usePhotoClock: true);
    // Drop any ghost rows that still point at the preview temp path.
    _removeGhostPaths(
      keepCaptureId: updated.captureId,
      removePath: previewPath,
      keepPath: durablePath,
    );
    _startedAt ??= updated.capturedAt ?? DateTime.now();
    await _persistDraft();
    return updated;
  }

  Future<VisitMediaItem?> _markAccepted(
    VisitMediaItem item, {
    VisitMediaGeo? geo,
    bool applyRx = true,
  }) async {
    CamPerf.stage(item.captureId, 'MARK_ACCEPTED_START', usePhotoClock: true);
    CamPerf.stage(item.captureId, 'MARK_ACCEPTED_LOOKUP', usePhotoClock: true);
    final index = _indexForCapture(captureId: item.captureId, path: item.path);
    if (index < 0) {
      CamPerf.stage(
        item.captureId,
        'MARK_ACCEPTED_END',
        detail: 'missingIndex',
        usePhotoClock: true,
      );
      return item;
    }
    if (!mediaItems[index].isPendingCapture &&
        geo == null &&
        mediaItems[index].path == item.path) {
      CamPerf.stage(
        item.captureId,
        'MARK_ACCEPTED_END',
        detail: 'noopAlreadyAccepted',
        usePhotoClock: true,
      );
      return mediaItems[index];
    }
    CamPerf.stage(
      item.captureId,
      'MARK_ACCEPTED_COPYWITH',
      usePhotoClock: true,
    );
    final updated = mediaItems[index].copyWith(
      // Prefer the durable path from [item] when warm import already moved it.
      path: item.path,
      capturedAt: geo?.capturedAt ?? item.capturedAt,
      latitude: geo?.latitude ?? item.latitude,
      longitude: geo?.longitude ?? item.longitude,
      accuracyMeters: geo?.accuracyMeters ?? item.accuracyMeters,
      isPendingCapture: false,
    );
    // Commit durable JSON BEFORE Rx mutation so Draft Obx does not rebuild /
    // decode thumbnails while Use Photo is still on the critical path.
    final snapshot = mediaItems.toList(growable: false);
    snapshot[index] = updated;
    CamPerf.stage(
      item.captureId,
      'MARK_ACCEPTED_PERSIST_QUEUE_ENTER',
      usePhotoClock: true,
    );
    await _persistDraftSnapshot(snapshot);
    if (!applyRx) {
      CamPerf.stage(
        item.captureId,
        'MARK_ACCEPTED_RX_DEFERRED',
        detail: 'diskCommitted pendingUiAssign',
        usePhotoClock: true,
      );
      CamPerf.stage(item.captureId, 'MARK_ACCEPTED_END', usePhotoClock: true);
      return updated;
    }
    CamPerf.stage(
      item.captureId,
      'MARK_ACCEPTED_RX_ASSIGN_START',
      detail: 'afterDiskCommit',
      usePhotoClock: true,
    );
    mediaItems[index] = updated;
    CamPerf.stage(
      item.captureId,
      'MARK_ACCEPTED_RX_ASSIGN_END',
      usePhotoClock: true,
    );
    CamPerf.stage(item.captureId, 'MARK_ACCEPTED_END', usePhotoClock: true);
    return updated;
  }

  /// Apply an already-persisted accepted item to the in-memory Draft list.
  void applyAcceptedMediaItem(VisitMediaItem item) {
    CamPerf.stage(
      item.captureId,
      'MARK_ACCEPTED_RX_ASSIGN_START',
      detail: 'afterReviewPop',
      usePhotoClock: true,
    );
    final index = _indexForCapture(captureId: item.captureId, path: item.path);
    if (index < 0) {
      mediaItems.add(item);
    } else {
      mediaItems[index] = item;
    }
    CamPerf.stage(
      item.captureId,
      'MARK_ACCEPTED_RX_ASSIGN_END',
      usePhotoClock: true,
    );
  }

  void removeGhostPreviewPath({
    required String captureId,
    required String previewPath,
    required String keepPath,
  }) {
    _removeGhostPaths(
      keepCaptureId: captureId,
      removePath: previewPath,
      keepPath: keepPath,
    );
  }

  /// Fast Use Photo path when warm durable import already finished.
  Future<VisitMediaItem?> acceptWarmCapture({
    required String captureId,
    required String previewPath,
    VisitMediaGeo? geo,
    bool assumeFileReady = false,
    bool applyRx = true,
  }) async {
    CamPerf.stage(
      captureId,
      'ACCEPT_WARM_FAST_PATH_START',
      usePhotoClock: true,
    );
    final existing = findByCaptureId(captureId) ?? findByPath(previewPath);
    if (existing == null) {
      CamPerf.stage(
        captureId,
        'ACCEPT_WARM_FAST_PATH_FALLBACK',
        detail: 'noExisting',
        usePhotoClock: true,
      );
      return null;
    }
    if (!_store.isManagedPath(existing.path)) {
      CamPerf.stage(
        captureId,
        'ACCEPT_WARM_FAST_PATH_FALLBACK',
        detail: 'notManaged path=${existing.path}',
        usePhotoClock: true,
      );
      return null;
    }
    if (!assumeFileReady) {
      CamPerf.stage(
        captureId,
        'ACCEPT_WARM_FILE_READY_START',
        usePhotoClock: true,
      );
      final ready = await _fileReady(existing.path);
      CamPerf.stage(
        captureId,
        'ACCEPT_WARM_FILE_READY_END',
        detail: 'ready=$ready',
        usePhotoClock: true,
      );
      if (!ready) return null;
    } else {
      CamPerf.stage(
        captureId,
        'ACCEPT_WARM_FILE_READY_SKIPPED',
        detail: 'trustedWarmPersist',
        usePhotoClock: true,
      );
    }
    final accepted = await _markAccepted(existing, geo: geo, applyRx: applyRx);
    if (accepted != null && previewPath != accepted.path && applyRx) {
      _removeGhostPaths(
        keepCaptureId: accepted.captureId,
        removePath: previewPath,
        keepPath: accepted.path,
      );
    }
    return accepted;
  }

  Future<void> updateCaptureGeo({
    required String mediaPath,
    required VisitMediaGeo geo,
    String? captureId,
  }) async {
    final index = _indexForCapture(captureId: captureId, path: mediaPath);
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

  VisitMediaItem? findByCaptureId(String captureId) {
    final id = captureId.trim();
    if (id.isEmpty) return null;
    for (final item in mediaItems) {
      if (item.captureId == id) return item;
    }
    return null;
  }

  /// Rollback a pending capture transaction (Close / Retake).
  Future<void> rollbackCaptureDraft({
    required String captureId,
    String? previewPath,
    String? durablePath,
  }) async {
    final id = captureId.trim();
    _txnLog('CANCEL_ROLLBACK id=$id');
    _finalizeInFlight.remove(id);
    if (previewPath != null) _finalizeInFlight.remove(previewPath);

    final pathsToDelete = <String>{};
    if (previewPath != null && previewPath.trim().isNotEmpty) {
      pathsToDelete.add(previewPath);
    }
    if (durablePath != null && durablePath.trim().isNotEmpty) {
      pathsToDelete.add(durablePath);
    }

    // Remove every row for this captureId (guards against prior duplicates).
    for (var i = mediaItems.length - 1; i >= 0; i--) {
      final item = mediaItems[i];
      final matchId = id.isNotEmpty && item.captureId == id;
      final matchPath = pathsToDelete.contains(item.path);
      if (!matchId && !matchPath) continue;
      pathsToDelete.add(item.path);
      if (item.voiceNotePath != null) {
        await _store.deleteQuietly(item.voiceNotePath);
      }
      _thumbnailFutures.remove(item.path);
      mediaItems.removeAt(i);
    }

    for (final path in pathsToDelete) {
      _txnLog('TEMP_DELETE id=$id path=$path');
      await _store.deleteQuietly(path);
      _thumbnailFutures.remove(path);
    }

    if (mediaItems.isEmpty) {
      _startedAt = null;
    }
    await _persistDraft();
  }

  void _upsertMediaItem(VisitMediaItem item) {
    final index = _indexForCapture(captureId: item.captureId, path: item.path);
    if (index >= 0) {
      mediaItems[index] = item;
    } else {
      mediaItems.add(item);
    }
  }

  int _indexForCapture({String? captureId, required String path}) {
    final id = captureId?.trim();
    if (id != null && id.isNotEmpty) {
      final byId = mediaItems.indexWhere((e) => e.captureId == id);
      if (byId >= 0) return byId;
    }
    return mediaItems.indexWhere((e) => e.path == path);
  }

  void _removeGhostPaths({
    String? keepCaptureId,
    required String removePath,
    required String keepPath,
  }) {
    if (removePath == keepPath) return;
    for (var i = mediaItems.length - 1; i >= 0; i--) {
      final item = mediaItems[i];
      if (item.path != removePath) continue;
      // Orphan row still pointing at the temp preview path.
      mediaItems.removeAt(i);
      _txnLog(
        'GHOST_REMOVED path=$removePath keep=$keepPath id=$keepCaptureId',
      );
    }
  }

  Future<bool> _fileReady(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      return await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  void _txnLog(String message) {
    if (kDebugMode) {
      debugPrint('[CaptureTxn] $message');
    }
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

  Future<void> setMediaAttentionNeeded({
    required String mediaPath,
    required bool attentionNeeded,
  }) async {
    final index = mediaItems.indexWhere((e) => e.path == mediaPath);
    if (index < 0) return;
    if (mediaItems[index].attentionNeeded == attentionNeeded) return;
    mediaItems[index] = mediaItems[index].copyWith(
      attentionNeeded: attentionNeeded,
    );
    await _persistDraft();
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
    final key =
        activeDraftKey.value ?? VisitDraftKey.fromContext(patrolContext.value);
    if (deleteFiles) {
      for (final item in mediaItems) {
        await _store.deleteQuietly(item.voiceNotePath);
        await _store.deleteQuietly(item.path);
      }
      await _store.deleteQuietly(batchNote.value.voiceNotePath);
      await _store.deleteQuietly(generalNote.value.voiceNotePath);
      await _store.clearDraft(deleteFiles: true, key: key);
    } else {
      await _store.clearDraft(deleteFiles: false, key: key);
    }
    _thumbnailFutures.clear();
    mediaItems.clear();
    batchNote.value = const VisitBatchNote();
    generalNote.value = const VisitBatchNote();
    activeCheckpointId.value = null;
    _startedAt = null;
    draftSiteName.value = null;
    draftRegionName.value = null;
    patrolContext.value = null;

    activeDraftKey.value = key;
  }
}
