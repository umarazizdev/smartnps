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
          child: Column(
            children: [
              _ReviewHeader(title: title, onCancel: controller.cancel),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isLandscape ? 20 : 12,
                    isLandscape ? 0 : 8,
                    isLandscape ? (Platform.isAndroid ? 12 : 0) : 12,
                    12,
                  ),
                  child: isLandscape
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Expanded(
                              flex: 5,
                              child: _PreviewBody(
                                isLandscape: true,
                                edgeToEdge: false,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: _actionBar(
                                context: context,
                                isLandscape: true,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            const Expanded(
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
  const _ReviewHeader({required this.title, required this.onCancel});

  final String title;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 10),
          TextButton.icon(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: const Size(0, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.close_rounded, size: 30),
            label: const Text(
              'Cancel',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 23,
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
        iconAsset: 'assets/images/capture_retake_icon.png',
        label: 'Retake',
        onPressed: busy ? null : onRetake,
      ),
      _ReviewActionTile(
        iconAsset: 'assets/images/capture_note_icon.png',
        assetScale: 1.05,
        label: hasTextNote ? 'Edit note' : 'Add note',
        onPressed: busy ? null : onTextNote,
      ),
      _ReviewActionTile(
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
      return Column(
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            Expanded(flex: index == 3 ? 6 : 5, child: actions[index]),
            if (index != actions.length - 1) const SizedBox(height: 10),
          ],
          const SizedBox(height: 12),
          _ReviewDoneButton(
            height: 62,
            busy: busy,
            onPressed: busy ? null : onDone,
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: actions[0]),
            const SizedBox(width: 8),
            Expanded(child: actions[1]),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: actions[2]),
            const SizedBox(width: 8),
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
    this.icon,
    this.iconAsset,
    this.assetScale = 1,
    required this.label,
    required this.onPressed,
  }) : assert(icon != null || iconAsset != null);

  final IconData? icon;
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              if (iconAsset != null)
                Transform.scale(
                  scale: assetScale,
                  child: Image.asset(
                    iconAsset!,
                    width: 36,
                    height: 36,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                )
              else
                Icon(icon, color: _kReviewAccent, size: 31),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onPressed == null ? Colors.white38 : Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
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
    final horizontalPad = isLandscape ? 14.0 : 10.0;
    final iconSize = isLandscape ? 30.0 : 26.0;
    final titleSize = isLandscape ? 17.0 : 16.0;
    final subtitleSize = isLandscape ? 12.0 : 11.0;
    final switchScale = isLandscape ? 0.78 : 0.70;

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
              SizedBox(width: isLandscape ? 12 : 8),
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
                          color: value ? Colors.white70 : Colors.white60,
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
  });

  final double height;
  final VoidCallback? onPressed;
  final bool busy;

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
            const Icon(Icons.check_rounded, size: 28),
            const SizedBox(width: 10),
          ],
          Text(
            busy ? 'Saving…' : 'Done',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ReviewStampRow(
              icon: Icons.calendar_today_outlined,
              text: timestamp,
            ),
            if (location.isNotEmpty) ...[
              const SizedBox(height: 7),
              _ReviewStampRow(icon: Icons.location_on_outlined, text: location),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewStampRow extends StatelessWidget {
  const _ReviewStampRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _kReviewAccent, size: 17),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        ),
      ],
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

  Size _actualDisplaySize({
    required double pixelWidth,
    required double pixelHeight,
    required double devicePixelRatio,
  }) {
    final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
    var width = pixelWidth / dpr;
    var height = pixelHeight / dpr;
    if (width <= 0 || height <= 0) {
      return Size(maxWidth, maxHeight);
    }
    final scale = (maxWidth / width < maxHeight / height)
        ? maxWidth / width
        : maxHeight / height;
    if (scale < 1.0) {
      width *= scale;
      height *= scale;
    }
    return Size(width, height);
  }

  @override
  Widget build(BuildContext context) {
    if (controller.isPhoto) {
      final screen = MediaQuery.sizeOf(context);
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final decodeW = (screen.longestSide * dpr).round().clamp(640, 1280);
      return Align(

        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: _MediaFrame(
            edgeToEdge: edgeToEdge,
            child: _withStamp(
              Image.file(
                File(controller.displayPath),
                fit: BoxFit.contain,
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
                  return SizedBox(
                    width: maxWidth.clamp(120, 320),
                    height: maxHeight.clamp(120, 240),
                    child: const ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  cOrange,
                                ),
                              ),
                            ),
                            SizedBox(height: 12),
                            Text(
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
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) =>
                    const _PreviewError(
                      message: 'Unable to load captured photo',
                    ),
              ),
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
      final size = video.value.size;
      final playing = controller.isPlaying.value;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final pixelW = size.width <= 0 ? maxWidth * dpr : size.width;
      final pixelH = size.height <= 0 ? maxHeight * dpr : size.height;
      final display = _actualDisplaySize(
        pixelWidth: pixelW,
        pixelHeight: pixelH,
        devicePixelRatio: dpr,
      );

      return GestureDetector(
        onTap: controller.togglePlayback,
        child: Center(
          child: SizedBox(
            width: display.width,
            height: display.height,
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
                    VideoPlayer(video),
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
