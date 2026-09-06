import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/app_navigator.dart';
import '../../widgets/dialogs/glass_action_dialog.dart';
import '../capture/capture_review_screen.dart';
import '../flow/visit_gps_session.dart';
import '../flow/visit_media_draft_store.dart';
import '../flow/visit_media_geo.dart';
import '../flow/visit_media_orientation.dart';
import '../flow/visit_orientation.dart';
import '../flow/visit_video_flow_controller.dart';

/// Opens the device system Camera for photo/video, then continues the
/// existing visit draft → review → upload pipeline.
class VisitSystemCaptureController extends GetxController
    with WidgetsBindingObserver {
  final isPortrait = true.obs;
  final isLaunchingCamera = false.obs;
  final isResolvingCaptureGps = false.obs;
  final cameraError = RxnString();

  final pendingCapturePath = RxnString();
  final pendingCaptureIsPhoto = false.obs;

  bool _gpsDialogVisible = false;
  String? _pendingDurablePath;
  final ImagePicker _picker = ImagePicker();

  bool get hasPendingCapture => pendingCapturePath.value != null;
  bool get isBusy =>
      isLaunchingCamera.value ||
      isResolvingCaptureGps.value ||
      hasPendingCapture;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    unawaited(VisitOrientation.enableCaptureOrientations());
    _syncOrientationFromMetrics();
    if (!Get.isRegistered<VisitVideoFlowController>()) {
      Get.put(VisitVideoFlowController());
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeMetrics() {
    _syncOrientationFromMetrics();
  }

  void syncOrientation(Orientation orientation) {
    _applyPortrait(orientation == Orientation.portrait);
  }

  void _syncOrientationFromMetrics() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final view = views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    if (size.isEmpty) return;
    _applyPortrait(size.height >= size.width);
  }

  void _applyPortrait(bool portrait) {
    if (isClosed) return;
    if (isPortrait.value == portrait) return;
    isPortrait.value = portrait;
  }

  Future<void> capturePhoto() async {
    await _launchSystemCamera(isPhoto: true);
  }

  Future<void> captureVideo() async {
    await _launchSystemCamera(isPhoto: false);
  }

  Future<void> _launchSystemCamera({required bool isPhoto}) async {
    if (isPortrait.value || isBusy) return;

    cameraError.value = null;
    isLaunchingCamera.value = true;

    try {
      final permitted = await _ensurePermissions(isPhoto: isPhoto);
      if (!permitted || isClosed) return;

      final XFile? file;
      if (isPhoto) {
        file = await _picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.rear,
          imageQuality: 100,
          requestFullMetadata: true,
        );
      } else {
        file = await _picker.pickVideo(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.rear,
        );
      }

      if (isClosed) return;
      if (file == null) return; // cancel → stay on Photo/Video chooser

      final path = file.path;
      if (path.isEmpty || !File(path).existsSync()) {
        cameraError.value = 'Capture failed. Please try again.';
        return;
      }

      final landscape = await VisitMediaOrientation.isLandscape(
        path: path,
        isPhoto: isPhoto,
      );
      if (isClosed) return;
      if (!landscape) {
        await VisitMediaDraftStore.instance.deleteQuietly(path);
        await _showPortraitCaptureDialog(isPhoto: isPhoto);
        return;
      }

      pendingCapturePath.value = path;
      pendingCaptureIsPhoto.value = isPhoto;
      isLaunchingCamera.value = false;
      await _finalizePendingCapture();
    } catch (e) {
      if (!isClosed) {
        cameraError.value =
            'Unable to open the camera. Please check permissions.';
      }
    } finally {
      if (!isClosed) isLaunchingCamera.value = false;
    }
  }

  Future<void> _showPortraitCaptureDialog({required bool isPhoto}) async {
    final context = AppNavigator.key.currentContext ?? Get.context;
    if (context == null || !context.mounted || isClosed) {
      cameraError.value = 'Please capture in landscape and try again.';
      return;
    }

    await GlassActionDialog.show(
      context: context,
      icon: Icons.screen_rotation_rounded,
      title: 'Landscape required',
      message: isPhoto
          ? 'Please rotate your device to landscape and take the photo again.'
          : 'Please rotate your device to landscape and record the video again.',
      primaryLabel: 'OK',
      iconColor: const Color(0xFFE48E15),
      barrierDismissible: false,
      useRootNavigator: true,
    );
  }

  Future<bool> _ensurePermissions({required bool isPhoto}) async {
    final camera = await Permission.camera.request();
    if (!camera.isGranted) {
      cameraError.value =
          'Camera permission is required to capture photos and videos.';
      return false;
    }

    if (!isPhoto) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        cameraError.value =
            'Microphone permission is required to record video.';
        return false;
      }
    }

    return true;
  }

  Future<void> _finalizePendingCapture() async {
    final path = pendingCapturePath.value;
    if (path == null || path.isEmpty) return;

    final isPhoto = pendingCaptureIsPhoto.value;
    final type = isPhoto ? VisitMediaType.photo : VisitMediaType.video;

    final flow = Get.isRegistered<VisitVideoFlowController>()
        ? Get.find<VisitVideoFlowController>()
        : Get.put(VisitVideoFlowController(), permanent: true);

    final capturedAt = DateTime.now();
    final captureId =
        'sys_${capturedAt.microsecondsSinceEpoch}_${path.hashCode.toUnsigned(32).toRadixString(16)}';
    await flow.registerCaptureDraft(
      VisitMediaItem(
        path: path,
        type: type,
        captureId: captureId,
        capturedAt: capturedAt,
        isPendingCapture: true,
      ),
    );
    if (isClosed) return;

    final warm = VisitGpsSession.instance.latestUsableFresh;
    final hasWarmGeo = warm != null;
    if (!hasWarmGeo) {
      isResolvingCaptureGps.value = true;
    }

    final geoFuture = hasWarmGeo
        ? Future<VisitMediaGeo>.value(
            VisitMediaGeo(
              capturedAt: capturedAt,
              latitude: warm.latitude,
              longitude: warm.longitude,
              accuracyMeters: warm.accuracy,
            ),
          )
        : VisitMediaGeo.captureFast();
    final persistFuture = flow.finalizeCaptureDraft(
      previewPath: path,
      type: type,
      captureId: captureId,
    );

    try {
      final durableItem = await persistFuture;
      if (isClosed) return;
      if (durableItem != null) {
        _pendingDurablePath = durableItem.path;
      }

      final openPath = _pendingDurablePath ?? path;

      if (hasWarmGeo) {
        final geo = await geoFuture;
        if (isClosed) return;
        await flow.updateCaptureGeo(
          mediaPath: openPath,
          geo: geo,
          captureId: captureId,
        );
        if (_pendingDurablePath != null && _pendingDurablePath != path) {
          await VisitMediaDraftStore.instance.deleteQuietly(path);
        }
        if (isClosed) return;

        final opened = CaptureReviewScreen.open(
          filePath: openPath,
          mediaType: type,
          captureId: captureId,
          geo: geo,
          resolveLocationInBackground: false,
        );
        _clearPendingCapture();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _deleteSelf();
        });
        await opened;
        return;
      }

      if (_pendingDurablePath != null && _pendingDurablePath != path) {
        await VisitMediaDraftStore.instance.deleteQuietly(path);
      }
      if (isClosed) return;

      final opened = CaptureReviewScreen.open(
        filePath: openPath,
        mediaType: type,
        captureId: captureId,
        geo: VisitMediaGeo(capturedAt: capturedAt),
        resolveLocationInBackground: true,
      );

      _clearPendingCapture();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _deleteSelf();
      });
      unawaited(geoFuture);
      await opened;
    } catch (_) {
      isResolvingCaptureGps.value = false;
      final shouldRetry = await _showGpsFailedDialog();
      if (shouldRetry) {
        await _finalizePendingCapture();
      } else {
        await _discardPendingCaptureAndLeave();
      }
    } finally {
      if (!isClosed) {
        isResolvingCaptureGps.value = false;
      }
    }
  }

  Future<bool> _showGpsFailedDialog() async {
    if (isClosed || _gpsDialogVisible) return false;
    _gpsDialogVisible = true;
    try {
      final failure = await VisitMediaGeo.describeFailure();
      final context = AppNavigator.key.currentContext ?? Get.context;
      if (context == null || !context.mounted || isClosed) return false;

      final retry = await GlassActionDialog.show(
        context: context,
        icon: Icons.gps_off_rounded,
        title: 'Failed to get GPS',
        message: failure,
        primaryLabel: 'Retry',
        secondaryLabel: 'Cancel',
        iconColor: const Color(0xFFE53935),
        variant: GlassActionDialogVariant.error,
        barrierDismissible: false,
        useRootNavigator: true,
      );
      return retry == true;
    } finally {
      _gpsDialogVisible = false;
    }
  }

  Future<void> _discardPendingCaptureAndLeave() async {
    final path = pendingCapturePath.value;
    final durable = _pendingDurablePath;
    final flow = Get.isRegistered<VisitVideoFlowController>()
        ? Get.find<VisitVideoFlowController>()
        : null;
    if (flow != null) {
      if (durable != null) {
        await flow.removeByPath(durable, deleteMediaFile: true);
      }
      if (path != null) {
        await flow.removeByPath(path, deleteMediaFile: true);
      }
    }
    await VisitMediaDraftStore.instance.deleteQuietly(path);
    await VisitMediaDraftStore.instance.deleteQuietly(durable);
    _clearPendingCapture();
    await _leaveCaptureScreen();
  }

  void _clearPendingCapture() {
    pendingCapturePath.value = null;
    pendingCaptureIsPhoto.value = false;
    isResolvingCaptureGps.value = false;
    _pendingDurablePath = null;
  }

  Future<void> handleLeave() async {
    if (hasPendingCapture) {
      await _discardPendingCaptureAndLeave();
      return;
    }
    await _leaveCaptureScreen();
  }

  Future<void> _leaveCaptureScreen() async {
    Get.back();
    _deleteSelf();
  }

  void _deleteSelf() {
    if (Get.isRegistered<VisitSystemCaptureController>()) {
      Get.delete<VisitSystemCaptureController>(force: true);
    }
  }
}
