import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;

import '../debug/session_debug_logger.dart';
import '../log_visit/flow/visit_flow_copy.dart';
import '../log_visit/flow/visit_flow_kind.dart';
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
    this.isNetworkFailure = false,
    this.flowKind,
  });

  final bool success;
  final int? visitId;
  final String? clientDraftId;
  final int? itemsSaved;
  final String? message;
  final int? statusCode;
  final Map<String, dynamic>? errors;

  final bool isNetworkFailure;
  final VisitFlowKind? flowKind;

  String get displayMessage {
    if (success) {
      final kind = flowKind;
      if (kind != null) return VisitFlowCopy(kind: kind).successMessage;
      final text = message?.trim();
      if (text != null && text.isNotEmpty) return text;
      return const VisitFlowCopy().successMessage;
    }
    final text = message?.trim();
    if (text != null && text.isNotEmpty) return text;
    return 'Upload failed';
  }

  bool get isClientDraftReuseError {
    if (success) return false;
    final map = errors;
    if (map != null) {
      for (final entry in map.entries) {
        final key = entry.key.toString().toLowerCase();
        if (key != 'client_draft_id' && key != 'clientdraftid') continue;
        for (final message in _errorMessages(entry.value)) {
          if (_looksLikeDraftReuseMessage(message)) return true;
        }
      }
    }
    return _looksLikeDraftReuseMessage(displayMessage);
  }

  static List<String> _errorMessages(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return const <String>[];
    return <String>[text];
  }

  static bool _looksLikeDraftReuseMessage(String? raw) {
    final text = raw?.trim().toLowerCase() ?? '';
    if (text.isEmpty) return false;
    return text.contains('already used for a different visit') ||
        (text.contains('client_draft_id') && text.contains('already used'));
  }

  static bool isNetworkDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.unknown:
        final cause = error.error;
        return cause is SocketException ||
            cause is HttpException ||
            error.response == null;
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
        return false;
    }
  }

  static VisitUploadResult parseHttp({
    required int statusCode,
    required dynamic data,
    VisitFlowKind? flowKind,
  }) {
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

    final idSource = _mapWithVisitId(map);
    final visitId = _visitIdFrom(idSource, allowBareId: idSource != map);
    final successFlag = map?['success'] ?? idSource?['success'];
    final statusOk = statusCode >= 200 && statusCode < 300;
    final claimedSuccess =
        successFlag == true || (successFlag == null && statusOk);
    final ok = claimedSuccess && visitId != null;

    Map<String, dynamic>? errors;
    final rawErrors = map?['errors'] ?? idSource?['errors'];
    if (rawErrors is Map) {
      errors = Map<String, dynamic>.from(rawErrors);
    }

    final apiMessage =
        _firstText(map, const ['message']) ??
        _firstText(idSource, const ['message']);
    final message = ok
        ? apiMessage
        : (claimedSuccess && visitId == null
              ? (apiMessage?.trim().isNotEmpty == true
                    ? apiMessage
                    : 'Upload response missing visit_id.')
              : apiMessage);

    return VisitUploadResult(
      success: ok,
      statusCode: statusCode,
      visitId: visitId,
      clientDraftId:
          _firstText(map, const ['client_draft_id', 'clientDraftId']) ??
          _firstText(idSource, const ['client_draft_id', 'clientDraftId']),
      itemsSaved:
          _firstInt(map, const ['items_saved', 'itemsSaved']) ??
          _firstInt(idSource, const ['items_saved', 'itemsSaved']),
      message: message,
      errors: errors,
      flowKind: flowKind,
    );
  }

  static const _visitIdKeys = <String>[
    'visit_id',
    'visitId',
    'report_id',
    'reportId',
  ];

  static const _envelopeKeys = <String>[
    'data',
    'payload',
    'result',
    'visit',
    'report',
  ];

  /// First object that actually contains a visit id.
  ///
  /// A blank or non-numeric `report_id` must not hide `visit_id`, and a
  /// wrapped patrol payload (`data.visit_id`, `visit.id`) still counts.
  static Map<String, dynamic>? _mapWithVisitId(Map<String, dynamic>? map) {
    if (map == null) return null;
    if (_visitIdFrom(map, allowBareId: false) != null) return map;

    for (final nested in _nestedMaps(map)) {
      if (_visitIdFrom(nested, allowBareId: true) != null) return nested;
    }
    return map;
  }

  static List<Map<String, dynamic>> _nestedMaps(Map<String, dynamic> map) {
    final maps = <Map<String, dynamic>>[];
    for (final key in _envelopeKeys) {
      final nested = _asMap(map[key]);
      if (nested == null) continue;
      maps.add(nested);
      for (final innerKey in _envelopeKeys) {
        final inner = _asMap(nested[innerKey]);
        if (inner != null) maps.add(inner);
      }
    }
    return maps;
  }

  static int? _visitIdFrom(
    Map<String, dynamic>? map, {
    required bool allowBareId,
  }) {
    final id = _firstInt(map, _visitIdKeys);
    if (id != null) return id;
    if (!allowBareId) return null;
    return _firstInt(map, const ['id']);
  }

  static int? _firstInt(Map<String, dynamic>? map, List<String> keys) {
    if (map == null) return null;
    for (final key in keys) {
      if (!map.containsKey(key)) continue;
      final parsed = _asInt(map[key]);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static String? _firstText(Map<String, dynamic>? map, List<String> keys) {
    if (map == null) return null;
    for (final key in keys) {
      final text = map[key]?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class VisitUploadApi {
  VisitUploadApi._();

  static final VisitUploadApi instance = VisitUploadApi._();

  Future<VisitUploadResult> uploadVisit({
    required Map<String, dynamic> meta,
    required List<VisitMediaItem> items,
    String? generalVoicePath,
    String? uploadUrl,
    void Function(int current, int total)? onProgress,
  }) async {
    final visitType = meta['visit_type']?.toString().trim().toLowerCase();
    final allowsEmptyMedia =
        visitType == VisitFlowKind.issueReportVisitType ||
        visitType == VisitFlowKind.incidentReportVisitType;
    if (items.isEmpty && !allowsEmptyMedia) {
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

    final itemByteWeights = List<int>.filled(items.length, 0);

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

      final mediaBytes = await mediaFile.length();
      itemByteWeights[i] = mediaBytes;

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
        itemByteWeights[i] += await voiceFile.length();
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

    final generalVoiceResult = await _attachGeneralVoice(
      form: form,
      meta: meta,
      generalVoicePath: generalVoicePath,
    );
    if (generalVoiceResult != null) {
      _logResult(generalVoiceResult);
      return generalVoiceResult;
    }

    final resolvedUploadUrl = _resolveUploadUrl(uploadUrl);
    final flowKind = _resolveFlowKind(meta: meta, uploadUrl: resolvedUploadUrl);

    if (kDebugMode) {
      debugPrint(
        '[VisitUploadApi] POST $resolvedUploadUrl '
        'items=${items.length} metaKeys=${meta.keys.toList()}',
      );
    }

    onProgress?.call(0, items.length);

    try {
      final response = await ApiClient.instance.dio.post<dynamic>(
        resolvedUploadUrl,
        data: form,
        options: Options(
          headers: const {'Accept': 'application/json'},
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(minutes: 10),
          receiveTimeout: const Duration(minutes: 3),
          validateStatus: (status) => status != null && status < 600,
        ),
        onSendProgress: (sent, total) {
          final current = _itemProgressFromBytes(
            sent: sent,
            totalHint: total,
            itemByteWeights: itemByteWeights,
          );
          onProgress?.call(current, items.length);
        },
      );

      onProgress?.call(items.length, items.length);
      final result = _parseResponse(response, flowKind: flowKind);
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
      final network = VisitUploadResult.isNetworkDioException(error);
      final parsed = error.response == null
          ? null
          : _parseResponse(error.response!, flowKind: flowKind);
      if (parsed != null && !network) {
        _logResult(parsed, responseBody: error.response?.data);
        return parsed;
      }
      final fallback = VisitUploadResult(
        success: false,
        statusCode: error.response?.statusCode,
        message: error.message ?? 'Network error while uploading visit.',
        isNetworkFailure: network || error.response == null,
        flowKind: flowKind,
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
      final network = error is SocketException || error is HttpException;
      final fallback = VisitUploadResult(
        success: false,
        message: error.toString(),
        isNetworkFailure: network,
        flowKind: flowKind,
      );
      _logResult(fallback);
      return fallback;
    }
  }

  static String _resolveUploadUrl(String? uploadUrl) {
    final trimmed = uploadUrl?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return ApiUrls.visitsUploadUrl;
    }
    return trimmed;
  }

  static VisitFlowKind _resolveFlowKind({
    required Map<String, dynamic> meta,
    required String uploadUrl,
  }) {
    final visitType =
        meta['visit_type']?.toString().trim() ??
        meta['visitType']?.toString().trim() ??
        '';
    if (visitType.isNotEmpty) {
      return VisitFlowKind.fromVisitType(visitType);
    }

    final path =
        Uri.tryParse(uploadUrl)?.path.toLowerCase() ?? uploadUrl.toLowerCase();
    if (path.contains('/issue-reports')) return VisitFlowKind.issueReport;
    if (path.contains('/incident-reports')) {
      return VisitFlowKind.incidentReport;
    }
    if (path.contains('/onsite-patrol/')) return VisitFlowKind.siteCheck;
    return VisitFlowKind.patrol;
  }

  static int _itemProgressFromBytes({
    required int sent,
    required int totalHint,
    required List<int> itemByteWeights,
  }) {
    if (itemByteWeights.isEmpty) return 0;
    if (sent <= 0) return 0;

    final mediaBytes = itemByteWeights.fold<int>(0, (sum, b) => sum + b);
    if (mediaBytes <= 0) {
      if (totalHint > 0) {
        final ratio = (sent / totalHint).clamp(0.0, 1.0);
        return (ratio * itemByteWeights.length).ceil().clamp(
          1,
          itemByteWeights.length,
        );
      }
      return 1;
    }

    final scale = totalHint > mediaBytes ? totalHint / mediaBytes : 1.0;
    var cumulative = 0.0;
    for (var i = 0; i < itemByteWeights.length; i++) {
      cumulative += itemByteWeights[i] * scale;
      if (sent < cumulative) return i + 1;
    }
    return itemByteWeights.length;
  }

  static String _bodyPreview(dynamic responseBody) {
    if (responseBody == null) return '';
    final text = responseBody.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return '';
    if (text.length <= 180) return text;
    return '${text.substring(0, 180)}…';
  }

  void _logResult(VisitUploadResult result, {dynamic responseBody}) {
    if (!result.success) {
      final path =
          Uri.tryParse(ApiUrls.visitsUploadUrl)?.path ?? '/visits/upload';
      final draftId = result.clientDraftId?.trim() ?? '';
      final ids = <String>[
        if (result.visitId != null) 'visitId=${result.visitId}',
        if (draftId.isNotEmpty) 'clientDraftId=$draftId',
      ].join(' ');
      SessionDebugLogger.instance.log(
        SessionDebugCategory.uploads,
        'FAIL POST $path status=${result.statusCode} '
        '${ids.isEmpty ? '' : '$ids '}'
        'message=${result.displayMessage} errors=${result.errors} '
        'body=${_bodyPreview(responseBody)}',
      );
    }
    if (!kDebugMode) return;
    if (result.success) {
      debugPrint(
        '[VisitUploadApi] SUCCESS status=${result.statusCode} '
        'visitId=${result.visitId} clientDraftId=${result.clientDraftId} '
        'itemsSaved=${result.itemsSaved} message=${result.displayMessage}',
      );
    } else {
      debugPrint(
        '[VisitUploadApi] FAIL status=${result.statusCode} '
        'message=${result.displayMessage} errors=${result.errors} '
        'body=$responseBody',
      );
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

  VisitUploadResult _parseResponse(
    Response<dynamic> response, {
    VisitFlowKind? flowKind,
  }) {
    return VisitUploadResult.parseHttp(
      statusCode: response.statusCode ?? 0,
      data: response.data,
      flowKind: flowKind,
    );
  }
}
