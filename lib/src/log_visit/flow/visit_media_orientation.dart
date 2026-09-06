import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Display-oriented size of a captured photo or video.
class VisitMediaSize {
  const VisitMediaSize({required this.width, required this.height});

  final int width;
  final int height;

  bool get isLandscape => width > height;
  bool get isPortrait => height > width;
  bool get isSquare => width == height;
}

class VisitMediaOrientation {
  VisitMediaOrientation._();

  /// Returns display size after codec / player rotation metadata is applied.
  static Future<VisitMediaSize?> readSize({
    required String path,
    required bool isPhoto,
  }) async {
    final file = File(path);
    if (!file.existsSync()) return null;
    return isPhoto ? _readPhotoSize(file) : _readVideoSize(file);
  }

  static Future<bool> isLandscape({
    required String path,
    required bool isPhoto,
  }) async {
    final size = await readSize(path: path, isPhoto: isPhoto);
    // FAIL CLOSED: unverifiable orientation must be rejected for evidence.
    if (size == null) return false;
    return size.isLandscape;
  }

  static Future<VisitMediaSize?> _readPhotoSize(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (width <= 0 || height <= 0) return null;
      return VisitMediaSize(width: width, height: height);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VisitMediaOrientation] photo size failed: $e');
      }
      return null;
    }
  }

  static Future<VisitMediaSize?> _readVideoSize(File file) async {
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(file);
      await controller.initialize();
      final size = controller.value.size;
      final width = size.width.round();
      final height = size.height.round();
      if (width <= 0 || height <= 0) return null;
      return VisitMediaSize(width: width, height: height);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VisitMediaOrientation] video size failed: $e');
      }
      return null;
    } finally {
      await controller?.dispose();
    }
  }
}
