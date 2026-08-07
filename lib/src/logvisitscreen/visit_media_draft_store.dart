import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
  });

  final List<VisitMediaItem> items;
  final VisitDraftKey draftKey;
  final DateTime? startedAt;
  final String? siteName;
  final VisitPatrolContext? context;
  final DateTime? savedAt;
  final VisitBatchNote batchNote;

  bool get hasItems => items.isNotEmpty;

  String? get displaySiteName {
    final fromContext = context?.displayPlaceName;
    if (fromContext != null && fromContext.isNotEmpty) return fromContext;
    final legacy = siteName?.trim();
    if (legacy == null || legacy.isEmpty) return null;
    return legacy;
  }

  /// "Site · Region" when both exist.
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

  /// Moves site drafts out of the old `accounts/{officerId}/` layout into the
  /// shared root. Existing site folders win if already present.
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
    for (final entity in source.listSync(recursive: false, followLinks: false)) {
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

  Future<void> setActiveKey(VisitDraftKey key) async {
    _activeKey = key;
    final root = await _ensureRoot();
    final file = File('${root.path}/$_activeKeyFileName');
    await file.writeAsString(
      jsonEncode(<String, dynamic>{'key': key.folderName}),
      flush: true,
    );
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
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('Source media file missing: $sourcePath');
    }

    if (isManagedPath(sourcePath)) {
      return sourcePath;
    }

    final dir = await _mediaDir(type, key);
    final ext = _extensionFor(
      sourcePath,
      fallback: type == VisitMediaType.photo ? '.jpg' : '.mp4',
    );
    final targetPath =
        '${dir.path}/media_${DateTime.now().microsecondsSinceEpoch}$ext';

    if (!deleteSource) {
      final target = await source.copy(targetPath);
      return target.path;
    }

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
  }) async {
    final draftKey = key ?? VisitDraftKey.fromContext(context);
    // Never create an on-disk draft until something is captured.
    if (items.isEmpty) {
      await clearDraft(deleteFiles: true, key: draftKey);
      await setActiveKey(draftKey);
      return;
    }

    await setActiveKey(draftKey);

    final file = await _draftFile(draftKey);
    final effectiveStartedAt = startedAt ??
        items
            .map((e) => e.capturedAt)
            .whereType<DateTime>()
            .fold<DateTime?>(null, (best, value) {
              if (best == null || value.isBefore(best)) return value;
              return best;
            });
    final effectiveSiteName =
        context?.siteName?.trim().isNotEmpty == true
            ? context!.siteName
            : siteName;
    final payload = <String, dynamic>{
      'version': 6,
      'draftKey': draftKey.folderName,
      'savedAt': DateTime.now().toIso8601String(),
      'startedAt': effectiveStartedAt?.toIso8601String(),
      'siteName': effectiveSiteName,
      'context': context?.toJson(),
      'attentionNeeded': batchNote.toJson(),
      'items': items.map(_itemToJson).toList(),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<VisitMediaDraftSnapshot> loadDraftSnapshot({VisitDraftKey? key}) async {
    final draftKey = key ?? _activeKey;
    return _loadSnapshotForKey(draftKey);
  }

  Future<VisitMediaDraftSnapshot> _loadSnapshotForKey(VisitDraftKey draftKey) async {
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
        if (!await File(item.path).exists()) continue;
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
      final effectiveKey =
          draftKey.isScoped ? draftKey : (resolvedKey.isScoped ? resolvedKey : draftKey);

      VisitBatchNote batch = const VisitBatchNote();
      final attentionRaw = map['attentionNeeded'] ?? map['batchNote'];
      if (attentionRaw is Map) {
        batch = VisitBatchNote.fromJson(Map<String, dynamic>.from(attentionRaw));
        final voice = batch.voiceNotePath;
        if (voice != null &&
            voice.isNotEmpty &&
            !await File(voice).exists()) {
          batch = batch.copyWith(clearVoiceNote: true);
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
      );
    } catch (_) {
      return VisitMediaDraftSnapshot(
        items: const <VisitMediaItem>[],
        draftKey: draftKey,
      );
    }
  }

  /// All unfinished site drafts on this device.
  Future<List<VisitMediaDraftSnapshot>> listPendingDrafts() async {
    final root = await _ensureRoot();
    final pending = <VisitMediaDraftSnapshot>[];

    for (final entity in root.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = entity.uri.pathSegments
          .where((e) => e.isNotEmpty)
          .last;
      final key = VisitDraftKey.tryParse(name);
      if (key == null) continue;
      final snapshot = await _loadSnapshotForKey(key);
      if (!snapshot.hasItems) continue;
      pending.add(snapshot);
    }

    pending.sort((a, b) {
      final aTime = a.savedAt ?? a.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.savedAt ?? b.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
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

  Future<void> clearDraft({
    bool deleteFiles = true,
    VisitDraftKey? key,
  }) async {
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
        for (final entity in dir.listSync(recursive: true, followLinks: false)) {
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
      'textNote': item.textNote,
      'voiceNotePath': item.voiceNotePath,
      'capturedAt': item.capturedAt?.toIso8601String(),
      'latitude': item.latitude,
      'longitude': item.longitude,
      'accuracyMeters': item.accuracyMeters,
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

    return VisitMediaItem(
      path: path,
      type: type,
      textNote: (json['textNote'] as String?) ?? '',
      voiceNotePath: json['voiceNotePath'] as String?,
      capturedAt: capturedAt,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
    );
  }
}
