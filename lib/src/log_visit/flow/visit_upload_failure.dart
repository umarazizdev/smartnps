import '../../api/visit_upload_api.dart';
import 'visit_checkpoint.dart';
import 'visit_media_draft_store.dart';
import 'visit_video_flow_controller.dart';

class VisitUploadFailurePresentation {
  const VisitUploadFailurePresentation({
    required this.title,
    required this.summary,
    this.guidance = '',
    this.affectedLabels = const <String>[],
    this.affectedItemIndexes = const <int>[],
    this.primaryItemIndex,
    this.isGeofence = false,
  });

  final String title;
  final String summary;
  final String guidance;
  final List<String> affectedLabels;
  final List<int> affectedItemIndexes;
  final int? primaryItemIndex;
  final bool isGeofence;

  bool get canFixMedia => primaryItemIndex != null;

  VisitDraftLastUploadIssue toDraftIssue({DateTime? occurredAt}) {
    return VisitDraftLastUploadIssue(
      title: title.trim().isEmpty ? 'Upload failed' : title.trim(),
      summary: summary.trim(),
      isGeofence: isGeofence,
      occurredAt: occurredAt ?? DateTime.now(),
    );
  }
}

class VisitUploadFailure {
  VisitUploadFailure._();

  static VisitUploadFailurePresentation present({
    required VisitUploadResult result,
    required List<VisitMediaItem> mediaItems,
    required List<VisitCheckpoint> checkpoints,
  }) {
    final errors = result.errors;
    if (errors == null || errors.isEmpty) {
      return VisitUploadFailurePresentation(
        title: 'Upload failed',
        summary: _cleanMessage(result.displayMessage),
        guidance: 'Please review your report and try again.',
      );
    }

    final itemIndexes = <int>{};
    final checkpointIndexes = <int>{};
    final rawMessages = <String>[];
    var isGeofence = false;

    for (final entry in errors.entries) {
      final key = entry.key.toString();
      final messages = _asStringList(entry.value);
      rawMessages.addAll(messages);

      final itemMatch = RegExp(r'^items\.(\d+)').firstMatch(key);
      if (itemMatch != null) {
        itemIndexes.add(int.parse(itemMatch.group(1)!));
      }

      final checkpointMatch = RegExp(r'^checkpoints\.(\d+)').firstMatch(key);
      if (checkpointMatch != null) {
        checkpointIndexes.add(int.parse(checkpointMatch.group(1)!));
      }

      if (key.contains('geofence') ||
          messages.any((m) => m.toLowerCase().contains('geofence'))) {
        isGeofence = true;
      }
    }

    final resolvedItemIndexes = <int>{...itemIndexes};
    final completed = _completedCheckpoints(mediaItems, checkpoints);
    for (final index in checkpointIndexes) {
      if (index < 0 || index >= completed.length) continue;
      final checkpoint = completed[index];
      final photoIndex = mediaItems.indexWhere(
        (e) => e.siteCheckpointId == checkpoint.id && e.isPhoto,
      );
      if (photoIndex >= 0) resolvedItemIndexes.add(photoIndex);
    }

    final sortedIndexes = resolvedItemIndexes.toList()..sort();
    final affected = <String>[
      for (final index in sortedIndexes)
        _mediaLabel(mediaItems, checkpoints, index),
    ];

    final detail = _preferOfficerMessage(rawMessages);
    final primary = sortedIndexes.isEmpty ? null : sortedIndexes.first;

    if (isGeofence) {
      return VisitUploadFailurePresentation(
        title: 'Outside site geofence',
        summary: detail.isNotEmpty
            ? detail
            : 'This capture GPS is outside the assigned site geofence.',
        guidance:
            'Move closer to the site and retake the affected media.\n'
            'If the site geofence looks wrong, contact Dispatch.',
        affectedLabels: affected,
        affectedItemIndexes: sortedIndexes,
        primaryItemIndex: primary,
        isGeofence: true,
      );
    }

    return VisitUploadFailurePresentation(
      title: 'Upload failed',
      summary: detail.isNotEmpty
          ? detail
          : _cleanMessage(result.displayMessage),
      guidance: primary == null
          ? 'Please review your report and try again.'
          : 'Delete or retake the affected media, then upload again.',
      affectedLabels: affected,
      affectedItemIndexes: sortedIndexes,
      primaryItemIndex: primary,
      isGeofence: false,
    );
  }

  static VisitUploadFailurePresentation presentUnexpected(Object _) {
    return const VisitUploadFailurePresentation(
      title: 'Upload failed',
      summary: 'Something went wrong while uploading this patrol report.',
      guidance: 'Please review your report and try again.',
    );
  }

  static String _mediaLabel(
    List<VisitMediaItem> mediaItems,
    List<VisitCheckpoint> checkpoints,
    int index,
  ) {
    if (index < 0 || index >= mediaItems.length) {
      return 'Media ${index + 1}';
    }
    final item = mediaItems[index];
    final kind = item.isPhoto ? 'Photo' : 'Video';

    if (item.siteCheckpointId != null) {
      VisitCheckpoint? checkpoint;
      for (final candidate in checkpoints) {
        if (candidate.id == item.siteCheckpointId) {
          checkpoint = candidate;
          break;
        }
      }
      final name = checkpoint?.name.trim();
      if (name != null && name.isNotEmpty) {
        return '$kind · $name checkpoint';
      }
      return '$kind · Checkpoint';
    }

    final additional = mediaItems
        .where((e) => e.isAdditionalMedia && !e.isPendingCapture)
        .toList(growable: false);
    final pos = additional.indexWhere(
      (e) =>
          (item.captureId != null &&
              e.captureId != null &&
              e.captureId == item.captureId) ||
          e.path == item.path,
    );
    final number = pos >= 0 ? pos + 1 : index + 1;
    return '$kind $number (Additional media)';
  }

  static List<VisitCheckpoint> _completedCheckpoints(
    List<VisitMediaItem> mediaItems,
    List<VisitCheckpoint> checkpoints,
  ) {
    final completed = <VisitCheckpoint>[];
    for (final checkpoint in checkpoints) {
      final hasPhoto = mediaItems.any(
        (e) => e.siteCheckpointId == checkpoint.id && e.isPhoto,
      );
      if (hasPhoto) completed.add(checkpoint);
    }
    return completed;
  }

  static List<String> _asStringList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return const <String>[];
    return <String>[text];
  }

  static String _preferOfficerMessage(List<String> messages) {
    final cleaned = messages
        .map(_cleanMessage)
        .where((e) => e.isNotEmpty)
        .where((e) => e.toLowerCase() != 'outside_site_geofence')
        .where((e) => e.toLowerCase() != 'validation failed')
        .toList(growable: false);
    if (cleaned.isEmpty) return '';

    final geo = cleaned.where((e) => e.toLowerCase().contains('geofence'));
    if (geo.isNotEmpty) return geo.first;

    final seen = <String>{};
    final unique = <String>[];
    for (final message in cleaned) {
      if (seen.add(message)) unique.add(message);
    }
    return unique.first;
  }

  static String _cleanMessage(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return '';
    if (text.startsWith('{') && text.contains('items.')) {
      return 'Validation failed';
    }
    return text;
  }
}
