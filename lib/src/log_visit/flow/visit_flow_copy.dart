import 'visit_media_draft_store.dart';
import 'visit_patrol_context.dart';

class VisitFlowCopy {
  const VisitFlowCopy({this.isSiteCheck = false});

  factory VisitFlowCopy.fromContext(VisitPatrolContext? context) {
    return VisitFlowCopy(isSiteCheck: context?.isSiteCheck == true);
  }

  factory VisitFlowCopy.fromDraft(VisitMediaDraftSnapshot? draft) {
    return VisitFlowCopy.fromContext(draft?.context);
  }

  factory VisitFlowCopy.fromDrafts(Iterable<VisitMediaDraftSnapshot> drafts) {
    final list = drafts.toList(growable: false);
    if (list.isEmpty) return const VisitFlowCopy();
    return VisitFlowCopy(
      isSiteCheck: list.every((d) => d.context?.isSiteCheck == true),
    );
  }

  final bool isSiteCheck;

  String get draftTitle => isSiteCheck ? 'Site Check Draft' : 'Patrol Draft';

  String get readyToStart =>
      isSiteCheck ? 'Update your site check' : 'Ready to start patrol';

  String get completeReportButton => isSiteCheck ? 'Submit' : 'Complete Report';

  String get completeReportButtonShort =>
      isSiteCheck ? 'Submit' : 'Complete report';

  String get emptyCaptureHint => isSiteCheck
      ? 'Capture a clear photo or hold the capture button to record a site check video.'
      : 'Capture a clear photo or hold the capture button to record a patrol round video.';

  String get roundTagCaptureTitle => 'Select patrol round';

  String get roundTagCaptureMessage =>
      'Choose which round this capture belongs to. '
      'Capture media for every round before uploading.';

  String get roundTagsRequiredTitle => 'All rounds required';

  String get roundTagsProgressTitle => 'Patrol rounds';

  String roundTagsProgressStatus({required int completed, required int total}) {
    if (total <= 0) return '';
    if (completed >= total) return 'All rounds captured';
    if (completed <= 0) {
      return 'Capture media for each round before completing';
    }
    return '$completed of $total rounds captured';
  }

  String roundTagsRequiredHint(Iterable<String> missingTags) {
    final labels = missingTags.map((e) => e.trim()).where((e) => e.isNotEmpty);
    if (labels.isEmpty) {
      return 'Please capture photos or videos for every round, '
          'then complete the report again.';
    }
    return 'Please capture media for: ${labels.join(', ')}.';
  }

  String get emptyRoundTagsHint =>
      'Tap Capture and select a patrol round. '
      'Finish every round before uploading your patrol report.';

  String completionRoundsSummary(Iterable<MapEntry<String, int>> counts) {
    final lines = counts
        .map((e) => e.key)
        .where((e) => e.trim().isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) return '';
    return lines.join('\n');
  }

  String get noLocation =>
      isSiteCheck ? 'No site check location' : 'No patrol location';

  String get checkpointsTitle =>
      isSiteCheck ? 'Site Check Checkpoints' : 'Patrol Checkpoints';

  String get additionalMediaSubtitle => isSiteCheck
      ? 'Optional photos or videos for this site check'
      : 'Optional photos or videos for this patrol';

  String get completionTitle =>
      isSiteCheck ? 'Site check completed?' : 'Patrol Round completed?';

  String get continueReportTitle =>
      isSiteCheck ? 'Continue site check report?' : 'Continue patrol report?';

  String completionMessage(String place) => isSiteCheck
      ? 'Have you done your site check at $place'
      : 'Have you done your patrol round at $place';

  String get yesUploadLabel => isSiteCheck
      ? 'Yes, site check completed upload report'
      : 'Yes, patrol completed upload report';

  String get successTitle =>
      isSiteCheck ? 'Site Check Done' : 'Site Patrol Done';

  String get typeBadgeLabel => isSiteCheck ? 'Site check' : 'Patrol';

  String get unfinishedReportsTitle => isSiteCheck
      ? 'Unfinished site check reports'
      : 'Unfinished patrol reports';

  static const String unfinishedMixedReportsTitle = 'Unfinished reports';

  String get discardTitle =>
      isSiteCheck ? 'Discard site check report?' : 'Discard patrol report?';

  String get noUnfinishedReports => isSiteCheck
      ? 'No unfinished site check reports'
      : 'No unfinished patrol reports';

  String get emptyDraftsBody => isSiteCheck
      ? 'There are no saved site check drafts on this device right now. '
            'Start a new site check to begin capturing your report.'
      : 'There are no saved patrol drafts on this device right now. '
            'Start a new patrol to begin capturing your report.';

  String unfinishedSitesMessage(int count) => isSiteCheck
      ? 'You left unfinished site checks on $count sites. '
            'Choose a site to continue.'
      : 'You left unfinished patrols on $count sites. '
            'Choose a site to continue.';

  static String unfinishedMixedSitesMessage(int count) =>
      'You left unfinished reports on $count sites. '
      'Choose a site to continue.';

  String get uploadFailureSummary => isSiteCheck
      ? 'Something went wrong while uploading this site check report.'
      : 'Something went wrong while uploading this patrol report.';

  String get completedChecklistSemanticLabel => isSiteCheck
      ? 'Completed site check checklist'
      : 'Completed patrol checklist';

  String deleteMediaMessage({required bool isPhoto, required bool hasNotes}) {
    final media = isPhoto ? 'photo' : 'video';
    final report = isSiteCheck ? 'site check report' : 'patrol round report';
    if (hasNotes) {
      return 'This $media and its note will be removed from your $report. '
          'This cannot be undone.';
    }
    return 'This $media will be removed from your $report. '
        'This cannot be undone.';
  }

  String minimumPhotosBody(int count, String photoLabel) => isSiteCheck
      ? 'This site requires $count $photoLabel for the site check report.'
      : 'This site requires $count $photoLabel for the patrol report.';

  String continueReportMessage({
    required String? location,
    required int checkpointTotal,
    required int checkpointCompleted,
  }) {
    final place = location?.trim();
    final atPlace = (place != null && place.isNotEmpty) ? ' at $place' : '';
    final report = isSiteCheck ? 'site check report' : 'patrol report';
    if (checkpointTotal > 0) {
      final remaining = checkpointTotal - checkpointCompleted;
      if (checkpointCompleted <= 0) {
        return 'Your $report$atPlace is still in progress. '
            'Continue to capture the $checkpointTotal '
            'checkpoint${checkpointTotal == 1 ? '' : 's'}.';
      }
      return 'Your $report$atPlace is still in progress. '
          '$checkpointCompleted of $checkpointTotal '
          'checkpoint${checkpointTotal == 1 ? '' : 's'} done — '
          '$remaining remaining. Continue to finish capturing.';
    }
    return 'Your $report$atPlace is still in progress. '
        'Continue to finish capturing media.';
  }
}
