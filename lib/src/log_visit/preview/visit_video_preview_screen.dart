import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import '../../api/visit_upload_api.dart';
import '../../app/app_navigator.dart';
import '../../app/app_routes.dart';
import '../../widgets/dialogs/glass_action_dialog.dart';
import '../flow/visit_gps_session.dart';
import '../flow/visit_media_geo.dart';
import '../flow/visit_video_flow_controller.dart';
import '../log_visit_theme.dart';
import '../notes/visit_batch_notes_panel.dart';
import '../notes/visit_media_notes_sheet.dart';
import '../notes/voice/inline_voice_note_player.dart';
import '../record/visit_video_recorder_controller.dart';
import '../record/visit_video_recorder_screen.dart';
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

enum _VisitMediaFilter { all, photos, videos }

class VisitVideoPreviewScreen extends GetView<VisitVideoFlowController> {
  static final Rx<_VisitMediaFilter> _mediaFilter = _VisitMediaFilter.all.obs;

  const VisitVideoPreviewScreen({
    super.key,
    this.onBack,
    this.onUploadSuccess,
    this.bottomBarClearance = 0,
  });

  final VoidCallback? onBack;
  final VoidCallback? onUploadSuccess;
  final double bottomBarClearance;

  @override
  VisitVideoFlowController get controller {
    if (!Get.isRegistered<VisitVideoFlowController>()) {
      Get.put(VisitVideoFlowController(), permanent: true);
    }
    return Get.find<VisitVideoFlowController>();
  }

  void _handleBack(BuildContext context) {
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
  }) {
    final media = isPhoto ? 'photo' : 'video';
    if (hasNotes) {
      return 'This $media and its note will be removed from your patrol round report. This cannot be undone.';
    }
    return 'This $media will be removed from your patrol round report. This cannot be undone.';
  }

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

  Future<void> _openMediaPreview(VisitMediaItem item, int index) async {
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
    );
  }

  Future<void> _openCaptureScreen() async {
    await Get.to(
      () => const VisitVideoRecorderScreen(),
      routeName: AppRoutes.visitVideoRecorder,
      binding: BindingsBuilder(() {
        Get.put(VisitVideoRecorderController());
      }),
    );
  }

  static Future<void> uploadCurrentDraft({
    BuildContext? context,
    VoidCallback? onSuccess,
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

    final items = flow.mediaItems.toList(growable: false);
    if (items.isEmpty) {
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

    final confirmed = await _confirmPatrolUploadCompletion(
      flow: flow,
      isDark: isDark,
      context: context,
    );
    if (!confirmed) return;

    flow.isUploading.value = true;
    _showUploadingSnack(itemCount: items.length, isDark: isDark);

    try {
      final meta = flow.buildUploadMeta();
      if (kDebugMode) {
        debugPrint('[VisitUpload] meta=$meta');
      }

      final result = await VisitUploadApi.instance.uploadVisit(
        meta: meta,
        items: items,
        batchVoicePath: flow.batchNote.value.voiceNotePath,
      );

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
        await flow.clearAll();
        unawaited(VisitGpsSession.instance.stop());
        if (context != null && !context.mounted) return;
        await _showUploadSuccessDialog(
          message: result.displayMessage,
          isDark: isDark,
          context: context,
        );
        onSuccess?.call();
        return;
      }

      final errorDetail = result.errors == null || result.errors!.isEmpty
          ? result.displayMessage
          : '${result.displayMessage}\n${result.errors}';
      if (kDebugMode) {
        debugPrint(
          '[VisitUpload] FAIL status=${result.statusCode} '
          'message=${result.displayMessage} errors=${result.errors}',
        );
      }
      _showTopSnack(
        title: 'Upload failed',
        message: errorDetail,
        isDark: isDark,
        isError: true,
        duration: const Duration(seconds: 5),
      );
    } catch (error, stack) {
      if (Get.isSnackbarOpen) {
        Get.closeAllSnackbars();
      }
      if (kDebugMode) {
        debugPrint('[VisitUpload] FAIL unexpected=$error');
        if (kDebugMode) {
          debugPrint('[VisitUpload] stack=$stack');
        }
      }
      _showTopSnack(
        title: 'Upload failed',
        message: error.toString(),
        isDark: isDark,
        isError: true,
        duration: const Duration(seconds: 5),
      );
    } finally {
      flow.isUploading.value = false;
    }
  }

  static Future<bool> _confirmPatrolUploadCompletion({
    required VisitVideoFlowController flow,
    required bool isDark,
    BuildContext? context,
  }) async {
    final dialogContext = (context != null && context.mounted)
        ? context
        : AppNavigator.key.currentContext ?? Get.context;
    if (dialogContext == null || !dialogContext.mounted) return false;

    final siteName = _resolvePatrolSiteName(flow);
    final accent = isDark ? const Color(0xFF93C5FD) : const Color(0xFF4F46E5);

    final result = await GlassActionDialog.showWithActions<bool>(
      context: dialogContext,
      icon: Icons.fact_check_outlined,
      iconColor: accent,
      title: 'Patrol Round completed?',
      titleColor: const Color(0xFFDC2626),
      barrierDismissible: true,
      showCloseButton: true,
      useRootNavigator: true,
      messageMaxHeightFactor: 0.58,
      content: _PatrolCompleteDialogBody(
        message: 'Have you done your patrol round at $siteName',
        flow: flow,
        isDark: isDark,
      ),
      actions: const [
        GlassDialogAction(
          label: 'No, continue report',
          value: false,
          tone: GlassDialogActionTone.neutral,
        ),
        GlassDialogAction(
          label: 'Yes, patrol completed upload report',
          value: true,
          tone: GlassDialogActionTone.primary,
        ),
      ],
    );

    return result == true;
  }

  static String _resolvePatrolSiteName(VisitVideoFlowController flow) {
    final fromContext = flow.patrolContext.value?.siteName?.trim();
    if (fromContext != null && fromContext.isNotEmpty) return fromContext;

    final fromDraft = flow.draftSiteName.value?.trim();
    if (fromDraft != null && fromDraft.isNotEmpty) return fromDraft;

    final subtitle = flow.locationSubtitle?.trim();
    if (subtitle != null && subtitle.isNotEmpty) return subtitle;

    return 'this site';
  }

  static void _showUploadingSnack({
    required int itemCount,
    required bool isDark,
  }) {
    final accent = _visitPrimaryActionColor(isDark);
    Get.snackbar(
      '',
      '',
      snackPosition: SnackPosition.TOP,
      backgroundColor: accent,
      colorText: Colors.white,
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      titleText: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Uploading patrol report',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Sending $itemCount item${itemCount == 1 ? '' : 's'} securely…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      messageText: const SizedBox.shrink(),
      shouldIconPulse: false,
      isDismissible: false,
      duration: const Duration(minutes: 10),
      animationDuration: const Duration(milliseconds: 350),
      boxShadows: [
        BoxShadow(
          color: accent.withValues(alpha: 0.35),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
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

  static Future<void> _showUploadSuccessDialog({
    required String message,
    required bool isDark,
    BuildContext? context,
  }) async {
    final dialogContext = (context != null && context.mounted)
        ? context
        : AppNavigator.key.currentContext ?? Get.context;
    if (dialogContext == null || !dialogContext.mounted) return;

    final accent = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    await GlassActionDialog.show(
      context: dialogContext,
      icon: Icons.check_circle_rounded,
      iconColor: accent,
      title: 'Upload successful',
      message: message,
      primaryLabel: 'OK',
      barrierDismissible: false,
      useRootNavigator: true,
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
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      backgroundColor: isDark ? cDarkBackground : cMainBg,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _VisitPageBackground(isDark: isDark),
            Obx(() {
              final media = controller.mediaItems.toList();
              final hasMedia = media.isNotEmpty;
              final photoCount = media.where((e) => e.isPhoto).length;
              final videoCount = media.where((e) => e.isVideo).length;
              final activeFilter = _mediaFilter.value;
              final visibleMedia = switch (activeFilter) {
                _VisitMediaFilter.all => media,
                _VisitMediaFilter.photos =>
                  media.where((e) => e.isPhoto).toList(),
                _VisitMediaFilter.videos =>
                  media.where((e) => e.isVideo).toList(),
              };
              final locationLabel = controller.locationSubtitle;
              controller.patrolContext.value;
              controller.draftSiteName.value;
              controller.draftRegionName.value;

              return Column(
                children: [
                  _VisitHeader(
                    isDark: isDark,
                    isLandscape: isLandscape,
                    totalCount: media.length,
                    photoCount: photoCount,
                    videoCount: videoCount,
                    activeFilter: activeFilter,
                    onFilterChanged: (filter) => _mediaFilter.value = filter,
                    locationLabel: locationLabel,
                    onBack: () => _handleBack(context),
                  ),
                  Expanded(
                    child: hasMedia
                        ? visibleMedia.isEmpty
                              ? _buildFilteredEmptyState(
                                  context,
                                  isDark,
                                  activeFilter,
                                )
                              : _buildMediaGrid(
                                  context,
                                  visibleMedia,
                                  isDark,
                                  isLandscape: isLandscape,
                                )
                        : _buildEmptyState(
                            context,
                            isDark,
                            locationLabel: locationLabel,
                            isLandscape: isLandscape,
                          ),
                  ),
                  _buildBottomActions(
                    context,
                    hasMedia,
                    isLandscape: isLandscape,
                  ),
                  if (bottomBarClearance > 0)
                    SizedBox(height: bottomBarClearance),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    bool isDark, {
    String? locationLabel,
    bool isLandscape = false,
  }) {
    final location = locationLabel?.trim();
    final hasLocation = location != null && location.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            22,
            isLandscape ? 12 : 28,
            22,
            isLandscape ? 12 : 22,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
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
                      onTap: _openCaptureScreen,
                      child: Container(
                        width: isLandscape ? 72 : 92,
                        height: isLandscape ? 72 : 92,
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
                              blurRadius: isLandscape ? 18 : 28,
                              offset: Offset(0, isLandscape ? 8 : 14),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.add_a_photo_outlined,
                          size: isLandscape ? 30 : 38,
                          color: isDark ? const Color(0xFF38BDF8) : cPrimary,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isLandscape ? 12 : 18),
                  Text(
                    'Ready to start patrol',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: isLandscape ? 20 : null,
                      color: isDark ? cDarkTextPrimary : cDarkText,
                    ),
                  ),
                  if (hasLocation) ...[
                    SizedBox(height: isLandscape ? 6 : 8),
                    Text(
                      location,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark ? const Color(0xFF38BDF8) : cPrimary,
                      ),
                    ),
                  ],
                  SizedBox(height: isLandscape ? 6 : 8),
                  Text(
                    'Capture a clear photo or hold the capture button to record a visit video.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.45,
                      color: isDark
                          ? cDarkTextSecondary
                          : const Color(0xFF667085),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilteredEmptyState(
    BuildContext context,
    bool isDark,
    _VisitMediaFilter filter,
  ) {
    final isVideoFilter = filter == _VisitMediaFilter.videos;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Text(
          isVideoFilter ? 'No videos captured yet' : 'No photos captured yet',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: _visitBodyColor(isDark),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildMediaGrid(
    BuildContext context,
    List<VisitMediaItem> media,
    bool isDark, {
    bool isLandscape = false,
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
        final useGrid = isWide && !isLandscape;
        final crossAxisCount = isWide ? 2 : 1;
        final horizontalInset = isWide || isLandscape ? 18.0 : 16.0;
        final gap = 8.0;

        Widget cardFor(int index) {
          final item = media[index];
          return _MediaPreviewCard(
            key: ValueKey('media-card-${item.path}'),
            item: item,
            index: index,
            isDark: isDark,
            featured: !isLandscape && isWide,
            compact: isLandscape,
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

        if (!useGrid || crossAxisCount <= 1) {
          final list = ListView.separated(
            key: ValueKey(
              isLandscape ? 'visit-media-list-land' : 'visit-media-list',
            ),
            padding: EdgeInsets.fromLTRB(
              horizontalInset,
              isLandscape ? 4 : 6,
              horizontalInset,
              isLandscape ? 10 : 14,
            ),
            itemCount: media.length,
            separatorBuilder: (_, index) => SizedBox(height: gap),
            itemBuilder: (context, index) => cardFor(index),
          );

          if (!isLandscape || constraints.maxWidth < 900) {
            return list;
          }

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: list,
            ),
          );
        }

        return GridView.builder(
          key: const ValueKey('visit-media-grid'),
          padding: EdgeInsets.fromLTRB(horizontalInset, 6, horizontalInset, 14),
          itemCount: media.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            childAspectRatio: 1.55,
          ),
          itemBuilder: (context, index) => cardFor(index),
        );
      },
    );
  }

  Widget _buildBottomActions(
    BuildContext context,
    bool hasMedia, {
    bool isLandscape = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                  onPressed: uploading ? null : _openCaptureScreen,
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: Text(
                    hasMedia ? 'Capture More' : 'Capture',
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
              final uploading = controller.isUploading.value;
              return ElevatedButton.icon(
                onPressed: hasMedia && !uploading
                    ? () => _uploadAllMedia(context)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _visitPrimaryActionColor(isDark),
                  disabledBackgroundColor: isDark
                      ? cDarkInputFillColor
                      : const Color(0xFFE6EAF1),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: isDark
                      ? cDarkTextSecondary
                      : const Color(0xFF9AA4B2),
                  minimumSize: Size.fromHeight(isLandscape ? 42 : 48),
                  elevation: hasMedia && !uploading ? 2 : 0,
                  shadowColor: _visitPrimaryActionColor(
                    isDark,
                  ).withValues(alpha: 0.24),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                label: Text(
                  hasMedia
                      ? 'Complete Report (${controller.mediaItems.length})'
                      : 'Complete Report',
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
        const SizedBox(height: 14),
        VisitBatchNotesPanel(flow: flow, isDark: isDark),
      ],
    );
  }
}

class _VisitPageBackground extends StatelessWidget {
  const _VisitPageBackground({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1724) : const Color(0xFFF3F7FB),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF0F1724), Color(0xFF172033), Color(0xFF111827)]
              : const [Color(0xFFF7FAFC), Color(0xFFEAF2F8), Color(0xFFF8FAFC)],
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
    this.isLandscape = false,
  });

  final bool isDark;
  final int totalCount;
  final int photoCount;
  final int videoCount;
  final _VisitMediaFilter activeFilter;
  final ValueChanged<_VisitMediaFilter> onFilterChanged;
  final VoidCallback onBack;
  final String? locationLabel;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    final location = locationLabel?.trim();
    final hasLocation = location != null && location.isNotEmpty;
    final titleColor = _visitTitleColor(isDark);

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
                child: Text(
                  'Patrol Draft',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: isLandscape ? 17 : 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (isLandscape && hasLocation) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _visitCardColor(isDark),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _visitBorderColor(isDark)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 14,
                          color: _visitPrimaryActionColor(isDark),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                          hasLocation ? location : 'No patrol location',
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
          SizedBox(height: isLandscape ? 6 : 8),
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

class _MediaPreviewCard extends StatelessWidget {
  const _MediaPreviewCard({
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

  @override
  Widget build(BuildContext context) {
    final thumbnailSize = compact
        ? 72.0
        : featured
        ? 118.0
        : 92.0;
    final title = item.isPhoto ? 'Photo ${index + 1}' : 'Video ${index + 1}';

    return Material(
      color: _visitCardColor(isDark),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _visitBorderColor(isDark)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.14 : 0.04),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 6 : (featured ? 10 : 8)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MediaThumbnail(
                item: item,
                isDark: isDark,
                size: thumbnailSize,
                thumbnailFuture: thumbnailFuture,
                onPreview: onPreview,
              ),
              SizedBox(width: compact ? 8 : (featured ? 12 : 9)),
              Expanded(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: thumbnailSize),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                                    fontSize: featured ? 16 : 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: featured ? 8 : 6),
                          Tooltip(
                            message: item.isPhoto
                                ? 'Delete photo'
                                : 'Delete video',
                            child: SizedBox.square(
                              dimension: featured ? 38 : 34,
                              child: OutlinedButton(
                                onPressed: onDelete,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: cRed,
                                  backgroundColor: cRed.withValues(
                                    alpha: isDark ? 0.12 : 0.055,
                                  ),
                                  side: BorderSide(
                                    color: cRed.withValues(
                                      alpha: isDark ? 0.38 : 0.25,
                                    ),
                                  ),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: VisitDeleteIcon(
                                  size: featured ? 16 : 15,
                                  color: cRed,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _InlineNotePanel(
                        item: item,
                        isDark: isDark,
                        compact: compact,
                        featured: featured,
                      ),
                      const SizedBox(height: 8),
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
                              onPressed: () => openVisitMediaNotesSheet(
                                context: context,
                                item: item,
                                kind: VisitMediaNoteKind.text,
                              ),
                            ),
                          ),
                          SizedBox(width: featured ? 8 : 6),
                          Expanded(
                            child: _MediaNoteButton(
                              label: item.hasVoiceNote ? 'Edit Voice' : 'Voice',
                              icon: item.hasVoiceNote
                                  ? Icons.mic_rounded
                                  : Icons.mic_none_rounded,
                              isDark: isDark,
                              dense: !featured,
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
            ],
          ),
        ),
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
  });

  final VisitMediaItem item;
  final bool isDark;
  final bool compact;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    final padding = EdgeInsets.symmetric(
      horizontal: compact ? 7 : 8,
      vertical: compact ? 5 : 6,
    );

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F1729).withValues(alpha: 0.58)
            : const Color(0xFFF3F6FA),
        borderRadius: radius,
        border: Border.all(
          color: _visitBorderColor(
            isDark,
          ).withValues(alpha: isDark ? 0.70 : 0.85),
        ),
      ),
      child: item.hasVoiceNote
          ? InlineVoiceNotePlayer(
              path: item.voiceNotePath!,
              isDark: isDark,
              accent: _visitAccentColor(isDark),
              compact: compact,
            )
          : Row(
              children: [
                Icon(
                  Icons.sticky_note_2_outlined,
                  size: compact ? 12 : 13,
                  color: _visitBodyColor(isDark),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.hasTextNote ? item.textNote : 'No note added',
                    maxLines: item.hasTextNote && !compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _visitBodyColor(isDark),
                      fontSize: compact ? 10.2 : (featured ? 12 : 10.8),
                      height: 1.25,
                      fontWeight: item.hasTextNote
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
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
              Positioned.fill(child: _previewImage()),
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

  Widget _previewImage() {
    if (item.isPhoto) {
      return Image.file(
        File(item.path),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) =>
            _fallback(Icons.broken_image_outlined),
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
            filterQuality: FilterQuality.medium,
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
  });

  final String label;
  final IconData icon;
  final bool isDark;
  final bool dense;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: dense ? 32 : 38,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _visitAccentColor(
            isDark,
          ).withValues(alpha: isDark ? 0.18 : 0.12),
          foregroundColor: _visitAccentColor(isDark),
          elevation: 0,
          padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 9),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(dense ? 11 : 13),
          ),
        ),
        icon: Icon(icon, size: dense ? 13 : 16),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: dense ? 10.5 : 12,
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
            child: Stack(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 8 || constraints.maxHeight < 8) {
                      return const ColoredBox(color: Colors.black);
                    }

                    return Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            8,
                            isLandscape ? 2 : 4,
                            8,
                            isLandscape ? 4 : 8,
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
                        Expanded(
                          child: InteractiveViewer(
                            minScale: 1,
                            maxScale: 4,
                            child: Center(
                              child: Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  Image.file(
                                    File(imagePath),
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
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
                        if (onDelete != null && !isLandscape)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: OutlinedButton.icon(
                                onPressed: () => _confirmDelete(context),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: cRed,
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
                      ],
                    );
                  },
                ),
              ],
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
                                        Colors.black.withAlpha(170),
                                        Colors.black.withAlpha(0),
                                      ],
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

            final videoSize = videoCtrl.value.size;
            final aspect = (videoSize.width <= 0 || videoSize.height <= 0)
                ? 16 / 9
                : videoSize.width / videoSize.height;

            var width = constraints.maxWidth;
            var height = width / aspect;
            if (height > constraints.maxHeight) {
              height = constraints.maxHeight;
              width = height * aspect;
            }

            return Center(
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
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
              ),
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
