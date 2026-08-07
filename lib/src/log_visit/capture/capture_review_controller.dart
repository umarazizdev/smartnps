import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import '../../app/app_navigator.dart';
import '../../app/app_routes.dart';
import '../../widgets/dialogs/glass_action_dialog.dart';
import '../flow/visit_media_draft_store.dart';
import '../flow/visit_media_geo.dart';
import '../flow/visit_orientation.dart';
import '../flow/visit_video_flow_controller.dart';
import '../record/visit_video_recorder_controller.dart';
import '../record/visit_video_recorder_screen.dart';

class CaptureReviewController extends GetxController {
  CaptureReviewController({
    required this.displayPath,
    required this.mediaType,
    required VisitMediaGeo initialGeo,
    this.resolveLocationInBackground = false,
  }) : geo = initialGeo.obs,
       mediaPath = displayPath.obs;

  final String displayPath;
  final VisitMediaType mediaType;
  final bool resolveLocationInBackground;

  final Rx<VisitMediaGeo> geo;
  final RxString mediaPath;

  final isBusy = false.obs;
  final isResolvingLocation = false.obs;
  final videoReady = false.obs;
  final videoError = false.obs;
  final isPlaying = false.obs;
  final gpsIssueMessage = RxnString();

  VideoPlayerController? videoController;
  String? _durablePath;
  bool _gpsDialogVisible = false;

  bool get isPhoto => mediaType == VisitMediaType.photo;
  String get filePath => mediaPath.value;
  bool get requiresGpsForDone => resolveLocationInBackground;
  bool get isDoneBlockedByMissingGps =>
      requiresGpsForDone && !geo.value.hasCoordinates;
  String get doneBlockedMessage =>
      'Done is disabled until GPS is available. You cannot finish without GPS.';

  VisitVideoFlowController get _flow {
    return Get.isRegistered<VisitVideoFlowController>()
        ? Get.find<VisitVideoFlowController>()
        : Get.put(VisitVideoFlowController(), permanent: true);
  }

  VisitMediaItem get mediaItem {
    return _flow.findByPath(mediaPath.value) ??
        _flow.findByPath(displayPath) ??
        VisitMediaItem(
          path: mediaPath.value,
          type: mediaType,
          capturedAt: geo.value.capturedAt,
          latitude: geo.value.latitude,
          longitude: geo.value.longitude,
          accuracyMeters: geo.value.accuracyMeters,
        );
  }

  @override
  void onInit() {
    super.onInit();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (isClosed) return;
      if (_flow.findByPath(displayPath) == null &&
          _flow.findByPath(mediaPath.value) == null) {
        unawaited(
          _flow.registerCaptureDraft(
            VisitMediaItem(
              path: displayPath,
              type: mediaType,
              capturedAt: geo.value.capturedAt,
              latitude: geo.value.latitude,
              longitude: geo.value.longitude,
              accuracyMeters: geo.value.accuracyMeters,
            ),
          ),
        );
      }
      if (resolveLocationInBackground || !_storeHasDurableCopy) {
        unawaited(_persistAndResolveLocation());
      }
    });
    if (!isPhoto) {
      _initVideo();
    }
  }

  bool get _storeHasDurableCopy {
    return VisitMediaDraftStore.instance.isManagedPath(displayPath);
  }

  @override
  void onClose() {
    videoController?.removeListener(_onVideoTick);
    videoController?.dispose();
    videoController = null;
    super.onClose();
  }

  Future<void> _persistAndResolveLocation() async {
    if (isClosed) return;
    isResolvingLocation.value = true;

    final shouldResolveGps = resolveLocationInBackground;
    final geoFuture = shouldResolveGps
        ? VisitMediaGeo.captureFast()
        : Future<VisitMediaGeo>.value(geo.value);
    final persistFuture = _flow.finalizeCaptureDraft(
      previewPath: displayPath,
      type: mediaType,
    );

    try {
      unawaited(
        geoFuture.then((resolvedGeo) {
          if (isClosed || !shouldResolveGps) return;
          if (resolvedGeo.hasCoordinates) {
            geo.value = resolvedGeo;
          }
        }),
      );

      final durableItem = await persistFuture;
      if (isClosed) return;
      if (durableItem != null) {
        _durablePath = durableItem.path;
        mediaPath.value = durableItem.path;
      }

      final resolvedGeo = await geoFuture;
      if (isClosed) return;

      if (shouldResolveGps && !resolvedGeo.hasCoordinates) {
        await _refreshGpsIssueMessage();
        isResolvingLocation.value = false;
        await _showGpsFailedDialog();
        return;
      }

      if (shouldResolveGps) {
        geo.value = resolvedGeo;
      }
      if (geo.value.hasCoordinates) {
        gpsIssueMessage.value = null;
      }
      await _flow.updateCaptureGeo(mediaPath: mediaPath.value, geo: geo.value);
    } catch (_) {
      if (shouldResolveGps && !isClosed) {
        await _refreshGpsIssueMessage();
        isResolvingLocation.value = false;
        await _showGpsFailedDialog();
        return;
      }
    } finally {
      if (!isClosed) {
        isResolvingLocation.value = false;
      }
    }
  }

  Future<void> _retryGps() async {
    if (isClosed || isBusy.value) return;
    isResolvingLocation.value = true;
    try {
      final resolvedGeo = await VisitMediaGeo.captureFast();
      if (isClosed) return;
      if (!resolvedGeo.hasCoordinates) {
        await _refreshGpsIssueMessage();
        isResolvingLocation.value = false;
        await _showGpsFailedDialog();
        return;
      }
      geo.value = resolvedGeo;
      gpsIssueMessage.value = null;
      await _flow.updateCaptureGeo(
        mediaPath: mediaPath.value,
        geo: resolvedGeo,
      );
    } catch (_) {
      if (!isClosed) {
        await _refreshGpsIssueMessage();
        isResolvingLocation.value = false;
        await _showGpsFailedDialog();
        return;
      }
    } finally {
      if (!isClosed) {
        isResolvingLocation.value = false;
      }
    }
  }

  Future<void> _showGpsFailedDialog() async {
    if (isClosed || _gpsDialogVisible) return;
    _gpsDialogVisible = true;

    try {
      final failure = await _refreshGpsIssueMessage();
      final readyContext = AppNavigator.key.currentContext ?? Get.context;
      if (readyContext == null || !readyContext.mounted || isClosed) {
        await cancel();
        return;
      }

      final retry = await GlassActionDialog.show(
        context: readyContext,
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

      if (isClosed) return;
      if (retry == true) {
        await _retryGps();
      } else {
        await cancel();
      }
    } finally {
      _gpsDialogVisible = false;
    }
  }

  Future<String> _refreshGpsIssueMessage() async {
    final failure = await VisitMediaGeo.describeFailure();
    if (!isClosed) {
      gpsIssueMessage.value =
          'GPS is missing, so we cannot stamp this media with your patrol location.\n$failure';
    }
    return failure;
  }

  Future<void> _initVideo() async {
    try {
      final controller = VideoPlayerController.file(File(displayPath));
      await controller.initialize();
      await controller.setLooping(true);
      controller.addListener(_onVideoTick);
      await controller.play();
      if (isClosed) {
        controller.removeListener(_onVideoTick);
        await controller.dispose();
        return;
      }
      videoController = controller;
      isPlaying.value = controller.value.isPlaying;
      videoReady.value = true;
    } catch (_) {
      if (!isClosed) {
        videoError.value = true;
      }
    }
  }

  void _onVideoTick() {
    if (isClosed) return;
    final playing = videoController?.value.isPlaying ?? false;
    if (isPlaying.value != playing) {
      isPlaying.value = playing;
    }
  }

  void togglePlayback() {
    final controller = videoController;
    if (controller == null || !videoReady.value) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  Future<void> _cleanupPreviewFiles({required bool keepDurable}) async {
    final durable = _durablePath ?? mediaPath.value;
    if (keepDurable) {
      if (displayPath != durable) {
        await VisitMediaDraftStore.instance.deleteQuietly(displayPath);
      }
      return;
    }

    await _flow.removeByPath(durable, deleteMediaFile: true);
    if (displayPath != durable) {
      await _flow.removeByPath(displayPath, deleteMediaFile: true);
      await VisitMediaDraftStore.instance.deleteQuietly(displayPath);
    }
  }

  Future<void> cancel() async {
    if (isBusy.value) return;
    isBusy.value = true;
    await videoController?.pause();
    await _cleanupPreviewFiles(keepDurable: false);
    if (isClosed) return;
    Get.back();
  }

  Future<void> retake() async {
    if (isBusy.value) return;
    isBusy.value = true;

    try {
      await videoController?.pause();
    } catch (_) {}

    final video = videoController;
    videoController = null;
    videoReady.value = false;
    if (video != null) {
      video.removeListener(_onVideoTick);
      unawaited(video.dispose());
    }

    final cleanupFuture = _cleanupPreviewFiles(keepDurable: false);
    unawaited(VisitOrientation.enableCaptureOrientations());

    final navFuture = Get.off(
      () => const VisitVideoRecorderScreen(),
      routeName: AppRoutes.visitVideoRecorder,
      transition: Transition.fadeIn,
      duration: const Duration(milliseconds: 120),
      binding: BindingsBuilder(() {
        Get.put(VisitVideoRecorderController());
      }),
    );

    await Future.wait<void>([
      cleanupFuture,
      if (navFuture != null) navFuture else Future<void>.value(),
    ]);
  }

  Future<void> done() async {
    if (isBusy.value) return;
    if (isDoneBlockedByMissingGps) {
      await _showGpsFailedDialog();
      return;
    }
    if (isBusy.value) return;
    isBusy.value = true;
    await videoController?.pause();

    if (_durablePath == null || mediaPath.value == displayPath) {
      await _flow.finalizeCaptureDraft(
        previewPath: displayPath,
        type: mediaType,
        geo: geo.value,
      );
    } else {
      await _flow.updateCaptureGeo(mediaPath: mediaPath.value, geo: geo.value);
    }

    final durable = _durablePath ?? mediaPath.value;
    if (displayPath != durable) {
      await VisitMediaDraftStore.instance.deleteQuietly(displayPath);
    }

    if (isClosed) return;
    Get.back();
  }
}
