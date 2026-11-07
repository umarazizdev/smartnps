import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:video_compress/video_compress.dart';

import '../../debug/session_debug_logger.dart';

class VisitVideoCompressor {
  VisitVideoCompressor._();

  static const int maxLongSidePx = 1280;
  static const VideoQuality quality = VideoQuality.Res1280x720Quality;
  static const int frameRate = 30;

  static Future<void>? _queueTail;

  static Future<String> compressForUpload({
    required String sourcePath,
    required String targetPath,
  }) {
    return _enqueue(() async {
      final source = File(sourcePath);
      if (!await source.exists()) {
        throw StateError('Video missing for compression: $sourcePath');
      }
      if (p.equals(sourcePath, targetPath)) {
        throw StateError('Video compression source and target must differ');
      }

      final target = File(targetPath);
      final parent = target.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      if (await target.exists()) {
        await target.delete();
      }

      final info = await VideoCompress.compressVideo(
        sourcePath,
        quality: quality,
        deleteOrigin: false,
        includeAudio: true,
        frameRate: frameRate,
      );
      final compressedPath = info?.path?.trim();
      if (compressedPath == null || compressedPath.isEmpty) {
        throw StateError('Video compression returned empty path');
      }
      final compressed = File(compressedPath);
      if (!await compressed.exists() || await compressed.length() <= 0) {
        throw StateError('Video compression produced empty file: $compressedPath');
      }

      if (p.equals(compressedPath, targetPath)) {
        return targetPath;
      }

      await compressed.copy(targetPath);
      if (!p.equals(compressedPath, sourcePath)) {
        await _deleteQuietly(compressedPath);
      }

      final out = File(targetPath);
      if (!await out.exists() || await out.length() <= 0) {
        throw StateError('Video compression copy failed: $targetPath');
      }

      final inBytes = await source.length();
      final outBytes = await out.length();
      final width = info?.width;
      final height = info?.height;
      final pixels = (width == null || height == null)
          ? 'unknown'
          : '${width}x$height';
      final summary =
          'video compress in=${_kb(inBytes)} out=${_kb(outBytes)} '
          'pixels=$pixels q=720p maxLong=$maxLongSidePx';
      if (kDebugMode) {
        debugPrint('[VisitVideoCompressor] $summary');
      }
      SessionDebugLogger.instance.log(SessionDebugCategory.media, summary);

      return targetPath;
    });
  }

  static Future<String> ensureUploadReady(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('Video missing for upload prep: $sourcePath');
    }

    if (await _alreadyMeetsSpec(sourcePath)) {
      final bytes = await source.length();
      SessionDebugLogger.instance.log(
        SessionDebugCategory.media,
        'video skip compress already-ready bytes=${_kb(bytes)}',
      );
      return sourcePath;
    }

    final dir = source.parent.path;
    final base = p.basenameWithoutExtension(sourcePath);
    final targetPath = p.join(
      dir,
      '${base}_opt_${DateTime.now().microsecondsSinceEpoch}.mp4',
    );

    try {
      return await compressForUpload(
        sourcePath: sourcePath,
        targetPath: targetPath,
      );
    } catch (error) {
      await _deleteQuietly(targetPath);
      if (kDebugMode) {
        debugPrint('[VisitVideoCompressor] ensureUploadReady failed: $error');
      }
      SessionDebugLogger.instance.log(
        SessionDebugCategory.media,
        'video ensureUploadReady failed: $error',
      );
      rethrow;
    }
  }

  static Future<bool> _alreadyMeetsSpec(String path) async {
    try {
      final info = await VideoCompress.getMediaInfo(path);
      final width = info.width ?? 0;
      final height = info.height ?? 0;
      if (width <= 0 || height <= 0) return false;
      return math.max(width, height) <= maxLongSidePx;
    } catch (_) {
      return false;
    }
  }

  static Future<T> _enqueue<T>(Future<T> Function() work) {
    final previous = _queueTail;
    final gate = Completer<void>();
    _queueTail = gate.future;
    return () async {
      try {
        if (previous != null) {
          await previous;
        }
        return await work();
      } finally {
        if (!gate.isCompleted) {
          gate.complete();
        }
        if (identical(_queueTail, gate.future)) {
          _queueTail = null;
        }
      }
    }();
  }

  static String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(1)}KB';

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
