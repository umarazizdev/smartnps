import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'cam_perf.dart';
import 'visit_patrol_context.dart';
import 'visit_video_flow_controller.dart';

class VisitDraftKey {
  const VisitDraftKey({this.regionId, this.siteId});

  final int? regionId;
  final int? siteId;

  static const unscoped = VisitDraftKey();

  bool get isScoped => regionId != null || siteId != null;

  String get folderName {
    if (!isScoped) return 'unscoped';
    return 'r${regionId ?? 0}_s${siteId ?? 0}';
  }

  static VisitDraftKey fromContext(VisitPatrolContext? context) {
    if (context == null) return unscoped;
    if (context.regionId == null && context.siteId == null) return unscoped;
    return VisitDraftKey(regionId: context.regionId, siteId: context.siteId);
  }

  static VisitDraftKey? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = raw.trim();
    if (value == 'unscoped' || value == 'legacy') return unscoped;
    final match = RegExp(r'^r(\d+)_s(\d+)$').firstMatch(value);
    if (match == null) return null;
    return VisitDraftKey(
      regionId: int.tryParse(match.group(1)!),
      siteId: int.tryParse(match.group(2)!),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VisitDraftKey &&
        other.regionId == regionId &&
        other.siteId == siteId;
  }

  @override
  int get hashCode => Object.hash(regionId, siteId);

  @override
  String toString() => folderName;
}

class VisitMediaDraftSnapshot {
  const VisitMediaDraftSnapshot({
    required this.items,
    required this.draftKey,
    this.startedAt,
    this.siteName,
    this.context,
    this.savedAt,
    this.batchNote = const VisitBatchNote(),
    this.generalNote = const VisitBatchNote(),
  });

  final List<VisitMediaItem> items;
  final VisitDraftKey draftKey;
  final DateTime? startedAt;
  final String? siteName;
  final VisitPatrolContext? context;
  final DateTime? savedAt;
  final VisitBatchNote batchNote;
  final VisitBatchNote generalNote;

  bool get hasItems => items.isNotEmpty;

  String? get displaySiteName {
    final fromContext = context?.displayPlaceName;
    if (fromContext != null && fromContext.isNotEmpty) return fromContext;
    final legacy = siteName?.trim();
    if (legacy == null || legacy.isEmpty) return null;
    return legacy;
  }

  String? get locationLabel {
    final fromContext = context?.locationSubtitle?.trim();
    if (fromContext != null && fromContext.isNotEmpty) return fromContext;
    return displaySiteName;
  }

  int get photoCount => items.where((e) => e.isPhoto).length;
  int get videoCount => items.where((e) => e.isVideo).length;
}

class VisitMediaDraftStore {
  VisitMediaDraftStore._();

  static final VisitMediaDraftStore instance = VisitMediaDraftStore._();

  static const _draftFileName = 'draft.json';
  static const _activeKeyFileName = 'active_key.json';
  static const _rootFolder = 'visit_media_draft';
  static const _legacyAccountsFolder = 'accounts';

  Directory? _root;
  VisitDraftKey _activeKey = VisitDraftKey.unscoped;
  Future<void>? _migrateLegacyFuture;

  VisitDraftKey get activeKey => _activeKey;

  /// Clears cached root/key so tests with a new PathProvider stay isolated.
  @visibleForTesting
  void debugResetForTest() {
    _root = null;
    _activeKey = VisitDraftKey.unscoped;
    _migrateLegacyFuture = null;
  }

  /// Pre-create draft root + media subdirectory while the camera preview is open.
  /// Does not create media rows or touch capture files.
  Future<void> prewarmCaptureContext({
    required VisitDraftKey key,
    required VisitMediaType type,
  }) async {
    await _ensureRoot();
    await setActiveKey(key);
    await _mediaDir(type, key);
  }

  Future<Directory> _ensureRoot() async {
    final cached = _root;
    if (cached != null && await cached.exists()) {
      return cached;
    }

    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/$_rootFolder');
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    _root = root;
    await _migrateLegacyAccountFolders(root);
    await _restoreActiveKey(root);
    return root;
  }

  Future<void> _migrateLegacyAccountFolders(Directory root) async {
    final inFlight = _migrateLegacyFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final completer = Future<void>(() async {
      final accounts = Directory('${root.path}/$_legacyAccountsFolder');
      if (!await accounts.exists()) return;

      try {
        for (final accountEntity in accounts.listSync(followLinks: false)) {
          if (accountEntity is! Directory) continue;
          for (final siteEntity in accountEntity.listSync(followLinks: false)) {
            if (siteEntity is! Directory) continue;
            final name = siteEntity.uri.pathSegments
                .where((e) => e.isNotEmpty)
                .last;
            if (VisitDraftKey.tryParse(name) == null) continue;

            final target = Directory('${root.path}/$name');
            if (await target.exists()) continue;

            try {
              await siteEntity.rename(target.path);
            } catch (_) {
              try {
                await _copyDirectory(siteEntity, target);
                await siteEntity.delete(recursive: true);
              } catch (e) {
                if (kDebugMode) {
                  debugPrint(
                    '[VisitDraftStore] legacy migrate failed for $name: $e',
                  );
                }
              }
            }
          }
        }

        try {
          await accounts.delete(recursive: true);
        } catch (_) {}

        if (kDebugMode) {
          debugPrint('[VisitDraftStore] migrated legacy account folders');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[VisitDraftStore] legacy migrate error: $e');
        }
      }
    });

    _migrateLegacyFuture = completer;
    try {
      await completer;
    } finally {
      _migrateLegacyFuture = null;
    }
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    for (final entity in source.listSync(
      recursive: false,
      followLinks: false,
    )) {
      final name = entity.uri.pathSegments.where((e) => e.isNotEmpty).last;
      if (entity is Directory) {
        await _copyDirectory(entity, Directory('${target.path}/$name'));
      } else if (entity is File) {
        await entity.copy('${target.path}/$name');
      }
    }
  }

  Future<void> _restoreActiveKey(Directory root) async {
    final file = File('${root.path}/$_activeKeyFileName');
    if (!await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        final key = VisitDraftKey.tryParse(decoded['key']?.toString());
        if (key != null) _activeKey = key;
      }
    } catch (_) {}
  }

  Future<void> setActiveKey(VisitDraftKey key, {bool force = false}) async {
    // Warm finalize + Use Photo both call saveDraft; skipping an unchanged
    // active-key flush removes a redundant disk sync on the Done critical path.
    if (!force && _activeKey == key) {
      CamPerf.stage(
        null,
        'SET_ACTIVE_KEY_SKIPPED',
        detail: 'key=${key.folderName}',
        usePhotoClock: true,
      );
      return;
    }
    CamPerf.stage(
      null,
      'SET_ACTIVE_KEY_START',
      detail: 'key=${key.folderName}',
      usePhotoClock: true,
    );
    _activeKey = key;
    final root = await _ensureRoot();
    final file = File('${root.path}/$_activeKeyFileName');
    await file.writeAsString(
      jsonEncode(<String, dynamic>{'key': key.folderName}),
      flush: true,
    );
    CamPerf.stage(null, 'SET_ACTIVE_KEY_END', usePhotoClock: true);
  }

  Future<Directory> _draftDir(VisitDraftKey key, {bool create = true}) async {
    final root = await _ensureRoot();
    final dir = Directory('${root.path}/${key.folderName}');
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _draftFile([VisitDraftKey? key]) async {
    final dir = await _draftDir(key ?? _activeKey);
    return File('${dir.path}/$_draftFileName');
  }

  Future<File?> _draftFileIfExists(VisitDraftKey key) async {
    final root = await _ensureRoot();
    final file = File('${root.path}/${key.folderName}/$_draftFileName');
    if (!await file.exists()) return null;
    return file;
  }

  Future<Directory> _mediaDir(VisitMediaType type, [VisitDraftKey? key]) async {
    final draftDir = await _draftDir(key ?? _activeKey);
    final name = switch (type) {
      VisitMediaType.photo => 'photos',
      VisitMediaType.video => 'videos',
    };
    final dir = Directory('${draftDir.path}/$name');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _voiceDir([VisitDraftKey? key]) async {
    final draftDir = await _draftDir(key ?? _activeKey);
    final dir = Directory('${draftDir.path}/voices');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  bool isManagedPath(String path) {
    final root = _root;
    if (root != null && path.startsWith(root.path)) return true;
    return path.contains('/$_rootFolder/');
  }

  Future<String> importMediaFile({
    required String sourcePath,
    required VisitMediaType type,
    bool deleteSource = true,
    VisitDraftKey? key,
    String? captureId,
  }) async {
    final id = captureId?.trim();
    CamPerf.stage(
      id,
      'IMPORT_MEDIA_FILE_START',
      detail: 'mediaType=${type.name} path=$sourcePath',
      usePhotoClock: true,
    );
    CamPerf.stage(id, 'SOURCE_FILE_STAT_START', usePhotoClock: true);
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('Source media file missing: $sourcePath');
    }
    final sourceBytes = await source.length();
    CamPerf.stage(
      id,
      'SOURCE_FILE_STAT_END',
      detail: 'bytes=$sourceBytes mb=${CamPerf.mb(sourceBytes)}',
      usePhotoClock: true,
    );
    if (sourceBytes <= 0) {
      throw StateError('Source media file empty: $sourcePath');
    }

    if (isManagedPath(sourcePath)) {
      CamPerf.stage(
        id,
        'IMPORT_MEDIA_FILE_END',
        detail: 'alreadyManaged path=$sourcePath',
        usePhotoClock: true,
      );
      return sourcePath;
    }

    final dir = await _mediaDir(type, key);
    CamPerf.stage(
      id,
      'DURABLE_DIRECTORY_READY',
      detail: dir.path,
      usePhotoClock: true,
    );
    final ext = _extensionFor(
      sourcePath,
      fallback: type == VisitMediaType.photo ? '.jpg' : '.mp4',
    );
    final fileId = (id != null && id.isNotEmpty)
        ? id
        : 'media_${DateTime.now().microsecondsSinceEpoch}_'
              '${sourceBytes.toRadixString(16)}';
    final finalPath = '${dir.path}/media_$fileId$ext';
    if (finalPath == sourcePath) {
      return sourcePath;
    }

    // Idempotent: if a prior import already committed this captureId, reuse it.
    final existing = File(finalPath);
    if (await existing.exists() && await existing.length() > 0) {
      CamPerf.stage(
        id,
        'IMPORT_MEDIA_FILE_END',
        detail: 'reuseExisting path=$finalPath',
        usePhotoClock: true,
      );
      if (deleteSource) {
        await deleteQuietly(sourcePath);
      }
      return finalPath;
    }

    final tmpPath = '$finalPath.tmp';
    final tmp = File(tmpPath);
    try {
      if (await tmp.exists()) {
        await tmp.delete();
      }
      CamPerf.stage(id, 'DURABLE_TEMP_COPY_START', usePhotoClock: true);
      final copyStarted = DateTime.now().millisecondsSinceEpoch;
      await source.copy(tmpPath);
      final copyElapsed = DateTime.now().millisecondsSinceEpoch - copyStarted;
      final copiedBytes = await tmp.length();
      CamPerf.stage(
        id,
        'DURABLE_TEMP_COPY_END',
        detail:
            'bytes=$copiedBytes mb=${CamPerf.mb(copiedBytes)} '
            'elapsed=${copyElapsed}ms '
            'throughput=${CamPerf.throughput(copiedBytes, copyElapsed)}',
        usePhotoClock: true,
      );
      if (copiedBytes <= 0) {
        await deleteQuietly(tmpPath);
        throw StateError('Copied media file empty: $tmpPath');
      }
      if (type == VisitMediaType.photo) {
        CamPerf.stage(id, 'DURABLE_FILE_VALIDATION_START', usePhotoClock: true);
        await _assertJpegHeader(tmp);
        CamPerf.stage(id, 'DURABLE_FILE_VALIDATION_END', usePhotoClock: true);
      }

      // Atomic replace into the durable name.
      if (await existing.exists()) {
        await existing.delete();
      }
      CamPerf.stage(id, 'DURABLE_ATOMIC_RENAME_START', usePhotoClock: true);
      await tmp.rename(finalPath);
      CamPerf.stage(id, 'DURABLE_ATOMIC_RENAME_END', usePhotoClock: true);

      final committed = File(finalPath);
      final committedBytes = await committed.exists()
          ? await committed.length()
          : 0;
      CamPerf.stage(
        id,
        'DURABLE_FILE_STAT',
        detail: 'bytes=$committedBytes path=$finalPath',
        usePhotoClock: true,
      );
      if (!await committed.exists() || committedBytes <= 0) {
        throw StateError('Durable rename failed: $finalPath');
      }

      if (deleteSource) {
        CamPerf.stage(id, 'TEMP_DELETE_START', usePhotoClock: true);
        await deleteQuietly(sourcePath);
        CamPerf.stage(id, 'TEMP_DELETE_END', usePhotoClock: true);
      }
      CamPerf.stage(
        id,
        'IMPORT_MEDIA_FILE_END',
        detail: 'path=$finalPath',
        usePhotoClock: true,
      );
      return finalPath;
    } catch (error) {
      await deleteQuietly(tmpPath);
      rethrow;
    }
  }

  /// Lightweight JPEG SOI check — does not decode pixels / mutate bytes.
  Future<void> _assertJpegHeader(File file) async {
    final lower = file.path.toLowerCase();
    if (!lower.endsWith('.jpg') && !lower.endsWith('.jpeg')) return;
    final raf = await file.open();
    try {
      final header = await raf.read(2);
      final isJpeg =
          header.length >= 2 && header[0] == 0xFF && header[1] == 0xD8;
      if (!isJpeg) {
        throw StateError('Invalid JPEG header: ${file.path}');
      }
    } finally {
      await raf.close();
    }
  }

  Future<String> createVoiceRecordingPath({VisitDraftKey? key}) async {
    final dir = await _voiceDir(key);
    return '${dir.path}/visit_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
  }

  Future<String> importVoiceFile(
    String sourcePath, {
    VisitDraftKey? key,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('Source voice file missing: $sourcePath');
    }

    if (isManagedPath(sourcePath)) {
      return sourcePath;
    }

    final dir = await _voiceDir(key);
    final ext = _extensionFor(sourcePath, fallback: '.m4a');
    final targetPath =
        '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}$ext';

    try {
      await source.rename(targetPath);
      return targetPath;
    } catch (_) {
      final target = await source.copy(targetPath);
      try {
        if (await source.exists()) {
          await source.delete();
        }
      } catch (_) {}
      return target.path;
    }
  }

  Future<void> saveDraft(
    List<VisitMediaItem> items, {
    DateTime? startedAt,
    String? siteName,
    VisitPatrolContext? context,
    VisitDraftKey? key,
    VisitBatchNote batchNote = const VisitBatchNote(),
    VisitBatchNote generalNote = const VisitBatchNote(),
  }) async {
    final draftKey = key ?? VisitDraftKey.fromContext(context);

    if (items.isEmpty) {
      await clearDraft(deleteFiles: true, key: draftKey);
      await setActiveKey(draftKey);
      return;
    }

    await setActiveKey(draftKey);

    CamPerf.stage(null, 'DRAFT_FILE_RESOLVE_START', usePhotoClock: true);
    final file = await _draftFile(draftKey);
    CamPerf.stage(null, 'DRAFT_FILE_RESOLVE_END', usePhotoClock: true);
    CamPerf.stage(null, 'DRAFT_PAYLOAD_BUILD_START', usePhotoClock: true);
    final effectiveStartedAt =
        startedAt ??
        items.map((e) => e.capturedAt).whereType<DateTime>().fold<DateTime?>(
          null,
          (best, value) {
            if (best == null || value.isBefore(best)) return value;
            return best;
          },
        );
    final effectiveSiteName = context?.siteName?.trim().isNotEmpty == true
        ? context!.siteName
        : siteName;
    final payload = <String, dynamic>{
      'version': 7,
      'draftKey': draftKey.folderName,
      'savedAt': DateTime.now().toIso8601String(),
      'startedAt': effectiveStartedAt?.toIso8601String(),
      'siteName': effectiveSiteName,
      'context': context?.toJson(),
      'attentionNeeded': batchNote.toJson(),
      'generalNote': generalNote.toJson(),
      'items': items.map(_itemToJson).toList(),
    };
    final encoded = jsonEncode(payload);
    CamPerf.stage(
      null,
      'DRAFT_PAYLOAD_BUILD_END',
      detail: 'jsonBytes=${encoded.length}',
      usePhotoClock: true,
    );
    CamPerf.stage(null, 'DRAFT_PERSIST_START', usePhotoClock: true);
    final started = DateTime.now().millisecondsSinceEpoch;
    await file.writeAsString(encoded, flush: true);
    final elapsed = DateTime.now().millisecondsSinceEpoch - started;
    CamPerf.stage(
      null,
      'DRAFT_PERSIST_END',
      detail:
          'items=${items.length} jsonBytes=${encoded.length} duration=${elapsed}ms',
      usePhotoClock: true,
    );
  }

  Future<VisitMediaDraftSnapshot> loadDraftSnapshot({
    VisitDraftKey? key,
  }) async {
    final draftKey = key ?? _activeKey;
    return _loadSnapshotForKey(draftKey);
  }

  Future<VisitMediaDraftSnapshot> _loadSnapshotForKey(
    VisitDraftKey draftKey,
  ) async {
    final file = await _draftFileIfExists(draftKey);
    if (file == null) {
      return VisitMediaDraftSnapshot(
        items: const <VisitMediaItem>[],
        draftKey: draftKey,
      );
    }

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return VisitMediaDraftSnapshot(
          items: const <VisitMediaItem>[],
          draftKey: draftKey,
        );
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return VisitMediaDraftSnapshot(
          items: const <VisitMediaItem>[],
          draftKey: draftKey,
        );
      }
      final map = Map<String, dynamic>.from(decoded);
      final list = map['items'];
      if (list is! List) {
        return VisitMediaDraftSnapshot(
          items: const <VisitMediaItem>[],
          draftKey: draftKey,
        );
      }

      final items = <VisitMediaItem>[];
      for (final entry in list) {
        if (entry is! Map) continue;
        final item = _itemFromJson(Map<String, dynamic>.from(entry));
        if (item == null) continue;
        final file = File(item.path);
        if (!await file.exists()) {
          if (kDebugMode) {
            debugPrint(
              '[CaptureTxn] DRAFT_LOAD missing path=${item.path} '
              'captureId=${item.captureId}',
            );
          }
          continue;
        }
        final bytes = await file.length();
        if (bytes <= 0) {
          if (kDebugMode) {
            debugPrint(
              '[CaptureTxn] DRAFT_LOAD empty path=${item.path} '
              'captureId=${item.captureId}',
            );
          }
          continue;
        }
        // Incomplete CaptureReview sessions must not resurface as Draft media.
        if (item.isPendingCapture) {
          if (kDebugMode) {
            debugPrint(
              '[CaptureTxn] DRAFT_LOAD drop pending path=${item.path} '
              'captureId=${item.captureId}',
            );
          }
          await deleteQuietly(item.path);
          continue;
        }
        if (kDebugMode) {
          debugPrint(
            '[CaptureTxn] DRAFT_LOAD mediaId=${item.path} '
            'captureId=${item.captureId} exists=true bytes=$bytes',
          );
        }
        final voice = item.voiceNotePath;
        if (voice != null && voice.isNotEmpty && !await File(voice).exists()) {
          items.add(item.copyWith(clearVoiceNote: true));
        } else {
          items.add(item);
        }
      }

      DateTime? startedAt;
      final startedRaw = map['startedAt'];
      if (startedRaw is String && startedRaw.isNotEmpty) {
        startedAt = DateTime.tryParse(startedRaw);
      }
      startedAt ??= items
          .map((e) => e.capturedAt)
          .whereType<DateTime>()
          .fold<DateTime?>(null, (best, value) {
            if (best == null || value.isBefore(best)) return value;
            return best;
          });

      DateTime? savedAt;
      final savedRaw = map['savedAt'];
      if (savedRaw is String && savedRaw.isNotEmpty) {
        savedAt = DateTime.tryParse(savedRaw);
      }

      final legacySiteName = (map['siteName'] as String?)?.trim();
      VisitPatrolContext? context;
      final contextRaw = map['context'];
      if (contextRaw is Map) {
        context = VisitPatrolContext.fromJson(
          Map<String, dynamic>.from(contextRaw),
        );
      }
      if (context == null &&
          legacySiteName != null &&
          legacySiteName.isNotEmpty) {
        context = VisitPatrolContext(siteName: legacySiteName);
      } else if (context != null &&
          (context.siteName == null || context.siteName!.isEmpty) &&
          legacySiteName != null &&
          legacySiteName.isNotEmpty) {
        context = context.copyWith(siteName: legacySiteName);
      }

      final resolvedKey = VisitDraftKey.fromContext(context);
      final effectiveKey = draftKey.isScoped
          ? draftKey
          : (resolvedKey.isScoped ? resolvedKey : draftKey);

      VisitBatchNote batch = const VisitBatchNote();
      final attentionRaw = map['attentionNeeded'] ?? map['batchNote'];
      if (attentionRaw is Map) {
        batch = VisitBatchNote.fromJson(
          Map<String, dynamic>.from(attentionRaw),
        );
        final voice = batch.voiceNotePath;
        if (voice != null && voice.isNotEmpty && !await File(voice).exists()) {
          batch = batch.copyWith(clearVoiceNote: true);
        }
      }

      VisitBatchNote general = const VisitBatchNote();
      final generalRaw = map['generalNote'] ?? map['general_note'];
      if (generalRaw is Map) {
        general = VisitBatchNote.fromJson(
          Map<String, dynamic>.from(generalRaw),
        );
        final voice = general.voiceNotePath;
        if (voice != null && voice.isNotEmpty && !await File(voice).exists()) {
          general = general.copyWith(clearVoiceNote: true);
        }
      }

      return VisitMediaDraftSnapshot(
        items: items,
        draftKey: effectiveKey,
        startedAt: startedAt,
        savedAt: savedAt,
        siteName: (legacySiteName == null || legacySiteName.isEmpty)
            ? context?.siteName
            : legacySiteName,
        context: context,
        batchNote: batch,
        generalNote: general,
      );
    } catch (_) {
      return VisitMediaDraftSnapshot(
        items: const <VisitMediaItem>[],
        draftKey: draftKey,
      );
    }
  }

  Future<List<VisitMediaDraftSnapshot>> listPendingDrafts() async {
    final root = await _ensureRoot();
    final pending = <VisitMediaDraftSnapshot>[];

    for (final entity in root.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = entity.uri.pathSegments.where((e) => e.isNotEmpty).last;
      final key = VisitDraftKey.tryParse(name);
      if (key == null) continue;
      final snapshot = await _loadSnapshotForKey(key);
      if (!snapshot.hasItems) continue;
      pending.add(snapshot);
    }

    pending.sort((a, b) {
      final aTime =
          a.savedAt ?? a.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          b.savedAt ?? b.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return pending;
  }

  Future<bool> hasAnyPendingDraft() async {
    final pending = await listPendingDrafts();
    return pending.isNotEmpty;
  }

  Future<List<VisitMediaItem>> loadDraft({VisitDraftKey? key}) async {
    final snapshot = await loadDraftSnapshot(key: key);
    return snapshot.items;
  }

  Future<bool> hasDraft({VisitDraftKey? key}) async {
    final snapshot = await loadDraftSnapshot(key: key);
    return snapshot.hasItems;
  }

  Future<void> clearDraft({bool deleteFiles = true, VisitDraftKey? key}) async {
    final draftKey = key ?? _activeKey;
    final root = await _ensureRoot();
    final dir = Directory('${root.path}/${draftKey.folderName}');
    final file = File('${dir.path}/$_draftFileName');
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    if (!deleteFiles) return;

    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        for (final entity in dir.listSync(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<void> deleteQuietly(String? path) async {
    if (path == null || path.trim().isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  String _extensionFor(String path, {required String fallback}) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot >= name.length - 1) return fallback;
    return name.substring(dot).toLowerCase();
  }

  Map<String, dynamic> _itemToJson(VisitMediaItem item) {
    return <String, dynamic>{
      'path': item.path,
      'type': item.type.name,
      'captureId': item.captureId,
      'textNote': item.textNote,
      'voiceNotePath': item.voiceNotePath,
      'capturedAt': item.capturedAt?.toIso8601String(),
      'latitude': item.latitude,
      'longitude': item.longitude,
      'accuracyMeters': item.accuracyMeters,
      'siteCheckpointId': item.siteCheckpointId,
      'attentionNeeded': item.attentionNeeded,
      'isPendingCapture': item.isPendingCapture,
    };
  }

  VisitMediaItem? _itemFromJson(Map<String, dynamic> json) {
    final path = (json['path'] as String?)?.trim() ?? '';
    if (path.isEmpty) return null;

    final typeName = (json['type'] as String?)?.trim() ?? 'photo';
    final type = typeName == VisitMediaType.video.name
        ? VisitMediaType.video
        : VisitMediaType.photo;

    DateTime? capturedAt;
    final capturedRaw = json['capturedAt'];
    if (capturedRaw is String && capturedRaw.isNotEmpty) {
      capturedAt = DateTime.tryParse(capturedRaw);
    }

    final checkpointRaw =
        json['siteCheckpointId'] ?? json['site_checkpoint_id'];
    int? siteCheckpointId;
    if (checkpointRaw is int) {
      siteCheckpointId = checkpointRaw;
    } else if (checkpointRaw is num) {
      siteCheckpointId = checkpointRaw.toInt();
    } else if (checkpointRaw != null) {
      siteCheckpointId = int.tryParse(checkpointRaw.toString());
    }

    final attentionRaw = json['attentionNeeded'] ?? json['attention_needed'];
    final attentionNeeded =
        attentionRaw == true ||
        attentionRaw == 1 ||
        attentionRaw == 'yes' ||
        attentionRaw == 'true';

    final pendingRaw = json['isPendingCapture'];
    final isPending =
        pendingRaw == true || pendingRaw == 1 || pendingRaw == 'true';

    return VisitMediaItem(
      path: path,
      type: type,
      captureId: (json['captureId'] as String?)?.trim(),
      textNote: (json['textNote'] as String?) ?? '',
      voiceNotePath: json['voiceNotePath'] as String?,
      capturedAt: capturedAt,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
      siteCheckpointId: siteCheckpointId,
      attentionNeeded: attentionNeeded,
      isPendingCapture: isPending,
    );
  }
}
