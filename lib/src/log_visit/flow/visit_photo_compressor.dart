import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;

import '../../debug/session_debug_logger.dart';

class VisitPhotoCompressor {
  VisitPhotoCompressor._();

  static const int maxWidthPx = 1920;
  static const int maxHeightPx = 1080;
  static const int jpegQuality = 85;

  static Future<String> compressForUpload({
    required String sourcePath,
    required String targetPath,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('Photo missing for compression: $sourcePath');
    }
    if (p.equals(sourcePath, targetPath)) {
      throw StateError('Photo compression source and target must differ');
    }

    final target = File(targetPath);
    final parent = target.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    if (await target.exists()) {
      await target.delete();
    }

    final inBytes = await source.length();
    final sourceSize = await _readPixelSize(source);
    var bounds = _fitInsideBox(
      width: sourceSize?.$1,
      height: sourceSize?.$2,
    );

    var result = await _compressOnce(
      sourcePath: sourcePath,
      workDir: parent.path,
      baseName: p.basenameWithoutExtension(targetPath),
      bounds: bounds,
    );

    if (result.size != null && !_sizeWithinBox(result.size!.$1, result.size!.$2)) {
      bounds = _fitInsideBox(
        width: result.size!.$1,
        height: result.size!.$2,
      );
      final refined = await _compressOnce(
        sourcePath: result.path,
        workDir: parent.path,
        baseName: '${p.basenameWithoutExtension(targetPath)}_fit',
        bounds: bounds,
      );
      if (refined.bytes <= result.bytes ||
          (refined.size != null &&
              _sizeWithinBox(refined.size!.$1, refined.size!.$2))) {
        if (refined.path != result.path) {
          await _deleteQuietly(result.path);
        }
        result = refined;
      } else {
        await _deleteQuietly(refined.path);
      }
    }

    if (!p.equals(result.path, targetPath)) {
      if (await target.exists()) {
        await target.delete();
      }
      await File(result.path).rename(targetPath);
    }

    final outBytes = await File(targetPath).length();
    final pixels =
        result.size == null ? 'unknown' : '${result.size!.$1}x${result.size!.$2}';
    final summary =
        'photo compress in=${_kb(inBytes)} out=${_kb(outBytes)} '
        'pixels=$pixels q=$jpegQuality max=${maxWidthPx}x$maxHeightPx '
        'bound=${bounds.$1}x${bounds.$2}';
    if (kDebugMode) {
      debugPrint('[VisitPhotoCompressor] $summary');
    }
    SessionDebugLogger.instance.log(SessionDebugCategory.media, summary);

    return targetPath;
  }

  static Future<({String path, int bytes, (int, int)? size})> _compressOnce({
    required String sourcePath,
    required String workDir,
    required String baseName,
    required (int, int) bounds,
  }) async {
    final attemptPath = p.join(workDir, '$baseName.tmp.jpg');
    await _deleteQuietly(attemptPath);

    final result = await FlutterImageCompress.compressAndGetFile(
      sourcePath,
      attemptPath,
      quality: jpegQuality,
      minWidth: bounds.$1,
      minHeight: bounds.$2,
      format: CompressFormat.jpeg,
      keepExif: true,
      autoCorrectionAngle: true,
    );

    final outPath = result?.path ?? attemptPath;
    final out = File(outPath);
    if (!await out.exists() || await out.length() <= 0) {
      await _deleteQuietly(outPath);
      throw StateError('Photo compression produced empty file: $outPath');
    }

    final outBytes = await out.length();
    final outSize = await _readPixelSize(out);
    return (path: outPath, bytes: outBytes, size: outSize);
  }

  static Future<String> ensureUploadReady(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('Photo missing for upload prep: $sourcePath');
    }

    if (await _alreadyMeetsSpec(source)) {
      final bytes = await source.length();
      final size = await _readPixelSize(source);
      final pixels = size == null ? 'unknown' : '${size.$1}x${size.$2}';
      SessionDebugLogger.instance.log(
        SessionDebugCategory.media,
        'photo skip compress already-ready '
        'bytes=${_kb(bytes)} pixels=$pixels',
      );
      return sourcePath;
    }

    final dir = source.parent.path;
    final base = p.basenameWithoutExtension(sourcePath);
    final targetPath = p.join(
      dir,
      '${base}_opt_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );

    try {
      final beforeBytes = await source.length();
      final compressedPath = await compressForUpload(
        sourcePath: sourcePath,
        targetPath: targetPath,
      );
      final compressed = File(compressedPath);
      final afterBytes = await compressed.length();

      if (afterBytes >= beforeBytes && await _dimensionsOk(source)) {
        await _deleteQuietly(compressedPath);
        SessionDebugLogger.instance.log(
          SessionDebugCategory.media,
          'photo keep source re-encode not smaller '
          'src=${_kb(beforeBytes)} out=${_kb(afterBytes)}',
        );
        return sourcePath;
      }

      final lower = sourcePath.toLowerCase();
      final sourceIsJpeg =
          lower.endsWith('.jpg') || lower.endsWith('.jpeg');
      if (sourceIsJpeg && compressedPath != sourcePath) {
        await source.delete();
        await compressed.rename(sourcePath);
        return sourcePath;
      }

      return compressedPath;
    } catch (error) {
      await _deleteQuietly(targetPath);
      if (kDebugMode) {
        debugPrint('[VisitPhotoCompressor] ensureUploadReady failed: $error');
      }
      SessionDebugLogger.instance.log(
        SessionDebugCategory.media,
        'photo ensureUploadReady failed: $error',
      );
      rethrow;
    }
  }

  static (int, int) _fitInsideBox({int? width, int? height}) {
    if (width == null || height == null || width <= 0 || height <= 0) {
      return (maxWidthPx, maxHeightPx);
    }
    final boxW = width >= height ? maxWidthPx : maxHeightPx;
    final boxH = width >= height ? maxHeightPx : maxWidthPx;
    if (width <= boxW && height <= boxH) {
      return (width, height);
    }
    final scale = math.min(boxW / width, boxH / height);
    return (
      math.max(1, (width * scale).round()),
      math.max(1, (height * scale).round()),
    );
  }

  static bool _sizeWithinBox(int width, int height) {
    final boxW = width >= height ? maxWidthPx : maxHeightPx;
    final boxH = width >= height ? maxHeightPx : maxWidthPx;
    return width <= boxW && height <= boxH;
  }

  static Future<bool> _alreadyMeetsSpec(File file) async {
    final lower = file.path.toLowerCase();
    if (!lower.endsWith('.jpg') && !lower.endsWith('.jpeg')) return false;
    final bytes = await file.length();
    if (bytes <= 0) return false;
    return _dimensionsOk(file);
  }

  static Future<bool> _dimensionsOk(File file) async {
    final size = await _readPixelSize(file);
    if (size == null) return false;
    return _sizeWithinBox(size.$1, size.$2);
  }

  static Future<(int, int)?> _readPixelSize(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (width <= 0 || height <= 0) return null;
      return (width, height);
    } catch (_) {
      return null;
    }
  }

  static String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(1)}KB';

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
