import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;

import '../log_visit/flow/visit_video_flow_controller.dart';
import 'api_client.dart';
import 'api_urls.dart';

class VisitUploadResult {
  const VisitUploadResult({
    required this.success,
    this.visitId,
    this.clientDraftId,
    this.itemsSaved,
    this.message,
    this.statusCode,
    this.errors,
  });

  final bool success;
  final int? visitId;
  final String? clientDraftId;
  final int? itemsSaved;
  final String? message;
  final int? statusCode;
  final Map<String, dynamic>? errors;

  String get displayMessage {
    final text = message?.trim();
    if (text != null && text.isNotEmpty) return text;
    if (success) return 'Patrol round report uploaded successfully';
    return 'Upload failed';
  }
}

class VisitUploadApi {
  VisitUploadApi._();

  static final VisitUploadApi instance = VisitUploadApi._();

  Future<VisitUploadResult> uploadVisit({
    required Map<String, dynamic> meta,
    required List<VisitMediaItem> items,
    String? batchVoicePath,
    String? generalVoicePath,
  }) async {
    if (items.isEmpty) {
      const result = VisitUploadResult(
        success: false,
        message: 'Please capture at least one photo or video before upload.',
      );
      _logResult(result);
      return result;
    }

    ApiClient.instance.ensureAuthInterceptorInstalled();

    final form = FormData();
    form.fields.add(MapEntry('meta', jsonEncode(meta)));

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final mediaFile = File(item.path);
      if (!await mediaFile.exists()) {
        final result = VisitUploadResult(
          success: false,
          message: 'Media file missing for item $i.',
        );
        _logResult(result);
        return result;
      }

      final mediaName = _mediaFileName(item, i);
      await _logMediaQuality(item: item, index: i, file: mediaFile);
      form.files.add(
        MapEntry(
          'media[$i]',
          await MultipartFile.fromFile(
            item.path,
            filename: mediaName,
            contentType: _mediaContentType(item),
          ),
        ),
      );

      final hasVoice = item.hasVoiceNote;
      final metaItem = _metaItemAt(meta, i);
      final metaWantsVoice = metaItem?['has_voice_note'] == true;
      if (hasVoice || metaWantsVoice) {
        final voicePath = item.voiceNotePath?.trim();
        if (voicePath == null || voicePath.isEmpty) {
          final result = VisitUploadResult(
            success: false,
            message: 'Voice note missing for client_index $i.',
          );
          _logResult(result);
          return result;
        }
        final voiceFile = File(voicePath);
        if (!await voiceFile.exists()) {
          final result = VisitUploadResult(
            success: false,
            message: 'Voice note file missing for client_index $i.',
          );
          _logResult(result);
          return result;
        }
        form.files.add(
          MapEntry(
            'voice[$i]',
            await MultipartFile.fromFile(
              voicePath,
              filename: _voiceFileName(voicePath, i),
              contentType: _voiceContentType(voicePath),
            ),
          ),
        );
      }
    }

    final batchVoiceResult = await _attachBatchVoice(
      form: form,
      meta: meta,
      batchVoicePath: batchVoicePath,
    );
    if (batchVoiceResult != null) {
      _logResult(batchVoiceResult);
      return batchVoiceResult;
    }

    final generalVoiceResult = await _attachGeneralVoice(
      form: form,
      meta: meta,
      generalVoicePath: generalVoicePath,
    );
    if (generalVoiceResult != null) {
      _logResult(generalVoiceResult);
      return generalVoiceResult;
    }

    if (kDebugMode) {
      debugPrint(
        '[VisitUploadApi] POST ${ApiUrls.visitsUploadUrl} '
        'items=${items.length} metaKeys=${meta.keys.toList()}',
      );
    }

    try {
      final response = await ApiClient.instance.dio.post<dynamic>(
        ApiUrls.visitsUploadUrl,
        data: form,
        options: Options(
          headers: const {'Accept': 'application/json'},
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(minutes: 10),
          receiveTimeout: const Duration(minutes: 3),
          validateStatus: (status) => status != null && status < 600,
        ),
      );

      final result = _parseResponse(response);
      _logResult(result, responseBody: response.data);
      return result;
    } on DioException catch (error) {
      ApiClient.logHttpError(
        error.requestOptions.method,
        error.requestOptions.uri,
        error.response?.statusCode ?? 0,
        error.message ?? error.type.name,
      );
      if (kDebugMode) {
        debugPrint(
          '[VisitUploadApi] ERROR dioType=${error.type.name} '
          'status=${error.response?.statusCode} '
          'message=${error.message} '
          'body=${error.response?.data}',
        );
      }
      final parsed = error.response == null
          ? null
          : _parseResponse(error.response!);
      if (parsed != null) {
        _logResult(parsed, responseBody: error.response?.data);
        return parsed;
      }
      final fallback = VisitUploadResult(
        success: false,
        statusCode: error.response?.statusCode,
        message: error.message ?? 'Network error while uploading visit.',
      );
      _logResult(fallback, responseBody: error.response?.data);
      return fallback;
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('[VisitUploadApi] ERROR unexpected=$error');
        if (kDebugMode) {
          debugPrint('[VisitUploadApi] stack=$stack');
        }
      }
      final fallback = VisitUploadResult(
        success: false,
        message: error.toString(),
      );
      _logResult(fallback);
      return fallback;
    }
  }

  void _logResult(VisitUploadResult result, {dynamic responseBody}) {
    if (!kDebugMode) return;
    if (result.success) {
      if (kDebugMode) {
        debugPrint(
          '[VisitUploadApi] SUCCESS status=${result.statusCode} '
          'visitId=${result.visitId} clientDraftId=${result.clientDraftId} '
          'itemsSaved=${result.itemsSaved} message=${result.displayMessage}',
        );
      }
    } else {
      if (kDebugMode) {
        debugPrint(
          '[VisitUploadApi] FAIL status=${result.statusCode} '
          'message=${result.displayMessage} errors=${result.errors} '
          'body=$responseBody',
        );
      }
    }
  }

  Future<void> _logMediaQuality({
    required VisitMediaItem item,
    required int index,
    required File file,
  }) async {
    if (!kDebugMode) return;

    final bytes = await file.length();
    final kb = (bytes / 1024).toStringAsFixed(1);
    final name = p.basename(item.path);

    if (item.isVideo) {
      if (kDebugMode) {
        debugPrint(
          '[VisitUploadApi] media[$index] video '
          'bytes=$bytes (${kb}KB) file=$name',
        );
      }
      return;
    }

    final size = await _photoPixelSize(file);
    final pixels = size == null ? 'unknown' : '${size.$1}x${size.$2}';
    final warn = size != null && (size.$1 < 1600 || size.$2 < 900)
        ? ' LOW_RES'
        : '';
    if (kDebugMode) {
      debugPrint(
        '[VisitUploadApi] media[$index] photo '
        'pixels=$pixels bytes=$bytes (${kb}KB) file=$name$warn',
      );
    }
  }

  Future<(int, int)?> _photoPixelSize(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      return (width, height);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[VisitUploadApi] photo dimension read failed: $error');
      }
      return null;
    }
  }

  Future<VisitUploadResult?> _attachBatchVoice({
    required FormData form,
    required Map<String, dynamic> meta,
    required String? batchVoicePath,
  }) async {
    final attentionNeeded = meta['attention_needed'] ?? meta['batch_note'];
    if (attentionNeeded is! Map) return null;

    final neededRaw = attentionNeeded['needed']
        ?.toString()
        .trim()
        .toLowerCase();
    final neededYes =
        neededRaw == 'yes' ||
        neededRaw == 'true' ||
        attentionNeeded['needed'] == true;
    final wantsVoice = neededYes && attentionNeeded['has_voice_note'] == true;
    if (!wantsVoice) return null;

    final path = batchVoicePath?.trim();
    if (path == null || path.isEmpty) {
      return const VisitUploadResult(
        success: false,
        message: 'Attention needed voice note missing.',
      );
    }
    final voiceFile = File(path);
    if (!await voiceFile.exists()) {
      return const VisitUploadResult(
        success: false,
        message: 'Attention needed voice note file missing.',
      );
    }

    form.files.add(
      MapEntry(
        'attention_voice',
        await MultipartFile.fromFile(
          path,
          filename: 'attention_voice${_extension(path) ?? '.m4a'}',
          contentType: _voiceContentType(path),
        ),
      ),
    );
    return null;
  }

  Future<VisitUploadResult?> _attachGeneralVoice({
    required FormData form,
    required Map<String, dynamic> meta,
    required String? generalVoicePath,
  }) async {
    final generalNote = meta['general_note'];
    if (generalNote is! Map) return null;

    final enabledRaw = generalNote['enabled']?.toString().trim().toLowerCase();
    final enabledYes =
        enabledRaw == 'yes' ||
        enabledRaw == 'true' ||
        generalNote['enabled'] == true;
    final wantsVoice = enabledYes && generalNote['has_voice_note'] == true;
    if (!wantsVoice) return null;

    final path = generalVoicePath?.trim();
    if (path == null || path.isEmpty) {
      return const VisitUploadResult(
        success: false,
        message: 'General note voice missing.',
      );
    }
    final voiceFile = File(path);
    if (!await voiceFile.exists()) {
      return const VisitUploadResult(
        success: false,
        message: 'General note voice file missing.',
      );
    }

    form.files.add(
      MapEntry(
        'general_voice',
        await MultipartFile.fromFile(
          path,
          filename: 'general_voice${_extension(path) ?? '.m4a'}',
          contentType: _voiceContentType(path),
        ),
      ),
    );
    return null;
  }

  Map<String, dynamic>? _metaItemAt(Map<String, dynamic> meta, int index) {
    final items = meta['items'];
    if (items is! List || index < 0 || index >= items.length) return null;
    final item = items[index];
    if (item is Map<String, dynamic>) return item;
    if (item is Map) return Map<String, dynamic>.from(item);
    return null;
  }

  String _mediaFileName(VisitMediaItem item, int index) {
    final ext = _extension(item.path) ?? (item.isVideo ? '.mp4' : '.jpg');
    return 'media_$index$ext';
  }

  String _voiceFileName(String path, int index) {
    final ext = _extension(path) ?? '.m4a';
    return 'voice_$index$ext';
  }

  String? _extension(String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext.isEmpty || ext == '.') return null;
    return ext;
  }

  MediaType _mediaContentType(VisitMediaItem item) {
    final ext = (_extension(item.path) ?? '').replaceFirst('.', '');
    if (item.isVideo) {
      return switch (ext) {
        'mov' => MediaType('video', 'quicktime'),
        'webm' => MediaType('video', 'webm'),
        _ => MediaType('video', 'mp4'),
      };
    }
    return switch (ext) {
      'png' => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
      'heic' => MediaType('image', 'heic'),
      _ => MediaType('image', 'jpeg'),
    };
  }

  MediaType _voiceContentType(String path) {
    final ext = (_extension(path) ?? '').replaceFirst('.', '');
    return switch (ext) {
      'mp3' => MediaType('audio', 'mpeg'),
      'wav' => MediaType('audio', 'wav'),
      'aac' => MediaType('audio', 'aac'),
      _ => MediaType('audio', 'mp4'),
    };
  }

  VisitUploadResult _parseResponse(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    final data = response.data;
    Map<String, dynamic>? map;
    if (data is Map<String, dynamic>) {
      map = data;
    } else if (data is Map) {
      map = Map<String, dynamic>.from(data);
    } else if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) map = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }

    final successFlag = map?['success'];
    final ok =
        successFlag == true ||
        (successFlag == null && status >= 200 && status < 300);

    Map<String, dynamic>? errors;
    final rawErrors = map?['errors'];
    if (rawErrors is Map) {
      errors = Map<String, dynamic>.from(rawErrors);
    }

    return VisitUploadResult(
      success: ok,
      statusCode: status,
      visitId: _asInt(map?['visit_id'] ?? map?['visitId']),
      clientDraftId:
          map?['client_draft_id']?.toString() ??
          map?['clientDraftId']?.toString(),
      itemsSaved: _asInt(map?['items_saved'] ?? map?['itemsSaved']),
      message: map?['message']?.toString(),
      errors: errors,
    );
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
