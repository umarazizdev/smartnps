import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/app_navigator.dart';
import '../../app/app_routes.dart';
import '../../native_camera/native_camera.dart';
import '../../utilities/permission_settings_helper.dart';
import '../../widgets/dialogs/glass_action_dialog.dart';
import '../capture/capture_review_screen.dart';
import '../capture/onboarding/capture_onboarding_catalog.dart';
import '../capture/onboarding/capture_onboarding_store.dart';
import '../flow/cam_perf.dart';
import '../flow/capture_work_coordinator.dart';
import '../flow/visit_media_draft_store.dart';
import '../flow/visit_media_orientation.dart';
import '../flow/visit_orientation.dart';
import '../flow/visit_video_flow_controller.dart';

class VisitNativeCaptureLauncher {
  VisitNativeCaptureLauncher._();

  static bool _opening = false;
  static Completer<void>? _openCompletion;
  static CaptureType _lastCaptureType = CaptureType.photo;

  static Future<void> reopenForRetake({
    CaptureType initialType = CaptureType.photo,
  }) async {
    final activeOpen = _openCompletion;
    if (activeOpen != null && !activeOpen.isCompleted) {
      await activeOpen.future;
    }
    await open(initialType: initialType);
  }

  static Future<void> open({
    CaptureType? initialType,
    bool allowModeSwitch = true,
  }) async {
    if (_opening) return;
    final requestedType = initialType ?? _lastCaptureType;
    _opening = true;
    final completion = Completer<void>();
    _openCompletion = completion;
    _log('CAMERA_REQUEST');

    var coverPushed = false;
    try {
      await VisitOrientation.enableCaptureOrientations();
      _log('ORIENTATION_UNLOCKED');

      final permitted = await _ensurePermissions(
        needsMicrophone: allowModeSwitch || requestedType == CaptureType.video,
      );
      if (!permitted) return;
      _log('PERMISSIONS_OK');

      final expectedType = requestedType == CaptureType.photo
          ? VisitMediaType.photo
          : VisitMediaType.video;
      final coordinator = CaptureWorkCoordinator.beginSession(
        expectedType: expectedType,
      );

      unawaited(NativeCamera.getCapabilities(type: requestedType));

      final showOnboarding = await CaptureOnboardingStore.instance.shouldShow();
      final onboardingSteps = showOnboarding
          ? CaptureOnboardingCatalog.forCurrentPlatform()
          : const <CaptureOnboardingStep>[];

      coverPushed = await _pushTransitionCover();
      _log('TRANSITION_COVER_${coverPushed ? "SHOWN" : "SKIPPED"}');

      final NativeCameraResult? result;
      try {
        _log('NATIVE_OPEN_INVOKE');
        CamPerf.resetCameraOpenFlow();
        CamPerf.log(null, 'FLUTTER_NATIVE_CAMERA_OPEN_START');
        result = await NativeCamera.open(
          type: requestedType,
          allowModeSwitch: allowModeSwitch,
          landscapeOnly: true,
          rearCameraOnly: true,
          quality: CaptureQuality.maximum,
          preferHeic: false,
          showOnboarding: showOnboarding,
          onboardingSteps: onboardingSteps,
        );
        if (NativeCamera.takeLastOnboardingCompleted()) {
          await CaptureOnboardingStore.instance.markCompleted();
        }
        _log('NATIVE_RESULT_RECEIVED');
        CamPerf.stage(
          result?.captureId,
          'CAMERA_OPEN_TO_RESULT',
          detail:
              'includes_preview_wait path=${result?.path} bytes=${result?.fileSizeBytes}',
        );
      } on NativeCameraException catch (error) {
        if (NativeCamera.takeLastOnboardingCompleted()) {
          await CaptureOnboardingStore.instance.markCompleted();
        }
        coordinator.disposeSession(reason: 'nativeError');
        await _popTransitionCoverIfNeeded(coverPushed);
        coverPushed = false;
        if (error.isCanceled) return;
        if (error.isPortraitRejected) {
          await _showPortraitDialog(
            isPhoto: requestedType == CaptureType.photo,
          );
          return;
        }
        if (error.isPermissionDenied) {
          await _showPermissionDeniedDialog(
            title: error.code == NativeCameraErrorCode.microphonePermissionDenied
                ? 'Microphone permission required'
                : 'Camera permission required',
            message: _userFacingMessage(error),
            icon: error.code == NativeCameraErrorCode.microphonePermissionDenied
                ? Icons.mic_off_outlined
                : Icons.photo_camera_outlined,
          );
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
      _lastCaptureType = result.type;
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
      final captureId =
          (result.captureId != null && result.captureId!.trim().isNotEmpty)
          ? result.captureId!.trim()
          : _fallbackCaptureId(result.path);
      final type = result.isPhoto ? VisitMediaType.photo : VisitMediaType.video;
      final geo = coordinator.bindNativeResult(
        captureId: captureId,
        capturedAt: result.capturedAt,
        mediaType: type,
      );
      final needsGps = !geo.hasUsableGps;
      CamPerf.markReviewOpen(captureId);
      await CaptureReviewScreen.open(
        filePath: result.path,
        mediaType: type,
        captureId: captureId,
        geo: geo,
        resolveLocationInBackground: needsGps,
        coordinator: coordinator,
      );
      coverPushed = false;
      CamPerf.stage(captureId, 'REVIEW_SCREEN_VISIBLE');
      _log('PREVIEW_VISIBLE');
    } finally {
      if (coverPushed) {
        await _popTransitionCoverIfNeeded(true);
      }
      _opening = false;
      if (!completion.isCompleted) {
        completion.complete();
      }
      if (identical(_openCompletion, completion)) {
        _openCompletion = null;
      }
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
      return w > h;
    }
    return VisitMediaOrientation.isLandscape(
      path: result.path,
      isPhoto: result.isPhoto,
    );
  }

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

  static void _log(String marker) {}

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
    final permissions = <Permission>[
      Permission.camera,
      if (needsMicrophone) Permission.microphone,
    ];

    Map<Permission, PermissionStatus> statuses;
    try {
      final pending = <Permission>[];
      for (final permission in permissions) {
        final status = await permission.status;
        if (!status.isGranted) {
          pending.add(permission);
        }
      }
      if (pending.isEmpty) {
        return true;
      }
      statuses = await pending.request();
    } on Exception catch (error) {
      final message = error.toString();
      if (message.contains('ALREADY_REQUESTING_PERMISSIONS')) {

        await Future<void>.delayed(const Duration(milliseconds: 400));
        statuses = {
          for (final permission in permissions)
            permission: await permission.status,
        };
      } else {
        rethrow;
      }
    }

    final camera = statuses[Permission.camera] ?? await Permission.camera.status;
    if (!camera.isGranted) {
      await _showPermissionDeniedDialog(
        title: 'Camera permission required',
        message: camera.isPermanentlyDenied
            ? 'Camera permission is permanently denied. Enable it in Settings '
                'to capture photos and videos.'
            : 'Camera permission is required to capture photos and videos.',
        icon: Icons.photo_camera_outlined,
      );
      return false;
    }

    if (needsMicrophone) {
      final mic =
          statuses[Permission.microphone] ?? await Permission.microphone.status;
      if (!mic.isGranted) {
        await _showPermissionDeniedDialog(
          title: 'Microphone permission required',
          message: mic.isPermanentlyDenied
              ? 'Microphone permission is permanently denied. Enable it in '
                  'Settings to record video.'
              : 'Microphone permission is required to record video.',
          icon: Icons.mic_off_outlined,
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

  static Future<void> _showPermissionDeniedDialog({
    required String title,
    required String message,
    required IconData icon,
  }) async {
    final context = AppNavigator.key.currentContext ?? Get.context;
    if (context == null || !context.mounted) return;
    final openSettings = await GlassActionDialog.show(
      context: context,
      icon: icon,
      title: title,
      message: message,
      primaryLabel: 'Open Settings',
      secondaryLabel: 'Cancel',
      showCloseButton: true,
      iconColor: const Color(0xFFE53935),
      variant: GlassActionDialogVariant.error,
      barrierDismissible: true,
      useRootNavigator: true,
    );
    if (openSettings == true) {
      await PermissionSettingsHelper.launchAppSettings();
    }
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

class _CaptureTransitionCover extends StatelessWidget {
  const _CaptureTransitionCover();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: CircularProgressIndicator(
              color: Colors.white70,
              strokeWidth: 2.5,
            ),
          ),
        ),
      ),
    );
  }
}
