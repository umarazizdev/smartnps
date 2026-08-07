import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

class VisitVideoPlayerController extends GetxController {
  final String videoPath;

  VisitVideoPlayerController({required this.videoPath});
  final volume = 0.25.obs;
  final isMuted = false.obs;
  final isLoading = true.obs;
  final errorMessage = Rxn<String>();
  final isPlaying = false.obs;
  final positionMs = 0.obs;
  final durationMs = 0.obs;
  final isSeeking = false.obs;
  VideoPlayerController? videoController;
  final wasPlayingBeforeSeek = false.obs;
  final showControls = true.obs;
  Orientation? _lastOrientation;

  Timer? _hideControlsTimer;

  bool get isPlayerReady {
    final c = videoController;
    return c != null && c.value.isInitialized;
  }

  void handleOrientationChange(Orientation orientation) {
    if (_lastOrientation != null && _lastOrientation != orientation) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (isClosed) return;
        revealControls(autoHide: isPlaying.value);
      });
    }
    _lastOrientation = orientation;
  }

  @override
  void onInit() {
    super.onInit();
    _initPlayer();
  }

  @override
  void onClose() {
    _hideControlsTimer?.cancel();
    videoController?.removeListener(_videoListener);
    videoController?.dispose();
    super.onClose();
  }

  void _videoListener() {
    final controller = videoController;
    if (isClosed || controller == null) return;

    final value = controller.value;
    final wasPlaying = isPlaying.value;

    isPlaying.value = value.isPlaying;
    positionMs.value = value.position.inMilliseconds;
    durationMs.value = value.duration.inMilliseconds;

    if (value.duration.inMilliseconds > 0 &&
        value.position.inMilliseconds >= value.duration.inMilliseconds &&
        value.isPlaying) {
      controller.pause();
      revealControls(autoHide: false);
      return;
    }

    if (!wasPlaying && value.isPlaying) {
      scheduleHideControls();
    } else if (wasPlaying && !value.isPlaying) {
      revealControls(autoHide: false);
    }
  }

  void revealControls({bool autoHide = true}) {
    if (isClosed) return;
    showControls.value = true;
    if (autoHide && isPlaying.value) {
      scheduleHideControls();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void scheduleHideControls({
    Duration delay = const Duration(milliseconds: 800),
  }) {
    _hideControlsTimer?.cancel();
    if (isClosed || !isPlaying.value) return;
    _hideControlsTimer = Timer(delay, () {
      if (isClosed) return;
      if (isPlaying.value && !isSeeking.value) {
        showControls.value = false;
      }
    });
  }

  void onScreenTap() {
    if (!showControls.value) {
      revealControls(autoHide: true);
      return;
    }
    unawaited(togglePlayPause());
  }

  Future<void> _initPlayer() async {
    VideoPlayerController? controller;
    String? error;

    if (controller != null && controller.value.isInitialized) {
      await controller.setVolume(volume.value);

      isPlaying.value = controller.value.isPlaying;
      positionMs.value = controller.value.position.inMilliseconds;
      durationMs.value = controller.value.duration.inMilliseconds;
    }
    try {
      controller = VideoPlayerController.file(File(videoPath));
      await controller.initialize().timeout(const Duration(seconds: 8));
      controller.addListener(_videoListener);
      await controller.setLooping(false);
      await controller.play();
    } on PlatformException catch (e) {
      if (e.code == 'channel-error' || (e.message ?? '').contains('channel')) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        try {
          await controller?.dispose();
          controller = VideoPlayerController.file(File(videoPath));
          await controller.initialize().timeout(const Duration(seconds: 8));
          controller.addListener(_videoListener);
          await controller.setLooping(false);
          await controller.play();
        } catch (_) {
          error =
              'Unable to play video on this session. Please close the app and reopen it once.';
        }
      } else {
        error = 'Unable to load this video.';
      }
    } on TimeoutException {
      error = 'Video is taking too long to load. Please try again.';
    } catch (_) {
      error = 'Unable to load this video.';
    }

    if (isClosed) {
      await controller?.dispose();
      return;
    }

    videoController = controller;
    errorMessage.value = error;
    isLoading.value = false;

    if (controller != null && controller.value.isInitialized) {
      isPlaying.value = controller.value.isPlaying;
      positionMs.value = controller.value.position.inMilliseconds;
      durationMs.value = controller.value.duration.inMilliseconds;
      if (controller.value.isPlaying) {
        scheduleHideControls();
      }
    }

    if (error != null) {
      Get.snackbar(
        'Video preview error',
        error,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(12),
      );
    }
  }

  Future<void> toggleMute() async {
    final controller = videoController;
    if (controller == null || !controller.value.isInitialized) return;

    if (isMuted.value || volume.value == 0) {
      final restoreVolume = volume.value == 0 ? 1.0 : volume.value;
      await controller.setVolume(restoreVolume);
      volume.value = restoreVolume;
      isMuted.value = false;
    } else {
      await controller.setVolume(0);
      isMuted.value = true;
    }
  }

  Future<void> setPlayerVolume(double newVolume) async {
    final controller = videoController;
    if (controller == null || !controller.value.isInitialized) return;

    final safeVolume = newVolume.clamp(0.0, 1.0);
    await controller.setVolume(safeVolume);

    volume.value = safeVolume;
    isMuted.value = safeVolume == 0;
  }

  Future<void> togglePlayPause() async {
    final controller = videoController;
    if (controller == null || !controller.value.isInitialized) return;

    final value = controller.value;
    final duration = value.duration.inMilliseconds;
    final position = value.position.inMilliseconds;

    final isAtEnd = duration > 0 && position >= duration - 200;

    if (value.isPlaying) {
      await controller.pause();
      revealControls(autoHide: false);
    } else {
      if (isAtEnd) {
        await controller.seekTo(Duration.zero);
        positionMs.value = 0;
      }
      await controller.play();
      revealControls(autoHide: true);
    }

    final updated = controller.value;
    isPlaying.value = updated.isPlaying;
    positionMs.value = updated.position.inMilliseconds;
    durationMs.value = updated.duration.inMilliseconds;
  }

  Future<void> seekTo(int milliseconds) async {
    final controller = videoController;
    if (controller == null || !controller.value.isInitialized) return;

    final duration = controller.value.duration.inMilliseconds;
    final safeMs = milliseconds.clamp(0, duration <= 0 ? 0 : duration);

    await controller.seekTo(Duration(milliseconds: safeMs));
    positionMs.value = safeMs;
    revealControls(autoHide: isPlaying.value);
  }
}
