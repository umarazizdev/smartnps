import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../utilities/app_config.dart';
import '../utilities/device_identity.dart';

class BackgroundLocationUploader {
  BackgroundLocationUploader({Dio? dio})
    : _dio = dio ?? ApiClient.instance.dio {
    ApiClient.instance.ensureAuthInterceptorInstalled();
  }

  final Dio _dio;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  static const String _boxName = 'gps_points';
  Box<Map>? _box;
  String? _deviceId;

  Timer? _batchTimer;
  int _consecutiveBatchFailures = 0;
  bool _isFlushing = false;
  DateTime? _nextBatchAllowedAt;
  DateTime? _lastSuccessfulBatchFlushAt;
  DateTime? _batchTimerStartedAt;
  final List<Map<String, dynamic>> _memoryBatch = [];

  static const int _maxBatchSize = 20;
  static const Duration _batchEvery = Duration(minutes: 1);
  static const Duration _maxBackoff = Duration(minutes: 2);

  Uri _pingUri() =>
      Uri.parse('${AppConfig.gpsApiBaseUrl}${AppConfig.gpsPingPath}');
  Uri _batchUri() =>
      Uri.parse('${AppConfig.gpsApiBaseUrl}${AppConfig.gpsBatchPath}');

  Future<void> init() async {
    _deviceId ??= await DeviceIdentity.getDeviceId();
    await _ensureStorage();
  }

  Future<void> _ensureStorage() async {
    if (_box != null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      Hive.init(dir.path);
      _box = await Hive.openBox<Map>(_boxName);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[BackgroundLocationUploader] storage init skipped (ping still works): $e',
        );
      }
    }
  }

  void start() {
    _batchTimerStartedAt ??= DateTime.now();

    _batchTimer ??= Timer.periodic(_batchEvery, (_) => unawaited(flushBatch()));

    _connectivitySub ??= Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);

      if (!hasNetwork) return;

      unawaited(
        flushBatch().catchError((Object e) {
          if (kDebugMode) {
            debugPrint(
              '[BackgroundLocationUploader] connectivity flush failed: $e',
            );
          }
        }),
      );
    });
  }

  Future<void> stop() async {
    _batchTimer?.cancel();
    _batchTimer = null;
    _batchTimerStartedAt = null;

    await _connectivitySub?.cancel();
    _connectivitySub = null;

    await flushBatch(force: true);
  }

  /// Stores points for batch upload only (Hive).
  ///
  /// Ping uploads are sent live and are not persisted.
  Future<void> add(Position position) async {
    await _ensureStorage();
    final point = _sanitizePoint(_buildPoint(position));
    final box = _box;
    if (box != null) {
      await box.add(point);

      // Cap on-disk queue size (drop oldest first).
      while (box.length > 2000) {
        await box.deleteAt(0);
      }

      await _maybeFlushBatchAfterAdd();
      return;
    }

    _memoryBatch.add(point);
    while (_memoryBatch.length > 2000) {
      _memoryBatch.removeAt(0);
    }
    await _maybeFlushBatchAfterAdd();
  }

  int _queuedPointCount() {
    final box = _box;
    if (box != null) return box.length;
    return _memoryBatch.length;
  }

  /// Flushes on full batch (20) or when the queue has 2+ points and the
  /// batch interval elapsed. Location wakes on iOS may not run [Timer.periodic].
  Future<void> _maybeFlushBatchAfterAdd() async {
    final count = _queuedPointCount();
    if (count < 2) return;
    if (count >= _maxBatchSize) {
      await flushBatch();
      return;
    }
    if (_isBatchIntervalElapsed()) {
      await flushBatch();
    }
  }

  bool _isBatchIntervalElapsed() {
    final anchor = _lastSuccessfulBatchFlushAt ?? _batchTimerStartedAt;
    if (anchor == null) return false;
    return DateTime.now().difference(anchor) >= _batchEvery;
  }

  /// Sends the current point to the ping API immediately (no local storage).
  Future<void> pingNow(Position position) async {
    _deviceId ??= await DeviceIdentity.getDeviceId();
    final point = _sanitizePoint(_buildPoint(position));

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
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[BackgroundLocationUploader] ping failed status=${e.response?.statusCode} '
          'body=${_truncateForLog(e.response?.data)}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BackgroundLocationUploader] ping failed: $e');
      }
    }
  }

  Map<String, dynamic> _buildPoint(Position position) {
    final dynamic p = position;
    final dynamic sourceInformation = _safeRead<dynamic>(
      () => p.sourceInformation,
    );
    final bool? isSimulatedBySoftware = _safeRead<bool?>(
      () => sourceInformation?.isSimulatedBySoftware as bool?,
    );

    // Geolocator reports when the GPS fix was measured (UTC), not when we flush batch.
    final recordedAtUtc = position.timestamp.toUtc();

    return {
      'app': AppConfig.appName,
      'platform': DeviceIdentity.platformName(),
      'device_id': _deviceId,
      'deviceId': _deviceId,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'altitudeAccuracy': _numOrNull(() => position.altitudeAccuracy),
      'timestampMs': recordedAtUtc.millisecondsSinceEpoch,
      'timestamp': recordedAtUtc.toIso8601String(),
      'altitude': position.altitude,
      'speed': _validSensorNumOrNull(() => position.speed),
      'speedAccuracy': _validSensorNumOrNull(() => position.speedAccuracy),
      'heading': _validSensorNumOrNull(() => position.heading),
      'headingAccuracy': _validSensorNumOrNull(() => position.headingAccuracy),
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

  Map<String, dynamic> _sanitizePoint(Map<String, dynamic> point) {
    final sanitized = Map<String, dynamic>.from(point);
    for (final key in const [
      'heading',
      'headingAccuracy',
      'speed',
      'speedAccuracy',
    ]) {
      final value = sanitized[key];
      if (value is num && (value.isNaN || value < 0)) {
        sanitized[key] = null;
      }
    }
    return sanitized;
  }

  /// iOS/CoreLocation uses negative sentinels (e.g. -1) when a value is unknown.
  /// The GPS API rejects those; omit the field instead.
  num? _validSensorNumOrNull(num Function() read, {num min = 0}) {
    try {
      final v = read();
      if (v.isNaN || v < min) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  Future<void> flushBatch({bool force = false}) async {
    if (_isFlushing) return;
    if (!force) {
      final nextAllowed = _nextBatchAllowedAt;
      if (nextAllowed != null && DateTime.now().isBefore(nextAllowed)) return;
    }

    final box = _box;
    if (box != null) {
      if (box.isEmpty) return;
      if (!force && box.length < 2) return;
      await _flushHiveBatch(box, force: force);
      return;
    }

    if (_memoryBatch.isEmpty) return;
    if (!force && _memoryBatch.length < 2) return;
    await _flushMemoryBatch(force: force);
  }

  Future<void> _flushHiveBatch(Box<Map> box, {bool force = false}) async {
    _isFlushing = true;
    final takeCount = box.length < _maxBatchSize ? box.length : _maxBatchSize;
    final keys = box.keys.take(takeCount).toList(growable: false);
    final batch = keys
        .map(
          (k) =>
              _sanitizePoint(Map<String, dynamic>.from(box.get(k) ?? const {})),
        )
        .where((m) => m.isNotEmpty)
        .toList(growable: false);

    if (batch.isEmpty || (!force && batch.length < 2)) {
      _isFlushing = false;
      return;
    }

    try {
      await _postBatch(batch);
      await box.deleteAll(keys);
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> _flushMemoryBatch({bool force = false}) async {
    _isFlushing = true;
    final takeCount = _memoryBatch.length < _maxBatchSize
        ? _memoryBatch.length
        : _maxBatchSize;
    final batch = _memoryBatch.take(takeCount).toList(growable: false);
    if (batch.isEmpty || (!force && batch.length < 2)) {
      _isFlushing = false;
      return;
    }

    try {
      await _postBatch(batch);
      _memoryBatch.removeRange(0, takeCount);
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> _postBatch(List<Map<String, dynamic>> batch) async {
    if (kDebugMode) {
      debugPrint(
        '[BackgroundLocationUploader] flushBatch count=${batch.length}',
      );
      debugPrint('[BackgroundLocationUploader] POST ${_batchUri()} (batch)');
      _logBatchTimestampSummary(batch);
      _logFullJson('batch request', {'points': batch});
    }

    final Options options = Options(
      headers: const {'Accept': 'application/json'},
      contentType: Headers.jsonContentType,
      sendTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
    );

    try {
      final response = await _dio.postUri(
        _batchUri(),
        data: {'points': batch},
        options: options,
      );

      _consecutiveBatchFailures = 0;
      _nextBatchAllowedAt = null;
      _lastSuccessfulBatchFlushAt = DateTime.now();

      if (kDebugMode) {
        final status = response.statusCode;
        final body = response.data;
        var bodyText = body == null ? '' : body.toString();
        if (bodyText.length > 800) {
          bodyText = '${bodyText.substring(0, 800)}...';
        }
        debugPrint(
          '[BackgroundLocationUploader] batch upload ok status=$status body=$bodyText',
        );
      }
    } catch (e) {
      _consecutiveBatchFailures++;
      final seconds = 1 << (_consecutiveBatchFailures.clamp(0, 6));
      var delay = Duration(seconds: seconds);
      if (delay < const Duration(seconds: 5)) {
        delay = const Duration(seconds: 5);
      }
      if (delay > _maxBackoff) delay = _maxBackoff;

      if (kDebugMode) {
        debugPrint(
          '[BackgroundLocationUploader] batch upload failed (will retry in ${delay.inSeconds}s): $e',
        );
      }
      _nextBatchAllowedAt = DateTime.now().add(delay);
      rethrow;
    }
  }

  String _truncateForLog(Object? value, {int max = 1200}) {
    final text = value?.toString() ?? '';
    if (text.length <= max) return text;
    return '${text.substring(0, max)}...';
  }

  /// Clarifies that batch `timestamp` values are per-point GPS fix times (UTC),
  /// which can look "old" vs device local clock or vs batch flush time.
  void _logBatchTimestampSummary(List<Map<String, dynamic>> batch) {
    if (!kDebugMode || batch.isEmpty) return;

    final nowUtc = DateTime.now().toUtc();
    final nowLocal = DateTime.now();

    DateTime? oldestUtc;
    DateTime? newestUtc;
    for (final point in batch) {
      final ms = point['timestampMs'];
      if (ms is! num) continue;
      final at = DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: true);
      oldestUtc = oldestUtc == null || at.isBefore(oldestUtc) ? at : oldestUtc;
      newestUtc = newestUtc == null || at.isAfter(newestUtc) ? at : newestUtc;
    }

    debugPrint(
      '[BackgroundLocationUploader] device now '
      'local=${nowLocal.toIso8601String()} utc=${nowUtc.toIso8601String()}',
    );

    if (oldestUtc == null || newestUtc == null) return;

    final oldestAge = nowUtc.difference(oldestUtc);
    final newestAge = nowUtc.difference(newestUtc);
    debugPrint(
      '[BackgroundLocationUploader] batch GPS fix times (UTC, not flush time): '
      'oldest=${oldestUtc.toIso8601String()} '
      '(local ${oldestUtc.toLocal().toIso8601String()}, '
      '${oldestAge.inSeconds}s before flush) '
      'newest=${newestUtc.toIso8601String()} '
      '(local ${newestUtc.toLocal().toIso8601String()}, '
      '${newestAge.inSeconds}s before flush)',
    );
  }

  /// Logs the full JSON body in debug builds, split across lines so logcat
  /// does not truncate payloads larger than ~4 KB (e.g. 20 GPS points).
  void _logFullJson(String label, Object? value) {
    if (!kDebugMode) return;

    final String json;
    try {
      json = const JsonEncoder.withIndent('  ').convert(value);
    } catch (e) {
      debugPrint('[BackgroundLocationUploader] $label json encode failed: $e');
      debugPrint(
        '[BackgroundLocationUploader] $label fallback=${_truncateForLog(value)}',
      );
      return;
    }

    const chunkSize = 3500;
    if (json.length <= chunkSize) {
      debugPrint('[BackgroundLocationUploader] $label json:\n$json');
      return;
    }

    final total = (json.length / chunkSize).ceil();
    for (var i = 0; i < total; i++) {
      final start = i * chunkSize;
      final end = start + chunkSize < json.length
          ? start + chunkSize
          : json.length;
      debugPrint(
        '[BackgroundLocationUploader] $label json part ${i + 1}/$total:\n'
        '${json.substring(start, end)}',
      );
    }
  }
}
