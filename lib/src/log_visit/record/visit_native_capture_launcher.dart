import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/app_navigator.dart';
import '../../app/app_routes.dart';
import '../../native_camera/native_camera.dart';
import '../../widgets/dialogs/glass_action_dialog.dart';
import '../capture/capture_review_screen.dart';
import '../flow/cam_perf.dart';
import '../flow/capture_work_coordinator.dart';
import '../flow/visit_media_draft_store.dart';
import '../flow/visit_media_orientation.dart';
import '../flow/visit_orientation.dart';
import '../flow/visit_video_flow_controller.dart';

/// Opens the native evidence camera and continues the existing draft → review
/// → upload pipeline without changing server contracts.
class VisitNativeCaptureLauncher {
  VisitNativeCaptureLauncher._();

  static bool _opening = false;
  static int? _openStartedMs;

  static Future<void> open({
    CaptureType initialType = CaptureType.photo,
    bool allowModeSwitch = true,
  }) async {
    if (_opening) return;
    _opening = true;
    _openStartedMs = DateTime.now().millisecondsSinceEpoch;
    _log('CAMERA_REQUEST');

    // Opaque cover so when the native Activity/VC dismisses, the Draft/Checkpoint
    // stack is never briefly painted before CaptureReview.
    var coverPushed = false;
    try {
      await VisitOrientation.enableCaptureOrientations();
      _log('ORIENTATION_UNLOCKED');

      final permitted = await _ensurePermissions(
        needsMicrophone: allowModeSwitch || initialType == CaptureType.video,
      );
      if (!permitted) return;
      _log('PERMISSIONS_OK');

      final expectedType = initialType == CaptureType.photo
          ? VisitMediaType.photo
          : VisitMediaType.video;
      final coordinator = CaptureWorkCoordinator.beginSession(
        expectedType: expectedType,
      );

      // Warm capability cache in the background — must NOT block camera open.
      unawaited(
        NativeCamera.getCapabilities(type: initialType).then((caps) {
          if (kDebugMode) {
            debugPrint(
              '[VisitNativeCapture] caps (async) '
              'auto=${caps.autoExtension} hdr=${caps.hdrPhoto} '
              'night=${caps.nightPhoto} heic=${caps.heic} '
              'ext=${caps.supportedExtensionModes}',
            );
          }
        }),
      );

      coverPushed = await _pushTransitionCover();
      _log('TRANSITION_COVER_${coverPushed ? "SHOWN" : "SKIPPED"}');

      final NativeCameraResult? result;
      try {
        _log('NATIVE_OPEN_INVOKE');
        CamPerf.resetCameraOpenFlow();
        CamPerf.log(null, 'FLUTTER_NATIVE_CAMERA_OPEN_START');
        result = await NativeCamera.open(
          type: initialType,
          allowModeSwitch: allowModeSwitch,
          landscapeOnly: true,
          rearCameraOnly: true,
          quality: CaptureQuality.maximum,
          // HEIC remains disabled for visit evidence until backend/storage/viewer
          // compatibility is verified. Keep JPEG originals for the upload path.
          preferHeic: false,
        );
        _log('NATIVE_RESULT_RECEIVED');
        CamPerf.stage(
          result?.captureId,
          'CAMERA_OPEN_TO_RESULT',
          detail:
              'includes_preview_wait path=${result?.path} bytes=${result?.fileSizeBytes}',
        );
      } on NativeCameraException catch (error) {
        coordinator.disposeSession(reason: 'nativeError');
        await _popTransitionCoverIfNeeded(coverPushed);
        coverPushed = false;
        if (error.isCanceled) return;
        if (error.isPortraitRejected) {
          await _showPortraitDialog(isPhoto: initialType == CaptureType.photo);
          return;
        }
        await _showErrorDialog(_userFacingMessage(error));
        return;
      }

      if (result == null) {
        coordinator.disposeSession(reason: 'canceled');
        await _popTransitionCoverIfNeeded(coverPushed);
        return;
      }
      CamPerf.stage(result.captureId, 'FLUTTER_RESULT_VALIDATION_START');
      if (result.path.isEmpty || !File(result.path).existsSync()) {
        coordinator.disposeSession(reason: 'invalidResult');
        await _popTransitionCoverIfNeeded(coverPushed);
        await _showErrorDialog('Capture failed. Please try again.');
        return;
      }

      if (result.isPhoto && !result.isRearCamera) {
        coordinator.disposeSession(reason: 'notRear');
        await VisitMediaDraftStore.instance.deleteQuietly(result.path);
        await _popTransitionCoverIfNeeded(coverPushed);
        await _showErrorDialog(
          'Rear camera capture could not be verified. Please try again.',
        );
        return;
      }

      // Prefer native-oriented dimensions (fail-closed if unverifiable).
      final landscape = await _isLandscapeFast(result);
      if (!landscape) {
        coordinator.disposeSession(reason: 'portrait');
        await VisitMediaDraftStore.instance.deleteQuietly(result.path);
        await _popTransitionCoverIfNeeded(coverPushed);
        await _showPortraitDialog(isPhoto: result.isPhoto);
        return;
      }
      CamPerf.stage(result.captureId, 'FLUTTER_RESULT_VALIDATION_END');

      _log('PREVIEW_PUSH_REQUESTED');
      // Open CaptureReview immediately while the opaque cover is still the
      // current route. Get.off replaces the cover → Draft never paints.
      final captureId =
          (result.captureId != null && result.captureId!.trim().isNotEmpty)
          ? result.captureId!.trim()
          : _fallbackCaptureId(result.path);
      if (kDebugMode) {
        debugPrint(
          '[CaptureTxn] NATIVE_RESULT id=$captureId path=${result.path} '
          'exists=${File(result.path).existsSync()} '
          'bytes=${result.fileSizeBytes}',
        );
      }
      final type = result.isPhoto ? VisitMediaType.photo : VisitMediaType.video;
      final geo = coordinator.bindNativeResult(
        captureId: captureId,
        capturedAt: result.capturedAt,
        mediaType: type,
      );
      // Preserve existing Done GPS gating: require coords when shutter had none.
      final needsGps = !geo.hasCoordinates;
      CamPerf.markReviewOpen(captureId);
      await CaptureReviewScreen.open(
        filePath: result.path,
        mediaType: type,
        captureId: captureId,
        geo: geo,
        resolveLocationInBackground: needsGps,
        coordinator: coordinator,
      );
      coverPushed = false; // replaced by Get.off
      CamPerf.stage(captureId, 'REVIEW_SCREEN_VISIBLE');
      _log('PREVIEW_VISIBLE');
    } finally {
      if (coverPushed) {
        await _popTransitionCoverIfNeeded(true);
      }
      _opening = false;
    }
  }

  static String _fallbackCaptureId(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final stem = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    if (stem.startsWith('IMG_') || stem.startsWith('VID_')) {
      return stem.substring(4);
    }
    return '${DateTime.now().microsecondsSinceEpoch}_'
        '${Random().nextInt(1 << 32).toRadixString(16)}';
  }

  static Future<bool> _isLandscapeFast(NativeCameraResult result) async {
    final w = result.width;
    final h = result.height;
    if (w != null && h != null && w > 0 && h > 0) {
      // Native layers already apply EXIF / track transform before reporting size.
      return w > h;
    }
    return VisitMediaOrientation.isLandscape(
      path: result.path,
      isPhoto: result.isPhoto,
    );
  }

  /// Full-screen black route that hides Draft/Checkpoint until Preview replaces it.
  static Future<bool> _pushTransitionCover() async {
    final nav = Get.key.currentState;
    if (nav == null) return false;
    unawaited(
      Get.to<void>(
        () => const _CaptureTransitionCover(),
        routeName: '${AppRoutes.captureReview}/transition',
        opaque: true,
        fullscreenDialog: true,
        transition: Transition.noTransition,
        popGesture: false,
      ),
    );
    // Let the cover paint before the native Activity/VC appears.
    await WidgetsBinding.instance.endOfFrame;
    return true;
  }

  static Future<void> _popTransitionCoverIfNeeded(bool pushed) async {
    if (!pushed) return;
    final route = Get.currentRoute;
    if (route.contains('/transition') &&
        (Get.key.currentState?.canPop() ?? false)) {
      Get.back<void>();
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  static void _log(String marker) {
    if (!kDebugMode) return;
    final start = _openStartedMs;
    final elapsed = start == null
        ? 0
        : DateTime.now().millisecondsSinceEpoch - start;
    debugPrint('[VisitNativeCapture] $marker +${elapsed}ms');
  }

  static String _userFacingMessage(NativeCameraException error) {
    final technical = error.message.trim();
    if (technical.contains('CameraUseCaseAdapter') ||
        technical.contains('IllegalArgumentException') ||
        technical.contains('surface combination') ||
        technical.contains('androidx.camera') ||
        technical.contains('at androidx.') ||
        technical.length > 180) {
      return switch (error.code) {
        NativeCameraErrorCode.cameraInUse =>
          'Camera is in use by another app. Close it and try again.',
        NativeCameraErrorCode.permissionDenied ||
        NativeCameraErrorCode.permissionPermanentlyDenied =>
          'Camera permission is required to capture photos and videos.',
        NativeCameraErrorCode.microphonePermissionDenied =>
          'Microphone permission is required to record video.',
        NativeCameraErrorCode.noRearCamera ||
        NativeCameraErrorCode.rearCameraRequired =>
          'No rear camera is available on this device.',
        _ => 'Unable to open the camera on this device. Please try again.',
      };
    }
    return technical.isEmpty
        ? 'Unable to open the camera. Please try again.'
        : technical;
  }

  static Future<bool> _ensurePermissions({
    required bool needsMicrophone,
  }) async {
    final camera = await Permission.camera.request();
    if (!camera.isGranted) {
      await _showErrorDialog(
        camera.isPermanentlyDenied
            ? 'Camera permission is permanently denied. Enable it in Settings.'
            : 'Camera permission is required to capture photos and videos.',
      );
      return false;
    }

    if (needsMicrophone) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        await _showErrorDialog(
          'Microphone permission is required to record video.',
        );
        return false;
      }
    }
    return true;
  }

  static Future<void> _showPortraitDialog({required bool isPhoto}) async {
    final context = AppNavigator.key.currentContext ?? Get.context;
    if (context == null || !context.mounted) return;
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

  static Future<void> _showErrorDialog(String message) async {
    final context = AppNavigator.key.currentContext ?? Get.context;
    if (context == null || !context.mounted) return;
    await GlassActionDialog.show(
      context: context,
      icon: Icons.photo_camera_outlined,
      title: 'Camera',
      message: message,
      primaryLabel: 'OK',
      iconColor: const Color(0xFFE53935),
      variant: GlassActionDialogVariant.error,
      barrierDismissible: true,
      useRootNavigator: true,
    );
  }
}

/// Opaque black placeholder that masks Draft/Checkpoint during native camera.
class _CaptureTransitionCover extends StatelessWidget {
  const _CaptureTransitionCover();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(child: ColoredBox(color: Colors.black)),
    );
  }
}
