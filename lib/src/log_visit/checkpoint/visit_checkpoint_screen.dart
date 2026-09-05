import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_routes.dart';
import '../../widgets/dialogs/glass_action_dialog.dart';
import '../flow/visit_checkpoint.dart';
import '../flow/visit_video_flow_controller.dart';
import '../log_visit_theme.dart';
import '../preview/visit_video_player_controller.dart';
import '../preview/visit_video_preview_screen.dart';
import '../record/visit_video_recorder_controller.dart';
import '../record/visit_video_recorder_screen.dart';

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
  const VisitCheckpointScreen({super.key, required this.checkpointId});

  final int checkpointId;

  static Future<T?> open<T>({required int checkpointId}) {
    return Get.to<T>(
          () => VisitCheckpointScreen(checkpointId: checkpointId),
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
    await Get.to(
      () => const VisitVideoRecorderScreen(),
      routeName: AppRoutes.visitVideoRecorder,
      binding: BindingsBuilder(() {
        Get.put(VisitVideoRecorderController());
      }),
    );
    flow.beginCheckpointCapture(widget.checkpointId);
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

                return Column(
                  children: [
                    _CheckpointHeader(
                      isDark: isDark,
                      isLandscape: isLandscape,
                      onBack: () {
                        flow.endCheckpointCapture();
                        Get.back();
                      },
                    ),
                    Expanded(
                      child: media.isEmpty
                          ? Padding(
                              padding: EdgeInsets.fromLTRB(
                                isLandscape ? 18 : 16,
                                4,
                                isLandscape ? 18 : 16,
                                isLandscape ? 8 : 12,
                              ),
                              child: Column(
                                children: [
                                  _CheckpointPlaceHeader(
                                    isDark: isDark,
                                    checkpoint: checkpoint,
                                    completed: completed,
                                  ),
                                  if ((checkpoint.description
                                          ?.trim()
                                          .isNotEmpty ??
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
                                          physics:
                                              const ClampingScrollPhysics(),
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
                                isLandscape ? 18 : 16,
                                isLandscape ? 12 : 18,
                              ),
                              children: [
                                _CheckpointPlaceHeader(
                                  isDark: isDark,
                                  checkpoint: checkpoint,
                                  completed: completed,
                                ),
                                if ((checkpoint.description
                                        ?.trim()
                                        .isNotEmpty ??
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
                                          color: const Color(0xFF059669)
                                              .withValues(
                                                alpha: isDark ? 0.22 : 0.12,
                                              ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
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
                            ),
                    ),
                    _CheckpointBottomBar(
                      isDark: isDark,
                      isLandscape: isLandscape,
                      hasMedia: media.isNotEmpty,
                      onCapture: _openCapture,
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
                width: 42,
                height: 42,
                child: Center(
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: _cpTitleColor(isDark),
                    size: 20,
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
                fontSize: isLandscape ? 17 : 20,
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
    // Match place-header card radius on all sides (incl. left).
    const radius = BorderRadius.all(Radius.circular(18));
    final outline = accent.withValues(alpha: isDark ? 0.36 : 0.22);

    // Uniform Border.all + separate accent strip (non-uniform Border +
    // borderRadius asserts and breaks layout).
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
                    Icon(Icons.checklist_rounded, size: 15, color: accent),
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

class _CheckpointBottomBar extends StatelessWidget {
  const _CheckpointBottomBar({
    required this.isDark,
    required this.hasMedia,
    required this.onCapture,
    this.isLandscape = false,
  });

  final bool isDark;
  final bool hasMedia;
  final VoidCallback onCapture;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    final primary = _cpPrimaryColor(isDark);
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.24),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: onCapture,
          icon: const Icon(Icons.camera_alt_rounded, size: 18),
          label: Text(
            hasMedia ? 'Capture More' : 'Capture',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            minimumSize: Size.fromHeight(isLandscape ? 42 : 48),
            elevation: 2,
            shadowColor: primary.withValues(alpha: 0.24),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
            ),
          ),
        ),
      ),
    );
  }
}
