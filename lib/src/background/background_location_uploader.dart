import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../utilities/app_config.dart';

class BackgroundLocationUploader {
  BackgroundLocationUploader({Dio? dio})
    : _dio = dio ?? ApiClient.instance.dio {
    ApiClient.instance.ensureAuthInterceptorInstalled();
  }

  final Dio _dio;

  static const String _boxName = 'gps_points';
  Box<Map>? _box;

  Timer? _batchTimer;
  int _consecutiveBatchFailures = 0;
  bool _isFlushing = false;
  DateTime? _nextBatchAllowedAt;

  static const int _maxBatchSize = 20;
  static const Duration _batchEvery = Duration(minutes: 1);
  static const Duration _maxBackoff = Duration(minutes: 2);

  Uri _pingUri() =>
      Uri.parse('${AppConfig.gpsApiBaseUrl}${AppConfig.gpsPingPath}');
  Uri _batchUri() =>
      Uri.parse('${AppConfig.gpsApiBaseUrl}${AppConfig.gpsBatchPath}');

  Future<void> init() async {
    if (_box != null) return;
    final dir = await getApplicationDocumentsDirectory();
    Hive.init(dir.path);
    _box = await Hive.openBox<Map>(_boxName);
  }

  void start() {
    _batchTimer ??= Timer.periodic(_batchEvery, (_) => unawaited(flushBatch()));
  }

  Future<void> stop() async {
    _batchTimer?.cancel();
    _batchTimer = null;
    await flushBatch();
  }

  /// Stores points for batch upload only (Hive).
  ///
  /// Ping uploads are sent live and are not persisted.
  Future<void> add(Position position, {String? deviceId}) async {
    final box = _box;
    if (box == null) {
      throw StateError('BackgroundLocationUploader.init() not called');
    }
    final point = _buildPoint(position, deviceId: deviceId);
    await box.add(point);

    // Cap on-disk queue size (drop oldest first).
    while (box.length > 2000) {
      await box.deleteAt(0);
    }

    if (box.length >= _maxBatchSize) {
      await flushBatch();
    }
  }

  /// Sends the current point to the ping API immediately (no local storage).
  Future<void> pingNow(Position position, {String? deviceId}) async {
    final point = _buildPoint(position, deviceId: deviceId);

    final Options options = Options(
      headers: const {'Accept': 'application/json'},
      contentType: Headers.jsonContentType,
      sendTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    );

    try {
      if (kDebugMode) {
        debugPrint('[BackgroundLocationUploader] POST ${_pingUri()}');
        debugPrint(
          '[BackgroundLocationUploader] body=${_truncateForLog(point)}',
        );
      }
      final response = await _dio.postUri(
        _pingUri(),
        data: point,
        options: options,
      );
      if (kDebugMode) {
        final status = response.statusCode;
        final body = response.data;
        var bodyText = body == null ? '' : body.toString();
        if (bodyText.length > 800) {
          bodyText = '${bodyText.substring(0, 800)}...';
        }
        debugPrint(
          '[BackgroundLocationUploader] ping ok status=$status body=$bodyText',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BackgroundLocationUploader] ping failed: $e');
      }
    }
  }

  Map<String, dynamic> _buildPoint(Position position, {String? deviceId}) {
    final dynamic p = position;
    final dynamic sourceInformation = _safeRead<dynamic>(
      () => p.sourceInformation,
    );
    final bool? isSimulatedBySoftware = _safeRead<bool?>(
      () => sourceInformation?.isSimulatedBySoftware as bool?,
    );

    return {
      'app': AppConfig.appName,
      'platform': Platform.operatingSystem,
      'deviceId': deviceId,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'altitudeAccuracy': _numOrNull(() => position.altitudeAccuracy),
      'timestampMs': position.timestamp.millisecondsSinceEpoch,
      'timestamp': position.timestamp.toIso8601String(),
      'altitude': position.altitude,
      'speed': position.speed,
      'speedAccuracy': _numOrNull(() => position.speedAccuracy),
      'heading': position.heading,
      'headingAccuracy': _numOrNull(() => position.headingAccuracy),
      'isMocked': position.isMocked,
      'isSimulatedBySoftware': isSimulatedBySoftware,
      'floor': _numOrNull(() => p.floor),
    };
  }

  T? _safeRead<T>(T Function() read) {
    try {
      return read();
    } catch (_) {
      return null;
    }
  }

  num? _numOrNull(num Function() read) {
    try {
      final v = read();
      return v;
    } catch (_) {
      return null;
    }
  }

  Future<void> flushBatch() async {
    if (_isFlushing) return;
    final nextAllowed = _nextBatchAllowedAt;
    if (nextAllowed != null && DateTime.now().isBefore(nextAllowed)) return;

    final box = _box;
    if (box == null) return;
    if (box.length < 2) return;

    _isFlushing = true;
    final takeCount = box.length < _maxBatchSize ? box.length : _maxBatchSize;
    final keys = box.keys.take(takeCount).toList(growable: false);
    final batch = keys
        .map((k) => Map<String, dynamic>.from(box.get(k) ?? const {}))
        .where((m) => m.isNotEmpty)
        .toList(growable: false);

    if (batch.length < 2) {
      _isFlushing = false;
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[BackgroundLocationUploader] flushBatch count=${batch.length}',
      );
    }

    final Options options = Options(
      headers: const {'Accept': 'application/json'},
      contentType: Headers.jsonContentType,
      sendTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
    );

    try {
      if (kDebugMode) {
        debugPrint('[BackgroundLocationUploader] POST ${_batchUri()} (batch)');
        debugPrint(
          '[BackgroundLocationUploader] body=${_truncateForLog({'points': batch})}',
        );
      }
      final response = await _dio.postUri(
        _batchUri(),
        data: {'points': batch},
        options: options,
      );

      _consecutiveBatchFailures = 0;
      _nextBatchAllowedAt = null;
      await box.deleteAll(keys);

      if (kDebugMode) {
        final status = response.statusCode;
        final body = response.data;
        var bodyText = body == null ? '' : body.toString();
        if (bodyText.length > 800)
          bodyText = '${bodyText.substring(0, 800)}...';
        debugPrint(
          '[BackgroundLocationUploader] batch upload ok status=$status body=$bodyText',
        );
      }
    } catch (e) {
      _consecutiveBatchFailures++;
      final seconds = 1 << (_consecutiveBatchFailures.clamp(0, 6));
      var delay = Duration(seconds: seconds);
      if (delay < const Duration(seconds: 5))
        delay = const Duration(seconds: 5);
      if (delay > _maxBackoff) delay = _maxBackoff;

      if (kDebugMode) {
        debugPrint(
          '[BackgroundLocationUploader] batch upload failed (will retry in ${delay.inSeconds}s): $e',
        );
      }
      _nextBatchAllowedAt = DateTime.now().add(delay);
    } finally {
      _isFlushing = false;
    }
  }

  String _truncateForLog(Object? value, {int max = 1200}) {
    final text = value?.toString() ?? '';
    if (text.length <= max) return text;
    return '${text.substring(0, max)}...';
  }
}
