import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:smartnps360/src/screens/main_screens/VisitVideoScreen/visit_video_recorder_controller.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

class VisitVideoRecorderScreen extends StatefulWidget {
  static const String routeName = '/visit-video-recorder';

  const VisitVideoRecorderScreen({super.key});

  @override
  State<VisitVideoRecorderScreen> createState() =>
      _VisitVideoRecorderScreenState();
}

class _VisitVideoRecorderScreenState extends State<VisitVideoRecorderScreen> {
  late final VisitVideoRecorderController _controller;
  final GlobalKey _recordButtonKey = GlobalKey();
  double _startDragDy = 0;
  @override
  void initState() {
    super.initState();
    _controller = Get.put(VisitVideoRecorderController());
  }

  @override
  void dispose() {
    Get.delete<VisitVideoRecorderController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) => _controller.handleLeave(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Obx(() {
            final isStarting = _controller.isStartingRecording.value;
            final isStopping = _controller.isStoppingRecording.value;
            final isRecording = _controller.isRecording.value;
            final isInitializing = _controller.isInitializingCamera.value;
            final cameraError = _controller.cameraError.value;
            final recordingSeconds = _controller.recordingSeconds.value;
            final isBusy = isStarting || isStopping;

            return Stack(
              children: [
                Column(
                  children: [
                    _buildTopBar(isDark),
                    Expanded(
                      child: _buildCameraView(
                        isInitializing: isInitializing,
                        cameraError: cameraError,
                      ),
                    ),
                    _buildBottomControls(
                      isRecording: isRecording,
                      isBusy: isBusy,
                      recordingSeconds: recordingSeconds,
                    ),
                  ],
                ),
                if (isRecording) _buildZoomIndicator(),
                if (isBusy)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withAlpha(64),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(166),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.3,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    cOrange,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                isStarting
                                    ? 'Starting recording...'
                                    : 'Finishing recording...',
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
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          InkWell(
            onTap: _controller.handleLeave,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? cDarkCardColor.withAlpha(179)
                    : Colors.black.withAlpha(140),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Record Visit Video',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraView({
    required bool isInitializing,
    required String? cameraError,
  }) {
    if (isInitializing) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(cOrange),
        ),
      );
    }

    if (cameraError != null) {
      return Center(
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
                onPressed: _controller.initCamera,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cPrimary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final cameraCtrl = _controller.cameraController;
    if (cameraCtrl == null || !cameraCtrl.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = cameraCtrl.value.previewSize;
        if (previewSize == null) {
          return Center(child: CameraPreview(cameraCtrl));
        }

        final previewWidth = previewSize.height;
        final previewHeight = previewSize.width;

        final screenRatio = constraints.maxWidth / constraints.maxHeight;
        final previewRatio = previewWidth / previewHeight;

        double scale = previewRatio / screenRatio;
        if (scale < 1) {
          scale = 1 / scale;
        }

        return ClipRect(
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: Center(
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: CameraPreview(cameraCtrl),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildZoomIndicator() {
    return Positioned(
      right: 18,
      bottom: 155,
      child: Obx(() {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(155),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            '${_controller.currentZoom.value.toStringAsFixed(1)}x',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildBottomControls({
    required bool isRecording,
    required bool isBusy,
    required int recordingSeconds,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withAlpha(0), Colors.black.withAlpha(166)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isRecording) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
                    fontSize: 18,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Recording... slide up a little to zoom',
              style: TextStyle(
                color: cOrange,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ] else
            const Text(
              'Hold to record (slide up a little to zoom)',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          const SizedBox(height: 14),
          GestureDetector(
            onLongPressStart: (details) async {
              _startDragDy = details.globalPosition.dy;

              if (!isBusy) {
                await _controller.startRecording();
              }
            },

            onLongPressMoveUpdate: (details) {
              final dragDy = details.globalPosition.dy - _startDragDy;

              _controller.setZoomFromDrag(dragDy: dragDy);
            },

            onLongPressEnd: (_) async {
              await _controller.stopRecording();
            },

            onLongPressCancel: () async {
              await _controller.stopRecording();
            },

            child: AnimatedContainer(
              key: _recordButtonKey,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              width: isRecording ? 88 : 82,
              height: isRecording ? 88 : 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isRecording ? cRed : Colors.white,
                border: Border.all(
                  color: isRecording ? Colors.white : cOrange,
                  width: 4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isRecording ? cRed : cOrange).withAlpha(102),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                child: Icon(
                  isRecording ? Icons.stop_rounded : Icons.videocam_rounded,
                  key: ValueKey(isRecording),
                  color: isRecording ? Colors.white : cPrimary,
                  size: 34,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
