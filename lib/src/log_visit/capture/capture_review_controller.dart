import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import '../../native_camera/native_camera.dart';
import '../flow/cam_perf.dart';
import '../flow/capture_work_coordinator.dart';
import '../flow/visit_media_draft_store.dart';
import '../flow/visit_media_geo.dart';
import '../flow/visit_orientation.dart';
import '../flow/visit_video_flow_controller.dart';
import '../record/visit_native_capture_launcher.dart';

class CaptureReviewController extends GetxController {
  CaptureReviewController({
    required this.displayPath,
    required this.mediaType,
    required this.captureId,
    required VisitMediaGeo initialGeo,
    this.resolveLocationInBackground = false,
    CaptureWorkCoordinator? coordinator,
  }) : geo = initialGeo.obs,
       mediaPath = displayPath.obs,
       _coordinator = coordinator ?? CaptureWorkCoordinator.active;

  final String displayPath;
  final VisitMediaType mediaType;
  final String captureId;
  final bool resolveLocationInBackground;
  final CaptureWorkCoordinator? _coordinator;

  final Rx<VisitMediaGeo> geo;
  final RxString mediaPath;

  final isBusy = false.obs;
  final isResolvingLocation = false.obs;
  final videoReady = false.obs;
  final videoError = false.obs;
  final isPlaying = false.obs;
  final persistError = RxnString();

  VideoPlayerController? videoController;
  String? _durablePath;
  bool _isClosing = false;
  bool _accepted = false;
  bool _firstFrameNotified = false;
  Future<VisitMediaItem?>? _legacyPersistFuture;

  bool get isPhoto => mediaType == VisitMediaType.photo;
  String get filePath => mediaPath.value;

  VisitVideoFlowController get _flow {
    return Get.isRegistered<VisitVideoFlowController>()
        ? Get.find<VisitVideoFlowController>()
        : Get.put(VisitVideoFlowController(), permanent: true);
  }

  VisitMediaItem get mediaItem {
    return _flow.findByCaptureId(captureId) ??
        _flow.findByPath(mediaPath.value) ??
        _flow.findByPath(displayPath) ??
        VisitMediaItem(
          path: mediaPath.value,
          type: mediaType,
          captureId: captureId,
          capturedAt: geo.value.capturedAt,
          latitude: geo.value.latitude,
          longitude: geo.value.longitude,
          accuracyMeters: geo.value.accuracyMeters,
          isPendingCapture: true,
        );
  }

  @override
  void onInit() {
    super.onInit();
    if (resolveLocationInBackground && !geo.value.hasUsableGps) {
      isResolvingLocation.value = true;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (isClosed) return;
      unawaited(_registerPendingOnly());
    });
    if (!isPhoto) {
      unawaited(_initVideo());
    }
  }

  void notifyDisplayFirstFrame() {
    if (_firstFrameNotified || isClosed || _isClosing) return;
    _firstFrameNotified = true;
    final coordinator = _coordinator;
    if (coordinator != null && !coordinator.isDisposed) {
      unawaited(
        coordinator.onReviewFirstFrame(
          captureId: captureId,
          displayPath: displayPath,
          mediaType: mediaType,
          geo: geo.value,
          onWarmItem: (item) {
            if (isClosed || _isClosing || _accepted) return;
            if (item != null) {
              _durablePath = item.path;
              persistError.value = null;
            }
          },
          onWarmError: (error) {
            if (!isClosed) {
              persistError.value = 'Could not save media. Please try again.';
            }
          },
          onGeoUpdated: (resolved) {
            if (isClosed || _isClosing || _accepted) return;
            geo.value = resolved;
            isResolvingLocation.value = false;
            unawaited(
              _flow.updateCaptureGeo(
                mediaPath: mediaPath.value,
                geo: resolved,
                captureId: captureId,
              ),
            );
          },
        ),
      );
      if (resolveLocationInBackground && !geo.value.hasUsableGps) {
        isResolvingLocation.value = true;
        unawaited(_watchCoordinatorGps());
      }
      return;
    }
    _startLegacyWarmPersist();
  }

  Future<void> _watchCoordinatorGps() async {
    final coordinator = _coordinator;
    if (coordinator == null) return;
    final fut = coordinator.gpsContinueFuture;
    if (fut == null) {
      if (!isClosed) isResolvingLocation.value = false;
      return;
    }
    try {
      final resolved = await fut;
      if (isClosed || _isClosing || _accepted) return;
      if (resolved != null && resolved.hasCoordinates) {
        geo.value = resolved;
        unawaited(
          _flow.updateCaptureGeo(
            mediaPath: mediaPath.value,
            geo: resolved,
            captureId: captureId,
          ),
        );
      }
    } catch (_) {

    } finally {
      if (!isClosed) {
        isResolvingLocation.value = false;
      }
    }
  }

  Future<void> _registerPendingOnly() async {
    await _flow.registerCaptureDraft(
      VisitMediaItem(
        path: displayPath,
        type: mediaType,
        captureId: captureId,
        capturedAt: geo.value.capturedAt,
        latitude: geo.value.latitude,
        longitude: geo.value.longitude,
        accuracyMeters: geo.value.accuracyMeters,
        isPendingCapture: true,
      ),
    );
  }

  void _startLegacyWarmPersist() {
    if (_legacyPersistFuture != null) return;
    _legacyPersistFuture = _flow.finalizeCaptureDraft(
      previewPath: displayPath,
      type: mediaType,
      captureId: captureId,
      geo: geo.value,
      markAccepted: false,
    );
    unawaited(
      _legacyPersistFuture!
          .then((item) {
            if (isClosed || _isClosing || _accepted) return;
            if (item != null) {
              _durablePath = item.path;
              persistError.value = null;
            }
          })
          .catchError((Object error) {
            if (!isClosed) {
              persistError.value = 'Could not save media. Please try again.';
            }
          }),
    );
    if (resolveLocationInBackground) {
      unawaited(_resolveLocationOnly());
    }
  }

  Future<void> _resolveLocationOnly() async {
    if (isClosed) return;
    isResolvingLocation.value = true;
    try {
      final resolvedGeo = await VisitMediaGeo.captureFast();
      if (isClosed || _isClosing) return;
      if (resolvedGeo.hasCoordinates) {
        geo.value = resolvedGeo;
        await _flow.updateCaptureGeo(
          mediaPath: mediaPath.value,
          geo: resolvedGeo,
          captureId: captureId,
        );
      }
    } catch (_) {

    } finally {
      if (!isClosed) {
        isResolvingLocation.value = false;
      }
    }
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
      notifyDisplayFirstFrame();
    } catch (_) {
      if (!isClosed) {
        videoError.value = true;
        notifyDisplayFirstFrame();
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

  Future<void> _detachVideo() async {
    final video = videoController;
    videoController = null;
    videoReady.value = false;
    isPlaying.value = false;
    if (video == null) return;
    try {
      video.removeListener(_onVideoTick);
    } catch (_) {}
    try {
      await video.pause();
    } catch (_) {}
    unawaited(
      Future<void>(() async {
        try {
          await video.dispose();
        } catch (_) {}
      }),
    );
  }

  Future<void> cancel() async {
    if (_accepted) return;
    if (_isClosing) return;
    _isClosing = true;
    isBusy.value = true;
    isResolvingLocation.value = false;

    _coordinator?.cancelCapture(reason: 'close');
    await _detachVideo();

    if (!isClosed) {
      Get.back();
    }

    _coordinator?.disposeSession(reason: 'close');

    unawaited(
      _flow.rollbackCaptureDraft(
        captureId: captureId,
        previewPath: displayPath,
        durablePath: _durablePath ?? _coordinator?.durablePath,
      ),
    );
  }

  Future<void> retake() async {
    if (_isClosing || _accepted || isBusy.value) return;
    _isClosing = true;
    isBusy.value = true;

    final initialType = isPhoto ? CaptureType.photo : CaptureType.video;

    _coordinator?.prepareRetake();
    await _detachVideo();
    await _flow.rollbackCaptureDraft(
      captureId: captureId,
      previewPath: displayPath,
      durablePath: _durablePath ?? _coordinator?.durablePath,
    );
    unawaited(VisitOrientation.enableCaptureOrientations());
    if (!isClosed) {
      Get.back();
    }
    await VisitNativeCaptureLauncher.reopenForRetake(initialType: initialType);
  }

  Future<void> done() async {
    if (_isClosing || _accepted) return;
    if (isBusy.value) return;
    CamPerf.markUsePhoto(captureId);
    CamPerf.stage(
      captureId,
      'ACCEPT_HANDLER_ENTER',
      detail: 'coordinator=${_coordinator != null}',
      usePhotoClock: true,
    );
    isBusy.value = true;

    try {
      await videoController?.pause();
    } catch (_) {}

    try {
      if (!_firstFrameNotified) {
        notifyDisplayFirstFrame();
      }

      VisitMediaItem? durable;
      var acceptGeo = geo.value;

      final coordinator = _coordinator;
      if (coordinator != null && !coordinator.isDisposed) {

        final waited = await coordinator.waitForAcceptRequirements(
          gpsRequired: resolveLocationInBackground,
          currentGeo: geo.value,
        );
        durable = waited.durable;
        acceptGeo = waited.geo;
        if (acceptGeo.hasCoordinates &&
            (!geo.value.hasCoordinates ||
                acceptGeo.accuracyMeters != geo.value.accuracyMeters)) {
          geo.value = acceptGeo;
        }
      } else {
        if (_legacyPersistFuture == null) {
          _startLegacyWarmPersist();
        }
        final warm = _legacyPersistFuture;
        if (warm != null) {
          CamPerf.stage(
            captureId,
            'AWAIT_WARM_PERSIST_START',
            usePhotoClock: true,
          );
          durable = await warm;
          CamPerf.stage(
            captureId,
            'AWAIT_WARM_PERSIST_END',
            usePhotoClock: true,
          );
        }
      }

      if (durable != null &&
          VisitMediaDraftStore.instance.isManagedPath(durable.path)) {
        final accepted = await _flow.acceptWarmCapture(
          captureId: captureId,
          previewPath: displayPath,
          geo: acceptGeo,
          assumeFileReady: true,
          applyRx: false,
        );
        durable = accepted ?? durable;
      } else {
        durable = await _flow.finalizeCaptureDraft(
          previewPath: displayPath,
          type: mediaType,
          captureId: captureId,
          geo: acceptGeo,
          markAccepted: true,
        );
      }
      if (durable == null) {
        persistError.value = 'Could not save media. Please try again.';
        isBusy.value = false;
        return;
      }
      _durablePath = durable.path;
      _accepted = true;

      if (isClosed) return;
      CamPerf.stage(captureId, 'REVIEW_POP_START', usePhotoClock: true);
      Get.back();
      CamPerf.stage(captureId, 'REVIEW_POP_END', usePhotoClock: true);
      _flow.applyAcceptedMediaItem(durable);
      if (displayPath != durable.path) {
        _flow.removeGhostPreviewPath(
          captureId: captureId,
          previewPath: displayPath,
          keepPath: durable.path,
        );
      }
      CamPerf.markDraftVisible(captureId);
      CamPerf.stage(captureId, 'USE_PHOTO_COMPLETE', usePhotoClock: true);

      coordinator?.disposeSession(reason: 'accepted');

      if (displayPath != durable.path) {
        unawaited(() async {
          CamPerf.stage(
            captureId,
            'POST_POP_CLEANUP_START',
            usePhotoClock: true,
          );
          CamPerf.stage(captureId, 'TEMP_DELETE_START', usePhotoClock: true);
          await VisitMediaDraftStore.instance.deleteQuietly(displayPath);
          CamPerf.stage(captureId, 'TEMP_DELETE_END', usePhotoClock: true);
          CamPerf.stage(captureId, 'POST_POP_CLEANUP_END', usePhotoClock: true);
        }());
      }
    } catch (error) {
      persistError.value = 'Could not save media. Please try again.';
      isBusy.value = false;
    }
  }
}
