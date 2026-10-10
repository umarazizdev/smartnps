import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import '../../api/visit_upload_api.dart';
import '../../app/app_navigator.dart';
import '../../app/app_routes.dart';
import '../../utilities/app_config.dart';
import '../../widgets/dialogs/glass_action_dialog.dart';
import '../capture/capture_review_controller.dart';
import '../checkpoint/visit_checkpoint_screen.dart';
import '../flow/cam_perf.dart';
import '../flow/visit_checkpoint.dart';
import '../flow/visit_flow_copy.dart';
import '../flow/visit_flow_kind.dart';
import '../flow/visit_gps_session.dart';
import '../flow/visit_media_draft_store.dart';
import '../flow/visit_media_geo.dart';
import '../flow/visit_patrol_round.dart';
import '../flow/visit_upload_failure.dart';
import '../flow/visit_upload_queue.dart';
import '../flow/visit_video_flow_controller.dart';
import '../log_visit_theme.dart';
import '../notes/visit_batch_notes_panel.dart';
import '../notes/visit_media_notes_sheet.dart';
import '../notes/voice/inline_voice_note_player.dart';
import '../record/visit_native_capture_launcher.dart';
import 'visit_report_details_panel.dart';
import 'visit_video_player_controller.dart';

Color _visitCardColor(bool isDark) {
  return isDark
      ? const Color(0xFF172033).withValues(alpha: 0.94)
      : Colors.white.withValues(alpha: 0.96);
}

Color _visitBorderColor(bool isDark) {
  return isDark
      ? Colors.white.withValues(alpha: 0.13)
      : const Color(0xFFD8E0EA);
}

Color _visitTitleColor(bool isDark) {
  return isDark ? cDarkTextPrimary : const Color(0xFF20283A);
}

Color _visitBodyColor(bool isDark) {
  return isDark
      ? cDarkTextSecondary.withValues(alpha: 0.92)
      : const Color(0xFF536176);
}

Color _visitAccentColor(bool isDark) {
  return isDark ? const Color(0xFF93C5FD) : const Color(0xFF4F46E5);
}

Color _visitPrimaryActionColor(bool isDark) {
  return isDark ? const Color(0xFF4F8DF7) : cPrimary;
}

/// Raw window inset — parent Scaffolds consume [MediaQuery.viewInsets], so
/// those read as 0 even while the keyboard is open and the body is resized.
bool _isSoftKeyboardOpen(BuildContext context) {
  final view = View.of(context);
  final inset = view.viewInsets.bottom / view.devicePixelRatio;
  return inset > AppConfig.keyboardOpenThreshold;
}

enum _VisitMediaFilter { all, photos, videos }

class VisitVideoPreviewScreen extends GetView<VisitVideoFlowController> {
  static final Rx<_VisitMediaFilter> _mediaFilter = _VisitMediaFilter.all.obs;

  static final RxnString _roundTagFilter = RxnString();
  static final RxBool _draftAutosaveNoticeDismissed = false.obs;
  static final RxBool _orientationCoverVisible = false.obs;
  static Orientation? _lastDraftOrientation;
  static DateTime? _ignoreMediaPreviewUntil;

  const VisitVideoPreviewScreen({
    super.key,
    this.onBack,
    this.onUploadSuccess,
    this.onUploadStarted,
    this.onFailureOpenDraft,
    this.bottomBarClearance = 0,
  });

  final VoidCallback? onBack;
  final VoidCallback? onUploadSuccess;
  final VoidCallback? onUploadStarted;
  final VoidCallback? onFailureOpenDraft;
  final double bottomBarClearance;

  @override
  VisitVideoFlowController get controller {
    if (!Get.isRegistered<VisitVideoFlowController>()) {
      Get.put(VisitVideoFlowController(), permanent: true);
    }
    return Get.find<VisitVideoFlowController>();
  }

  void _handleBack(BuildContext context) {
    if (controller.isPreparingReport.value) return;
    if (onBack != null) {
      onBack!();
      return;
    }
    if (Navigator.of(context).canPop()) {
      Get.back();
    }
  }

  static String deleteMediaMessage({
    required bool isPhoto,
    required bool hasNotes,
    bool isSiteCheck = false,
  }) {
    return VisitFlowCopy(isSiteCheck: isSiteCheck).deleteMediaMessage(
      isPhoto: isPhoto,
      hasNotes: hasNotes,
    );
  }

  VisitFlowCopy get _copy =>
      VisitFlowCopy.fromContext(controller.patrolContext.value);

  Future<void> _removeMedia(int index) async {
    await controller.removeAt(index);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    VisitMediaItem item,
    int index,
  ) async {
    final confirmed = await GlassActionDialog.show(
      context: context,
      icon: Icons.delete_outline_rounded,
      iconWidget: const VisitDeleteIcon(size: 28, color: Color(0xFFE53935)),
      iconColor: cRed,
      title: item.isPhoto ? 'Delete Photo?' : 'Delete Video?',
      message: deleteMediaMessage(
        isPhoto: item.isPhoto,
        hasNotes: item.hasNotes,
        isSiteCheck: controller.patrolContext.value?.isSiteCheck == true,
      ),
      secondaryLabel: 'Cancel',
      primaryLabel: 'Delete',
      variant: GlassActionDialogVariant.error,
      destructiveSecondary: false,
    );
    if (confirmed == true) {
      await _removeMedia(index);
    }
  }

  void _noteDraftOrientation(Orientation orientation) {
    if (_lastDraftOrientation != null &&
        _lastDraftOrientation != orientation) {
      _ignoreMediaPreviewUntil =
          DateTime.now().add(const Duration(milliseconds: 500));
      _orientationCoverVisible.value = true;
      Future<void>.delayed(const Duration(milliseconds: 280), () {
        _orientationCoverVisible.value = false;
      });
      final route = Get.currentRoute;
      final onReview =
          route == AppRoutes.captureReview ||
          route.contains(AppRoutes.captureReview);
      if (!onReview && Get.isRegistered<CaptureReviewController>()) {
        Get.delete<CaptureReviewController>(force: true);
      }
    }
    _lastDraftOrientation = orientation;
  }

  Future<void> _openMediaPreview(VisitMediaItem item, int index) async {
    final ignoreUntil = _ignoreMediaPreviewUntil;
    if (ignoreUntil != null && DateTime.now().isBefore(ignoreUntil)) {
      return;
    }

    if (item.isPhoto) {
      await Get.to(
        () => VisitPhotoViewer(
          imagePath: item.path,
          stampLabel: item.stampLabel,
          hasNotes: item.hasNotes,
          onDelete: () {
            final i = controller.mediaItems.indexWhere(
              (e) => e.path == item.path,
            );
            if (i >= 0) _removeMedia(i);
          },
        ),
        routeName: AppRoutes.visitPhotoViewer,
        transition: Transition.noTransition,
        preventDuplicates: true,
        opaque: true,
      );
      return;
    }

    await Get.to(
      () => VisitVideoPlayerDialog(
        videoPath: item.path,
        stampLabel: item.stampLabel,
        hasNotes: item.hasNotes,
        onDelete: () {
          final i = controller.mediaItems.indexWhere(
            (e) => e.path == item.path,
          );
          if (i >= 0) _removeMedia(i);
        },
      ),
      routeName: AppRoutes.visitVideoPlayer,
      transition: Transition.noTransition,
      preventDuplicates: true,
      opaque: true,
      binding: BindingsBuilder(() {
        Get.put(
          VisitVideoPlayerController(videoPath: item.path),
          tag: item.path,
        );
      }),
    );
    if (Get.isRegistered<VisitVideoPlayerController>(tag: item.path)) {
      Get.delete<VisitVideoPlayerController>(tag: item.path, force: true);
    }
  }

  Future<void> _uploadAllMedia(BuildContext context) async {
    await VisitVideoPreviewScreen.uploadCurrentDraft(
      context: context,
      onSuccess: onUploadSuccess ?? onBack,
      onUploadStarted: onUploadStarted,
      onFailureOpenDraft: onFailureOpenDraft,
    );
  }

  Future<void> _openCaptureScreen(BuildContext context) async {
    controller.endCheckpointCapture();
    final opened = await pickRoundTagAndOpenCapture(
      context: context,
      flow: controller,
    );
    if (!opened) return;
  }

  static Future<bool> pickRoundTagAndOpenCapture({
    required BuildContext context,
    required VisitVideoFlowController flow,
    bool endCheckpointCapture = false,
    VisitPatrolRound? preselectedRound,
  }) async {
    if (endCheckpointCapture) {
      flow.endCheckpointCapture();
    }

    if (flow.supportsRoundTags) {
      if (preselectedRound != null) {
        flow.setActiveRound(preselectedRound);
      } else {
        if (!context.mounted) return false;
        final round = await promptRoundTagChoice(context: context, flow: flow);
        if (round == null) return false;
        flow.setActiveRound(round);
      }
    }

    await VisitNativeCaptureLauncher.open();
    flow.setActiveRound(null);
    return true;
  }

  Future<void> _openCaptureForRound(
    BuildContext context,
    VisitPatrolRound round,
  ) async {
    if (!context.mounted) return;
    await pickRoundTagAndOpenCapture(
      context: context,
      flow: controller,
      preselectedRound: round,
    );
  }

  static Future<VisitPatrolRound?> promptRoundTagChoice({
    required BuildContext context,
    required VisitVideoFlowController flow,
  }) async {
    if (!context.mounted) return null;
    final rounds = flow.patrolRounds;
    if (rounds.isEmpty) return null;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _visitPrimaryActionColor(isDark);
    final copy = VisitFlowCopy.fromContext(flow.patrolContext.value);

    return GlassActionDialog.showWithActions<VisitPatrolRound>(
      context: context,
      icon: Icons.route_outlined,
      iconColor: accent,
      title: copy.roundTagCaptureTitle,
      message: copy.roundTagCaptureMessage,
      barrierDismissible: true,
      showCloseButton: true,
      useRootNavigator: true,
      actions: const <GlassDialogAction<VisitPatrolRound>>[],
      content: _RoundTagChoicePanel(
        isDark: isDark,
        message: copy.roundTagCaptureMessage,
        rounds: rounds,
        colorPalette: VisitPatrolRoundColors.mapForTags(
          rounds.map((e) => e.roundTag),
        ),
      ),
    );
  }

  Future<void> _openCheckpoint(VisitCheckpoint checkpoint) async {
    await VisitCheckpointScreen.open(checkpointId: checkpoint.id);
  }

  static Future<void> uploadCurrentDraft({
    BuildContext? context,
    VoidCallback? onSuccess,
    VoidCallback? onUploadStarted,
    VoidCallback? onFailureOpenDraft,
    bool skipCompletionConfirm = false,
  }) async {
    final flow = Get.isRegistered<VisitVideoFlowController>()
        ? Get.find<VisitVideoFlowController>()
        : Get.put(VisitVideoFlowController(), permanent: true);
    await flow.ensureDraftLoaded();
    if (context != null && !context.mounted) return;

    final isDark = context != null
        ? Theme.of(context).brightness == Brightness.dark
        : (Get.context != null &&
              Theme.of(Get.context!).brightness == Brightness.dark);

    if (flow.isUploading.value) return;

    final items = flow.visibleMediaItems;
    if (items.isEmpty && !flow.isStructuredReport) {
      _showTopSnack(
        title: 'No media',
        message: 'Please capture at least one photo or video before upload.',
        isDark: isDark,
        isError: true,
      );
      return;
    }

    final ctx = flow.patrolContext.value;
    if (ctx?.siteId == null || ctx?.regionId == null) {
      _showTopSnack(
        title: 'Missing site',
        message:
            'Site and region are required before upload. Open Log Visit from the web site again.',
        isDark: isDark,
        isError: true,
      );
      return;
    }

    if (flow.hasIncompleteCheckpoints) return;

    if (flow.supportsRoundTags && !flow.hasAllRequiredRoundTags) {
      final copy = VisitFlowCopy.fromContext(flow.patrolContext.value);
      _showTopSnack(
        title: copy.roundTagsRequiredTitle,
        message: copy.roundTagsRequiredHint(
          flow.missingRoundTags.map((e) => e.roundTag),
        ),
        isDark: isDark,
        isError: true,
      );
      return;
    }

    if (flow.isStructuredReport && !flow.hasCompleteReportDetails) {
      final message = flow.reportDetails.value.validationMessageFor(
        flow.flowKind,
      );
      _showTopSnack(
        title: 'Report details needed',
        message: message ?? 'Please complete the required report fields.',
        isDark: isDark,
        isError: true,
      );
      return;
    }

    if (flow.isStructuredReport &&
        flow.patrolContext.value?.hasReportContext != true) {
      final contextError = await flow.ensureOperationalReportContext();
      if (contextError != null ||
          flow.patrolContext.value?.hasReportContext != true) {
        _showTopSnack(
          title: 'Report not authorized',
          message:
              contextError ??
              'This report is missing a server context. Open it again while online.',
          isDark: isDark,
          isError: true,
        );
        return;
      }
    }

    final minimumPhotos = ctx?.minimumPhotos;
    if (minimumPhotos != null &&
        minimumPhotos > 0 &&
        !flow.meetsMinimumPhotoRequirement) {
      final photoLabel = minimumPhotos == 1 ? 'photo' : 'photos';
      final captured = flow.capturedPhotoCount;
      _showTopSnack(
        title: 'More photos needed',
        message:
            'This site requires at least $minimumPhotos $photoLabel. '
            'You have $captured so far. Videos do not count toward this requirement.',
        isDark: isDark,
        isError: true,
      );
      return;
    }

    final locationLabel = flow.locationSubtitle?.trim() ?? '';
    final movedToDashboard = onUploadStarted != null;
    // Capture before leaving the editor so upload does not depend on a
    // post-release disk reload (form-only drafts / race with markInFlight).
    final uploadSnapshot = flow.captureDraftSnapshot();
    final draftKey = uploadSnapshot.draftKey;
    final progressTotal = uploadSnapshot.items.isEmpty
        ? 1
        : uploadSnapshot.items.length;

    void beginLeaveDraftUi({required bool showProgress}) {
      if (showProgress) {
        flow.isUploading.value = true;
        flow.isQueueUploading.value = false;
        flow.uploadProgressCurrent.value = 0;
        flow.uploadProgressTotal.value = progressTotal;
        flow.uploadLocationLabel.value = locationLabel;
      } else {
        flow.isUploading.value = false;
        flow.isQueueUploading.value = false;
        flow.uploadProgressCurrent.value = 0;
        flow.uploadProgressTotal.value = 0;
        flow.uploadLocationLabel.value = '';
      }
      onUploadStarted?.call();
    }

    Future<void>? claimForQueueFuture;
    Future<void> claimDraftForQueue() {
      return claimForQueueFuture ??= () async {
        await VisitMediaDraftStore.instance.saveDraft(
          uploadSnapshot.items,
          key: draftKey,
          startedAt: uploadSnapshot.startedAt,
          siteName: uploadSnapshot.siteName,
          context: uploadSnapshot.context,
          batchNote: uploadSnapshot.batchNote,
          generalNote: uploadSnapshot.generalNote,
          reportDetails: uploadSnapshot.reportDetails,
          lastUploadIssue: null,
        );
        await flow.clearLastUploadIssue(persist: false);
        await VisitUploadQueue.instance.markInFlight(draftKey);
        await flow.releaseEditorAfterQueuedClaim();
      }();
    }

    if (!skipCompletionConfirm) {
      var leaveStarted = false;
      final confirmed = await _confirmPatrolUploadCompletion(
        flow: flow,
        isDark: isDark,
        context: context,
        onYesPressed: () {
          leaveStarted = true;
          unawaited(claimDraftForQueue());
          beginLeaveDraftUi(showProgress: true);
        },
      );
      if (!confirmed) return;
      if (!leaveStarted) {
        beginLeaveDraftUi(showProgress: true);
      }
    } else {
      beginLeaveDraftUi(showProgress: true);
    }

    await claimDraftForQueue();

    final online = await _hasNetworkInterface();
    if (!online) {
      await _enqueueForSilentRetry(flow: flow, draftKey: draftKey);
      return;
    }

    if (!uploadSnapshot.canUpload) {
      _clearUploadProgress(flow);
      await VisitUploadQueue.instance.remove(draftKey);
      _showTopSnack(
        title: 'Upload not ready',
        message: flow.isStructuredReport
            ? (uploadSnapshot.reportDetails.validationMessageFor(
                    uploadSnapshot.context?.flowKind ?? flow.flowKind,
                  ) ??
                  'Please complete the report fields and try again.')
            : 'Please capture at least one photo or video before upload.',
        isDark: isDark,
        isError: true,
      );
      return;
    }

    flow.isUploading.value = true;
    flow.isQueueUploading.value = false;
    flow.uploadProgressCurrent.value = 0;
    flow.uploadProgressTotal.value = progressTotal;
    flow.uploadLocationLabel.value =
        uploadSnapshot.locationLabel?.trim().isNotEmpty == true
        ? uploadSnapshot.locationLabel!.trim()
        : locationLabel;

    try {
      var activeSnapshot = uploadSnapshot;
      Future<VisitUploadResult> runUpload(VisitMediaDraftSnapshot draft) async {
        final meta = await VisitUploadMeta.buildFromSnapshot(draft);
        if (kDebugMode) {
          debugPrint('[VisitUpload] meta=$meta');
        }
        return VisitUploadApi.instance.uploadVisit(
          meta: meta,
          items: draft.items,
          batchVoicePath: draft.batchNote.voiceNotePath,
          generalVoicePath: draft.generalNote.voiceNotePath,
          uploadUrl: draft.context?.uploadUrl,
          onProgress: (current, total) {
            flow.uploadProgressCurrent.value = current;
            flow.uploadProgressTotal.value = total;
          },
        );
      }

      var result = await runUpload(activeSnapshot);

      if (!result.success &&
          !result.isNetworkFailure &&
          result.isClientDraftReuseError) {
        if (kDebugMode) {
          debugPrint(
            '[VisitUpload] client_draft_id reuse; rotating and retrying once',
          );
        }
        activeSnapshot = await VisitMediaDraftStore.instance.rotateClientDraftId(
          activeSnapshot,
        );
        result = await runUpload(activeSnapshot);
      }

      if (Get.isSnackbarOpen) {
        Get.closeAllSnackbars();
      }

      if (result.success) {
        if (kDebugMode) {
          debugPrint(
            '[VisitUpload] SUCCESS status=${result.statusCode} '
            'visitId=${result.visitId} clientDraftId=${result.clientDraftId} '
            'itemsSaved=${result.itemsSaved} message=${result.displayMessage}',
          );
        }
        _clearUploadProgress(flow);
        await VisitUploadQueue.instance.remove(draftKey);
        await VisitMediaDraftStore.instance.clearDraft(
          deleteFiles: true,
          key: draftKey,
        );
        unawaited(VisitGpsSession.instance.stop());
        await _showUploadSuccessFeedback(
          isDark: isDark,
          flowKind:
              activeSnapshot.context?.flowKind ?? VisitFlowKind.patrol,
        );
        if (!movedToDashboard) {
          onSuccess?.call();
        }
        return;
      }

      if (kDebugMode) {
        debugPrint(
          '[VisitUpload] FAIL status=${result.statusCode} '
          'network=${result.isNetworkFailure} '
          'message=${result.displayMessage} errors=${result.errors}',
        );
      }

      if (result.isNetworkFailure) {
        await _enqueueForSilentRetry(flow: flow, draftKey: draftKey);
        return;
      }

      _clearUploadProgress(flow);
      await VisitUploadQueue.instance.remove(draftKey);
      final presentation = VisitUploadFailure.present(
        result: result,
        mediaItems: activeSnapshot.items,
        checkpoints: activeSnapshot.context?.checkpoints ?? const [],
      );
      await flow.activateDraft(draftKey);
      await flow.recordLastUploadIssue(presentation.toDraftIssue());
      await _showUploadFailureDialog(
        flow: flow,
        presentation: presentation,
        locationLabel: locationLabel,
        isDark: isDark,
        context: context,
        onOpenDraft: onFailureOpenDraft,
      );
    } catch (error, stack) {
      if (Get.isSnackbarOpen) {
        Get.closeAllSnackbars();
      }
      if (kDebugMode) {
        debugPrint('[VisitUpload] FAIL unexpected=$error');
        debugPrint('[VisitUpload] stack=$stack');
      }
      if (_isNetworkError(error)) {
        await _enqueueForSilentRetry(flow: flow, draftKey: draftKey);
        return;
      }
      _clearUploadProgress(flow);
      await VisitUploadQueue.instance.remove(draftKey);
      final presentation = VisitUploadFailure.presentUnexpected(
        error,
        flowKind: uploadSnapshot.context?.flowKind ?? VisitFlowKind.patrol,
      );
      await flow.activateDraft(draftKey);
      await flow.recordLastUploadIssue(presentation.toDraftIssue());
      await _showUploadFailureDialog(
        flow: flow,
        presentation: presentation,
        locationLabel: locationLabel,
        isDark: isDark,
        context: context,
        onOpenDraft: onFailureOpenDraft,
      );
    }
  }

  static void _clearUploadProgress(VisitVideoFlowController flow) {
    flow.isUploading.value = false;
    flow.isQueueUploading.value = false;
    flow.uploadProgressCurrent.value = 0;
    flow.uploadProgressTotal.value = 0;
    flow.uploadLocationLabel.value = '';
  }

  static Future<void> _enqueueForSilentRetry({
    required VisitVideoFlowController flow,
    required VisitDraftKey draftKey,
  }) async {
    _clearUploadProgress(flow);

    await VisitUploadQueue.instance.enqueue(draftKey);
    unawaited(VisitGpsSession.instance.stop());
    if (kDebugMode) {
      debugPrint(
        '[VisitUpload] queued for silent retry draft=${draftKey.folderName}',
      );
    }
  }

  static Future<bool> _hasNetworkInterface() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.isEmpty) return false;
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  static bool _isNetworkError(Object error) {
    if (error is SocketException || error is HttpException) return true;
    if (error is DioException) {
      return VisitUploadResult.isNetworkDioException(error);
    }
    return false;
  }

  static Future<void> presentQueuedUploadFailure({
    required VisitDraftKey draftKey,
    required VisitUploadFailurePresentation presentation,
    required VisitMediaDraftSnapshot snapshot,
    VoidCallback? onOpenDraft,
  }) async {
    final flow = Get.isRegistered<VisitVideoFlowController>()
        ? Get.find<VisitVideoFlowController>()
        : Get.put(VisitVideoFlowController(), permanent: true);
    await flow.activateDraft(draftKey);
    await flow.persistCurrentDraft();

    final dialogContext = await _waitForDialogContext();
    final isDark = dialogContext != null
        ? Theme.of(dialogContext).brightness == Brightness.dark
        : (Get.context != null &&
              Theme.of(Get.context!).brightness == Brightness.dark);
    final locationLabel =
        snapshot.locationLabel?.trim() ?? flow.locationSubtitle?.trim() ?? '';

    await _showUploadFailureDialog(
      flow: flow,
      presentation: presentation,
      locationLabel: locationLabel,
      isDark: isDark,
      context: dialogContext,
      onOpenDraft: onOpenDraft,
    );
  }

  static Future<BuildContext?> _waitForDialogContext() async {
    for (var i = 0; i < 20; i++) {
      final ctx = AppNavigator.key.currentContext ?? Get.context;
      if (ctx != null && ctx.mounted) return ctx;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return AppNavigator.key.currentContext ?? Get.context;
  }

  static Future<bool> _confirmPatrolUploadCompletion({
    required VisitVideoFlowController flow,
    required bool isDark,
    BuildContext? context,
    VoidCallback? onYesPressed,
  }) async {
    final dialogContext = (context != null && context.mounted)
        ? context
        : AppNavigator.key.currentContext ?? Get.context;
    if (dialogContext == null || !dialogContext.mounted) return false;

    final place = _resolvePatrolLocationLabel(flow);
    final copy = VisitFlowCopy.fromContext(flow.patrolContext.value);
    final accent = isDark ? const Color(0xFF93C5FD) : const Color(0xFF4F46E5);
    final viewport = MediaQuery.sizeOf(dialogContext);
    final isLandscape = viewport.width > viewport.height;

    final result = await GlassActionDialog.showWithActions<bool>(
      context: dialogContext,
      icon: Icons.fact_check_outlined,
      iconColor: accent,
      title: copy.completionTitle,
      titleColor: const Color(0xFFDC2626),
      barrierDismissible: true,
      showCloseButton: true,
      useRootNavigator: true,
      messageMaxHeightFactor: 0.58,
      maxWidth: isLandscape ? 680 : null,
      insetPadding: isLandscape
          ? const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
          : const EdgeInsets.symmetric(horizontal: 28),
      content: _PatrolCompleteDialogBody(
        message: copy.completionMessage(place),
        flow: flow,
        isDark: isDark,
      ),
      actions: [
        const GlassDialogAction(
          label: 'No, view/continue report',
          value: false,
          tone: GlassDialogActionTone.neutral,
        ),
        GlassDialogAction(
          label: copy.yesUploadLabel,
          value: true,
          tone: GlassDialogActionTone.primary,
          beforePop: () {
            onYesPressed?.call();
            return true;
          },
        ),
      ],
    );

    return result == true;
  }

  static String _resolvePatrolLocationLabel(VisitVideoFlowController flow) {
    final fromContext = flow.patrolContext.value?.locationSubtitle?.trim();
    if (fromContext != null && fromContext.isNotEmpty) return fromContext;

    final site =
        flow.patrolContext.value?.siteName?.trim() ??
        flow.draftSiteName.value?.trim();
    final region =
        flow.patrolContext.value?.regionName?.trim() ??
        flow.draftRegionName.value?.trim();
    if (site != null &&
        site.isNotEmpty &&
        region != null &&
        region.isNotEmpty) {
      return '$site · $region';
    }
    if (site != null && site.isNotEmpty) return site;
    if (region != null && region.isNotEmpty) return region;

    final subtitle = flow.locationSubtitle?.trim();
    if (subtitle != null && subtitle.isNotEmpty) return subtitle;

    return 'this site';
  }

  static void _showTopSnack({
    required String title,
    required String message,
    required bool isDark,
    bool isError = false,
    Duration duration = const Duration(seconds: 4),
  }) {
    final bg = isError
        ? (isDark ? const Color(0xFF3A1F24) : const Color(0xFFFFF1F2))
        : _visitCardColor(isDark);
    final fg = isError
        ? (isDark ? const Color(0xFFFECACA) : const Color(0xFF9F1239))
        : _visitTitleColor(isDark);
    final accent = isError
        ? const Color(0xFFE53935)
        : _visitPrimaryActionColor(isDark);

    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.TOP,
      backgroundColor: bg,
      colorText: fg,
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      borderColor: accent.withValues(alpha: isDark ? 0.35 : 0.22),
      borderWidth: 1,
      icon: Icon(
        isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
        color: accent,
      ),
      shouldIconPulse: false,
      duration: duration,
      animationDuration: const Duration(milliseconds: 350),
      boxShadows: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  static Future<void> showQueuedUploadSuccessFeedback({
    required bool isDark,
    VisitFlowKind flowKind = VisitFlowKind.patrol,
    bool isSiteCheck = false,
  }) {
    return _showUploadSuccessFeedback(
      isDark: isDark,
      flowKind: isSiteCheck ? VisitFlowKind.siteCheck : flowKind,
    );
  }

  static Future<void> _showUploadSuccessFeedback({
    required bool isDark,
    VisitFlowKind flowKind = VisitFlowKind.patrol,
  }) async {
    if (Get.isSnackbarOpen) {
      Get.closeAllSnackbars();
    }

    final bg = isDark ? const Color(0xFF059669) : const Color(0xFF047857);
    const duration = Duration(seconds: 3);
    final successTitle = VisitFlowCopy(kind: flowKind).successTitle;

    Get.rawSnackbar(
      snackPosition: SnackPosition.TOP,
      backgroundColor: bg,
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      duration: duration,
      animationDuration: const Duration(milliseconds: 250),
      isDismissible: true,
      messageText: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  successTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Your report was sent successfully.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      boxShadows: [
        BoxShadow(
          color: bg.withValues(alpha: 0.45),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
    );

    await Future<void>.delayed(duration);
  }

  static Future<void> _showUploadFailureDialog({
    required VisitVideoFlowController flow,
    required VisitUploadFailurePresentation presentation,
    required bool isDark,
    BuildContext? context,
    String locationLabel = '',
    VoidCallback? onOpenDraft,
  }) async {
    final dialogContext = (context != null && context.mounted)
        ? context
        : AppNavigator.key.currentContext ?? Get.context;
    if (dialogContext == null || !dialogContext.mounted) return;

    final canFix = presentation.canFixMedia;
    final placeLabel = presentation.isGeofence ? locationLabel.trim() : '';
    final action = await GlassActionDialog.showWithActions<String>(
      context: dialogContext,
      icon: presentation.isGeofence
          ? Icons.location_off_rounded
          : Icons.error_outline_rounded,
      iconColor: const Color(0xFFE53935),
      title: presentation.title,
      message: '',
      content: _UploadFailureDialogBody(
        summary: presentation.summary,
        locationLabel: placeLabel,
        affectedLabels: presentation.affectedLabels,
        guidance: presentation.guidance,
        isDark: isDark,
      ),
      variant: GlassActionDialogVariant.error,
      barrierDismissible: false,
      showCloseButton: false,
      useRootNavigator: true,
      messageMaxHeightFactor: 0.55,
      actions: [
        if (canFix)
          const GlassDialogAction(
            label: 'Delete & Retake',
            value: 'retake',
            tone: GlassDialogActionTone.primary,
          ),
        const GlassDialogAction(
          label: 'Okay',
          value: 'close',
          tone: GlassDialogActionTone.neutral,
        ),
      ],
    );

    onOpenDraft?.call();

    if (action == 'retake') {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await _resolveAffectedMedia(
        flow: flow,
        presentation: presentation,
        retake: true,
      );
    }
  }

  static Future<void> _resolveAffectedMedia({
    required VisitVideoFlowController flow,
    required VisitUploadFailurePresentation presentation,
    required bool retake,
  }) async {
    final index = presentation.primaryItemIndex;
    if (index == null || index < 0 || index >= flow.mediaItems.length) {
      return;
    }

    final item = flow.mediaItems[index];
    final checkpointId = item.siteCheckpointId;

    await flow.removeAt(index);

    if (!retake) return;

    if (checkpointId != null) {
      await VisitCheckpointScreen.open(
        checkpointId: checkpointId,
        openCaptureOnStart: true,
      );
      return;
    }

    flow.endCheckpointCapture();
    final dialogContext =
        AppNavigator.key.currentContext ?? Get.context;
    if (dialogContext == null || !dialogContext.mounted) {
      await VisitNativeCaptureLauncher.open();
      return;
    }
    await pickRoundTagAndOpenCapture(
      context: dialogContext,
      flow: flow,
    );
  }

  static Future<void> queueUploadFeedback({
    BuildContext? context,
    int? count,
  }) async {
    await uploadCurrentDraft(context: context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);
    final orientation = mediaQuery.orientation;
    final isLandscape = orientation == Orientation.landscape;
    // Subscribe to MediaQuery size so keyboard-driven scaffold resize rebuilds
    // this screen; inset detection itself uses FlutterView (see below).
    mediaQuery.size;
    _noteDraftOrientation(orientation);
    final scaffoldBg = isDark ? cDarkBackground : cMainBg;

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: scaffoldBg),
            VisitPageBackground(isDark: isDark),
            Obx(() {
              // Nested Scaffolds zero MediaQuery.viewInsets; use raw view inset.
              final keyboardOpen = _isSoftKeyboardOpen(context);
              final supportsRoundTags = controller.supportsRoundTags;
              final rounds = controller.patrolRounds;
              final allMedia = controller.visibleMediaItems;
              final checkpoints = controller.checkpoints;
              final hasCheckpoints = checkpoints.isNotEmpty;
              final additionalMedia = hasCheckpoints
                  ? controller.additionalMediaItems
                  : allMedia;
              final hasMedia = allMedia.isNotEmpty;
              final photoCount = additionalMedia.where((e) => e.isPhoto).length;
              final videoCount = additionalMedia.where((e) => e.isVideo).length;
              final activeFilter = _mediaFilter.value;
              final selectedRoundTag = supportsRoundTags
                  ? _roundTagFilter.value
                  : null;
              final activeRoundTag =
                  selectedRoundTag != null &&
                      rounds.any(
                        (r) =>
                            r.roundTag.trim().toLowerCase() ==
                            selectedRoundTag.trim().toLowerCase(),
                      )
                  ? selectedRoundTag
                  : null;

              List<VisitMediaItem> typeFiltered;
              if (supportsRoundTags) {
                typeFiltered = additionalMedia;
              } else {
                typeFiltered = switch (activeFilter) {
                  _VisitMediaFilter.all => additionalMedia,
                  _VisitMediaFilter.photos =>
                    additionalMedia.where((e) => e.isPhoto).toList(),
                  _VisitMediaFilter.videos =>
                    additionalMedia.where((e) => e.isVideo).toList(),
                };
              }

              final visibleMedia = activeRoundTag == null
                  ? typeFiltered
                  : typeFiltered
                        .where(
                          (e) =>
                              e.resolvedRoundTag?.toLowerCase() ==
                              activeRoundTag.trim().toLowerCase(),
                        )
                        .toList(growable: false);

              final locationLabel = controller.locationSubtitle;
              controller.patrolContext.value;
              controller.draftSiteName.value;
              controller.draftRegionName.value;
              controller.activeRound.value;
              final completedCheckpoints = controller.completedCheckpointCount;
              final completedRounds = controller.completedRoundTagCount;
              final showFilters =
                  !hasCheckpoints || additionalMedia.isNotEmpty;

              Widget? roundsScrollHeader() {
                if (!supportsRoundTags || hasCheckpoints) return null;
                final titleColor = _visitTitleColor(isDark);
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    isLandscape ? 18 : 16,
                    isLandscape ? 2 : 4,
                    isLandscape ? 18 : 16,
                    isLandscape ? 4 : 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _RoundTagProgressPanel(
                        isDark: isDark,
                        compact: isLandscape,
                        rounds: rounds,
                        completedCount: completedRounds,
                        mediaCountFor: controller.mediaCountForRoundTag,
                        onCapture: (round) =>
                            _openCaptureForRound(context, round),
                      ),
                      SizedBox(height: isLandscape ? 10 : 12),
                      Text(
                        'Captured Media (${additionalMedia.length})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: titleColor,
                          fontWeight: FontWeight.w800,
                          fontSize: isLandscape ? 13 : null,
                        ),
                      ),
                      if (showFilters) ...[
                        SizedBox(height: isLandscape ? 6 : 8),
                        _RoundTagFilterBar(
                          isDark: isDark,
                          rounds: rounds,
                          activeRoundTag: activeRoundTag,
                          onChanged: (tag) => _roundTagFilter.value = tag,
                          compact: isLandscape,
                        ),
                      ],
                      SizedBox(height: isLandscape ? 6 : 8),
                    ],
                  ),
                );
              }

              Widget? reportDetailsHeader() {
                if (!controller.isStructuredReport) return null;
                final titleColor = _visitTitleColor(isDark);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    VisitReportDetailsPanel(
                      flow: controller,
                      isDark: isDark,
                      compact: isLandscape,
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        isLandscape ? 18 : 16,
                        isLandscape ? 2 : 4,
                        isLandscape ? 18 : 16,
                        isLandscape ? 4 : 6,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Captured Media (${additionalMedia.length})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: titleColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize: isLandscape ? 13 : null,
                                ),
                          ),
                          if (showFilters) ...[
                            SizedBox(height: isLandscape ? 6 : 8),
                            _MediaFilterBar(
                              isDark: isDark,
                              activeFilter: activeFilter,
                              totalCount: additionalMedia.length,
                              photoCount: photoCount,
                              videoCount: videoCount,
                              onChanged: (filter) =>
                                  _mediaFilter.value = filter,
                              compact: isLandscape,
                            ),
                          ],
                          SizedBox(height: isLandscape ? 6 : 8),
                        ],
                      ),
                    ),
                  ],
                );
              }

              Widget? scrollLeading() {
                final report = reportDetailsHeader();
                final rounds = roundsScrollHeader();
                if (report == null && rounds == null) return null;
                if (report == null) return rounds;
                if (rounds == null) return report;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [report, rounds],
                );
              }

              Widget mediaBody() {
                final leading = scrollLeading();
                if (!hasMedia) {
                  return _buildEmptyState(
                    context,
                    isDark,
                    locationLabel: locationLabel,
                    isLandscape: isLandscape,
                    supportsRoundTags: supportsRoundTags,
                    leading: leading,
                  );
                }
                if (visibleMedia.isEmpty) {
                  return _buildScrollableWithLeading(
                    leading: leading,
                    child: _buildFilteredEmptyState(
                      context,
                      isDark,
                      activeFilter,
                      roundTag: activeRoundTag,
                    ),
                  );
                }
                return _buildMediaGrid(
                  context,
                  visibleMedia,
                  isDark,
                  isLandscape: isLandscape,
                  leading: leading,
                );
              }

              _VisitHeader header() {
                return _VisitHeader(
                  isDark: isDark,
                  isLandscape: isLandscape,
                  totalCount: additionalMedia.length,
                  photoCount: photoCount,
                  videoCount: videoCount,
                  activeFilter: activeFilter,
                  onFilterChanged: (filter) => _mediaFilter.value = filter,
                  locationLabel: locationLabel,
                  minimumPhotos: controller.patrolContext.value?.minimumPhotos,
                  onBack: () => _handleBack(context),
                  hasCheckpoints: hasCheckpoints,
                  checkpointCompleted: completedCheckpoints,
                  checkpointTotal: checkpoints.length,
                  showMediaFilters:
                      showFilters &&
                      !(supportsRoundTags && !hasCheckpoints) &&
                      !controller.isStructuredReport,
                  flowKind: controller.flowKind,
                  roundTags: supportsRoundTags ? rounds : const [],
                  roundTagCompleted: completedRounds,
                  activeRoundTag: activeRoundTag,
                  onRoundTagChanged: (tag) => _roundTagFilter.value = tag,
                  deferCapturedMediaSection:
                      (supportsRoundTags && !hasCheckpoints) ||
                      controller.isStructuredReport,
                );
              }

              return isLandscape
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              header(),
                              Expanded(
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: hasCheckpoints
                                          ? _buildCheckpointAwareBody(
                                              context,
                                              isDark: isDark,
                                              isLandscape: isLandscape,
                                              checkpoints: checkpoints,
                                              visibleMedia: visibleMedia,
                                              additionalMedia: additionalMedia,
                                              activeFilter: activeFilter,
                                              locationLabel: locationLabel,
                                            )
                                          : mediaBody(),
                                    ),
                                    _DraftAutosaveNotice(
                                      isDark: isDark,
                                      compact: true,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!keyboardOpen)
                          _DraftLandscapeSidebar(
                            isDark: isDark,
                            hasMedia: hasMedia,
                            hasCheckpoints: hasCheckpoints,
                            onCapture: () => _openCaptureScreen(context),
                            onComplete: () => _uploadAllMedia(context),
                          ),
                      ],
                    )
                  : Column(
                      children: [
                        header(),
                        Expanded(
                          child: hasCheckpoints
                              ? _buildCheckpointAwareBody(
                                  context,
                                  isDark: isDark,
                                  isLandscape: isLandscape,
                                  checkpoints: checkpoints,
                                  visibleMedia: visibleMedia,
                                  additionalMedia: additionalMedia,
                                  activeFilter: activeFilter,
                                  locationLabel: locationLabel,
                                )
                              : mediaBody(),
                        ),
                        if (!keyboardOpen) ...[
                          _DraftAutosaveNotice(isDark: isDark),
                          _buildBottomActions(
                            context,
                            hasMedia,
                            hasCheckpoints: hasCheckpoints,
                          ),
                          if (bottomBarClearance > 0)
                            SizedBox(height: bottomBarClearance),
                        ],
                      ],
                    );
            }),
            Obx(() {
              if (!_orientationCoverVisible.value) {
                return const SizedBox.shrink();
              }
              return Positioned.fill(
                child: ColoredBox(color: scaffoldBg),
              );
            }),
            Obx(() {
              if (!controller.isPreparingReport.value) {
                return const SizedBox.shrink();
              }
              return Positioned.fill(
                child: _ReportPreparingOverlay(
                  isDark: isDark,
                  copy: VisitFlowCopy.fromContext(
                    controller.patrolContext.value,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollableWithLeading({
    required Widget child,
    Widget? leading,
  }) {
    if (leading == null) return child;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: leading),
        SliverFillRemaining(
          hasScrollBody: false,
          child: child,
        ),
      ],
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    bool isDark, {
    String? locationLabel,
    bool isLandscape = false,
    bool supportsRoundTags = false,
    Widget? leading,
  }) {
    final location = locationLabel?.trim();
    final hasLocation = location != null && location.isNotEmpty;
    final readyTitle = _copy.readyToStart;
    final captureHint = supportsRoundTags
        ? _copy.emptyRoundTagsHint
        : _copy.emptyCaptureHint;
    final compact = leading != null || isLandscape;
    final buttonSize = compact ? 72.0 : 92.0;
    final emptyContent = Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        compact ? 8 : 28,
        22,
        compact ? 8 : 22,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: isDark
                ? cDarkCardColor.withValues(alpha: 0.82)
                : Colors.white.withValues(alpha: 0.94),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _openCaptureScreen(context),
              child: Container(
                width: buttonSize,
                height: buttonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.white,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.28 : 0.10,
                      ),
                      blurRadius: compact ? 18 : 28,
                      offset: Offset(0, compact ? 8 : 14),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.add_a_photo_outlined,
                  size: compact ? 30 : 38,
                  color: isDark ? const Color(0xFF38BDF8) : cPrimary,
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 10 : 18),
          Text(
            readyTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: compact ? 20 : null,
              color: isDark ? cDarkTextPrimary : cDarkText,
            ),
          ),
          if (hasLocation && leading == null) ...[
            SizedBox(height: compact ? 6 : 8),
            Text(
              location,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark ? const Color(0xFF38BDF8) : cPrimary,
              ),
            ),
          ],
          SizedBox(height: compact ? 6 : 8),
          Text(
            captureHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              height: 1.35,
              fontSize: compact ? 13 : null,
              color: isDark
                  ? cDarkTextSecondary
                  : const Color(0xFF667085),
            ),
          ),
        ],
      ),
    );

    if (leading == null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(child: emptyContent),
            ),
          );
        },
      );
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: leading),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: emptyContent),
        ),
      ],
    );
  }

  Widget _buildFilteredEmptyState(
    BuildContext context,
    bool isDark,
    _VisitMediaFilter filter, {
    String? roundTag,
  }) {
    final message = roundTag != null && roundTag.trim().isNotEmpty
        ? 'No media for ${roundTag.trim()} yet'
        : filter == _VisitMediaFilter.videos
        ? 'No videos captured yet'
        : 'No photos captured yet';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: _visitBodyColor(isDark),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildCheckpointAwareBody(
    BuildContext context, {
    required bool isDark,
    required bool isLandscape,
    required List<VisitCheckpoint> checkpoints,
    required List<VisitMediaItem> visibleMedia,
    required List<VisitMediaItem> additionalMedia,
    required _VisitMediaFilter activeFilter,
    String? locationLabel,
  }) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        isLandscape ? 18 : 16,
        isLandscape ? 4 : 6,
        isLandscape ? 18 : 16,
        isLandscape ? 12 : 16,
      ),
      children: [
        Text(
          _copy.checkpointsTitle,
          style: TextStyle(
            color: _visitTitleColor(isDark),
            fontSize: isLandscape ? 13 : 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: isLandscape ? 8 : 10),
        _CheckpointProgressBar(
          isDark: isDark,
          completed: controller.completedCheckpointCount,
          total: checkpoints.length,
        ),
        if (controller.supportsRoundTags) ...[
          SizedBox(height: isLandscape ? 8 : 10),
          _RoundTagProgressPanel(
            isDark: isDark,
            compact: isLandscape,
            rounds: controller.patrolRounds,
            completedCount: controller.completedRoundTagCount,
            mediaCountFor: controller.mediaCountForRoundTag,
            onCapture: (round) => _openCaptureForRound(context, round),
          ),
        ],
        SizedBox(height: isLandscape ? 8 : 10),
        for (var i = 0; i < checkpoints.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _CheckpointListCard(
            checkpoint: checkpoints[i],
            index: i,
            isDark: isDark,
            completed: controller.isCheckpointCompleted(checkpoints[i].id),
            mediaCount: controller.mediaForCheckpoint(checkpoints[i].id).length,
            onTap: () => _openCheckpoint(checkpoints[i]),
          ),
        ],
        SizedBox(height: isLandscape ? 16 : 20),
        Text(
          additionalMedia.isEmpty
              ? 'Additional media'
              : 'Additional media (${additionalMedia.length})',
          style: TextStyle(
            color: _visitTitleColor(isDark),
            fontSize: isLandscape ? 13 : 14,
            fontWeight: FontWeight.w800,
          ),
        ),

        SizedBox(height: isLandscape ? 8 : 10),
        if (additionalMedia.isEmpty)
          _AdditionalMediaEmptyCard(
            isDark: isDark,
            isLandscape: isLandscape,
            isSiteCheck: controller.patrolContext.value?.isSiteCheck == true,
            onCapture: () => _openCaptureScreen(context),
          )
        else if (visibleMedia.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              activeFilter == _VisitMediaFilter.videos
                  ? 'No additional videos yet'
                  : 'No additional photos yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _visitBodyColor(isDark),
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          for (var i = 0; i < visibleMedia.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final item = visibleMedia[i];
                return VisitMediaPreviewCard(
                  key: ValueKey('extra-media-${item.path}'),
                  item: item,
                  index: i,
                  isDark: isDark,
                  compact: isLandscape,
                  thumbnailFuture: item.isVideo
                      ? controller.videoThumbnail(item.path)
                      : null,
                  onPreview: () => _openMediaPreview(item, i),
                  onDelete: () {
                    final actualIndex = controller.mediaItems.indexWhere(
                      (e) => e.path == item.path,
                    );
                    if (actualIndex >= 0) {
                      _confirmDelete(context, item, actualIndex);
                    }
                  },
                );
              },
            ),
          ],
      ],
    );
  }

  Widget _buildMediaGrid(
    BuildContext context,
    List<VisitMediaItem> media,
    bool isDark, {
    bool isLandscape = false,
    Widget? leading,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth ||
            !constraints.hasBoundedHeight ||
            constraints.maxWidth < 8 ||
            constraints.maxHeight < 8) {
          return const SizedBox.shrink();
        }

        final isWide = constraints.maxWidth >= 720;
        final useTwoColumns = isLandscape || isWide;
        final horizontalInset = isWide || isLandscape ? 18.0 : 16.0;
        final gap = 8.0;
        final topPad = isLandscape ? 4.0 : 6.0;
        final bottomPad = isLandscape ? 10.0 : 14.0;
        final rowCount =
            media.isEmpty ? 0 : (useTwoColumns ? (media.length + 1) ~/ 2 : media.length);

        Widget cardFor(int index) {
          final item = media[index];
          return VisitMediaPreviewCard(
            key: ValueKey('media-card-${item.path}'),
            item: item,
            index: index,
            isDark: isDark,
            featured: !isLandscape && isWide,
            compact: isLandscape || useTwoColumns,
            thumbnailFuture: item.isVideo
                ? controller.videoThumbnail(item.path)
                : null,
            onPreview: () => _openMediaPreview(item, index),
            onDelete: () {
              final actualIndex = controller.mediaItems.indexWhere(
                (e) => e.path == item.path,
              );
              if (actualIndex >= 0) {
                _confirmDelete(context, item, actualIndex);
              }
            },
          );
        }

        Widget rowFor(int rowIndex) {
          if (!useTwoColumns) {
            return cardFor(rowIndex);
          }
          final leftIndex = rowIndex * 2;
          final rightIndex = leftIndex + 1;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cardFor(leftIndex)),
                SizedBox(width: gap),
                Expanded(
                  child: rightIndex < media.length
                      ? cardFor(rightIndex)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          );
        }

        final scrollView = CustomScrollView(
          key: ValueKey(
            isLandscape
                ? 'visit-media-scroll-land'
                : useTwoColumns
                ? 'visit-media-scroll-wide'
                : 'visit-media-scroll',
          ),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (leading != null) SliverToBoxAdapter(child: leading),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalInset,
                topPad,
                horizontalInset,
                bottomPad,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (useTwoColumns) {
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index < rowCount - 1 ? gap : 0,
                        ),
                        child: rowFor(index),
                      );
                    }
                    final itemIndex = index ~/ 2;
                    if (index.isOdd) return SizedBox(height: gap);
                    return cardFor(itemIndex);
                  },
                  childCount: useTwoColumns
                      ? rowCount
                      : (media.isEmpty ? 0 : media.length * 2 - 1),
                ),
              ),
            ),
          ],
        );

        if (!isLandscape || constraints.maxWidth < 900) {
          return scrollView;
        }

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: scrollView,
          ),
        );
      },
    );
  }

  Widget _buildBottomActions(
    BuildContext context,
    bool hasMedia, {
    bool isLandscape = false,
    bool hasCheckpoints = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final captureLabel = hasCheckpoints
        ? 'Add More'
        : (hasMedia ? 'Capture More' : 'Capture');
    return Container(
      padding: EdgeInsets.fromLTRB(
        isLandscape ? 16 : 18,
        isLandscape ? 6 : 10,
        isLandscape ? 16 : 18,
        isLandscape ? 8 : 14,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF101827).withValues(alpha: 0.90)
            : Colors.white.withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : const Color(0xFFD8E0EA),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.055),
            blurRadius: 16,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Obx(() {
              final uploading = controller.isUploading.value;
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.14 : 0.04,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed:
                      uploading ? null : () => _openCaptureScreen(context),
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: Text(
                    captureLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? const Color(0xFF1B2638)
                        : Colors.white,
                    disabledBackgroundColor: isDark
                        ? cDarkInputFillColor
                        : Colors.white.withValues(alpha: 0.72),
                    foregroundColor: isDark ? cDarkTextPrimary : cPrimary,
                    disabledForegroundColor: isDark
                        ? cDarkTextSecondary
                        : cPrimary.withValues(alpha: 0.42),
                    minimumSize: Size.fromHeight(isLandscape ? 42 : 48),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                      side: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.13)
                            : const Color(0xFFD8E0EA),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          SizedBox(width: isLandscape ? 8 : 10),
          Expanded(
            child: Obx(() {
              controller.mediaItems.length;
              controller.patrolContext.value;
              controller.isUploading.value;
              final canComplete = controller.canCompleteReport;
              final copy = VisitFlowCopy.fromContext(
                controller.patrolContext.value,
              );
              final completeAccent = _visitPrimaryActionColor(isDark);
              return ElevatedButton.icon(
                onPressed:
                    canComplete ? () => _uploadAllMedia(context) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: completeAccent,
                  disabledBackgroundColor: isDark
                      ? const Color(0xFF2A3548)
                      : const Color(0xFFC5D0E3),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.55)
                      : const Color(0xFF3F516A),
                  minimumSize: Size.fromHeight(isLandscape ? 42 : 48),
                  elevation: canComplete ? 2 : 0,
                  shadowColor: completeAccent.withValues(alpha: 0.24),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                    side: canComplete
                        ? BorderSide.none
                        : BorderSide(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.14)
                                : const Color(0xFF8FA3BD),
                          ),
                  ),
                ),
                icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                label: Text(
                  copy.completeReportButton,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _CheckpointProgressBar extends StatelessWidget {
  const _CheckpointProgressBar({
    required this.isDark,
    required this.completed,
    required this.total,
  });

  final bool isDark;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = total <= 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);
    final allDone = total > 0 && completed >= total;
    final accent = allDone
        ? const Color(0xFF059669)
        : _visitPrimaryActionColor(isDark);
    final track = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFE6EAF1);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _visitCardColor(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: allDone
              ? accent.withValues(alpha: isDark ? 0.40 : 0.26)
              : _visitBorderColor(isDark),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                allDone ? Icons.verified_rounded : Icons.flag_circle_outlined,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  allDone
                      ? 'All checkpoints completed'
                      : completed == 0
                      ? 'No checkpoints completed yet'
                      : '$completed of $total checkpoints completed',
                  style: TextStyle(
                    color: _visitTitleColor(isDark),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 7,
                  backgroundColor: track,
                  color: accent,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCheckpointProgressChip extends StatelessWidget {
  const _HeaderCheckpointProgressChip({
    required this.isDark,
    required this.completed,
    required this.total,
  });

  final bool isDark;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final allDone = total > 0 && completed >= total;
    final accent = allDone
        ? const Color(0xFF059669)
        : _visitPrimaryActionColor(isDark);
    final progress = total <= 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2.4,
                  backgroundColor: accent.withValues(alpha: 0.22),
                  color: accent,
                ),
                if (allDone) Icon(Icons.check_rounded, size: 11, color: accent),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$completed/$total',
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundTagProgressPanel extends StatelessWidget {
  const _RoundTagProgressPanel({
    required this.isDark,
    required this.rounds,
    required this.completedCount,
    required this.mediaCountFor,
    required this.onCapture,
    this.compact = false,
  });

  final bool isDark;
  final List<VisitPatrolRound> rounds;
  final int completedCount;
  final int Function(String roundTag) mediaCountFor;
  final ValueChanged<VisitPatrolRound> onCapture;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (rounds.isEmpty) return const SizedBox.shrink();

    final total = rounds.length;
    final completed = completedCount.clamp(0, total);
    final progress = total <= 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);
    final allDone = completed >= total;
    final accent = allDone
        ? const Color(0xFF059669)
        : _visitPrimaryActionColor(isDark);
    final track = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFE6EAF1);
    final copy = const VisitFlowCopy();
    final palette = VisitPatrolRoundColors.mapForTags(
      rounds.map((e) => e.roundTag),
    );

    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 12,
        compact ? 9 : 11,
        compact ? 10 : 12,
        compact ? 9 : 11,
      ),
      decoration: BoxDecoration(
        color: _visitCardColor(isDark),
        borderRadius: BorderRadius.circular(compact ? 13 : 15),
        border: Border.all(
          color: allDone
              ? accent.withValues(alpha: isDark ? 0.40 : 0.26)
              : _visitBorderColor(isDark),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                allDone ? Icons.verified_rounded : Icons.route_outlined,
                size: compact ? 16 : 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.roundTagsProgressTitle,
                      style: TextStyle(
                        color: _visitTitleColor(isDark),
                        fontSize: compact ? 12 : 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      copy.roundTagsProgressStatus(
                        completed: completed,
                        total: total,
                      ),
                      style: TextStyle(
                        color: _visitBodyColor(isDark),
                        fontSize: compact ? 10.5 : 11.5,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$completed/$total',
                style: TextStyle(
                  color: accent,
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 7 : 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: compact ? 6 : 7,
                  backgroundColor: track,
                  color: accent,
                );
              },
            ),
          ),
          SizedBox(height: compact ? 8 : 10),
          for (var i = 0; i < rounds.length; i++) ...[
            if (i > 0) SizedBox(height: compact ? 6 : 7),
            _RoundTagChecklistRow(
              isDark: isDark,
              compact: compact,
              round: rounds[i],
              color: VisitPatrolRoundColors.forTag(
                rounds[i].roundTag,
                palette: palette,
              ),
              mediaCount: mediaCountFor(rounds[i].roundTag),
              onTap: () => onCapture(rounds[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoundTagChecklistRow extends StatelessWidget {
  const _RoundTagChecklistRow({
    required this.isDark,
    required this.round,
    required this.color,
    required this.mediaCount,
    required this.onTap,
    this.compact = false,
  });

  final bool isDark;
  final VisitPatrolRound round;
  final Color color;
  final int mediaCount;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final done = mediaCount > 0;
    final statusColor = done ? const Color(0xFF059669) : color;
    final statusLabel = done
        ? (mediaCount == 1 ? '1 item' : '$mediaCount items')
        : 'Needed';
    final fill = done
        ? statusColor.withValues(alpha: isDark ? 0.16 : 0.08)
        : (isDark
              ? Colors.white.withValues(alpha: 0.04)
              : const Color(0xFFF7F9FC));
    final border = done
        ? statusColor.withValues(alpha: isDark ? 0.42 : 0.28)
        : _visitBorderColor(isDark);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 8 : 10,
              compact ? 8 : 9,
              compact ? 8 : 10,
              compact ? 8 : 9,
            ),
            child: Row(
              children: [
                Container(
                  width: compact ? 22 : 24,
                  height: compact ? 22 : 24,
                  decoration: BoxDecoration(
                    color: done
                        ? statusColor
                        : color.withValues(alpha: isDark ? 0.22 : 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    done ? Icons.check_rounded : Icons.circle_outlined,
                    size: compact ? 13 : 14,
                    color: done ? Colors.white : color,
                  ),
                ),
                SizedBox(width: compact ? 8 : 10),
                Expanded(
                  child: Text(
                    round.roundTag,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _visitTitleColor(isDark),
                      fontSize: compact ? 12.5 : 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 7 : 8,
                    vertical: compact ? 3 : 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: isDark ? 0.20 : 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: compact ? 10.5 : 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(width: compact ? 4 : 6),
                Icon(
                  Icons.camera_alt_outlined,
                  size: compact ? 15 : 16,
                  color: done ? statusColor : color,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckpointListCard extends StatelessWidget {
  const _CheckpointListCard({
    required this.checkpoint,
    required this.index,
    required this.isDark,
    required this.completed,
    required this.mediaCount,
    required this.onTap,
  });

  final VisitCheckpoint checkpoint;
  final int index;
  final bool isDark;
  final bool completed;
  final int mediaCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = completed
        ? const Color(0xFF059669)
        : _visitPrimaryActionColor(isDark);
    final statusLabel = completed
        ? (mediaCount > 1 ? 'Completed · $mediaCount items' : 'Completed')
        : (mediaCount > 0
              ? 'In progress · $mediaCount item${mediaCount == 1 ? '' : 's'}'
              : null);
    final photoUrl = checkpoint.photoUrl?.trim();
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    final description = checkpoint.description?.trim();
    final hasDescription = description != null && description.isNotEmpty;

    final subtitle = hasDescription ? description : statusLabel;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: completed
                ? accent.withValues(alpha: isDark ? 0.14 : 0.07)
                : _visitCardColor(isDark),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: completed
                  ? accent.withValues(alpha: isDark ? 0.48 : 0.30)
                  : _visitBorderColor(isDark),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.035),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: hasPhoto
                          ? Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, error, stackTrace) =>
                                  ColoredBox(
                                    color: accent,
                                    child: const Icon(
                                      Icons.location_on_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                            )
                          : ColoredBox(
                              color: accent,
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                    ),
                  ),
                  if (completed)
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        width: 17,
                        height: 17,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF0F1724)
                                : Colors.white,
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${index + 1}. ${checkpoint.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _visitTitleColor(isDark),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: completed && !hasDescription
                              ? (isDark
                                    ? const Color(0xFF6EE7B7)
                                    : const Color(0xFF047857))
                              : _visitBodyColor(isDark),
                          fontSize: 12,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (completed)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.22 : 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Done',
                    style: TextStyle(
                      color: isDark
                          ? const Color(0xFF6EE7B7)
                          : const Color(0xFF047857),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              else
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _visitPrimaryActionColor(
                      isDark,
                    ).withValues(alpha: isDark ? 0.16 : 0.08),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: _visitPrimaryActionColor(isDark),
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdditionalMediaEmptyCard extends StatelessWidget {
  const _AdditionalMediaEmptyCard({
    required this.isDark,
    required this.onCapture,
    this.isLandscape = false,
    this.isSiteCheck = false,
  });

  final bool isDark;
  final VoidCallback onCapture;
  final bool isLandscape;
  final bool isSiteCheck;

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.22)
        : const Color(0xFF9AA8BC);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onCapture,
        child: CustomPaint(
          painter: VisitDottedRoundedRectPainter(
            color: borderColor,
            radius: 16,
            strokeWidth: 1.4,
            dashLength: 6,
            gapLength: 4,
          ),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: isLandscape ? 14 : 16,
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _visitPrimaryActionColor(
                      isDark,
                    ).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.add_a_photo_outlined,
                    color: _visitPrimaryActionColor(isDark),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add More',
                        style: TextStyle(
                          color: _visitTitleColor(isDark),
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        VisitFlowCopy(
                          isSiteCheck: isSiteCheck,
                        ).additionalMediaSubtitle,
                        style: TextStyle(
                          color: _visitBodyColor(isDark),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: _visitBodyColor(isDark),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PatrolCompleteDialogBody extends StatelessWidget {
  const _PatrolCompleteDialogBody({
    required this.message,
    required this.flow,
    required this.isDark,
  });

  final String message;
  final VisitVideoFlowController flow;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.78)
        : const Color(0xFF475467);
    final copy = VisitFlowCopy.fromContext(flow.patrolContext.value);
    final showRounds = flow.supportsRoundTags;
    final roundSummary = copy.completionRoundsSummary(
      flow.patrolRounds.map(
        (round) => MapEntry(
          round.roundTag,
          flow.mediaCountForRoundTag(round.roundTag),
        ),
      ),
    );
    return Column(
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
        if (showRounds && roundSummary.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFF3F6FB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _visitBorderColor(isDark)),
            ),
            child: Text(
              roundSummary,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _visitTitleColor(isDark),
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        if (!copy.isStructuredReport) ...[
          const SizedBox(height: 14),
          VisitBatchNotesPanel(
            flow: flow,
            isDark: isDark,
            scope: VisitBatchNoteScope.generalNote,
            titleOverride: 'Additional note',
            showToggle: false,
            alwaysShowActions: true,
          ),
        ],
      ],
    );
  }
}

class _DraftLandscapeSidebar extends StatelessWidget {
  const _DraftLandscapeSidebar({
    required this.isDark,
    required this.hasMedia,
    required this.hasCheckpoints,
    required this.onCapture,
    required this.onComplete,
  });

  final bool isDark;
  final bool hasMedia;
  final bool hasCheckpoints;
  final VoidCallback onCapture;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<VisitVideoFlowController>();
    final primary = _visitPrimaryActionColor(isDark);
    final rightPad = Platform.isAndroid ? 8.0 : 6.0;
    final captureLabel = hasCheckpoints
        ? 'Add more'
        : (hasMedia ? 'Take more photos' : 'Take photos');
    final panelBg = isDark ? const Color(0xFF151E2F) : const Color(0xFFE7EEF7);
    final panelBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFD0DBE8);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: panelBg,
        border: Border(left: BorderSide(color: panelBorder)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(8, 8, rightPad, 8),
        child: SizedBox(
          width: 128,
          child: Obx(() {
            final uploading = controller.isUploading.value;
            controller.mediaItems.length;
            controller.patrolContext.value;
            final canComplete = controller.canCompleteReport;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 96,
                  child: _DraftLandscapeRailButton(
                    isDark: isDark,
                    filled: false,
                    accent: primary,
                    icon: Icons.add_a_photo_outlined,
                    label: captureLabel,
                    onPressed: uploading ? null : onCapture,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 96,
                  child: _DraftLandscapeRailButton(
                    isDark: isDark,
                    filled: true,
                    accent: primary,
                    icon: Icons.check_rounded,
                    label: VisitFlowCopy.fromContext(
                      controller.patrolContext.value,
                    ).completeReportButtonShort,
                    onPressed: canComplete ? onComplete : null,
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _DraftLandscapeRailButton extends StatelessWidget {
  const _DraftLandscapeRailButton({
    required this.isDark,
    required this.filled,
    required this.accent,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool isDark;
  final bool filled;
  final Color accent;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    final bg = filled
        ? (enabled
              ? accent
              : (isDark ? const Color(0xFF2A3548) : const Color(0xFFC5D0E3)))
        : (isDark ? const Color(0xFF1B2638) : Colors.white);
    final border = filled
        ? (enabled
              ? Colors.transparent
              : (isDark
                    ? Colors.white.withValues(alpha: 0.14)
                    : const Color(0xFF8FA3BD)))
        : (isDark
              ? Colors.white.withValues(alpha: 0.16)
              : const Color(0xFFD5DEEA));
    final labelColor = filled
        ? (enabled
              ? Colors.white
              : (isDark
                    ? Colors.white.withValues(alpha: 0.55)
                    : const Color(0xFF3F516A)))
        : (enabled
              ? (isDark ? cDarkTextPrimary : const Color(0xFF1F2A44))
              : (isDark
                    ? Colors.white.withValues(alpha: 0.45)
                    : const Color(0xFF98A2B3)));
    final iconFg = filled
        ? (enabled ? Colors.white : labelColor)
        : (enabled ? accent : labelColor);
    final iconBg = filled
        ? (enabled
              ? Colors.white.withValues(alpha: isDark ? 0.22 : 0.2)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFAEBDD2)))
        : accent.withValues(
            alpha: enabled ? (isDark ? 0.2 : 0.1) : (isDark ? 0.1 : 0.06),
          );

    return Material(
      color: bg,
      elevation: filled && enabled ? 1.5 : 0,
      shadowColor: accent.withValues(alpha: isDark ? 0.35 : 0.22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: iconBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconFg, size: 18),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportPreparingOverlay extends StatelessWidget {
  const _ReportPreparingOverlay({
    required this.isDark,
    required this.copy,
  });

  final bool isDark;
  final VisitFlowCopy copy;

  @override
  Widget build(BuildContext context) {
    final titleColor = isDark ? cDarkTextPrimary : const Color(0xFF0F172A);
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.72)
        : const Color(0xFF475467);
    final cardColor = isDark
        ? const Color(0xFF151E2F).withValues(alpha: 0.98)
        : Colors.white.withValues(alpha: 0.98);
    final accent = _visitPrimaryActionColor(isDark);

    return AbsorbPointer(
      child: ColoredBox(
        color: (isDark ? const Color(0xFF0B1220) : const Color(0xFFF4F7FB))
            .withValues(alpha: 0.92),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Material(
              color: cardColor,
              elevation: 0,
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : const Color(0xFFD8E0EA),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.28 : 0.08,
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 42,
                      height: 42,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.2,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      copy.preparingReportTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      copy.preparingReportMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: bodyColor,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VisitHeader extends StatelessWidget {
  const _VisitHeader({
    required this.isDark,
    required this.totalCount,
    required this.photoCount,
    required this.videoCount,
    required this.activeFilter,
    required this.onFilterChanged,
    required this.onBack,
    this.locationLabel,
    this.minimumPhotos,
    this.isLandscape = false,
    this.hasCheckpoints = false,
    this.checkpointCompleted = 0,
    this.checkpointTotal = 0,
    this.showMediaFilters = true,
    this.flowKind = VisitFlowKind.patrol,
    this.roundTags = const <VisitPatrolRound>[],
    this.roundTagCompleted = 0,
    this.activeRoundTag,
    this.onRoundTagChanged,
    this.deferCapturedMediaSection = false,
  });

  final bool isDark;
  final int totalCount;
  final int photoCount;
  final int videoCount;
  final _VisitMediaFilter activeFilter;
  final ValueChanged<_VisitMediaFilter> onFilterChanged;
  final VoidCallback onBack;
  final String? locationLabel;
  final int? minimumPhotos;
  final bool isLandscape;
  final bool hasCheckpoints;
  final int checkpointCompleted;
  final int checkpointTotal;
  final bool showMediaFilters;
  final VisitFlowKind flowKind;
  final List<VisitPatrolRound> roundTags;
  final int roundTagCompleted;
  final String? activeRoundTag;
  final ValueChanged<String?>? onRoundTagChanged;
  final bool deferCapturedMediaSection;

  @override
  Widget build(BuildContext context) {
    final location = locationLabel?.trim();
    final hasLocation = location != null && location.isNotEmpty;
    final titleColor = _visitTitleColor(isDark);
    final copy = VisitFlowCopy(kind: flowKind);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        isLandscape ? 4 : 8,
        16,
        isLandscape ? 4 : 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _HeaderIconButton(
                isDark: isDark,
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: onBack,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.draftTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: isLandscape ? 17 : 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    if (isLandscape) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            size: 13,
                            color: _visitPrimaryActionColor(isDark),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              hasLocation ? location : copy.noLocation,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _visitBodyColor(isDark),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (hasCheckpoints) ...[
                const SizedBox(width: 8),
                _HeaderCheckpointProgressChip(
                  isDark: isDark,
                  completed: checkpointCompleted,
                  total: checkpointTotal,
                ),
              ] else if (roundTags.isNotEmpty) ...[
                const SizedBox(width: 8),
                _HeaderCheckpointProgressChip(
                  isDark: isDark,
                  completed: roundTagCompleted,
                  total: roundTags.length,
                ),
              ],
            ],
          ),
          if (!isLandscape) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: _visitCardColor(isDark),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _visitBorderColor(isDark)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isDark ? 0.12 : 0.035,
                    ),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _visitPrimaryActionColor(isDark),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasLocation ? location : copy.noLocation,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            height: 1.18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (minimumPhotos != null && minimumPhotos! > 0) ...[
            SizedBox(height: isLandscape ? 6 : 10),
            _MinimumPhotosNotice(
              isDark: isDark,
              compact: isLandscape,
              minimumPhotos: minimumPhotos,
              embedded: true,
              isSiteCheck: flowKind == VisitFlowKind.siteCheck,
            ),
          ],
          if (!hasCheckpoints && !deferCapturedMediaSection) ...[
            SizedBox(height: isLandscape ? 6 : 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Captured Media ($totalCount)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: titleColor,
                      fontWeight: FontWeight.w800,
                      fontSize: isLandscape ? 13 : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (showMediaFilters &&
              !hasCheckpoints &&
              !deferCapturedMediaSection) ...[
            SizedBox(height: isLandscape ? 6 : 8),
            if (roundTags.isNotEmpty && onRoundTagChanged != null)
              _RoundTagFilterBar(
                isDark: isDark,
                rounds: roundTags,
                activeRoundTag: activeRoundTag,
                onChanged: onRoundTagChanged!,
                compact: isLandscape,
              )
            else
              _MediaFilterBar(
                isDark: isDark,
                activeFilter: activeFilter,
                totalCount: totalCount,
                photoCount: photoCount,
                videoCount: videoCount,
                onChanged: onFilterChanged,
                compact: isLandscape,
              ),
          ],
        ],
      ),
    );
  }
}

class _RoundTagChoicePanel extends StatelessWidget {
  const _RoundTagChoicePanel({
    required this.isDark,
    required this.message,
    required this.rounds,
    required this.colorPalette,
  });

  final bool isDark;
  final String message;
  final List<VisitPatrolRound> rounds;
  final Map<String, Color> colorPalette;

  @override
  Widget build(BuildContext context) {
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.72)
        : const Color(0xFF475467);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: bodyColor,
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < rounds.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _RoundTagChoiceButton(
            round: rounds[i],
            isDark: isDark,
            color: VisitPatrolRoundColors.forTag(
              rounds[i].roundTag,
              palette: colorPalette,
            ),
            onTap: () => Navigator.of(context).pop(rounds[i]),
          ),
        ],
      ],
    );
  }
}

class _RoundTagChoiceButton extends StatelessWidget {
  const _RoundTagChoiceButton({
    required this.round,
    required this.isDark,
    required this.color,
    required this.onTap,
  });

  final VisitPatrolRound round;
  final bool isDark;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final fill = color.withValues(alpha: isDark ? 0.18 : 0.08);
    final border = color.withValues(alpha: isDark ? 0.55 : 0.42);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: 1.4),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 13, 12, 13),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isDark ? 0.28 : 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.route_rounded,
                    color: color,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    round.roundTag,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: color.withValues(alpha: 0.9),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundTagFilterBar extends StatelessWidget {
  const _RoundTagFilterBar({
    required this.isDark,
    required this.rounds,
    required this.activeRoundTag,
    required this.onChanged,
    this.compact = false,
  });

  final bool isDark;
  final List<VisitPatrolRound> rounds;
  final String? activeRoundTag;
  final ValueChanged<String?> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = VisitPatrolRoundColors.mapForTags(
      rounds.map((e) => e.roundTag),
    );
    return Wrap(
      spacing: compact ? 6 : 8,
      runSpacing: compact ? 6 : 8,
      children: [
        _RoundFilterChip(
          label: 'All',
          color: _visitPrimaryActionColor(isDark),
          selected: activeRoundTag == null,
          isDark: isDark,
          compact: compact,
          onTap: () => onChanged(null),
        ),
        for (final round in rounds)
          _RoundFilterChip(
            label: round.roundTag,
            color: VisitPatrolRoundColors.forTag(
              round.roundTag,
              palette: palette,
            ),
            selected:
                activeRoundTag?.trim().toLowerCase() ==
                round.roundTag.trim().toLowerCase(),
            isDark: isDark,
            compact: compact,
            onTap: () => onChanged(round.roundTag),
          ),
      ],
    );
  }
}

class _RoundFilterChip extends StatelessWidget {
  const _RoundFilterChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.isDark,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final Color color;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? color
          : (isDark
                ? color.withValues(alpha: 0.16)
                : color.withValues(alpha: 0.10)),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 7 : 9,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? color
                  : color.withValues(alpha: isDark ? 0.45 : 0.28),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.22),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? Colors.white
                  : (isDark ? color.withValues(alpha: 0.95) : color),
              fontSize: compact ? 11.5 : 12.5,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundTagBadge extends StatelessWidget {
  const _RoundTagBadge({
    required this.label,
    required this.isDark,
    this.compact = false,
  });

  final String label;
  final bool isDark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    List<String> amongTags = const <String>[];
    if (Get.isRegistered<VisitVideoFlowController>()) {
      amongTags = Get.find<VisitVideoFlowController>()
          .patrolRounds
          .map((e) => e.roundTag)
          .toList(growable: false);
    }
    final accent = VisitPatrolRoundColors.forTag(
      label,
      amongTags: amongTags,
    );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? accent.withValues(alpha: 0.20)
            : accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark
              ? accent.withValues(alpha: 0.40)
              : accent.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: accent,
          fontSize: compact ? 10.5 : 11.5,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}

class _MediaFilterBar extends StatelessWidget {
  const _MediaFilterBar({
    required this.isDark,
    required this.activeFilter,
    required this.totalCount,
    required this.photoCount,
    required this.videoCount,
    required this.onChanged,
    this.compact = false,
  });

  final bool isDark;
  final _VisitMediaFilter activeFilter;
  final int totalCount;
  final int photoCount;
  final int videoCount;
  final ValueChanged<_VisitMediaFilter> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MediaFilterChip(
            label: 'All',
            selected: activeFilter == _VisitMediaFilter.all,
            isDark: isDark,
            compact: compact,
            onTap: () => onChanged(_VisitMediaFilter.all),
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        Expanded(
          child: _MediaFilterChip(
            label: compact ? 'Photos' : 'Photos ($photoCount)',
            selected: activeFilter == _VisitMediaFilter.photos,
            isDark: isDark,
            compact: compact,
            onTap: () => onChanged(_VisitMediaFilter.photos),
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        Expanded(
          child: _MediaFilterChip(
            label: compact ? 'Videos' : 'Videos ($videoCount)',
            selected: activeFilter == _VisitMediaFilter.videos,
            isDark: isDark,
            compact: compact,
            onTap: () => onChanged(_VisitMediaFilter.videos),
          ),
        ),
      ],
    );
  }
}

class _MediaFilterChip extends StatelessWidget {
  const _MediaFilterChip({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final selectedColor = _visitPrimaryActionColor(isDark);
    return Material(
      color: selected
          ? selectedColor
          : (isDark ? const Color(0xFF172033) : Colors.white),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: compact ? 30 : 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? selectedColor
                  : _visitBorderColor(isDark).withValues(alpha: 0.95),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: selectedColor.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : _visitTitleColor(isDark),
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.isDark,
    required this.icon,
    required this.onTap,
  });

  final bool isDark;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _visitCardColor(isDark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _visitBorderColor(isDark)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Center(
            child: Icon(icon, color: _visitTitleColor(isDark), size: 20),
          ),
        ),
      ),
    );
  }
}

class VisitMediaPreviewCard extends StatelessWidget {
  const VisitMediaPreviewCard({
    super.key,
    required this.item,
    required this.index,
    required this.isDark,
    required this.onPreview,
    required this.onDelete,
    this.featured = false,
    this.compact = false,
    this.thumbnailFuture,
  });

  final VisitMediaItem item;
  final int index;
  final bool isDark;
  final VoidCallback onPreview;
  final VoidCallback onDelete;
  final bool featured;
  final bool compact;
  final Future<Uint8List?>? thumbnailFuture;

  bool get _hideMediaAttentionToggle {
    if (!Get.isRegistered<VisitVideoFlowController>()) return false;
    return Get.find<VisitVideoFlowController>().isStructuredReport;
  }

  @override
  Widget build(BuildContext context) {
    final thumbnailSize = compact
        ? 72.0
        : featured
        ? 118.0
        : 92.0;
    final title = item.isPhoto ? 'Photo ${index + 1}' : 'Video ${index + 1}';
    final roundTag = item.resolvedRoundTag;
    const attentionAccent = Color(0xFFE11D48);
    final attentionOn =
        item.attentionNeeded && !_hideMediaAttentionToggle;

    return Material(
      color: _visitCardColor(isDark),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border(
            top: BorderSide(color: _visitBorderColor(isDark)),
            right: BorderSide(color: _visitBorderColor(isDark)),
            bottom: BorderSide(color: _visitBorderColor(isDark)),
            left: BorderSide(
              color: attentionOn ? attentionAccent : _visitBorderColor(isDark),
              width: attentionOn ? 3 : 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.14 : 0.04),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : (featured ? 12 : 10),
            compact ? 8 : (featured ? 12 : 10),
            compact ? 8 : (featured ? 12 : 10),
            compact ? 8 : (featured ? 12 : 10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MediaThumbnail(
                    item: item,
                    isDark: isDark,
                    size: thumbnailSize,
                    thumbnailFuture: thumbnailFuture,
                    onPreview: onPreview,
                  ),
                  SizedBox(width: compact ? 10 : (featured ? 12 : 11)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _visitTitleColor(isDark),
                                      fontSize: featured ? 15.5 : 14,
                                      fontWeight: FontWeight.w800,
                                      height: 1.15,
                                    ),
                                  ),
                                  if (roundTag != null) ...[
                                    const SizedBox(height: 5),
                                    _RoundTagBadge(
                                      label: roundTag,
                                      isDark: isDark,
                                      compact: compact,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: item.isPhoto
                                  ? 'Delete photo'
                                  : 'Delete video',
                              child: Material(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: onDelete,
                                  child: SizedBox(
                                    width: featured ? 34 : 32,
                                    height: featured ? 34 : 32,
                                    child: Center(
                                      child: VisitDeleteIcon(
                                        size: featured ? 15 : 14,
                                        color: cRed.withValues(
                                          alpha: isDark ? 0.92 : 0.88,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!_hideMediaAttentionToggle) ...[
                          SizedBox(height: compact ? 8 : 10),
                          _MediaAttentionToggle(
                            item: item,
                            isDark: isDark,
                            compact: compact,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 7 : 8),
              _InlineNotePanel(
                item: item,
                isDark: isDark,
                compact: compact,
                featured: featured,
                attentionNeeded: attentionOn && !_hideMediaAttentionToggle,
              ),
              SizedBox(height: compact ? 8 : 9),
              Row(
                children: [
                  Expanded(
                    child: _MediaNoteButton(
                      label: item.hasTextNote ? 'Edit Text' : 'Text',
                      icon: item.hasTextNote
                          ? Icons.edit_note_rounded
                          : Icons.sticky_note_2_outlined,
                      isDark: isDark,
                      dense: !featured,
                      alertStyle: attentionOn,
                      onPressed: () => openVisitMediaNotesSheet(
                        context: context,
                        item: item,
                        kind: VisitMediaNoteKind.text,
                      ),
                    ),
                  ),
                  SizedBox(width: featured ? 8 : 7),
                  Expanded(
                    child: _MediaNoteButton(
                      label: item.hasVoiceNote ? 'Edit Voice' : 'Voice',
                      icon: item.hasVoiceNote
                          ? Icons.mic_rounded
                          : Icons.mic_none_rounded,
                      isDark: isDark,
                      dense: !featured,
                      alertStyle: attentionOn,
                      onPressed: () => openVisitMediaNotesSheet(
                        context: context,
                        item: item,
                        kind: VisitMediaNoteKind.voice,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaAttentionToggle extends StatelessWidget {
  const _MediaAttentionToggle({
    required this.item,
    required this.isDark,
    required this.compact,
  });

  final VisitMediaItem item;
  final bool isDark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFE11D48);
    final on = item.attentionNeeded;
    final flow = Get.find<VisitVideoFlowController>();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 10,
        compact ? 5 : 6,
        compact ? 2 : 4,
        compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: on
            ? accent.withValues(alpha: isDark ? 0.16 : 0.08)
            : (isDark
                  ? Colors.white.withValues(alpha: 0.045)
                  : const Color(0xFFF3F6FA)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              'Attention needed/Urgent',
              maxLines: 2,
              softWrap: true,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: on
                    ? (isDark
                          ? const Color(0xFFFFE4E6)
                          : const Color(0xFF9F1239))
                    : _visitTitleColor(isDark),
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 2),
          SizedBox(
            width: compact ? 34 : 36,
            height: compact ? 20 : 22,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.centerRight,
              child: Switch.adaptive(
                value: on,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                activeTrackColor: accent.withValues(alpha: 0.55),
                activeThumbColor: accent,
                onChanged: (value) {
                  unawaited(
                    flow.setMediaAttentionNeeded(
                      mediaPath: item.path,
                      attentionNeeded: value,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineNotePanel extends StatelessWidget {
  const _InlineNotePanel({
    required this.item,
    required this.isDark,
    required this.compact,
    required this.featured,
    this.attentionNeeded = false,
  });

  final VisitMediaItem item;
  final bool isDark;
  final bool compact;
  final bool featured;
  final bool attentionNeeded;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(10);
    final padding = EdgeInsets.symmetric(
      horizontal: compact ? 8 : 9,
      vertical: compact ? 7 : 8,
    );

    final accent = _visitAccentColor(isDark);
    final bodyColor = _visitBodyColor(isDark);
    final panelBg = attentionNeeded
        ? (isDark
              ? const Color(0xFF1A1520).withValues(alpha: 0.55)
              : const Color(0xFFFFF7F8))
        : (isDark
              ? const Color(0xFF0F1729).withValues(alpha: 0.55)
              : const Color(0xFFF3F6FA));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(color: panelBg, borderRadius: radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.hasTextNote || !item.hasVoiceNote)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.sticky_note_2_outlined,
                    size: compact ? 13 : 14,
                    color: bodyColor.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    item.hasTextNote ? item.textNote : 'No note added',
                    softWrap: true,
                    style: TextStyle(
                      color: item.hasTextNote
                          ? _visitTitleColor(isDark)
                          : bodyColor,
                      fontSize: compact ? 11 : (featured ? 12.5 : 12),
                      height: 1.35,
                      fontWeight: item.hasTextNote
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          if (item.hasTextNote && item.hasVoiceNote)
            SizedBox(height: compact ? 6 : 8),
          if (item.hasVoiceNote)
            InlineVoiceNotePlayer(
              path: item.voiceNotePath!,
              isDark: isDark,
              accent: accent,
              compact: compact,
            ),
        ],
      ),
    );
  }
}

class _MediaThumbnail extends StatelessWidget {
  const _MediaThumbnail({
    required this.item,
    required this.isDark,
    required this.size,
    required this.onPreview,
    this.thumbnailFuture,
  });

  final VisitMediaItem item;
  final bool isDark;
  final double size;
  final VoidCallback onPreview;
  final Future<Uint8List?>? thumbnailFuture;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPreview,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: _previewImage(context)),
              Positioned(
                top: 6,
                left: 6,
                child: _MediaOverlayPill(
                  icon: item.isPhoto
                      ? Icons.photo_outlined
                      : Icons.videocam_outlined,
                  label: item.isPhoto ? 'Photo' : 'Video',
                ),
              ),
              if (item.isVideo)
                const Center(
                  child: VisitMediaPlayOverlay(
                    size: VisitMediaPlayOverlaySize.compact,
                  ),
                ),
              if (item.hasStamp)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: VisitMediaStampBar(
                    label: item.stampLabel,
                    compact: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewImage(BuildContext context) {
    if (item.isPhoto) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final px = (size * dpr).round().clamp(96, 256);
      return Image(
        key: ValueKey<String>('thumb-${item.captureId ?? item.path}'),
        image: ResizeImage(
          FileImage(File(item.path)),
          width: px,
          height: px,
          allowUpscaling: false,
        ),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            CamPerf.firstFrameOnce(
              'thumb:${item.captureId ?? item.path}',
              item.captureId,
              'DRAFT_THUMBNAIL_FIRST_FRAME',
              fromDraftVisible: true,
            );
            return child;
          }
          return ColoredBox(
            color: isDark ? const Color(0xFF182334) : Colors.black12,
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return _fallback(Icons.broken_image_outlined);
        },
      );
    }

    return FutureBuilder<Uint8List?>(
      future: thumbnailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ColoredBox(
            color: isDark ? const Color(0xFF182334) : Colors.black12,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _fallback(Icons.video_file_rounded);
      },
    );
  }

  Widget _fallback(IconData icon) {
    return ColoredBox(
      color: isDark ? const Color(0xFF182334) : Colors.grey.shade200,
      child: Icon(icon, color: Colors.black54, size: 28),
    );
  }
}

class _MediaNoteButton extends StatelessWidget {
  const _MediaNoteButton({
    required this.label,
    required this.icon,
    required this.isDark,
    required this.dense,
    required this.onPressed,
    this.alertStyle = false,
  });

  final String label;
  final IconData icon;
  final bool isDark;
  final bool dense;
  final VoidCallback onPressed;
  final bool alertStyle;

  @override
  Widget build(BuildContext context) {
    const alert = Color(0xFFE11D48);
    final brand = _visitAccentColor(isDark);
    final foreground = alertStyle
        ? (isDark ? const Color(0xFFFFE4E6) : const Color(0xFF9F1239))
        : brand;
    final background = alertStyle
        ? alert.withValues(alpha: isDark ? 0.14 : 0.07)
        : brand.withValues(alpha: isDark ? 0.16 : 0.10);

    return SizedBox(
      height: dense ? 34 : 38,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(dense ? 10 : 11),
          ),
        ),
        icon: Icon(icon, size: dense ? 14 : 16),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: dense ? 11 : 12,
          ),
        ),
      ),
    );
  }
}

class _MediaOverlayPill extends StatelessWidget {
  const _MediaOverlayPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class VisitPhotoViewer extends StatelessWidget {
  const VisitPhotoViewer({
    super.key,
    required this.imagePath,
    this.stampLabel = '',
    this.hasNotes = false,
    this.onDelete,
  });

  final String imagePath;
  final String stampLabel;
  final bool hasNotes;
  final VoidCallback? onDelete;

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await GlassActionDialog.show(
      context: context,
      icon: Icons.delete_outline_rounded,
      iconWidget: const VisitDeleteIcon(size: 28, color: Color(0xFFE53935)),
      iconColor: cRed,
      title: 'Delete Photo?',
      message: VisitVideoPreviewScreen.deleteMediaMessage(
        isPhoto: true,
        hasNotes: hasNotes,
        isSiteCheck: Get.isRegistered<VisitVideoFlowController>() &&
            Get.find<VisitVideoFlowController>()
                    .patrolContext
                    .value
                    ?.isSiteCheck ==
                true,
      ),
      secondaryLabel: 'Cancel',
      primaryLabel: 'Delete',
      variant: GlassActionDialogVariant.error,
    );
    if (confirmed == true) {
      onDelete?.call();
      Get.back();
    }
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        final isLandscape = orientation == Orientation.landscape;

        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 8 || constraints.maxHeight < 8) {
                  return const ColoredBox(color: Colors.black);
                }

                final coverLandscape = isLandscape;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 4,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          child: coverLandscape
                              ? Stack(
                                  fit: StackFit.expand,
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    Image.file(
                                      File(imagePath),
                                      fit: BoxFit.cover,
                                      alignment: Alignment.center,
                                      width: constraints.maxWidth,
                                      height: constraints.maxHeight,
                                      gaplessPlayback: true,
                                      cacheWidth:
                                          (MediaQuery.sizeOf(context)
                                                      .longestSide *
                                                  MediaQuery.devicePixelRatioOf(
                                                    context,
                                                  ))
                                              .round()
                                              .clamp(720, 2560),
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const Center(
                                                child: Text(
                                                  'Unable to load this photo',
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                              ),
                                    ),
                                    if (stampLabel.isNotEmpty)
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: 0,
                                        child: VisitMediaStampBar(
                                          label: stampLabel,
                                        ),
                                      ),
                                  ],
                                )
                              : Center(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: constraints.maxWidth,
                                      maxHeight: constraints.maxHeight,
                                    ),
                                    child: Stack(
                                      alignment: Alignment.bottomCenter,
                                      children: [
                                        Image.file(
                                          File(imagePath),
                                          fit: BoxFit.contain,
                                          gaplessPlayback: true,
                                          cacheWidth:
                                              (MediaQuery.sizeOf(context)
                                                          .longestSide *
                                                      MediaQuery
                                                          .devicePixelRatioOf(
                                                            context,
                                                          ))
                                                  .round()
                                                  .clamp(720, 2560),
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  const Text(
                                                    'Unable to load this photo',
                                                    style: TextStyle(
                                                      color: Colors.white70,
                                                    ),
                                                  ),
                                        ),
                                        if (stampLabel.isNotEmpty)
                                          Positioned(
                                            left: 0,
                                            right: 0,
                                            bottom: 0,
                                            child: VisitMediaStampBar(
                                              label: stampLabel,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.55),
                              Colors.black.withValues(alpha: 0.28),
                              Colors.black.withValues(alpha: 0.0),
                            ],
                            stops: const [0.0, 0.55, 1.0],
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            8,
                            isLandscape ? 2 : 4,
                            8,
                            isLandscape ? 18 : 22,
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: () => Get.back(),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              const Expanded(
                                child: Text(
                                  'Photo Preview',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              if (onDelete != null)
                                IconButton(
                                  onPressed: () => _confirmDelete(context),
                                  icon: const VisitDeleteIcon(
                                    size: 22,
                                    color: cRed,
                                  ),
                                )
                              else
                                const SizedBox(width: 48),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (onDelete != null && !isLandscape)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.45),
                                Colors.black.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: OutlinedButton.icon(
                                onPressed: () => _confirmDelete(context),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: cRed,
                                  backgroundColor:
                                      Colors.black.withValues(alpha: 0.35),
                                  side: BorderSide(
                                    color: cRed.withValues(alpha: 0.7),
                                  ),
                                ),
                                icon: const VisitDeleteIcon(
                                  size: 18,
                                  color: cRed,
                                ),
                                label: const Text('Delete Photo'),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class VisitVideoPlayerDialog extends GetView<VisitVideoPlayerController> {
  final String videoPath;
  final String stampLabel;
  final bool hasNotes;
  final VoidCallback? onDelete;

  const VisitVideoPlayerDialog({
    super.key,
    required this.videoPath,
    this.stampLabel = '',
    this.hasNotes = false,
    this.onDelete,
  });

  @override
  String? get tag => videoPath;

  @override
  Widget build(BuildContext context) {
    final fileName = videoPath.split('/').last;

    return OrientationBuilder(
      builder: (context, orientation) {
        controller.handleOrientationChange(orientation);
        final isLandscape = orientation == Orientation.landscape;

        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 8 || constraints.maxHeight < 8) {
                  return const ColoredBox(color: Colors.black);
                }

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: Obx(() {
                        if (controller.isLoading.value) {
                          return const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                cOrange,
                              ),
                            ),
                          );
                        }

                        if (controller.errorMessage.value != null) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Text(
                                controller.errorMessage.value!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                          );
                        }

                        final videoCtrl = controller.videoController;
                        if (videoCtrl == null ||
                            !videoCtrl.value.isInitialized) {
                          return const Center(
                            child: Text(
                              'Unable to load this video',
                              style: TextStyle(color: Colors.white70),
                            ),
                          );
                        }

                        return _buildVideoArea(videoCtrl);
                      }),
                    ),
                    Obx(() {
                      final visible = controller.showControls.value;
                      return IgnorePointer(
                        ignoring: !visible,
                        child: AnimatedOpacity(
                          opacity: visible ? 1 : 0,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: Stack(
                            children: [
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding: EdgeInsets.fromLTRB(
                                    4,
                                    isLandscape ? 2 : 6,
                                    4,
                                    isLandscape ? 4 : 8,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black.withValues(alpha: 0.55),
                                        Colors.black.withValues(alpha: 0.28),
                                        Colors.black.withValues(alpha: 0.0),
                                      ],
                                      stops: const [0.0, 0.55, 1.0],
                                    ),
                                  ),
                                  child: _buildTopBar(context, fileName),
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: _buildControlBar(
                                  context,
                                  isLandscape: isLandscape,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context, String fileName) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.close_rounded, color: Colors.white),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        if (onDelete != null)
          IconButton(
            onPressed: () => _showDeleteDialog(context),
            tooltip: 'Delete',
            icon: const VisitDeleteIcon(size: 22, color: cRed),
          ),
      ],
    );
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final confirmed = await GlassActionDialog.show(
      context: context,
      icon: Icons.delete_outline_rounded,
      iconWidget: const VisitDeleteIcon(size: 28, color: Color(0xFFE53935)),
      iconColor: cRed,
      title: 'Delete Video?',
      message: VisitVideoPreviewScreen.deleteMediaMessage(
        isPhoto: false,
        hasNotes: hasNotes,
        isSiteCheck: Get.isRegistered<VisitVideoFlowController>() &&
            Get.find<VisitVideoFlowController>()
                    .patrolContext
                    .value
                    ?.isSiteCheck ==
                true,
      ),
      secondaryLabel: 'Cancel',
      primaryLabel: 'Delete',
      variant: GlassActionDialogVariant.error,
    );

    if (confirmed == true) {
      onDelete?.call();
      Get.back();
    }
  }

  Widget _buildVideoArea(VideoPlayerController videoCtrl) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: controller.onScreenTap,
      child: ColoredBox(
        color: Colors.black,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 8 || constraints.maxHeight < 8) {
              return const SizedBox.expand();
            }

            final isLandscape =
                MediaQuery.orientationOf(context) == Orientation.landscape;
            final videoSize = videoCtrl.value.size;
            final aspect = (videoSize.width <= 0 || videoSize.height <= 0)
                ? 16 / 9
                : videoSize.width / videoSize.height;

            Widget playerStack({required double width, required double height}) {
              return SizedBox(
                width: width,
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    if (isLandscape)
                      FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: videoSize.width <= 0 ? 16 : videoSize.width,
                          height: videoSize.height <= 0 ? 9 : videoSize.height,
                          child: VideoPlayer(videoCtrl),
                        ),
                      )
                    else
                      VideoPlayer(videoCtrl),
                    Obx(() {
                      final showPlayButton =
                          controller.showControls.value &&
                          !controller.isPlaying.value &&
                          !controller.isSeeking.value &&
                          !controller.wasPlayingBeforeSeek.value;

                      if (!showPlayButton) {
                        return const SizedBox.shrink();
                      }

                      return const VisitMediaPlayOverlay(
                        size: VisitMediaPlayOverlaySize.large,
                      );
                    }),
                    if (stampLabel.isNotEmpty)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: VisitMediaStampBar(label: stampLabel),
                      ),
                  ],
                ),
              );
            }

            if (isLandscape) {
              return playerStack(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
              );
            }

            var width = constraints.maxWidth;
            var height = width / aspect;
            if (height > constraints.maxHeight) {
              height = constraints.maxHeight;
              width = height * aspect;
            }

            return Center(
              child: playerStack(width: width, height: height),
            );
          },
        ),
      ),
    );
  }

  Widget _buildControlBar(BuildContext context, {required bool isLandscape}) {
    if (controller.isLoading.value || !controller.isPlayerReady) {
      return const SizedBox(height: 24);
    }

    final durationMs = controller.durationMs.value;
    final positionMs = controller.positionMs.value.clamp(
      0,
      durationMs == 0 ? 0 : durationMs,
    );

    final seekSlider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        activeTrackColor: cOrange,
        inactiveTrackColor: Colors.white24,
        thumbColor: cOrange,
        overlayColor: cOrange.withAlpha(40),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      child: Slider(
        value: durationMs <= 0 ? 0 : positionMs.toDouble(),
        min: 0,
        max: durationMs <= 0 ? 1 : durationMs.toDouble(),
        onChangeStart: (_) {
          controller.wasPlayingBeforeSeek.value = controller.isPlaying.value;
          controller.isSeeking.value = true;
          controller.revealControls(autoHide: false);
        },
        onChanged: (v) async {
          await controller.seekTo(v.round());
        },
        onChangeEnd: (_) async {
          final shouldResume = controller.wasPlayingBeforeSeek.value;
          controller.isSeeking.value = false;
          controller.wasPlayingBeforeSeek.value = false;

          if (shouldResume && !controller.isPlaying.value) {
            final video = controller.videoController;
            if (video != null && video.value.isInitialized) {
              await video.play();
            }
          }
          controller.revealControls(autoHide: controller.isPlaying.value);
        },
      ),
    );

    final transportRow = Row(
      children: [
        IconButton(
          onPressed: controller.togglePlayPause,
          icon: Icon(
            controller.isPlaying.value
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_fill_rounded,
            color: Colors.white,
            size: 36,
          ),
        ),
        IconButton(
          onPressed: () {
            controller.toggleMute();
            controller.revealControls(autoHide: controller.isPlaying.value);
          },
          icon: Icon(
            controller.isMuted.value || controller.volume.value == 0
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.5,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white.withAlpha(35),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: controller.volume.value,
              min: 0,
              max: 1,
              onChanged: (v) {
                controller.setPlayerVolume(v);
                controller.revealControls(autoHide: controller.isPlaying.value);
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${formatMMSS((positionMs / 1000).floor())} / ${formatMMSS((durationMs / 1000).floor())}',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 8),
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isLandscape ? 10 : 12,
        isLandscape ? 2 : 4,
        isLandscape ? 10 : 12,
        isLandscape ? 6 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(210),
        border: const Border(top: BorderSide(color: Colors.white12)),
      ),
      child: isLandscape
          ? Row(
              children: [
                IconButton(
                  onPressed: controller.togglePlayPause,
                  icon: Icon(
                    controller.isPlaying.value
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                Expanded(child: seekSlider),
                IconButton(
                  onPressed: () {
                    controller.toggleMute();
                    controller.revealControls(
                      autoHide: controller.isPlaying.value,
                    );
                  },
                  icon: Icon(
                    controller.isMuted.value || controller.volume.value == 0
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3.5,
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white.withAlpha(35),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                    ),
                    child: Slider(
                      value: controller.volume.value,
                      min: 0,
                      max: 1,
                      onChanged: (v) {
                        controller.setPlayerVolume(v);
                        controller.revealControls(
                          autoHide: controller.isPlaying.value,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${formatMMSS((positionMs / 1000).floor())} / ${formatMMSS((durationMs / 1000).floor())}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 6),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [seekSlider, transportRow],
            ),
    );
  }
}

class _DraftAutosaveNotice extends StatelessWidget {
  const _DraftAutosaveNotice({required this.isDark, this.compact = false});

  final bool isDark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (VisitVideoPreviewScreen._draftAutosaveNoticeDismissed.value) {
        return const SizedBox.shrink();
      }

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
      final closeColor = isDark
          ? Colors.white.withValues(alpha: 0.55)
          : const Color(0xFF64748B);

      return Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 16,
          compact ? 4 : 0,
          compact ? 12 : 16,
          compact ? 8 : 8,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(compact ? 12 : 14),
            border: Border.all(color: border),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 10 : 12,
              compact ? 8 : 10,
              compact ? 4 : 6,
              compact ? 8 : 10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: compact ? 1 : 2),
                  child: Icon(
                    Icons.cloud_done_outlined,
                    size: compact ? 16 : 18,
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
                        'Saved as a draft',
                        style: TextStyle(
                          color: titleColor,
                          fontSize: compact ? 12 : 13,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: compact ? 2 : 3),
                      Text(
                        'You can leave the app anytime. Your report will be saved. '
                        'Open the app later to finish and upload.',
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
                IconButton(
                  onPressed: () {
                    VisitVideoPreviewScreen
                            ._draftAutosaveNoticeDismissed
                            .value =
                        true;
                  },
                  tooltip: 'Close',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(
                    minWidth: compact ? 28 : 32,
                    minHeight: compact ? 28 : 32,
                  ),
                  icon: Icon(
                    Icons.close_rounded,
                    size: compact ? 16 : 18,
                    color: closeColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _MinimumPhotosNotice extends StatelessWidget {
  const _MinimumPhotosNotice({
    required this.isDark,
    required this.minimumPhotos,
    this.compact = false,
    this.embedded = false,
    this.isSiteCheck = false,
  });

  final bool isDark;
  final int? minimumPhotos;
  final bool compact;
  final bool embedded;
  final bool isSiteCheck;

  @override
  Widget build(BuildContext context) {
    final count = minimumPhotos;
    if (count == null || count <= 0) {
      return const SizedBox.shrink();
    }

    final photoLabel = count == 1 ? 'photo' : 'photos';
    final bg = isDark
        ? const Color(0xFF2A2118).withValues(alpha: 0.95)
        : const Color(0xFFFFF7ED);
    final border = isDark
        ? const Color(0xFFE48E15).withValues(alpha: 0.35)
        : const Color(0xFFFDBA74);
    final iconColor = isDark
        ? const Color(0xFFFBBF24)
        : const Color(0xFFC2410C);
    final titleColor = isDark ? Colors.white : const Color(0xFF7C2D12);
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.75)
        : const Color(0xFF9A3412);
    final bodyText = VisitFlowCopy(
      isSiteCheck: isSiteCheck,
    ).minimumPhotosBody(count, photoLabel);

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        border: Border.all(color: border),
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
            Padding(
              padding: EdgeInsets.only(top: compact ? 1 : 2),
              child: Icon(
                Icons.photo_library_outlined,
                size: compact ? 16 : 18,
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
                    'Report requirement',
                    style: TextStyle(
                      color: titleColor,
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: compact ? 2 : 3),
                  Text(
                    bodyText,
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

    if (embedded) return card;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 16,
        0,
        compact ? 12 : 16,
        compact ? 6 : 8,
      ),
      child: card,
    );
  }
}

class _UploadFailureDialogBody extends StatelessWidget {
  const _UploadFailureDialogBody({
    required this.summary,
    required this.locationLabel,
    required this.affectedLabels,
    required this.guidance,
    required this.isDark,
  });

  final String summary;
  final String locationLabel;
  final List<String> affectedLabels;
  final String guidance;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.86)
        : const Color(0xFF475467);
    final chipBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFF3F5F8);
    final chipFg = isDark ? const Color(0xFFFECACA) : const Color(0xFF9F1239);
    final summaryText = summary.trim();
    final guidanceText = guidance.trim();
    final place = locationLabel.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (place.isNotEmpty) ...[
          Text(
            place,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF2563EB),
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (summaryText.isNotEmpty)
          Text(
            summaryText,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: bodyColor,
              fontSize: 14.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        if (guidanceText.isNotEmpty) ...[
          if (summaryText.isNotEmpty) const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFFE53935).withValues(alpha: 0.12)
                  : const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFE53935).withValues(alpha: 0.28),
              ),
            ),
            child: Column(
              children: [
                for (final line
                    in guidanceText
                        .split('\n')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)) ...[
                  Text(
                    line,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark
                          ? const Color(0xFFFECACA)
                          : const Color(0xFF9F1239),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ],
            ),
          ),
        ],
        if (affectedLabels.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Affected media',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF20283A),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final label in affectedLabels)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFFE53935).withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: chipFg,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
