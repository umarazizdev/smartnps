import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_navigator.dart';
import '../../utilities/overlay_prompt_guard.dart';
import '../../widgets/dialogs/glass_action_dialog.dart';
import '../notes/visit_batch_notes_panel.dart';
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
    final location = draft.locationLabel ?? 'this site';
    final activeFlow = flow ?? ensureFlowController();
    return GlassActionDialog.showWithActions<VisitDraftResumeAction>(
      context: context,
      icon: Icons.assignment_late_outlined,
      iconColor: const Color(0xFF3B82F6),
      title: 'Patrol Round completed?',
      titleColor: const Color(0xFFDC2626),
      barrierDismissible: true,
      showCloseButton: true,
      messageMaxHeightFactor: 0.58,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Have you done your patrol round at $location',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.78)
                  : const Color(0xFF475467),
              fontSize: 15,
              height: 1.48,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          VisitBatchNotesPanel(flow: activeFlow, isDark: isDark),
        ],
      ),
      actions: const [
        GlassDialogAction(
          label: 'No, continue report',
          value: VisitDraftResumeAction.continueReport,
          tone: GlassDialogActionTone.neutral,
        ),
        GlassDialogAction(
          label: 'Yes, patrol completed upload report',
          value: VisitDraftResumeAction.submitReport,
          tone: GlassDialogActionTone.primary,
        ),
        GlassDialogAction(
          label: 'Discard report',
          value: VisitDraftResumeAction.discardReport,
          tone: GlassDialogActionTone.destructive,
        ),
      ],
    );
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

  static VisitVideoFlowController ensureFlowController() {
    if (Get.isRegistered<VisitVideoFlowController>()) {
      return Get.find<VisitVideoFlowController>();
    }
    return Get.put(VisitVideoFlowController(), permanent: true);
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).pop(draft),
        child: Ink(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_on_outlined,
                  color: Color(0xFF3B82F6),
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
