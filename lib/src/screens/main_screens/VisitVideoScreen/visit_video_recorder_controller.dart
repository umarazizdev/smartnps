import 'dart:async';

import 'package:camera/camera.dart';
import 'package:get/get.dart';

import 'package:smartnps360/src/screens/main_screens/VisitVideoScreen/visit_video_flow_controller.dart';
import 'package:smartnps360/src/screens/main_screens/VisitVideoScreen/visit_video_preview_screen.dart';

class VisitVideoRecorderController extends GetxController {
  final isInitializingCamera = true.obs;
  final isStartingRecording = false.obs;
  final isStoppingRecording = false.obs;
  final isRecording = false.obs;
  final cameraError = Rxn<String>();
  final recordingSeconds = 0.obs;

  final currentZoom = 1.0.obs;
  final minZoom = 1.0.obs;
  final maxZoom = 1.0.obs;

  bool _stopRequestedWhileStarting = false;
  bool _isRecorderPrepared = false;
  CameraController? cameraController;
  Timer? _recordingTimer;

  late final VisitVideoFlowController _flowController;

  @override
  void onInit() {
    super.onInit();
    _flowController = Get.isRegistered<VisitVideoFlowController>()
        ? Get.find<VisitVideoFlowController>()
        : Get.put(VisitVideoFlowController());
    initCamera();
  }

  @override
  void onClose() {
    final controller = cameraController;
    if (controller != null && controller.value.isRecordingVideo) {
      unawaited(controller.stopVideoRecording());
    }
    _stopRecordingTimer(reset: false);
    cameraController?.dispose();
    super.onClose();
  }

  Future<void> initCamera() async {
    isInitializingCamera.value = true;
    cameraError.value = null;

    try {
      final cameras = await availableCameras();
      if (isClosed) return;

      if (cameras.isEmpty) {
        cameraError.value = 'No camera found on this device.';
        isInitializingCamera.value = false;
        return;
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: true,
      );

      await controller.initialize();

      final fetchedMinZoom = await controller.getMinZoomLevel();
      final fetchedMaxZoom = await controller.getMaxZoomLevel();

      minZoom.value = fetchedMinZoom < 1.0 ? 1.0 : fetchedMinZoom;
      maxZoom.value = fetchedMaxZoom < 1.0 ? 1.0 : fetchedMaxZoom;

      await controller.setZoomLevel(1.0);
      currentZoom.value = 1.0;

      if (isClosed) {
        await controller.dispose();
        return;
      }

      await _prepareRecorder(controller);
      if (isClosed) {
        await controller.dispose();
        return;
      }

      cameraController = controller;
      isInitializingCamera.value = false;
    } catch (_) {
      if (isClosed) return;
      cameraError.value = 'Unable to open camera. Please check permissions.';
      isInitializingCamera.value = false;
    }
  }

  Future<void> _prepareRecorder(CameraController controller) async {
    if (_isRecorderPrepared) return;
    try {
      await controller.prepareForVideoRecording();
      _isRecorderPrepared = true;
    } catch (_) {
      _isRecorderPrepared = false;
    }
  }

  Future<void> startRecording() async {
    final controller = cameraController;
    if (controller == null) return;
    if (!controller.value.isInitialized) return;
    if (controller.value.isRecordingVideo) return;
    if (isStartingRecording.value || isStoppingRecording.value) return;

    isStartingRecording.value = true;
    _stopRequestedWhileStarting = false;

    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));

      if (!_isRecorderPrepared) {
        unawaited(_prepareRecorder(controller));
      }

      try {
        await controller.setZoomLevel(currentZoom.value);
        await controller.startVideoRecording();
      } catch (_) {
        await _prepareRecorder(controller);
        await controller.setZoomLevel(currentZoom.value);
        await controller.startVideoRecording();
      }

      if (isClosed) return;

      if (_stopRequestedWhileStarting) {
        isStartingRecording.value = false;
        await stopRecording();
        return;
      }

      isRecording.value = true;
      _startRecordingTimer();
    } catch (_) {
    } finally {
      if (!isClosed) isStartingRecording.value = false;
    }
  }

  Future<void> stopRecording({bool moveToPreview = true}) async {
    if (isStoppingRecording.value) return;

    if (isStartingRecording.value) {
      _stopRequestedWhileStarting = true;
      return;
    }

    final controller = cameraController;
    if (controller == null) return;
    if (!controller.value.isRecordingVideo) return;

    isStoppingRecording.value = true;

    try {
      isRecording.value = false;
      _stopRecordingTimer(reset: true);

      await Future<void>.delayed(const Duration(milliseconds: 140));

      final file = await controller.stopVideoRecording();
      if (isClosed) return;

      _flowController.addVideo(file.path);

      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (isClosed) return;

      if (moveToPreview) {
        await Get.off(() => const VisitVideoPreviewScreen());
      }

      unawaited(resetZoom());
    } catch (_) {
      unawaited(resetZoom());
    } finally {
      if (!isClosed) {
        isStoppingRecording.value = false;
      }
      _isRecorderPrepared = false;
      final c = cameraController;
      if (c != null && c.value.isInitialized) {
        unawaited(_prepareRecorder(c));
      }
    }
  }

  Future<void> setZoomFromDrag({
    required double dragDy,
    double maxDragDistance = 200,
  }) async {
    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (!isRecording.value) return;

    // Only upward drag zooms
    final upwardDrag = (-dragDy).clamp(0.0, maxDragDistance);
    final progress = upwardDrag / maxDragDistance;

    final targetZoom =
        minZoom.value + ((maxZoom.value - minZoom.value) * progress);

    final safeZoom = targetZoom.clamp(minZoom.value, maxZoom.value);

    if ((safeZoom - currentZoom.value).abs() < 0.01) return;

    try {
      await controller.setZoomLevel(safeZoom);
      currentZoom.value = safeZoom;
    } catch (_) {}
  }

  Future<void> resetZoom() async {
    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      await controller.setZoomLevel(1.0);
      currentZoom.value = 1.0;
    } catch (_) {}
  }

  void _startRecordingTimer() {
    _stopRecordingTimer(reset: true);
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isClosed) recordingSeconds.value += 1;
    });
  }

  void _stopRecordingTimer({bool reset = false}) {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    if (reset && !isClosed) {
      recordingSeconds.value = 0;
    }
  }

  Future<void> handleLeave() async {
    final controller = cameraController;
    final recording = controller?.value.isRecordingVideo ?? false;
    if (recording) {
      await stopRecording(moveToPreview: false);
    }
    Get.back();
  }
}
