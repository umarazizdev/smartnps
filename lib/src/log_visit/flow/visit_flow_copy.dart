import 'visit_flow_kind.dart';
import 'visit_media_draft_store.dart';
import 'visit_patrol_context.dart';

class VisitFlowCopy {
  const VisitFlowCopy({
    VisitFlowKind kind = VisitFlowKind.patrol,
    bool isSiteCheck = false,
  }) : kind = isSiteCheck ? VisitFlowKind.siteCheck : kind;

  factory VisitFlowCopy.fromContext(VisitPatrolContext? context) {
    return VisitFlowCopy(kind: context?.flowKind ?? VisitFlowKind.patrol);
  }

  factory VisitFlowCopy.fromDraft(VisitMediaDraftSnapshot? draft) {
    return VisitFlowCopy.fromContext(draft?.context);
  }

  factory VisitFlowCopy.fromDrafts(Iterable<VisitMediaDraftSnapshot> drafts) {
    final list = drafts.toList(growable: false);
    if (list.isEmpty) return const VisitFlowCopy();
    final kinds = list.map((d) => d.context?.flowKind ?? VisitFlowKind.patrol);
    final first = kinds.first;
    if (kinds.every((k) => k == first)) {
      return VisitFlowCopy(kind: first);
    }
    return const VisitFlowCopy();
  }

  final VisitFlowKind kind;

  bool get isSiteCheck => kind == VisitFlowKind.siteCheck;
  bool get isIssueReport => kind == VisitFlowKind.issueReport;
  bool get isIncidentReport => kind == VisitFlowKind.incidentReport;
  bool get isStructuredReport => kind.isStructuredReport;

  String get draftTitle {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'Site Check Draft';
      case VisitFlowKind.issueReport:
        return 'Issue Report Draft';
      case VisitFlowKind.incidentReport:
        return 'Incident Report Draft';
      case VisitFlowKind.patrol:
        return 'Patrol Draft';
    }
  }

  String get readyToStart {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'Update your site check';
      case VisitFlowKind.issueReport:
        return 'Ready to report an issue';
      case VisitFlowKind.incidentReport:
        return 'Ready to document an incident';
      case VisitFlowKind.patrol:
        return 'Ready to start patrol';
    }
  }

  String get preparingReportTitle {
    switch (kind) {
      case VisitFlowKind.issueReport:
        return 'Starting issue report';
      case VisitFlowKind.incidentReport:
        return 'Starting incident report';
      case VisitFlowKind.siteCheck:
        return 'Starting site check';
      case VisitFlowKind.patrol:
        return 'Starting patrol';
    }
  }

  String get preparingReportMessage {
    switch (kind) {
      case VisitFlowKind.issueReport:
      case VisitFlowKind.incidentReport:
        return 'Authorizing this draft with the server…';
      case VisitFlowKind.siteCheck:
      case VisitFlowKind.patrol:
        return 'Preparing your draft…';
    }
  }

  String get completeReportButton {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'Submit';
      case VisitFlowKind.issueReport:
        return 'Submit Issue';
      case VisitFlowKind.incidentReport:
        return 'Submit Incident';
      case VisitFlowKind.patrol:
        return 'Complete Report';
    }
  }

  String get completeReportButtonShort {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'Submit';
      case VisitFlowKind.issueReport:
        return 'Submit issue';
      case VisitFlowKind.incidentReport:
        return 'Submit incident';
      case VisitFlowKind.patrol:
        return 'Complete report';
    }
  }

  String get emptyCaptureHint {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'Capture a clear photo or hold the capture button to record a site check video.';
      case VisitFlowKind.issueReport:
        return 'Capture photos or video of the issue, then fill in the report fields above.';
      case VisitFlowKind.incidentReport:
        return 'Capture photos or video of the incident, then fill in the report fields above.';
      case VisitFlowKind.patrol:
        return 'Capture a clear photo or hold the capture button to record a patrol round video.';
    }
  }

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

  String get noLocation {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'No site check location';
      case VisitFlowKind.issueReport:
        return 'No issue location';
      case VisitFlowKind.incidentReport:
        return 'No incident location';
      case VisitFlowKind.patrol:
        return 'No patrol location';
    }
  }

  String get checkpointsTitle =>
      isSiteCheck ? 'Site Check Checkpoints' : 'Patrol Checkpoints';

  String get additionalMediaSubtitle {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'Optional photos or videos for this site check';
      case VisitFlowKind.issueReport:
        return 'Photos or videos for this issue report';
      case VisitFlowKind.incidentReport:
        return 'Photos or videos for this incident report';
      case VisitFlowKind.patrol:
        return 'Optional photos or videos for this patrol';
    }
  }

  String get completionTitle {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'Site check completed?';
      case VisitFlowKind.issueReport:
        return 'Submit issue report?';
      case VisitFlowKind.incidentReport:
        return 'Submit incident report?';
      case VisitFlowKind.patrol:
        return 'Patrol Round completed?';
    }
  }

  String get continueReportTitle {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'Continue site check report?';
      case VisitFlowKind.issueReport:
        return 'Continue issue report?';
      case VisitFlowKind.incidentReport:
        return 'Continue incident report?';
      case VisitFlowKind.patrol:
        return 'Continue patrol report?';
    }
  }

  String completionMessage(String place) {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'Have you done your site check at $place';
      case VisitFlowKind.issueReport:
        return 'Ready to submit this issue report for $place?';
      case VisitFlowKind.incidentReport:
        return 'Ready to submit this incident report for $place?';
      case VisitFlowKind.patrol:
        return 'Have you done your patrol round at $place';
    }
  }

  String get yesUploadLabel {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'Yes, site check completed upload report';
      case VisitFlowKind.issueReport:
        return 'Yes, submit issue report';
      case VisitFlowKind.incidentReport:
        return 'Yes, submit incident report';
      case VisitFlowKind.patrol:
        return 'Yes, patrol completed upload report';
    }
  }

  String get successTitle {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'Site Check Done';
      case VisitFlowKind.issueReport:
        return 'Issue Reported';
      case VisitFlowKind.incidentReport:
        return 'Incident Reported';
      case VisitFlowKind.patrol:
        return 'Site Patrol Done';
    }
  }

  String get typeBadgeLabel {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'Site check';
      case VisitFlowKind.issueReport:
        return 'Issue';
      case VisitFlowKind.incidentReport:
        return 'Incident';
      case VisitFlowKind.patrol:
        return 'Patrol';
    }
  }

  String get unfinishedReportsTitle {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'Unfinished site check reports';
      case VisitFlowKind.issueReport:
        return 'Unfinished issue reports';
      case VisitFlowKind.incidentReport:
        return 'Unfinished incident reports';
      case VisitFlowKind.patrol:
        return 'Unfinished patrol reports';
    }
  }

  static const String unfinishedMixedReportsTitle = 'Unfinished reports';

  String get discardTitle {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'Discard site check report?';
      case VisitFlowKind.issueReport:
        return 'Discard issue report?';
      case VisitFlowKind.incidentReport:
        return 'Discard incident report?';
      case VisitFlowKind.patrol:
        return 'Discard patrol report?';
    }
  }

  String get noUnfinishedReports {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'No unfinished site check reports';
      case VisitFlowKind.issueReport:
        return 'No unfinished issue reports';
      case VisitFlowKind.incidentReport:
        return 'No unfinished incident reports';
      case VisitFlowKind.patrol:
        return 'No unfinished patrol reports';
    }
  }

  String get emptyDraftsBody {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'There are no saved site check drafts on this device right now. '
            'Start a new site check to begin capturing your report.';
      case VisitFlowKind.issueReport:
        return 'There are no saved issue report drafts on this device right now. '
            'Start a new issue report to begin.';
      case VisitFlowKind.incidentReport:
        return 'There are no saved incident report drafts on this device right now. '
            'Start a new incident report to begin.';
      case VisitFlowKind.patrol:
        return 'There are no saved patrol drafts on this device right now. '
            'Start a new patrol to begin capturing your report.';
    }
  }

  String unfinishedSitesMessage(int count) {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'You left unfinished site checks on $count sites. '
            'Choose a site to continue.';
      case VisitFlowKind.issueReport:
        return 'You left unfinished issue reports on $count sites. '
            'Choose a site to continue.';
      case VisitFlowKind.incidentReport:
        return 'You left unfinished incident reports on $count sites. '
            'Choose a site to continue.';
      case VisitFlowKind.patrol:
        return 'You left unfinished patrols on $count sites. '
            'Choose a site to continue.';
    }
  }

  static String unfinishedMixedSitesMessage(int count) =>
      unfinishedMixedReportsMessage(count);

  static String unfinishedMixedReportsMessage(int count) {
    if (count <= 1) {
      return 'You have an unfinished report. Choose it to continue.';
    }
    return 'You have $count unfinished reports. '
        'Choose one to continue.';
  }

  String incompleteReportDetailsMessage(String? location) {
    final place = location?.trim();
    final atPlace = (place != null && place.isNotEmpty) ? ' at $place' : '';
    switch (kind) {
      case VisitFlowKind.issueReport:
        return 'Your issue report$atPlace still needs title, category, and details. '
            'Continue to finish the form and media.';
      case VisitFlowKind.incidentReport:
        return 'Your incident report$atPlace still needs title and description. '
            'Continue to finish the form and media.';
      case VisitFlowKind.siteCheck:
      case VisitFlowKind.patrol:
        return continueReportMessage(
          location: location,
          checkpointTotal: 0,
          checkpointCompleted: 0,
        );
    }
  }

  String get uploadFailureSummary {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'Something went wrong while uploading this site check report.';
      case VisitFlowKind.issueReport:
        return 'Something went wrong while uploading this issue report.';
      case VisitFlowKind.incidentReport:
        return 'Something went wrong while uploading this incident report.';
      case VisitFlowKind.patrol:
        return 'Something went wrong while uploading this patrol report.';
    }
  }

  String get completedChecklistSemanticLabel => isSiteCheck
      ? 'Completed site check checklist'
      : 'Completed patrol checklist';

  String deleteMediaMessage({required bool isPhoto, required bool hasNotes}) {
    final media = isPhoto ? 'photo' : 'video';
    final String report;
    switch (kind) {
      case VisitFlowKind.siteCheck:
        report = 'site check report';
      case VisitFlowKind.issueReport:
        report = 'issue report';
      case VisitFlowKind.incidentReport:
        report = 'incident report';
      case VisitFlowKind.patrol:
        report = 'patrol round report';
    }
    if (hasNotes) {
      return 'This $media and its note will be removed from your $report. '
          'This cannot be undone.';
    }
    return 'This $media will be removed from your $report. '
        'This cannot be undone.';
  }

  String minimumPhotosBody(int count, String photoLabel) {
    switch (kind) {
      case VisitFlowKind.siteCheck:
        return 'This site requires $count $photoLabel for the site check report.';
      case VisitFlowKind.issueReport:
        return 'This site requires $count $photoLabel for the issue report.';
      case VisitFlowKind.incidentReport:
        return 'This site requires $count $photoLabel for the incident report.';
      case VisitFlowKind.patrol:
        return 'This site requires $count $photoLabel for the patrol report.';
    }
  }

  String continueReportMessage({
    required String? location,
    required int checkpointTotal,
    required int checkpointCompleted,
  }) {
    final place = location?.trim();
    final atPlace = (place != null && place.isNotEmpty) ? ' at $place' : '';
    final String report;
    switch (kind) {
      case VisitFlowKind.siteCheck:
        report = 'site check report';
      case VisitFlowKind.issueReport:
        report = 'issue report';
      case VisitFlowKind.incidentReport:
        report = 'incident report';
      case VisitFlowKind.patrol:
        report = 'patrol report';
    }
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
