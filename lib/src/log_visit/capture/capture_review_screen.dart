import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import '../../app/app_routes.dart';
import '../flow/visit_media_geo.dart';
import '../flow/visit_video_flow_controller.dart';
import '../log_visit_theme.dart';
import '../notes/visit_media_notes_sheet.dart';
import 'capture_review_controller.dart';

/// Bright accent for cinema (black) chrome — brand navy (`cPrimary`) vanishes on black.
const Color _kReviewAccent = Color(0xFF3B82F6);
const Color _kReviewAccentPressed = Color(0xFF2563EB);

class CaptureReviewScreen extends GetView<CaptureReviewController> {
  const CaptureReviewScreen({super.key});

  static Future<T?>? open<T>({
    required String filePath,
    required VisitMediaType mediaType,
    required VisitMediaGeo geo,
    bool resolveLocationInBackground = false,
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
            initialGeo: geo,
            resolveLocationInBackground: resolveLocationInBackground,
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
        flow.findByPath(controller.mediaPath.value) ??
        flow.findByPath(controller.displayPath);
    if (item == null) return;
    await openVisitMediaNotesSheet(context: context, item: item, kind: kind);
  }

  Widget _actionBar({
    required BuildContext context,
    required bool isLandscape,
    required bool topPlacement,
  }) {
    return Obx(() {
      final busy = controller.isBusy.value;
      final gpsBlocked = controller.isDoneBlockedByMissingGps;
      final flow = Get.find<VisitVideoFlowController>();
      VisitMediaItem? item;
      for (final e in flow.mediaItems) {
        if (e.path == controller.mediaPath.value ||
            e.path == controller.displayPath) {
          item = e;
          break;
        }
      }
      final hasTextNote = item?.hasTextNote ?? false;
      final hasVoiceNote = item?.hasVoiceNote ?? false;
      final attentionNeeded = item?.attentionNeeded ?? false;
      final mediaPath = item?.path ?? controller.mediaPath.value;
      return _CaptureReviewActionBar(
        isLandscape: isLandscape,
        topPlacement: topPlacement,
        busy: busy,
        gpsBlocked: gpsBlocked,
        gpsBlockedMessage: controller.doneBlockedMessage,
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
                  capturedAt: controller.geo.value.capturedAt,
                  latitude: controller.geo.value.latitude,
                  longitude: controller.geo.value.longitude,
                  accuracyMeters: controller.geo.value.accuracyMeters,
                  attentionNeeded: value,
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

  Widget _gpsBanner({required bool isLandscape}) {
    return Obx(() {
      final issue = controller.gpsIssueMessage.value?.trim();
      final showIssue =
          issue != null &&
          issue.isNotEmpty &&
          !controller.geo.value.hasCoordinates;
      if (!showIssue) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.fromLTRB(
          isLandscape ? 12 : 12,
          isLandscape ? 6 : 0,
          isLandscape ? 12 : 12,
          isLandscape ? 0 : 8,
        ),
        child: _GpsIssueBanner(message: issue),
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
        if (didPop || controller.isBusy.value) return;
        controller.cancel();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: isLandscape
              ? Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 8, 6),
                      child: Row(
                        children: [
                          Obx(
                            () => TextButton(
                              onPressed: controller.isBusy.value
                                  ? null
                                  : controller.cancel,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                disabledForegroundColor: Colors.white38,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                minimumSize: const Size(64, 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              title,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: _actionBar(
                              context: context,
                              isLandscape: true,
                              topPlacement: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _gpsBanner(isLandscape: true),
                    const Expanded(
                      child: _PreviewBody(isLandscape: true, edgeToEdge: true),
                    ),
                  ],
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
                      child: SizedBox(
                        height: 44,
                        child: Row(
                          children: [
                            Obx(
                              () => TextButton(
                                onPressed: controller.isBusy.value
                                    ? null
                                    : controller.cancel,
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white.withValues(
                                    alpha: 0.88,
                                  ),
                                  disabledForegroundColor: Colors.white38,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  minimumSize: const Size(64, 40),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                title,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            Obx(() {
                              final blocked =
                                  controller.isBusy.value ||
                                  controller.isDoneBlockedByMissingGps;
                              return _ReviewHeaderDoneButton(
                                enabled: !blocked,
                                onPressed: blocked ? null : controller.done,
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    const Expanded(
                      child: _PreviewBody(isLandscape: false, edgeToEdge: true),
                    ),
                    _gpsBanner(isLandscape: false),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: _actionBar(
                        context: context,
                        isLandscape: false,
                        topPlacement: false,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CaptureReviewActionBar extends StatelessWidget {
  const _CaptureReviewActionBar({
    required this.isLandscape,
    required this.topPlacement,
    required this.busy,
    required this.gpsBlocked,
    required this.gpsBlockedMessage,
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
  final bool topPlacement;
  final bool busy;
  final bool gpsBlocked;
  final String gpsBlockedMessage;
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
    if (topPlacement && isLandscape) {
      return Row(
        children: [
          _ReviewAttentionChip(
            compact: true,
            enabled: !busy,
            value: attentionNeeded,
            onChanged: onAttentionChanged,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ReviewActionChip(
              height: 34,
              icon: hasTextNote
                  ? Icons.edit_note_rounded
                  : Icons.sticky_note_2_outlined,
              label: hasTextNote ? 'Edit' : 'Text',
              alertStyle: attentionNeeded,
              onPressed: busy ? null : onTextNote,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ReviewActionChip(
              height: 34,
              icon: hasVoiceNote ? Icons.mic_rounded : Icons.mic_none_rounded,
              label: hasVoiceNote ? 'Edit' : 'Voice',
              alertStyle: attentionNeeded,
              onPressed: busy ? null : onVoiceNote,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ReviewSecondaryButton(
              height: 34,
              label: 'Retake',
              onPressed: busy ? null : onRetake,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ReviewDoneButton(
              height: 34,
              onPressed: (busy || gpsBlocked) ? null : onDone,
            ),
          ),
        ],
      );
    }

    final noteActions = Row(
      children: [
        Expanded(
          child: _ReviewActionChip(
            height: 42,
            icon: hasTextNote
                ? Icons.edit_note_rounded
                : Icons.sticky_note_2_outlined,
            label: hasTextNote ? 'Edit Text' : 'Text',
            alertStyle: attentionNeeded,
            onPressed: busy ? null : onTextNote,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ReviewActionChip(
            height: 42,
            icon: hasVoiceNote ? Icons.mic_rounded : Icons.mic_none_rounded,
            label: hasVoiceNote ? 'Edit Voice' : 'Voice',
            alertStyle: attentionNeeded,
            onPressed: busy ? null : onVoiceNote,
          ),
        ),
      ],
    );

    final blockedMessage = gpsBlocked
        ? Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              gpsBlockedMessage,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFFFCDD2),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.22,
              ),
            ),
          )
        : const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ReviewAttentionToggle(
          enabled: !busy,
          value: attentionNeeded,
          onChanged: onAttentionChanged,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: attentionNeeded
                    ? const EdgeInsets.fromLTRB(7, 7, 7, 7)
                    : EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: attentionNeeded
                      ? const Color(0xFFEF4444).withValues(alpha: 0.10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: attentionNeeded
                      ? Border.all(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.28),
                        )
                      : null,
                ),
                child: noteActions,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ReviewSecondaryButton(
                height: 42,
                label: 'Retake',
                onPressed: busy ? null : onRetake,
              ),
            ),
          ],
        ),
        if (gpsBlocked) ...[const SizedBox(height: 8), blockedMessage],
      ],
    );
  }
}

class _ReviewAttentionToggle extends StatelessWidget {
  const _ReviewAttentionToggle({
    required this.enabled,
    required this.value,
    required this.onChanged,
  });

  final bool enabled;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFEF4444);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: 40,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 0, 4, 0),
      decoration: BoxDecoration(
        color: value
            ? accent.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value
              ? accent.withValues(alpha: 0.42)
              : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          Icon(
            value
                ? Icons.priority_high_rounded
                : Icons.report_gmailerrorred_outlined,
            size: 15,
            color: value
                ? const Color(0xFFF87171)
                : Colors.white.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Attention needed/Urgent',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: value
                    ? const Color(0xFFFECACA)
                    : Colors.white.withValues(alpha: 0.88),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
                height: 1.1,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.72,
            alignment: Alignment.centerRight,
            child: Switch.adaptive(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeTrackColor: accent.withValues(alpha: 0.50),
              activeThumbColor: accent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewAttentionChip extends StatelessWidget {
  const _ReviewAttentionChip({
    required this.compact,
    required this.enabled,
    required this.value,
    required this.onChanged,
  });

  final bool compact;
  final bool enabled;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFEF4444);
    return Material(
      color: value
          ? accent.withValues(alpha: 0.22)
          : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        child: Container(
          height: compact ? 34 : 42,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: value
                  ? accent.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.16),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.priority_high_rounded,
                size: 14,
                color: value ? const Color(0xFFFCA5A5) : Colors.white70,
              ),
              const SizedBox(width: 4),
              Text(
                'Alert',
                style: TextStyle(
                  color: value ? const Color(0xFFFECACA) : Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewHeaderDoneButton extends StatelessWidget {
  const _ReviewHeaderDoneButton({
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? _kReviewAccent : _kReviewAccent.withValues(alpha: 0.32),
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        splashColor: Colors.white.withValues(alpha: 0.18),
        highlightColor: _kReviewAccentPressed.withValues(alpha: 0.55),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Text(
            'Done',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: 0.15,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewActionChip extends StatelessWidget {
  const _ReviewActionChip({
    required this.height,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.alertStyle = false,
  });

  final double height;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool alertStyle;

  @override
  Widget build(BuildContext context) {
    const alert = Color(0xFFEF4444);
    final foreground = alertStyle
        ? const Color(0xFFFECACA)
        : Colors.white.withValues(alpha: 0.94);
    final background = alertStyle
        ? alert.withValues(alpha: 0.20)
        : Colors.white.withValues(alpha: 0.07);
    final border = alertStyle
        ? alert.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.16);

    return SizedBox(
      height: height,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          disabledForegroundColor: Colors.white38,
          backgroundColor: background,
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

class _ReviewSecondaryButton extends StatelessWidget {
  const _ReviewSecondaryButton({
    required this.height,
    required this.label,
    required this.onPressed,
  });

  final double height;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white.withValues(alpha: 0.94),
        disabledForegroundColor: Colors.white38,
        backgroundColor: Colors.white.withValues(alpha: 0.04),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
        minimumSize: Size.fromHeight(height),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ReviewDoneButton extends StatelessWidget {
  const _ReviewDoneButton({required this.height, required this.onPressed});

  final double height;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // Landscape chrome is also black — never use navy `cPrimary` here.
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
      child: const Text(
        'Done',
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
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
          return const ColoredBox(color: Colors.black);
        }

        return ColoredBox(
          color: Colors.black,
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
      final stamp = controller.geo.value.stampLabel;
      final resolving = controller.isResolvingLocation.value;
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
              child: VisitMediaStampBar(label: stamp),
            )
          else if (resolving)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VisitMediaStampBar(label: 'Getting location…'),
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
    final dpr = MediaQuery.devicePixelRatioOf(context);

    if (controller.isPhoto) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: _MediaFrame(
            edgeToEdge: edgeToEdge,
            child: _withStamp(
              Image.file(
                File(controller.displayPath),
                scale: dpr,
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                gaplessPlayback: true,
                filterQuality: FilterQuality.high,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded || frame != null) {
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
                final stamp = controller.geo.value.stampLabel;
                final resolving = controller.isResolvingLocation.value;
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
                        child: VisitMediaStampBar(label: stamp),
                      )
                    else if (resolving)
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: VisitMediaStampBar(label: 'Getting location…'),
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

class _GpsIssueBanner extends StatelessWidget {
  const _GpsIssueBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF3B1D20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x66E53935)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.gps_off_rounded,
                size: 16,
                color: Color(0xFFFF8A80),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFFFFCDD2),
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
