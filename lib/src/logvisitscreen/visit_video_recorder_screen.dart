import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'log_visit_theme.dart';
import 'visit_orientation_prompt_overlay.dart';
import 'visit_video_recorder_controller.dart';

class VisitVideoRecorderScreen extends GetView<VisitVideoRecorderController> {
  static const String routeName = '/visit-video-recorder';

  const VisitVideoRecorderScreen({super.key});

  @override
  VisitVideoRecorderController get controller {
    if (!Get.isRegistered<VisitVideoRecorderController>()) {
      Get.put(VisitVideoRecorderController());
    }
    return Get.find<VisitVideoRecorderController>();
  }

  @override
  Widget build(BuildContext context) {
    final mediaOrientation = MediaQuery.orientationOf(context);
    if (controller.isPortrait.value !=
        (mediaOrientation == Orientation.portrait)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!Get.isRegistered<VisitVideoRecorderController>()) return;
        controller.syncOrientation(mediaOrientation);
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) => controller.handleLeave(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                key: controller.previewCaptureKey,
                child: const _StableCameraPreview(),
              ),
            ),
            Positioned.fill(
              child: Obx(() {
                if (!controller.lensHoldVisible.value) {
                  return const SizedBox.shrink();
                }
                final image = controller.lensHoldImage.value;
                if (image == null) return const SizedBox.shrink();
                return IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: controller.lensHoldOpacity.value,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    onEnd: () {
                      if (controller.lensHoldOpacity.value < 0.05) {
                        controller.clearLensHoldFrame();
                      }
                    },
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: image.width.toDouble(),
                        height: image.height.toDouble(),
                        child: RawImage(
                          image: image,
                          fit: BoxFit.fill,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            Positioned.fill(
              child: Obx(() {
                final path = controller.pendingCapturePath.value;
                if (path == null || path.isEmpty) {
                  return const SizedBox.shrink();
                }
                final isPhoto = controller.pendingCaptureIsPhoto.value;
                if (!isPhoto) {
                  return const ColoredBox(color: Color(0x99000000));
                }
                return ColoredBox(
                  color: Colors.black,
                  child: Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                );
              }),
            ),
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapUp: (details) {
                      if (!Get.isRegistered<VisitVideoRecorderController>()) {
                        return;
                      }
                      if (controller.isInitializingCamera.value) return;
                      if (controller.isSwitchingLens.value) return;
                      if (controller.cameraError.value != null) return;
                      if (controller.isCapturingPhoto.value) return;
                      if (controller.hasPendingCapture) return;
                      if (constraints.maxWidth <= 0 ||
                          constraints.maxHeight <= 0) {
                        return;
                      }

                      final local = details.localPosition;
                      final normalized = Offset(
                        (local.dx / constraints.maxWidth).clamp(0.0, 1.0),
                        (local.dy / constraints.maxHeight).clamp(0.0, 1.0),
                      );
                      unawaited(
                        controller.focusAt(
                          normalizedPoint: normalized,
                          uiPoint: local,
                        ),
                      );
                    },
                    child: Obx(() {
                      final point = controller.focusUiPoint.value;
                      if (point == null) return const SizedBox.expand();
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned(
                            left: point.dx - 34,
                            top: point.dy - 34,
                            child: _FocusReticle(),
                          ),
                        ],
                      );
                    }),
                  );
                },
              ),
            ),
            Positioned.fill(
              child: Obx(() {
                final isPortrait = controller.isPortrait.value;
                return IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: isPortrait
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.35),
                                Colors.transparent,
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.55),
                              ],
                              stops: const [0, 0.2, 0.65, 1],
                            )
                          : LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.black.withValues(alpha: 0.4),
                                Colors.transparent,
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.45),
                              ],
                              stops: const [0, 0.18, 0.72, 1],
                            ),
                    ),
                  ),
                );
              }),
            ),
            SafeArea(
              child: Obx(() {
                final isStarting = controller.isStartingRecording.value;
                final isStopping = controller.isStoppingRecording.value;
                final isCapturing = controller.isCapturingPhoto.value;
                final isRecording = controller.isRecording.value;
                final recordingSeconds = controller.recordingSeconds.value;
                final portraitBlocked = controller.isPortrait.value;
                final pending = controller.hasPendingCapture;
                final resolvingGps = controller.isResolvingCaptureGps.value;
                final isBusy =
                    isStarting || isStopping || isCapturing || pending;
                final controlsLocked = isBusy || portraitBlocked;
                final showBusyOverlay =
                    isStopping || isStarting || isCapturing;
                final hideCaptureChrome = pending;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!hideCaptureChrome) ...[
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: AnimatedOpacity(
                          opacity: portraitBlocked ? 1 : 0,
                          duration: const Duration(milliseconds: 90),
                          curve: Curves.easeOut,
                          child: IgnorePointer(
                            ignoring: !portraitBlocked,
                            child: _buildBottomControls(
                              isRecording: isRecording,
                              isBusy: isBusy,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        bottom: 0,
                        child: AnimatedOpacity(
                          opacity: portraitBlocked ? 0 : 1,
                          duration: const Duration(milliseconds: 90),
                          curve: Curves.easeOut,
                          child: IgnorePointer(
                            ignoring: portraitBlocked,
                            child: _buildRightControls(
                              isRecording: isRecording,
                              isBusy: controlsLocked,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (showBusyOverlay)
                      _buildBusyOverlay(
                        isStarting: isStarting,
                        isCapturing: isCapturing,
                      ),
                    if (pending && resolvingGps)
                      _buildBusyOverlay(
                        isStarting: false,
                        isCapturing: false,
                        label: 'Getting location…',
                      ),
                    if (!hideCaptureChrome)
                      Positioned.fill(
                        child: AnimatedOpacity(
                          opacity: portraitBlocked ? 1 : 0,
                          duration: const Duration(milliseconds: 100),
                          curve: Curves.easeOut,
                          child: IgnorePointer(
                            ignoring: !portraitBlocked,
                            child: const VisitOrientationPromptOverlay(
                              mode: VisitOrientationPromptMode.landscape,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _buildTopChrome(
                        isRecording:
                            isRecording && !portraitBlocked && !pending,
                        recordingSeconds: recordingSeconds,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopChrome({
    required bool isRecording,
    required int recordingSeconds,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: SizedBox(
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _GlassCircleButton(
                onTap: controller.handleLeave,
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            if (isRecording) _buildRecordingBadge(recordingSeconds),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingBadge(int recordingSeconds) {
    return _GlassPill(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: cRed,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatMMSS(recordingSeconds),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              letterSpacing: 1.2,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureHints({
    required bool isRecording,
    bool compact = true,
  }) {
    return Text(
      isRecording
          ? 'Slide up/down to zoom'
          : (compact ? 'Tap photo\nHold video' : 'Tap photo · Hold video'),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: isRecording ? cOrange : Colors.white.withValues(alpha: 0.92),
        fontWeight: FontWeight.w600,
        fontSize: compact ? 11 : 13,
        height: 1.2,
        shadows: const [
          Shadow(color: Color(0x99000000), blurRadius: 8),
        ],
      ),
    );
  }

  Widget _buildZoomSelector({bool vertical = false, bool isRecording = false}) {
    return Obx(() {
      const presets = <double>[0.5, 1.0, 2.0];
      final children = [
        for (var i = 0; i < presets.length; i++) ...[
          if (i > 0)
            SizedBox(width: vertical ? 0 : 6, height: vertical ? 6 : 0),
          _ZoomChip(
            factor: presets[i],
            label: controller.zoomChipLabel(presets[i]),
            selected: controller.isZoomChipActive(presets[i]),
            onTap: isRecording
                ? null
                : () => unawaited(controller.setZoomPreset(presets[i])),
          ),
        ],
      ];

      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: vertical ? 5 : 6,
          vertical: vertical ? 6 : 5,
        ),
        decoration: BoxDecoration(
          color: const Color(0x6E3A3A3C),
          borderRadius: BorderRadius.circular(22),
        ),
        child: vertical
            ? Column(mainAxisSize: MainAxisSize.min, children: children)
            : Row(mainAxisSize: MainAxisSize.min, children: children),
      );
    });
  }

  Widget _buildBottomControls({
    required bool isRecording,
    required bool isBusy,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: isBusy ? 0.45 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCaptureHints(isRecording: isRecording, compact: false),
            const SizedBox(height: 12),
            _buildZoomSelector(isRecording: isRecording),
            const SizedBox(height: 14),
            _buildRecordButton(isRecording: isRecording, isBusy: isBusy),
          ],
        ),
      ),
    );
  }

  Widget _buildRightControls({
    required bool isRecording,
    required bool isBusy,
  }) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: isBusy ? 0.45 : 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildZoomSelector(
                vertical: true,
                isRecording: isRecording,
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 92,
                height: 72,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    _buildRecordButton(
                      isRecording: isRecording,
                      isBusy: isBusy,
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 78,
                      child: _buildCaptureHints(isRecording: isRecording),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordButton({
    required bool isRecording,
    required bool isBusy,
  }) {
    return GestureDetector(
      onTap: () async {
        if (isBusy || isRecording) return;
        await controller.capturePhoto();
      },
      onLongPressStart: (details) {
        if (isBusy) return;
        controller.onRecordingGestureStart(details.globalPosition);
        unawaited(controller.startRecording());
      },
      onLongPressMoveUpdate: (details) {
        controller.setZoomFromDrag(globalPosition: details.globalPosition);
      },
      onLongPressEnd: (_) async {
        controller.onRecordingGestureEnd();
        await controller.stopRecording();
      },
      onLongPressCancel: () async {
        controller.onRecordingGestureEnd();
        await controller.stopRecording();
      },
      child: Container(
                width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isRecording ? cRed : Colors.white,
          border: Border.all(
            color: isRecording ? Colors.white : cOrange,
            width: 3.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: (isRecording ? cRed : cOrange).withValues(alpha: 0.35),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Icon(
          isRecording ? Icons.stop_rounded : Icons.camera_alt_rounded,
          color: isRecording ? Colors.white : cPrimary,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildBusyOverlay({
    required bool isStarting,
    required bool isCapturing,
    String? label,
  }) {
    final resolvedLabel = label ??
        (isCapturing
            ? 'Capturing...'
            : isStarting
                ? 'Starting...'
                : 'Saving...');

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.28),
        child: Center(
          child: _GlassPill(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.3,
                    valueColor: AlwaysStoppedAnimation<Color>(cOrange),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  resolvedLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
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

class _StableCameraPreview extends StatefulWidget {
  const _StableCameraPreview();

  @override
  State<_StableCameraPreview> createState() => _StableCameraPreviewState();
}

class _StableCameraPreviewState extends State<_StableCameraPreview> {
  double _lastW = 0;
  double _lastH = 0;

  VisitVideoRecorderController get controller =>
      Get.find<VisitVideoRecorderController>();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isInitializing = controller.isInitializingCamera.value;
      final cameraError = controller.cameraError.value;
      final isPortrait = controller.isPortrait.value;
      controller.stablePreviewAspect.value;
      controller.lensGeneration.value;
      controller.isSwitchingLens.value;

      if (isInitializing) {
        return const ColoredBox(
          color: Colors.black,
          child: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(cOrange),
            ),
          ),
        );
      }

      if (cameraError != null) {
        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.videocam_off_rounded,
                    color: Colors.white70,
                    size: 42,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    cameraError,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: controller.initCamera,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cPrimary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      final cameraCtrl = controller.cameraController;
      final hasLive =
          cameraCtrl != null && cameraCtrl.value.isInitialized;
      if (!hasLive) {
        return const ColoredBox(color: Colors.black);
      }

      final aspect = controller.stablePreviewAspect.value ??
          cameraCtrl.value.aspectRatio;

      return ColoredBox(
        color: Colors.black,
        child: LayoutBuilder(
          builder: (context, constraints) {
            var maxW = constraints.maxWidth;
            var maxH = constraints.maxHeight;

            if (maxW < 48 || maxH < 48) {
              if (_lastW >= 48 && _lastH >= 48) {
                maxW = _lastW;
                maxH = _lastH;
              } else {
                return const ColoredBox(color: Colors.black);
              }
            } else {
              _lastW = maxW;
              _lastH = maxH;
            }

            final safeAspect = aspect > 0 ? aspect : (maxW / maxH);
            final gen = controller.lensGeneration.value;

            return ClipRect(
              child: FittedBox(
                fit: isPortrait ? BoxFit.cover : BoxFit.contain,
                alignment: Alignment.center,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: safeAspect * 1000,
                  height: 1000,
                  child: _PinnedCameraPreview(
                    key: ValueKey<String>(
                      'cam_${gen}_${identityHashCode(cameraCtrl)}',
                    ),
                    cameraController: cameraCtrl,
                    aspectRatio: safeAspect,
                  ),
                ),
              ),
            );
          },
        ),
      );
    });
  }
}

class _PinnedCameraPreview extends StatelessWidget {
  const _PinnedCameraPreview({
    super.key,
    required this.cameraController,
    required this.aspectRatio,
  });

  final CameraController cameraController;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: CameraPreview(cameraController),
    );
  }
}

class _FocusReticle extends StatefulWidget {
  const _FocusReticle();

  @override
  State<_FocusReticle> createState() => _FocusReticleState();
}

class _FocusReticleState extends State<_FocusReticle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.28, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 70,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.94)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
    ]).animate(_controller);
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(1), weight: 70),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: 0.55)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.scale(
            scale: _scale.value,
            child: child,
          ),
        );
      },
      child: SizedBox(
        width: 68,
        height: 68,
        child: CustomPaint(painter: _FocusReticlePainter()),
      ),
    );
  }
}

class _FocusReticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(1.5, 1.5, size.width - 3, size.height - 3);
    final paint = Paint()
      ..color = const Color(0xFFFFCC33)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    const corner = 14.0;
    final path = Path()
      ..moveTo(rect.left, rect.top + corner)
      ..lineTo(rect.left, rect.top)
      ..lineTo(rect.left + corner, rect.top)
      ..moveTo(rect.right - corner, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, rect.top + corner)
      ..moveTo(rect.right, rect.bottom - corner)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.right - corner, rect.bottom)
      ..moveTo(rect.left + corner, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.bottom - corner);

    canvas.drawPath(path, paint);

    final cross = Paint()
      ..color = const Color(0xFFFFCC33).withValues(alpha: 0.85)
      ..strokeWidth = 1.2;
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawLine(Offset(cx - 5, cy), Offset(cx + 5, cy), cross);
    canvas.drawLine(Offset(cx, cy - 5), Offset(cx, cy + 5), cross);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ZoomChip extends StatelessWidget {
  const _ZoomChip({
    required this.factor,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final double factor;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final compact = !selected || label.length <= 2;
    final width = selected ? (compact ? 40.0 : 46.0) : 34.0;
    final height = selected ? 40.0 : 34.0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          color: selected
              ? const Color(0xCC2C2C2E)
              : const Color(0x992C2C2E),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          style: TextStyle(
            color: selected ? const Color(0xFFFFD60A) : Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: selected ? (label.length > 2 ? 9 : 11) : 10,
            height: 1,
            letterSpacing: -0.3,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.onTap,
    required this.child,
  });

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.42),
      shape: const CircleBorder(
        side: BorderSide(color: Colors.white24),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: child,
    );
  }
}
