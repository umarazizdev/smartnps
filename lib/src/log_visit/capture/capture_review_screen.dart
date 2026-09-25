import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import '../../app/app_routes.dart';
import '../flow/cam_perf.dart';
import '../flow/capture_work_coordinator.dart';
import '../flow/visit_media_geo.dart';
import '../flow/visit_video_flow_controller.dart';
import '../log_visit_theme.dart';
import '../notes/visit_media_notes_sheet.dart';
import 'capture_review_controller.dart';

const Color _kReviewAccent = Color(0xFF3B82F6);

class CaptureReviewScreen extends GetView<CaptureReviewController> {
  const CaptureReviewScreen({super.key});

  static Future<T?>? open<T>({
    required String filePath,
    required VisitMediaType mediaType,
    required VisitMediaGeo geo,
    required String captureId,
    bool resolveLocationInBackground = false,
    CaptureWorkCoordinator? coordinator,
  }) {
    return Get.off<T>(
      () => const CaptureReviewScreen(),
      routeName: AppRoutes.captureReview,
      transition: Transition.fadeIn,
      duration: const Duration(milliseconds: 160),
      binding: BindingsBuilder(() {
        Get.put(
          CaptureReviewController(
            displayPath: filePath,
            mediaType: mediaType,
            captureId: captureId,
            initialGeo: geo,
            resolveLocationInBackground: resolveLocationInBackground,
            coordinator: coordinator,
          ),
        );
      }),
    );
  }

  Future<void> _openNotes(
    BuildContext context, {
    required VisitMediaNoteKind kind,
  }) async {
    if (controller.isBusy.value) return;
    final flow = Get.find<VisitVideoFlowController>();
    final item =
        flow.findByCaptureId(controller.captureId) ??
        flow.findByPath(controller.mediaPath.value) ??
        flow.findByPath(controller.displayPath);
    if (item == null) return;
    await openVisitMediaNotesSheet(context: context, item: item, kind: kind);
  }

  Widget _actionBar({
    required BuildContext context,
    required bool isLandscape,
  }) {
    return Obx(() {
      final busy = controller.isBusy.value;
      final flow = Get.find<VisitVideoFlowController>();
      final item =
          flow.findByCaptureId(controller.captureId) ??
          flow.findByPath(controller.mediaPath.value) ??
          flow.findByPath(controller.displayPath);
      final hasTextNote = item?.hasTextNote ?? false;
      final hasVoiceNote = item?.hasVoiceNote ?? false;
      final attentionNeeded = item?.attentionNeeded ?? false;
      final mediaPath = item?.path ?? controller.mediaPath.value;
      return _CaptureReviewActionBar(
        isLandscape: isLandscape,
        busy: busy,
        hasTextNote: hasTextNote,
        hasVoiceNote: hasVoiceNote,
        attentionNeeded: attentionNeeded,
        onAttentionChanged: (value) {
          unawaited(() async {
            var path = mediaPath;
            if (flow.findByPath(path) == null) {
              final registered = await flow.registerCaptureDraft(
                VisitMediaItem(
                  path: controller.displayPath,
                  type: controller.mediaType,
                  captureId: controller.captureId,
                  capturedAt: controller.geo.value.capturedAt,
                  latitude: controller.geo.value.latitude,
                  longitude: controller.geo.value.longitude,
                  accuracyMeters: controller.geo.value.accuracyMeters,
                  attentionNeeded: value,
                  isPendingCapture: true,
                ),
              );
              if (registered != null) {
                path = registered.path;
                if (registered.attentionNeeded == value) return;
              }
            }
            await flow.setMediaAttentionNeeded(
              mediaPath: path,
              attentionNeeded: value,
            );
          }());
        },
        onTextNote: () => _openNotes(context, kind: VisitMediaNoteKind.text),
        onVoiceNote: () => _openNotes(context, kind: VisitMediaNoteKind.voice),
        onRetake: controller.retake,
        onDone: controller.done,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final title = controller.isPhoto ? 'Photo Preview' : 'Video Preview';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        controller.cancel();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF101115),
        body: SafeArea(
          child: isLandscape
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _ReviewHeader(
                            title: title,
                            isLandscape: true,
                            onCancel: controller.cancel,
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(8, 0, 0, 8),
                              child: _PreviewBody(
                                isLandscape: true,
                                edgeToEdge: false,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        0,
                        4,
                        Platform.isAndroid ? 6 : 4,
                        8,
                      ),
                      child: SizedBox(
                        width: (MediaQuery.sizeOf(context).width * 0.20).clamp(
                          148.0,
                          164.0,
                        ),
                        child: _actionBar(context: context, isLandscape: true),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _ReviewHeader(
                      title: title,
                      isLandscape: false,
                      onCancel: controller.cancel,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                        child: Column(
                          children: [
                            Expanded(
                              child: _PreviewBody(
                                isLandscape: false,
                                edgeToEdge: false,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _actionBar(context: context, isLandscape: false),
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

class _ReviewHeader extends StatelessWidget {
  const _ReviewHeader({
    required this.title,
    required this.isLandscape,
    required this.onCancel,
  });

  final String title;
  final bool isLandscape;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: isLandscape ? 40 : 48,
      child: Row(
        children: [
          SizedBox(width: isLandscape ? 4 : 10),
          TextButton.icon(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                horizontal: isLandscape ? 8 : 10,
                vertical: isLandscape ? 6 : 8,
              ),
              minimumSize: Size(0, isLandscape ? 38 : 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Icon(Icons.close_rounded, size: isLandscape ? 26 : 30),
            label: Text(
              'Cancel',
              style: TextStyle(
                fontSize: isLandscape ? 15 : 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: isLandscape ? 14 : 18),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: isLandscape ? 21 : 23,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(width: 20),
        ],
      ),
    );
  }
}

class _CaptureReviewActionBar extends StatelessWidget {
  const _CaptureReviewActionBar({
    required this.isLandscape,
    required this.busy,
    required this.hasTextNote,
    required this.hasVoiceNote,
    required this.attentionNeeded,
    required this.onAttentionChanged,
    required this.onTextNote,
    required this.onVoiceNote,
    required this.onRetake,
    required this.onDone,
  });

  final bool isLandscape;
  final bool busy;
  final bool hasTextNote;
  final bool hasVoiceNote;
  final bool attentionNeeded;
  final ValueChanged<bool> onAttentionChanged;
  final VoidCallback onTextNote;
  final VoidCallback onVoiceNote;
  final VoidCallback onRetake;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      _ReviewActionTile(
        isLandscape: isLandscape,
        iconAsset: 'assets/images/capture_retake_icon.png',
        label: 'Retake',
        onPressed: busy ? null : onRetake,
      ),
      _ReviewActionTile(
        isLandscape: isLandscape,
        iconAsset: 'assets/images/capture_note_icon.png',
        assetScale: 1.05,
        label: hasTextNote ? 'Edit note' : 'Add note',
        onPressed: busy ? null : onTextNote,
      ),
      _ReviewActionTile(
        isLandscape: isLandscape,
        icon: hasVoiceNote ? Icons.mic_rounded : Icons.mic_none_rounded,
        label: hasVoiceNote ? 'Edit audio' : 'Add audio',
        onPressed: busy ? null : onVoiceNote,
      ),
      _ReviewAlertTile(
        isLandscape: isLandscape,
        enabled: !busy,
        value: attentionNeeded,
        onChanged: onAttentionChanged,
      ),
    ];

    if (isLandscape) {
      return LayoutBuilder(
        builder: (context, constraints) {
          const actionGap = 8.0;
          const doneGap = 10.0;
          const doneHeight = 52.0;
          const actionHeight = 44.0;

          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < actions.length; index++) ...[
                SizedBox(height: actionHeight, child: actions[index]),
                if (index != actions.length - 1)
                  const SizedBox(height: actionGap),
              ],
              const SizedBox(height: doneGap),
              _ReviewDoneButton(
                height: doneHeight,
                compact: true,
                busy: busy,
                onPressed: busy ? null : onDone,
              ),
            ],
          );
        },
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: actions[0]),
            const SizedBox(width: 6),
            Expanded(child: actions[1]),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: actions[2]),
            const SizedBox(width: 6),
            Expanded(child: actions[3]),
          ],
        ),
        const SizedBox(height: 10),
        _ReviewDoneButton(
          height: 54,
          busy: busy,
          onPressed: busy ? null : onDone,
        ),
      ],
    );
  }
}

class _ReviewActionTile extends StatelessWidget {
  const _ReviewActionTile({
    this.isLandscape = false,
    this.icon,
    this.iconAsset,
    this.assetScale = 1,
    required this.label,
    required this.onPressed,
  }) : assert(icon != null || iconAsset != null);

  final IconData? icon;
  final bool isLandscape;
  final String? iconAsset;
  final double assetScale;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF121318),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        splashColor: _kReviewAccent.withValues(alpha: 0.18),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isLandscape ? 8 : 10,
            vertical: isLandscape ? 6 : 8,
          ),
          child: Row(
            children: [
              if (iconAsset != null)
                Transform.scale(
                  scale: assetScale,
                  child: Image.asset(
                    iconAsset!,
                    width: isLandscape ? 28 : 36,
                    height: isLandscape ? 28 : 36,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                )
              else
                Icon(icon, color: _kReviewAccent, size: isLandscape ? 27 : 31),
              SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: onPressed == null ? Colors.white38 : Colors.white,
                      fontSize: isLandscape ? 15 : 16,
                      fontWeight: FontWeight.w700,
                    ),
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

class _ReviewAlertTile extends StatelessWidget {
  const _ReviewAlertTile({
    required this.isLandscape,
    required this.enabled,
    required this.value,
    required this.onChanged,
  });

  final bool isLandscape;
  final bool enabled;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const alertRed = Color(0xFFEF4444);
    final accent = value ? alertRed : _kReviewAccent;
    final horizontalPad = 6.0;
    final iconSize = isLandscape ? 27.0 : 26.0;
    final titleSize = isLandscape ? 16.0 : 16.0;
    const subtitleSize = 11.0;
    final switchScale = isLandscape ? 0.68 : 0.70;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: value
            ? alertRed.withValues(alpha: 0.14)
            : const Color(0xFF121318),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value
              ? alertRed.withValues(alpha: 0.85)
              : Colors.white.withValues(alpha: 0.22),
        ),
      ),
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        borderRadius: BorderRadius.circular(16),
        splashColor: accent.withValues(alpha: 0.18),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPad,
            vertical: isLandscape ? 6 : 4,
          ),
          child: Row(
            children: [
              Icon(
                value
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                color: accent,
                size: iconSize,
              ),
              SizedBox(width: isLandscape ? 9 : 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alert',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),

                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Flag for attention',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: value || isLandscape
                              ? Colors.white70
                              : Colors.white60,
                          fontSize: subtitleSize,
                          fontWeight: FontWeight.w400,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Transform.scale(
                scale: switchScale,
                child: Switch.adaptive(
                  value: value,
                  onChanged: enabled ? onChanged : null,
                  activeTrackColor: alertRed.withValues(alpha: 0.55),
                  activeThumbColor: alertRed,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewDoneButton extends StatelessWidget {
  const _ReviewDoneButton({
    required this.height,
    required this.onPressed,
    this.busy = false,
    this.compact = false,
  });

  final double height;
  final VoidCallback? onPressed;
  final bool busy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _kReviewAccent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _kReviewAccent.withValues(alpha: 0.35),
        disabledForegroundColor: Colors.white70,
        minimumSize: Size.fromHeight(height),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!busy) ...[
            Icon(Icons.check_rounded, size: compact ? 24 : 28),
            SizedBox(width: compact ? 8 : 10),
          ],
          Text(
            busy ? 'Saving…' : 'Done',
            style: TextStyle(
              fontSize: compact ? 16 : 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewMediaStamp extends StatelessWidget {
  const _ReviewMediaStamp({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final parts = label.split(' · ');
    final timestamp = parts.isEmpty ? label : parts.first;
    final location = parts.length > 1 ? parts.sublist(1).join(' · ') : '';

    return ColoredBox(
      color: const Color(0xE6121318),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                color: _kReviewAccent,
                size: 17,
              ),
              const SizedBox(width: 8),
              Text(
                timestamp,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1,
                ),
              ),
              if (location.isNotEmpty) ...[
                const SizedBox(width: 14),
                const Icon(
                  Icons.location_on_outlined,
                  color: _kReviewAccent,
                  size: 17,
                ),
                const SizedBox(width: 8),
                Text(
                  location,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewBody extends GetView<CaptureReviewController> {
  const _PreviewBody({required this.isLandscape, required this.edgeToEdge});

  final bool isLandscape;
  final bool edgeToEdge;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 8 || constraints.maxHeight < 8) {
          return const SizedBox.shrink();
        }

        return SizedBox.expand(
          child: _MediaContent(
            isLandscape: isLandscape,
            edgeToEdge: edgeToEdge,
            maxWidth: constraints.maxWidth,
            maxHeight: constraints.maxHeight,
          ),
        );
      },
    );
  }
}

class _MediaContent extends GetView<CaptureReviewController> {
  const _MediaContent({
    required this.isLandscape,
    required this.edgeToEdge,
    required this.maxWidth,
    required this.maxHeight,
  });

  final bool isLandscape;
  final bool edgeToEdge;
  final double maxWidth;
  final double maxHeight;

  Widget _withStamp(Widget child) {
    return Obx(() {
      final resolving = controller.isResolvingLocation.value;
      final stamp = controller.geo.value.reviewStampLabel(
        resolvingLocation: resolving,
      );
      return Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.hardEdge,
        children: [
          child,
          if (stamp.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _ReviewMediaStamp(label: stamp),
            ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (controller.isPhoto) {
      final screen = MediaQuery.sizeOf(context);
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final decodeW = (screen.longestSide * dpr).round().clamp(640, 1280);
      return _MediaFrame(
        edgeToEdge: edgeToEdge,
        child: _withStamp(
          SizedBox(
            width: maxWidth,
            height: maxHeight,
            child: Image.file(
              File(controller.displayPath),
              fit: isLandscape ? BoxFit.cover : BoxFit.contain,
              alignment: Alignment.center,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              cacheWidth: decodeW,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded || frame != null) {
                  CamPerf.firstFrameOnce(
                    'review:${controller.captureId}',
                    controller.captureId,
                    'REVIEW_IMAGE_FIRST_FRAME',
                  );
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    controller.notifyDisplayFirstFrame();
                  });
                  return child;
                }
                return ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation<Color>(cOrange),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Loading preview…',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) =>
                  const _PreviewError(message: 'Unable to load captured photo'),
            ),
          ),
        ),
      );
    }

    return Obx(() {
      if (controller.videoError.value) {
        return const _PreviewError(message: 'Unable to load captured video');
      }

      if (!controller.videoReady.value || controller.videoController == null) {
        return const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(cOrange),
          ),
        );
      }

      final video = controller.videoController!;
      final playing = controller.isPlaying.value;

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: controller.togglePlayback,
        child: SizedBox(
          width: maxWidth,
          height: maxHeight,
          child: _MediaFrame(
            edgeToEdge: edgeToEdge,
            child: Obx(() {
              final resolving = controller.isResolvingLocation.value;
              final stamp = controller.geo.value.reviewStampLabel(
                resolvingLocation: resolving,
              );
              return Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  FittedBox(
                    fit: isLandscape ? BoxFit.cover : BoxFit.contain,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: video.value.size.width,
                      height: video.value.size.height,
                      child: VideoPlayer(video),
                    ),
                  ),
                  if (!playing)
                    const VisitMediaPlayOverlay(
                      size: VisitMediaPlayOverlaySize.large,
                    ),
                  if (stamp.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _ReviewMediaStamp(label: stamp),
                    ),
                ],
              );
            }),
          ),
        ),
      );
    });
  }
}

class _MediaFrame extends StatelessWidget {
  const _MediaFrame({required this.child, required this.edgeToEdge});

  final Widget child;
  final bool edgeToEdge;

  @override
  Widget build(BuildContext context) {
    if (edgeToEdge) {
      return ColoredBox(color: Colors.black, child: child);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: ColoredBox(color: Colors.black, child: child),
      ),
    );
  }
}

class _PreviewError extends StatelessWidget {
  const _PreviewError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ),
    );
  }
}
