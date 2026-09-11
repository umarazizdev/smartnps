import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_navigator.dart';
import '../../utilities/overlay_prompt_guard.dart';
import '../../widgets/dialogs/glass_action_dialog.dart';
import '../notes/visit_batch_notes_panel.dart';
import '../notes/visit_media_notes_sheet.dart';
import 'visit_media_draft_store.dart';
import 'visit_video_flow_controller.dart';

enum VisitDraftResumeAction { continueReport, submitReport, discardReport }

class VisitDraftResumeResult {
  const VisitDraftResumeResult({required this.action, required this.draft});

  final VisitDraftResumeAction action;
  final VisitMediaDraftSnapshot draft;
}

class VisitDraftResumeDialog {
  VisitDraftResumeDialog._();

  static bool _visible = false;

  static String buildMessage({
    required VisitMediaDraftSnapshot draft,
    String? siteName,
    String? regionName,
    String? locationLabel,
  }) {
    final mediaSummary = _mediaSummary(
      photoCount: draft.photoCount,
      videoCount: draft.videoCount,
    );
    final location = _resolveLocationLabel(
      draft: draft,
      siteName: siteName,
      regionName: regionName,
      locationLabel: locationLabel,
    );
    final started = _formatStarted(draft.startedAt ?? DateTime.now());
    return '$mediaSummary taken at $location, started $started. '
        'Nothing has been submitted yet.';
  }

  static String siteTileSubtitle(VisitMediaDraftSnapshot draft) {
    final mediaSummary = _mediaSummary(
      photoCount: draft.photoCount,
      videoCount: draft.videoCount,
    );
    final started = _formatStarted(draft.startedAt ?? DateTime.now());
    return '$mediaSummary · started $started';
  }

  static String _resolveLocationLabel({
    required VisitMediaDraftSnapshot draft,
    String? siteName,
    String? regionName,
    String? locationLabel,
  }) {
    final explicit = locationLabel?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final site = (siteName ?? draft.context?.siteName ?? draft.siteName)
        ?.trim();
    final region = (regionName ?? draft.context?.regionName)?.trim();
    if (site != null &&
        site.isNotEmpty &&
        region != null &&
        region.isNotEmpty) {
      return '$site · $region';
    }
    if (site != null && site.isNotEmpty) return site;
    if (region != null && region.isNotEmpty) return region;

    final fromDraft = draft.locationLabel?.trim();
    if (fromDraft != null && fromDraft.isNotEmpty) return fromDraft;
    return 'your site';
  }

  static String _mediaSummary({
    required int photoCount,
    required int videoCount,
  }) {
    final parts = <String>[];
    if (photoCount > 0) {
      parts.add('$photoCount photo${photoCount == 1 ? '' : 's'}');
    }
    if (videoCount > 0) {
      parts.add('$videoCount video${videoCount == 1 ? '' : 's'}');
    }
    if (parts.isEmpty) return 'Media';
    if (parts.length == 1) return parts.first;
    return '${parts[0]} and ${parts[1]}';
  }

  static String _formatStarted(DateTime value) {
    final local = value.toLocal();
    final month = local.month;
    final day = local.day;
    final year = (local.year % 100).toString().padLeft(2, '0');
    final hour24 = local.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'pm' : 'am';
    return '$month/$day/$year $hour12:$minute$period';
  }

  static Future<VisitDraftResumeResult?> showPending({
    List<VisitMediaDraftSnapshot>? drafts,
  }) async {
    if (_visible) return null;

    final pending =
        drafts ?? await VisitMediaDraftStore.instance.listPendingDrafts();
    if (pending.isEmpty) return null;

    final context = AppNavigator.key.currentContext;
    if (context == null || !context.mounted) return null;

    await OverlayPromptGuard.waitUntilReady();

    final readyContext = AppNavigator.key.currentContext;
    if (readyContext == null || !readyContext.mounted) return null;

    _visible = true;
    try {
      VisitMediaDraftSnapshot? selected;
      if (pending.length == 1) {
        selected = pending.first;
      } else {
        selected = await _showSitePicker(readyContext, pending);
      }
      if (selected == null) return null;
      final flow = ensureFlowController();
      await flow.activateDraft(selected.draftKey);

      final actionContext = AppNavigator.key.currentContext;
      if (actionContext == null || !actionContext.mounted) return null;

      final action = await _showActionsForDraft(
        actionContext,
        selected,
        flow: flow,
      );
      if (action == null) return null;
      return VisitDraftResumeResult(action: action, draft: selected);
    } finally {
      _visible = false;
    }
  }

  static Future<VisitMediaDraftSnapshot?> _showSitePicker(
    BuildContext context,
    List<VisitMediaDraftSnapshot> drafts,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassActionDialog.showWithActions<VisitMediaDraftSnapshot?>(
      context: context,
      icon: Icons.assignment_late_outlined,
      iconColor: const Color(0xFF3B82F6),
      title: 'Unfinished patrol reports',
      barrierDismissible: true,
      showCloseButton: true,
      closeButtonTooltip: 'Keep drafts for later',
      messageMaxHeightFactor: 0.52,
      content: _PendingSitesList(drafts: drafts, isDark: isDark),
      actions: const [
        GlassDialogAction<VisitMediaDraftSnapshot?>(
          label: 'Not now',
          value: null,
          tone: GlassDialogActionTone.neutral,
        ),
      ],
    );
  }

  static Future<VisitDraftResumeAction?> _showActionsForDraft(
    BuildContext context,
    VisitMediaDraftSnapshot draft, {
    VisitVideoFlowController? flow,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final place = _resolveLocationLabel(draft: draft);
    final activeFlow = flow ?? ensureFlowController();
    final canSubmitReport = !activeFlow.hasIncompleteCheckpoints;
    final lastIssue =
        activeFlow.lastUploadIssue.value ?? draft.lastUploadIssue;
    final viewport = MediaQuery.sizeOf(context);
    final isLandscape = viewport.width > viewport.height;
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.78)
        : const Color(0xFF475467);

    final title = canSubmitReport
        ? 'Patrol Round completed?'
        : 'Continue patrol report?';
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final icon = canSubmitReport
        ? Icons.fact_check_outlined
        : Icons.pending_actions_rounded;
    final iconColor = canSubmitReport
        ? const Color(0xFF3B82F6)
        : const Color(0xFF2563EB);

    final message = canSubmitReport
        ? 'Have you done your patrol round at $place'
        : _continueReportMessage(flow: activeFlow, location: place);

    Future<bool> confirmDiscard() async {
      if (!context.mounted) return false;
      final confirmed = await GlassActionDialog.show(
        context: context,
        icon: Icons.delete_forever_outlined,
        iconColor: const Color(0xFFE53935),
        title: 'Discard patrol report?',
        message:
            'This will permanently delete this draft and all captured photos, videos, and notes. This cannot be undone.',
        secondaryLabel: 'Keep report',
        primaryLabel: 'Discard report',
        variant: GlassActionDialogVariant.error,
        barrierDismissible: true,
        showCloseButton: true,
        useRootNavigator: true,
        maxWidth: isLandscape ? 520 : null,
        insetPadding: isLandscape
            ? const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
            : const EdgeInsets.symmetric(horizontal: 28),
      );
      return confirmed == true;
    }

    return GlassActionDialog.showWithActions<VisitDraftResumeAction>(
      context: context,
      icon: icon,
      iconColor: iconColor,
      iconWidget: canSubmitReport
          ? Image.asset(
              'assets/images/patrol_complete_icon.png',
              width: 34,
              height: 34,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              semanticLabel: 'Completed patrol checklist',
            )
          : null,
      title: title,
      titleColor: titleColor,
      barrierDismissible: true,
      showCloseButton: true,
      closeButtonTooltip: 'Keep as draft',
      messageMaxHeightFactor: 0.58,
      maxWidth: isLandscape ? 680 : null,
      insetPadding: isLandscape
          ? const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
          : const EdgeInsets.symmetric(horizontal: 28),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: bodyColor,
              fontSize: 15,
              height: 1.48,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (lastIssue != null) ...[
            SizedBox(height: isLandscape ? 10 : 12),
            _LastUploadIssueCard(
              issue: lastIssue,
              isDark: isDark,
              compact: isLandscape,
            ),
          ],
          SizedBox(height: isLandscape ? 10 : 12),
          _DraftKeepHint(isDark: isDark, compact: isLandscape),
          if (canSubmitReport) ...[
            SizedBox(height: isLandscape ? 10 : 14),
            VisitBatchNotesPanel(
              flow: activeFlow,
              isDark: isDark,
              scope: VisitBatchNoteScope.generalNote,
              titleOverride: 'Additional note',
              showToggle: false,
              alwaysShowActions: true,
            ),
          ],
        ],
      ),
      actions: [
        if (canSubmitReport) ...[
          const GlassDialogAction(
            label: 'No, view/continue report',
            value: VisitDraftResumeAction.continueReport,
            tone: GlassDialogActionTone.neutral,
            icon: Icons.arrow_back_rounded,
          ),
          const GlassDialogAction(
            label: 'Yes, patrol completed upload report',
            value: VisitDraftResumeAction.submitReport,
            tone: GlassDialogActionTone.primary,
            icon: Icons.cloud_upload_outlined,
          ),
          GlassDialogAction(
            label: 'Discard report',
            value: VisitDraftResumeAction.discardReport,
            tone: GlassDialogActionTone.destructive,
            icon: Icons.delete_outline_rounded,
            beforePop: confirmDiscard,
          ),
        ] else ...[
          const GlassDialogAction(
            label: 'Yes, continue report',
            value: VisitDraftResumeAction.continueReport,
            tone: GlassDialogActionTone.primary,
            icon: Icons.arrow_forward_rounded,
          ),
          GlassDialogAction(
            label: 'Discard report',
            value: VisitDraftResumeAction.discardReport,
            tone: GlassDialogActionTone.destructive,
            icon: Icons.delete_outline_rounded,
            beforePop: confirmDiscard,
          ),
        ],
      ],
    );
  }

  static String _continueReportMessage({
    required VisitVideoFlowController flow,
    String? location,
  }) {
    final place = location?.trim();
    final atPlace = (place != null && place.isNotEmpty) ? ' at $place' : '';
    final total = flow.checkpoints.length;
    final completed = flow.completedCheckpointCount;
    if (total > 0) {
      final remaining = total - completed;
      if (completed <= 0) {
        return 'Your patrol report$atPlace is still in progress. '
            'Continue to capture the $total checkpoint${total == 1 ? '' : 's'}.';
      }
      return 'Your patrol report$atPlace is still in progress. '
          '$completed of $total checkpoint${total == 1 ? '' : 's'} done — '
          '$remaining remaining. Continue to finish capturing.';
    }
    return 'Your patrol report$atPlace is still in progress. '
        'Continue to finish capturing media.';
  }

  static Future<VisitDraftResumeAction?> show({
    required VisitMediaDraftSnapshot draft,
    String? siteName,
    String? regionName,
    String? locationLabel,
  }) async {
    final result = await showPending(drafts: [draft]);
    return result?.action;
  }

  static Future<void> showEmptyState() async {
    if (_visible) return;

    final context = AppNavigator.key.currentContext;
    if (context == null || !context.mounted) return;

    await OverlayPromptGuard.waitUntilReady();

    final readyContext = AppNavigator.key.currentContext;
    if (readyContext == null || !readyContext.mounted) return;

    final isDark = Theme.of(readyContext).brightness == Brightness.dark;
    final viewport = MediaQuery.sizeOf(readyContext);
    final isLandscape = viewport.width > viewport.height;
    final accent = isDark ? const Color(0xFF93C5FD) : const Color(0xFF3B82F6);
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.72)
        : const Color(0xFF64748B);

    _visible = true;
    try {
      await GlassActionDialog.showWithActions<bool>(
        context: readyContext,
        icon: Icons.folder_open_rounded,
        iconColor: accent,
        title: 'No draft saved',
        barrierDismissible: true,
        showCloseButton: true,
        useRootNavigator: true,
        messageMaxHeightFactor: 0.42,
        maxWidth: isLandscape ? 480 : 360,
        insetPadding: isLandscape
            ? const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
            : const EdgeInsets.symmetric(horizontal: 32),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No unfinished patrol reports',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 15.5,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'There are no saved patrol drafts on this device right now. '
              'Start a new patrol to begin capturing your report.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: bodyColor,
                fontSize: 14.5,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: const [
          GlassDialogAction(
            label: 'Okay',
            value: true,
            tone: GlassDialogActionTone.primary,
          ),
        ],
      );
    } finally {
      _visible = false;
    }
  }

  static VisitVideoFlowController ensureFlowController() {
    if (Get.isRegistered<VisitVideoFlowController>()) {
      return Get.find<VisitVideoFlowController>();
    }
    return Get.put(VisitVideoFlowController(), permanent: true);
  }
}

class _LastUploadIssueCard extends StatelessWidget {
  const _LastUploadIssueCard({
    required this.issue,
    required this.isDark,
    this.compact = false,
  });

  final VisitDraftLastUploadIssue issue;
  final bool isDark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = issue.isGeofence
        ? const Color(0xFFD97706)
        : const Color(0xFFDC2626);
    final bg = isDark
        ? accent.withValues(alpha: 0.14)
        : accent.withValues(alpha: 0.08);
    final border = accent.withValues(alpha: isDark ? 0.35 : 0.22);
    final titleColor = isDark ? Colors.white : const Color(0xFF1F2937);
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.78)
        : const Color(0xFF4B5563);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            issue.isGeofence
                ? Icons.location_off_rounded
                : Icons.error_outline_rounded,
            color: accent,
            size: compact ? 18 : 20,
          ),
          SizedBox(width: compact ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last upload issue',
                  style: TextStyle(
                    color: accent,
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: compact ? 3 : 4),
                Text(
                  issue.title,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: compact ? 13 : 14,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                if (issue.summary.trim().isNotEmpty &&
                    issue.summary.trim().toLowerCase() !=
                        issue.title.trim().toLowerCase()) ...[
                  SizedBox(height: compact ? 2 : 3),
                  Text(
                    issue.summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: bodyColor,
                      fontSize: compact ? 12 : 12.5,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DraftKeepHint extends StatelessWidget {
  const _DraftKeepHint({required this.isDark, this.compact = false});

  final bool isDark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bg = isDark
        ? const Color(0xFF1B2434).withValues(alpha: 0.95)
        : const Color(0xFFEFF6FF);
    final border = isDark
        ? const Color(0xFF4F8DF7).withValues(alpha: 0.28)
        : const Color(0xFF93C5FD);
    final iconColor = isDark
        ? const Color(0xFF93C5FD)
        : const Color(0xFF2563EB);
    final titleColor = isDark ? Colors.white : const Color(0xFF1E3A5F);
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.72)
        : const Color(0xFF475569);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        border: Border.all(color: border.withValues(alpha: 0.72)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 10 : 12,
          compact ? 8 : 10,
          compact ? 10 : 12,
          compact ? 8 : 10,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: compact ? 28 : 32,
              height: compact ? 28 : 32,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: isDark ? 0.16 : 0.10),
                borderRadius: BorderRadius.circular(compact ? 8 : 10),
              ),
              child: Icon(
                Icons.folder_special_outlined,
                size: compact ? 15 : 17,
                color: iconColor,
              ),
            ),
            SizedBox(width: compact ? 8 : 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Close keeps your draft',
                    style: TextStyle(
                      color: titleColor,
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: compact ? 2 : 3),
                  Text(
                    'Your report is already saved on this device. '
                    'Closing this dialog keeps it under Drafts so you can '
                    'finish and upload later. Nothing is submitted until you upload.',
                    style: TextStyle(
                      color: bodyColor,
                      fontSize: compact ? 11 : 12,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingSitesList extends StatelessWidget {
  const _PendingSitesList({required this.drafts, required this.isDark});

  final List<VisitMediaDraftSnapshot> drafts;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final border = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);
    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.03);
    final titleColor = isDark ? Colors.white : const Color(0xFF171717);
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.68)
        : const Color(0xFF5D6168);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'You left unfinished patrols on ${drafts.length} sites. '
          'Choose a site to continue.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: bodyColor,
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < drafts.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _siteTile(
            context: context,
            draft: drafts[i],
            border: border,
            cardBg: cardBg,
            titleColor: titleColor,
            bodyColor: bodyColor,
          ),
        ],
      ],
    );
  }

  Widget _siteTile({
    required BuildContext context,
    required VisitMediaDraftSnapshot draft,
    required Color border,
    required Color cardBg,
    required Color titleColor,
    required Color bodyColor,
  }) {
    final title = draft.locationLabel ?? 'Unknown site';
    final subtitle = VisitDraftResumeDialog.siteTileSubtitle(draft);
    final issue = draft.lastUploadIssue;
    final issueColor = issue == null
        ? null
        : (issue.isGeofence
              ? const Color(0xFFD97706)
              : const Color(0xFFDC2626));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).pop(draft),
        child: Ink(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: issueColor?.withValues(alpha: 0.35) ?? border,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (issueColor ?? const Color(0xFF3B82F6))
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  issue == null
                      ? Icons.location_on_outlined
                      : (issue.isGeofence
                            ? Icons.location_off_rounded
                            : Icons.error_outline_rounded),
                  color: issueColor ?? const Color(0xFF3B82F6),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: bodyColor,
                        fontSize: 12.5,
                        height: 1.3,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    if (issue != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Last issue: ${issue.shortLabel}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: issueColor,
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: bodyColor),
            ],
          ),
        ),
      ),
    );
  }
}
