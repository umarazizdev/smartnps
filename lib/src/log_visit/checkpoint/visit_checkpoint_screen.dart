import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_routes.dart';
import '../../widgets/dialogs/glass_action_dialog.dart';
import '../flow/visit_checkpoint.dart';
import '../flow/visit_video_flow_controller.dart';
import '../log_visit_theme.dart';
import '../preview/visit_video_player_controller.dart';
import '../preview/visit_video_preview_screen.dart';
import '../record/visit_native_capture_launcher.dart';

Color _cpCardColor(bool isDark) {
  return isDark
      ? const Color(0xFF172033).withValues(alpha: 0.94)
      : Colors.white.withValues(alpha: 0.96);
}

Color _cpBorderColor(bool isDark) {
  return isDark
      ? Colors.white.withValues(alpha: 0.13)
      : const Color(0xFFD8E0EA);
}

Color _cpTitleColor(bool isDark) {
  return isDark ? cDarkTextPrimary : const Color(0xFF20283A);
}

Color _cpPrimaryColor(bool isDark) {
  return isDark ? const Color(0xFF4F8DF7) : cPrimary;
}

class VisitCheckpointScreen extends StatefulWidget {
  const VisitCheckpointScreen({
    super.key,
    required this.checkpointId,
    this.openCaptureOnStart = false,
  });

  final int checkpointId;
  final bool openCaptureOnStart;

  static Future<T?> open<T>({
    required int checkpointId,
    bool openCaptureOnStart = false,
  }) {
    return Get.to<T>(
          () => VisitCheckpointScreen(
            checkpointId: checkpointId,
            openCaptureOnStart: openCaptureOnStart,
          ),
          routeName: AppRoutes.visitCheckpoint,
        ) ??
        Future<T?>.value();
  }

  @override
  State<VisitCheckpointScreen> createState() => _VisitCheckpointScreenState();
}

class _VisitCheckpointScreenState extends State<VisitCheckpointScreen> {
  VisitVideoFlowController get flow {
    if (!Get.isRegistered<VisitVideoFlowController>()) {
      Get.put(VisitVideoFlowController(), permanent: true);
    }
    return Get.find<VisitVideoFlowController>();
  }

  @override
  void initState() {
    super.initState();
    flow.beginCheckpointCapture(widget.checkpointId);
    if (widget.openCaptureOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openCapture();
      });
    }
  }

  @override
  void dispose() {
    if (flow.activeCheckpointId.value == widget.checkpointId) {
      flow.endCheckpointCapture();
    }
    super.dispose();
  }

  VisitCheckpoint? get _checkpoint =>
      flow.patrolContext.value?.checkpointById(widget.checkpointId);

  Future<void> _openCapture() async {
    flow.beginCheckpointCapture(widget.checkpointId);
    await VisitNativeCaptureLauncher.open();
    flow.beginCheckpointCapture(widget.checkpointId);
  }

  void _returnToDraft() {
    flow.endCheckpointCapture();
    Get.back();
  }

  Future<void> _confirmDelete(VisitMediaItem item) async {
    final actualIndex = flow.mediaItems.indexWhere((e) => e.path == item.path);
    if (actualIndex < 0) return;

    final confirmed = await GlassActionDialog.show(
      context: context,
      icon: Icons.delete_outline_rounded,
      iconWidget: const VisitDeleteIcon(size: 28, color: Color(0xFFE53935)),
      iconColor: cRed,
      title: item.isPhoto ? 'Delete Photo?' : 'Delete Video?',
      message: VisitVideoPreviewScreen.deleteMediaMessage(
        isPhoto: item.isPhoto,
        hasNotes: item.hasNotes,
      ),
      secondaryLabel: 'Cancel',
      primaryLabel: 'Delete',
      variant: GlassActionDialogVariant.error,
      destructiveSecondary: false,
    );
    if (confirmed == true) {
      await flow.removeAt(actualIndex);
    }
  }

  Future<void> _openMediaPreview(VisitMediaItem item) async {
    if (item.isPhoto) {
      await Get.to(
        () => VisitPhotoViewer(
          imagePath: item.path,
          stampLabel: item.stampLabel,
          hasNotes: item.hasNotes,
          onDelete: () {
            final i = flow.mediaItems.indexWhere((e) => e.path == item.path);
            if (i >= 0) flow.removeAt(i);
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
          final i = flow.mediaItems.indexWhere((e) => e.path == item.path);
          if (i >= 0) flow.removeAt(i);
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) flow.endCheckpointCapture();
      },
      child: Scaffold(
        backgroundColor: isDark ? cDarkBackground : cMainBg,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              VisitPageBackground(isDark: isDark),
              Obx(() {
                flow.mediaItems.length;
                flow.patrolContext.value;
                final checkpoint = _checkpoint;
                if (checkpoint == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Checkpoint not found',
                        style: TextStyle(
                          color: _cpTitleColor(isDark),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }

                final media = flow.mediaForCheckpoint(checkpoint.id);
                final completed = flow.isCheckpointCompleted(checkpoint.id);

                final content = media.isEmpty
                    ? Padding(
                        padding: EdgeInsets.fromLTRB(
                          isLandscape ? 18 : 16,
                          4,
                          isLandscape ? 12 : 16,
                          isLandscape ? 8 : 12,
                        ),
                        child: Column(
                          children: [
                            _CheckpointPlaceHeader(
                              isDark: isDark,
                              checkpoint: checkpoint,
                              completed: completed,
                            ),
                            if ((checkpoint.description?.trim().isNotEmpty ??
                                false)) ...[
                              SizedBox(height: isLandscape ? 8 : 10),
                              _CheckpointTaskCard(
                                isDark: isDark,
                                text: checkpoint.description!.trim(),
                              ),
                            ],
                            SizedBox(height: isLandscape ? 10 : 14),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  return SingleChildScrollView(
                                    physics: const ClampingScrollPhysics(),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: constraints.maxHeight,
                                      ),
                                      child: Center(
                                        child: _CheckpointEmptyCapture(
                                          isDark: isDark,
                                          isLandscape: isLandscape,
                                          onCapture: _openCapture,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: EdgeInsets.fromLTRB(
                          isLandscape ? 18 : 16,
                          4,
                          isLandscape ? 12 : 16,
                          isLandscape ? 12 : 18,
                        ),
                        children: [
                          _CheckpointPlaceHeader(
                            isDark: isDark,
                            checkpoint: checkpoint,
                            completed: completed,
                          ),
                          if ((checkpoint.description?.trim().isNotEmpty ??
                              false)) ...[
                            SizedBox(height: isLandscape ? 8 : 10),
                            _CheckpointTaskCard(
                              isDark: isDark,
                              text: checkpoint.description!.trim(),
                            ),
                          ],
                          SizedBox(height: isLandscape ? 12 : 16),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Captured (${media.length})',
                                  style: TextStyle(
                                    color: _cpTitleColor(isDark),
                                    fontSize: isLandscape ? 13 : 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (completed)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF059669).withValues(
                                      alpha: isDark ? 0.22 : 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'Completed',
                                    style: TextStyle(
                                      color: isDark
                                          ? const Color(0xFF6EE7B7)
                                          : const Color(0xFF047857),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: isLandscape ? 8 : 10),
                          ...List.generate(media.length, (index) {
                            final item = media[index];
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index == media.length - 1 ? 0 : 8,
                              ),
                              child: VisitMediaPreviewCard(
                                item: item,
                                index: index,
                                isDark: isDark,
                                compact: isLandscape,
                                thumbnailFuture: item.isVideo
                                    ? flow.videoThumbnail(item.path)
                                    : null,
                                onPreview: () => _openMediaPreview(item),
                                onDelete: () => _confirmDelete(item),
                              ),
                            );
                          }),
                        ],
                      );

                return isLandscape
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                _CheckpointHeader(
                                  isDark: isDark,
                                  isLandscape: isLandscape,
                                  onBack: _returnToDraft,
                                ),
                                Expanded(child: content),
                              ],
                            ),
                          ),
                          _CheckpointLandscapeSidebar(
                            isDark: isDark,
                            hasMedia: media.isNotEmpty,
                            canComplete: completed,
                            onCapture: _openCapture,
                            onComplete: _returnToDraft,
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _CheckpointHeader(
                            isDark: isDark,
                            isLandscape: isLandscape,
                            onBack: _returnToDraft,
                          ),
                          Expanded(child: content),
                          _CheckpointBottomBar(
                            isDark: isDark,
                            hasMedia: media.isNotEmpty,
                            canComplete: completed,
                            onCapture: _openCapture,
                            onComplete: _returnToDraft,
                          ),
                        ],
                      );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckpointHeader extends StatelessWidget {
  const _CheckpointHeader({
    required this.isDark,
    required this.onBack,
    this.isLandscape = false,
  });

  final bool isDark;
  final VoidCallback onBack;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        isLandscape ? 4 : 8,
        16,
        isLandscape ? 4 : 8,
      ),
      child: Row(
        children: [
          Material(
            color: _cpCardColor(isDark),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: _cpBorderColor(isDark)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onBack,
              child: SizedBox(
                width: isLandscape ? 38 : 42,
                height: isLandscape ? 38 : 42,
                child: Center(
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: _cpTitleColor(isDark),
                    size: isLandscape ? 18 : 20,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Patrol Checkpoints',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _cpTitleColor(isDark),
                fontSize: isLandscape ? 16 : 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckpointPlaceHeader extends StatelessWidget {
  const _CheckpointPlaceHeader({
    required this.isDark,
    required this.checkpoint,
    required this.completed,
  });

  final bool isDark;
  final VisitCheckpoint checkpoint;
  final bool completed;

  Future<void> _openPreview(BuildContext context) async {
    final url = checkpoint.photoUrl?.trim();
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.92),
        pageBuilder: (context, animation, secondaryAnimation) {
          return _CheckpointReferenceViewer(
            title: checkpoint.name,
            imageUrl: (url != null && url.isNotEmpty) ? url : null,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = checkpoint.hasReferencePhoto;
    final doneColor = const Color(0xFF059669);
    final pinColor = completed ? doneColor : _cpPrimaryColor(isDark);
    final subtitle = hasPhoto
        ? 'Tap to view reference photo'
        : (completed ? 'Checkpoint captured' : 'Checkpoint location');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openPreview(context),
        child: Ink(
          decoration: BoxDecoration(
            color: _cpCardColor(isDark),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _cpBorderColor(isDark)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _CheckpointThumb(
                    accent: pinColor,
                    photoUrl: hasPhoto ? checkpoint.photoUrl : null,
                  ),
                  if (completed)
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: doneColor,
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
                          size: 11,
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      checkpoint.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _cpTitleColor(isDark),
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark
                            ? cDarkTextSecondary.withValues(alpha: 0.9)
                            : const Color(0xFF667085),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (completed)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: doneColor.withValues(alpha: isDark ? 0.22 : 0.12),
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
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckpointTaskCard extends StatelessWidget {
  const _CheckpointTaskCard({required this.isDark, required this.text});

  final bool isDark;
  final String text;

  @override
  Widget build(BuildContext context) {
    final accent = _cpPrimaryColor(isDark);

    const radius = BorderRadius.all(Radius.circular(18));
    final outline = accent.withValues(alpha: isDark ? 0.36 : 0.22);

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _cpCardColor(isDark),
        borderRadius: radius,
        border: Border.all(color: outline),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 6,
            child: ColoredBox(color: accent),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/images/task_checklist_icon.png',
                      width: 18,
                      height: 18,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      semanticLabel: 'Task checklist',
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'YOUR TASK',
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: TextStyle(
                    color: _cpTitleColor(isDark),
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckpointThumb extends StatelessWidget {
  const _CheckpointThumb({required this.accent, this.photoUrl});

  final Color accent;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl?.trim();
    final hasPhoto = url != null && url.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 46,
        height: 46,
        child: hasPhoto
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stackTrace) => _pinFallback(),
              )
            : _pinFallback(),
      ),
    );
  }

  Widget _pinFallback() {
    return ColoredBox(
      color: accent,
      child: const Icon(
        Icons.location_on_rounded,
        color: Colors.white,
        size: 23,
      ),
    );
  }
}

class _CheckpointReferenceViewer extends StatelessWidget {
  const _CheckpointReferenceViewer({required this.title, this.imageUrl});

  final String title;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: hasImage
                  ? InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Image.network(
                        imageUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, error, stackTrace) =>
                            const _ReferenceMissingState(),
                      ),
                    )
                  : const _ReferenceMissingState(),
            ),
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: Colors.white.withValues(alpha: 0.14),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
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

class _ReferenceMissingState extends StatelessWidget {
  const _ReferenceMissingState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_on_rounded, color: Colors.white70, size: 56),
        SizedBox(height: 12),
        Text(
          'No reference photo',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CheckpointEmptyCapture extends StatelessWidget {
  const _CheckpointEmptyCapture({
    required this.isDark,
    required this.onCapture,
    this.isLandscape = false,
  });

  final bool isDark;
  final VoidCallback onCapture;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.22)
        : const Color(0xFF9AA8BC);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onCapture,
        child: CustomPaint(
          painter: VisitDottedRoundedRectPainter(
            color: borderColor,
            radius: 18,
            strokeWidth: 1.4,
            dashLength: 6,
            gapLength: 4,
          ),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 14 : 18,
              vertical: isLandscape ? 10 : 18,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Material(
                    color: isDark
                        ? cDarkCardColor.withValues(alpha: 0.82)
                        : Colors.white.withValues(alpha: 0.94),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      width: isLandscape ? 48 : 72,
                      height: isLandscape ? 48 : 72,
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
                            blurRadius: isLandscape ? 12 : 20,
                            offset: Offset(0, isLandscape ? 4 : 10),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.add_a_photo_outlined,
                        size: isLandscape ? 22 : 30,
                        color: isDark ? const Color(0xFF38BDF8) : cPrimary,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: isLandscape ? 8 : 12),
                Text(
                  'Ready to capture',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: isLandscape ? 15 : 18,
                    color: isDark ? cDarkTextPrimary : cDarkText,
                  ),
                ),
                SizedBox(height: isLandscape ? 4 : 6),
                Text(
                  'Capture a clear photo or hold Capture to record a short video.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.35,
                    fontSize: isLandscape ? 12 : 13,
                    color: isDark
                        ? cDarkTextSecondary
                        : const Color(0xFF667085),
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

class _CheckpointLandscapeSidebar extends StatelessWidget {
  const _CheckpointLandscapeSidebar({
    required this.isDark,
    required this.hasMedia,
    required this.canComplete,
    required this.onCapture,
    required this.onComplete,
  });

  final bool isDark;
  final bool hasMedia;
  final bool canComplete;
  final VoidCallback onCapture;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final primary = _cpPrimaryColor(isDark);
    final rightPad = Platform.isAndroid ? 14.0 : 10.0;
    final panelBg = isDark
        ? const Color(0xFF151E2F)
        : const Color(0xFFE7EEF7);
    final panelBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFD0DBE8);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: panelBg,
        border: Border(left: BorderSide(color: panelBorder)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(10, 10, rightPad, 10),
        child: SizedBox(
          width: 152,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 118,
                child: _CheckpointLandscapeRailButton(
                  isDark: isDark,
                  filled: false,
                  accent: primary,
                  icon: Icons.add_a_photo_outlined,
                  label: hasMedia ? 'Take more photos' : 'Take photos',
                  onPressed: onCapture,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 118,
                child: _CheckpointLandscapeRailButton(
                  isDark: isDark,
                  filled: true,
                  accent: primary,
                  icon: Icons.check_rounded,
                  label: 'Report completed',
                  onPressed: canComplete ? onComplete : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckpointLandscapeRailButton extends StatelessWidget {
  const _CheckpointLandscapeRailButton({
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
              : (isDark
                    ? const Color(0xFF2A3548)
                    : const Color(0xFFC5D0E3)))
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
            alpha: enabled
                ? (isDark ? 0.2 : 0.1)
                : (isDark ? 0.1 : 0.06),
          );

    return Material(
      color: bg,
      elevation: filled && enabled ? 2 : 0,
      shadowColor: accent.withValues(alpha: isDark ? 0.35 : 0.22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: border, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: iconBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: iconFg,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: -0.15,
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

class _CheckpointBottomBar extends StatelessWidget {
  const _CheckpointBottomBar({
    required this.isDark,
    required this.hasMedia,
    required this.canComplete,
    required this.onCapture,
    required this.onComplete,
  });

  final bool isDark;
  final bool hasMedia;
  final bool canComplete;
  final VoidCallback onCapture;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final primary = _cpPrimaryColor(isDark);
    final captureLabel = hasMedia ? 'Capture More' : 'Capture';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
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
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.14 : 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: onCapture,
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
                  foregroundColor: isDark ? cDarkTextPrimary : cPrimary,
                  minimumSize: const Size.fromHeight(48),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                    side: BorderSide(color: _cpBorderColor(isDark)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: canComplete ? onComplete : null,
              icon: const Icon(Icons.check_circle_rounded, size: 18),
              label: const Text(
                'Completed',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                disabledBackgroundColor: isDark
                    ? const Color(0xFF2A3548)
                    : const Color(0xFFC5D0E3),
                foregroundColor: Colors.white,
                disabledForegroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.55)
                    : const Color(0xFF3F516A),
                minimumSize: const Size.fromHeight(48),
                elevation: canComplete ? 2 : 0,
                shadowColor: primary.withValues(alpha: 0.24),
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
            ),
          ),
        ],
      ),
    );
  }
}
