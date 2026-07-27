import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../auth/auth_repository.dart';
import '../location/batch_displacement_gate.dart';
import '../location/speed_adaptive_gps_policy.dart';
import '../motion/motion_activity_fusion_controller.dart';
import '../motion/vehicle_session_fusion.dart';
import 'background_location_accuracy.dart';
import '../utilities/app_config.dart';
import '../utilities/app_version_info.dart';
import '../utilities/device_identity.dart';

class BackgroundLocationUploader {
  BackgroundLocationUploader({Dio? dio})
    : _dio = dio ?? ApiClient.instance.dio {
    ApiClient.instance.ensureAuthInterceptorInstalled();
  }

  final Dio _dio;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  static const String _boxName = 'gps_points';
  static const String _fallbackQueueFileName = 'gps_points_fallback.jsonl';
  Box<Map>? _box;
  File? _fallbackQueueFile;
  int _fallbackQueueCount = 0;
  String? _deviceId;

  Timer? _batchTimer;
  int _consecutiveBatchFailures = 0;
  bool _isFlushing = false;
  /// When false, [pingNow]/[add] no-op so off-duty flush cannot record new points.
  bool _acceptingNewPoints = true;
  DateTime? _nextBatchAllowedAt;
  DateTime? _lastSuccessfulBatchFlushAt;
  DateTime? _batchTimerStartedAt;
  final List<Map<String, dynamic>> _memoryBatch = [];
  int _nextQueueSeqId = 0;
  int _batchRunNumber = 0;
  int _totalBatchPointsQueued = 0;
  int _totalBatchPointsUploaded = 0;
  final SpeedAdaptiveGpsPolicyTracker _policyTracker =
      SpeedAdaptiveGpsPolicyTracker();
  final BatchDisplacementGate _batchDisplacementGate = BatchDisplacementGate();

  static const int _maxBatchSize = 20;
  /// Minimum / curve-boost GPS cadence (adaptive stream uses policy bands).
  static const Duration pingInterval = Duration(seconds: 1);
  static const Duration _batchEvery = Duration(minutes: 1);
  static const Duration _maxBackoff = Duration(minutes: 2);
  static const Duration logoutFlushBudget = Duration(seconds: 15);

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
      _fallbackQueueFile ??= File('${dir.path}/$_fallbackQueueFileName');
      _fallbackQueueCount = await _countFallbackQueue();

      try {
        Hive.init(dir.path);
        _box = await Hive.openBox<Map>(_boxName);
        await _migrateFallbackQueueToHive();
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[BackgroundLocationUploader] Hive storage init skipped '
            '(file fallback enabled): $e',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[BackgroundLocationUploader] storage path init failed '
          '(memory fallback only): $e',
        );
      }
    }
  }

  Future<int> _countFallbackQueue() async {
    final file = _fallbackQueueFile;
    if (file == null || !await file.exists()) return 0;
    return file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.trim().isNotEmpty)
        .length;
  }

  Future<List<Map<String, dynamic>>> _readFallbackQueue() async {
    final file = _fallbackQueueFile;
    if (file == null || !await file.exists()) return const [];

    final points = <Map<String, dynamic>>[];
    final seenIds = <String>{};
    try {
      final lines = file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map) continue;
          final point = _sanitizePoint(Map<String, dynamic>.from(decoded));
          if (point.isEmpty) continue;
          _normalizeLocalPointKey(point);
          final id = point['_local_point_key']?.toString();
          if (id != null && id.isNotEmpty && !seenIds.add(id)) continue;
          points.add(point);
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[BackgroundLocationUploader] fallback queue read failed: $e',
        );
      }
    }
    return points;
  }

  Future<void> _rewriteFallbackQueue(List<Map<String, dynamic>> points) async {
    final file = _fallbackQueueFile;
    if (file == null) {
      _fallbackQueueCount = 0;
      return;
    }

    if (points.isEmpty) {
      if (await file.exists()) {
        await file.delete();
      }
      _fallbackQueueCount = 0;
      return;
    }

    final sink = file.openWrite(mode: FileMode.write);
    try {
      for (final point in points) {
        sink.writeln(jsonEncode(point));
      }
    } finally {
      await sink.close();
    }
    _fallbackQueueCount = points.length;
  }

  Future<void> _appendFallbackPoint(Map<String, dynamic> point) async {
    final file = _fallbackQueueFile;
    if (file == null) {
      throw StateError('Fallback queue file is unavailable');
    }

    final sink = file.openWrite(mode: FileMode.append);
    try {
      sink.writeln(jsonEncode(point));
    } finally {
      await sink.close();
    }

    _fallbackQueueCount++;
    if (_fallbackQueueCount > 2000) {
      final points = await _readFallbackQueue();
      await _rewriteFallbackQueue(
        points.length > 2000 ? points.sublist(points.length - 2000) : points,
      );
    }
  }

  Future<void> _migrateFallbackQueueToHive() async {
    final box = _box;
    if (box == null || _fallbackQueueCount == 0) return;

    final fallbackPoints = await _readFallbackQueue();
    if (fallbackPoints.isEmpty) {
      await _rewriteFallbackQueue(const []);
      return;
    }

    final existingIds = box.values
        .map(
          (value) =>
              value['_local_point_key']?.toString() ??
              value['client_point_id']?.toString(),
        )
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    for (final point in fallbackPoints) {
      _normalizeLocalPointKey(point);
      _assignQueueSeq(point);
      final id = point['_local_point_key']?.toString();
      if (id != null && id.isNotEmpty && existingIds.contains(id)) continue;
      await box.add(point);
      if (id != null && id.isNotEmpty) existingIds.add(id);
    }

    await _rewriteFallbackQueue(const []);
  }

  void start() {
    _acceptingNewPoints = true;
    _batchTimerStartedAt ??= DateTime.now();

    _batchTimer ??= Timer.periodic(_batchEvery, (_) => unawaited(flushBatch()));

    if (kDebugMode) {
      _batchConsoleLog(
        'batch tracking started interval=${_batchEvery.inSeconds}s '
        'min_points=2 max_batch=$_maxBatchSize',
      );
    }

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

  /// Drains the on-device queue before shutdown (e.g. off duty).
  Future<void> flushAllPendingBatches({int maxRounds = 200}) async {
    for (var round = 0; round < maxRounds; round++) {
      final remaining = _queuedPointCount();
      if (remaining == 0) return;

      try {
        await flushBatch(force: true);
      } catch (_) {
        // Best-effort: stop if a round makes no progress.
        if (_queuedPointCount() >= remaining) return;
      }

      if (_queuedPointCount() >= remaining) {
        // Partial failure or single-point edge; retry once more for leftovers.
        if (round > 0) return;
      }
    }
  }

  /// Best-effort upload during logout, bounded by [timeout].
  Future<void> flushAllPendingBatchesBounded({
    Duration timeout = logoutFlushBudget,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final remaining = _queuedPointCount();
      if (remaining == 0) return;

      final before = remaining;
      try {
        await flushBatch(force: true);
      } catch (_) {}

      if (_queuedPointCount() < before) continue;
      if (DateTime.now().isAfter(deadline)) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Drops any queued GPS points still on disk or in memory.
  Future<int> discardPendingQueue() async {
    await _ensureStorage();
    final discarded = _queuedPointCount();
    _memoryBatch.clear();
    final box = _box;
    if (box != null && box.isNotEmpty) {
      await box.clear();
    }
    await _rewriteFallbackQueue(const []);
    if (kDebugMode && discarded > 0) {
      debugPrint(
        '[BackgroundLocationUploader] discarded $discarded queued GPS point(s)',
      );
    }
    return discarded;
  }

  /// Logout teardown: bounded flush while auth still exists, then purge leftovers.
  Future<void> drainAndDiscardOnLogout({
    Duration timeout = logoutFlushBudget,
  }) async {
    _batchTimer?.cancel();
    _batchTimer = null;
    _batchTimerStartedAt = null;
    await _connectivitySub?.cancel();
    _connectivitySub = null;

    await _ensureStorage();
    final before = _queuedPointCount();
    if (before == 0) return;

    if (kDebugMode) {
      debugPrint(
        '[BackgroundLocationUploader] logout drain start queued=$before '
        'timeout=${timeout.inSeconds}s',
      );
    }

    await flushAllPendingBatchesBounded(timeout: timeout);
    final remaining = await discardPendingQueue();
    if (kDebugMode && remaining > 0) {
      debugPrint(
        '[BackgroundLocationUploader] logout drain complete '
        'uploaded=${before - remaining} discarded=$remaining',
      );
    }
  }

  /// Opens shared Hive storage and drains/discards even when tracking is off.
  static Future<void> drainAndDiscardOnLogoutStatic({
    Duration timeout = logoutFlushBudget,
  }) async {
    final uploader = BackgroundLocationUploader();
    await uploader.init();
    await uploader.drainAndDiscardOnLogout(timeout: timeout);
  }

  /// Opens shared storage and retries queued GPS batches without discarding
  /// leftovers. Useful when the app resumes after iOS background suspension.
  static Future<void> flushPendingBatchesStatic({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final uploader = BackgroundLocationUploader();
    await uploader.init();
    await uploader.flushAllPendingBatchesBounded(timeout: timeout);
  }

  Future<void> stop() async {
    // Reject new ping/queue first; flush already-queued batches only.
    _acceptingNewPoints = false;
    _batchTimer?.cancel();
    _batchTimer = null;
    _batchTimerStartedAt = null;
    _batchDisplacementGate.reset();

    await _connectivitySub?.cancel();
    _connectivitySub = null;

    await flushAllPendingBatches();
  }

  /// Stops timers/connectivity without flushing (logout instant phase).
  ///
  /// Also closes [pingNow]/[add] so in-flight GPS callbacks cannot record
  /// new points while a pending-batch flush runs.
  Future<void> stopCollectingOnly() async {
    _acceptingNewPoints = false;
    _batchTimer?.cancel();
    _batchTimer = null;
    _batchTimerStartedAt = null;
    _batchDisplacementGate.reset();
    await _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  /// Stores points for batch upload only (Hive).
  ///
  /// Ping uploads are sent live and are not persisted.
  /// Stationary / below 2 km/h points are ping-only and never queued here.
  /// Points that have not moved far enough (GPS drift while standing) are also
  /// skipped here without affecting ping.
  Future<void> add(
    Position position, {
    SpeedAdaptiveGpsPolicyDecision? policyDecision,
    VehicleSessionSnapshot? motionFusion,
  }) async {
    if (!_acceptingNewPoints) return;
    if (!BackgroundLocationAccuracy.isAcceptable(position)) return;
    if (!await _hasUploadAuth()) return;
    if (!_acceptingNewPoints) return;
    final policy = policyDecision ?? _policyTracker.evaluate(position);
    final fusion = motionFusion ??
        await MotionActivityFusionController.instance.evaluatePosition(
          position,
        );
    if (!policy.shouldQueueForBatch) {
      if (kDebugMode) {
        _batchConsoleLog(
          'skipped batch queue '
          'band=${policy.band.label} '
          'motion=${fusion.apiMotionActivity} '
          'fused=${fusion.fusedState} '
          'speedKmh=${(policy.smoothedSpeedKmh ?? policy.rawSpeedKmh)?.toStringAsFixed(1)} '
          '(ping-only)',
        );
      }
      return;
    }
    if (!_batchDisplacementGate.shouldQueue(position)) {
      if (kDebugMode) {
        _batchConsoleLog(
          'skipped batch queue '
          'dist=${_batchDisplacementGate.distanceFromLastQueuedMeters(position).toStringAsFixed(1)}m '
          'need=${_batchDisplacementGate.requiredMetersFor(position).toStringAsFixed(1)}m '
          '(not moved)',
        );
      }
      return;
    }
    await _ensureStorage();
    if (!_acceptingNewPoints) return;
    final recordedAtUtc = position.timestamp.toUtc();
    final apiPoint = await _buildApiPoint(
      position,
      policyDecision: policy,
      motionFusion: fusion,
    );
    if (!_acceptingNewPoints) return;
    final point = Map<String, dynamic>.from(apiPoint)
      ..['_local_point_key'] = _localPointKey(position, recordedAtUtc);
    _assignQueueSeq(point);
    final newPointId = _queueSeqLabel(point);
    _totalBatchPointsQueued++;
    _batchDisplacementGate.markQueued(position);
    final box = _box;
    if (box != null) {
      await box.add(point);

      // Cap on-disk queue size (drop oldest first).
      while (box.length > 2000) {
        await box.deleteAt(0);
      }

      if (kDebugMode) {
        _logBatchQueueSnapshot(
          'received',
          newPointId: newPointId,
          detail: 'queued for batch upload',
        );
      }

      await _maybeFlushBatchAfterAdd();
      return;
    }

    try {
      await _appendFallbackPoint(point);
      _memoryBatch.clear();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[BackgroundLocationUploader] fallback file append failed '
          '(memory fallback used): $e',
        );
      }
      _memoryBatch.add(point);
      while (_memoryBatch.length > 2000) {
        _memoryBatch.removeAt(0);
      }
    }

    if (kDebugMode) {
      _logBatchQueueSnapshot(
        'received',
        newPointId: newPointId,
        detail: 'queued for batch upload',
      );
    }
    await _maybeFlushBatchAfterAdd();
  }

  int _queuedPointCount() {
    final box = _box;
    if (box != null) return box.length;
    return _fallbackQueueCount + _memoryBatch.length;
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
      return;
    }

    if (kDebugMode) {
      final anchor = _lastSuccessfulBatchFlushAt ?? _batchTimerStartedAt;
      final elapsedSec = anchor == null
          ? 0
          : DateTime.now().difference(anchor).inSeconds;
      _logBatchQueueSnapshot(
        'hold',
        detail:
            'waiting_for_1min_interval elapsed=${elapsedSec}s/${_batchEvery.inSeconds}s',
      );
    }
  }

  bool _isBatchIntervalElapsed() {
    final anchor = _lastSuccessfulBatchFlushAt ?? _batchTimerStartedAt;
    if (anchor == null) return false;
    return DateTime.now().difference(anchor) >= _batchEvery;
  }

  Future<bool> _hasUploadAuth() async {
    final token = await AuthRepository.instance.ensureValidAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// Sends the current point to the ping API immediately (no local storage).
  Future<void> pingNow(
    Position position, {
    SpeedAdaptiveGpsPolicyDecision? policyDecision,
    VehicleSessionSnapshot? motionFusion,
  }) async {
    if (!_acceptingNewPoints) return;
    if (!BackgroundLocationAccuracy.isAcceptable(position)) return;
    if (!await _hasUploadAuth()) return;
    if (!_acceptingNewPoints) return;
    final fusion = motionFusion ??
        await MotionActivityFusionController.instance.evaluatePosition(
          position,
        );
    final point = await _buildApiPoint(
      position,
      policyDecision: policyDecision,
      motionFusion: fusion,
    );
    if (!_acceptingNewPoints) return;

    final Options options = Options(
      headers: const {'Accept': 'application/json'},
      contentType: Headers.jsonContentType,
      sendTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    );

    try {
      await _dio.postUri(
        _pingUri(),
        data: point,
        options: options,
      );
    } on DioException {
      // ApiClient logs path, status, and error.
    } catch (_) {
      // ApiClient logs path, status, and error.
    }
  }

  /// Canonical API payload shared by ping and each batch point.
  Future<Map<String, dynamic>> _buildApiPoint(
    Position position, {
    SpeedAdaptiveGpsPolicyDecision? policyDecision,
    VehicleSessionSnapshot? motionFusion,
  }) async {
    _deviceId ??= await DeviceIdentity.getDeviceId();
    return _sanitizePoint(
      await _buildPoint(
        position,
        policyDecision: policyDecision,
        motionFusion: motionFusion,
      ),
    );
  }

  Future<Map<String, dynamic>> _buildPoint(
    Position position, {
    SpeedAdaptiveGpsPolicyDecision? policyDecision,
    VehicleSessionSnapshot? motionFusion,
  }) async {
    final dynamic p = position;
    final dynamic sourceInformation = _safeRead<dynamic>(
      () => p.sourceInformation,
    );
    final bool? isSimulatedBySoftware = _safeRead<bool?>(
      () => sourceInformation?.isSimulatedBySoftware as bool?,
    );

    // Geolocator reports when the GPS fix was measured (UTC), not when we flush batch.
    final recordedAtUtc = position.timestamp.toUtc();
    final policy = policyDecision ?? _policyTracker.evaluate(position);
    final fusion = motionFusion ??
        await MotionActivityFusionController.instance.evaluatePosition(
          position,
        );

    return {
      'app': AppConfig.appName,
      'platform': DeviceIdentity.platformName(),
      'device_id': _deviceId,
      'deviceId': _deviceId,
      'build': AppVersionInfo.buildNumber,
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
      // Same engine as Motion Activity screen (native OS + GPS speed fusion).
      // Never use speed-band labels for motion — policy is timing-only below.
      'motionActivity': fusion.apiMotionActivity,
      'motionSource': 'vehicle_session_fusion',
      'motionFusedState': fusion.fusedState,
      'motionNativeActivity': fusion.nativeActivity,
      'motionNativeConfidence': fusion.nativeConfidence,
      'motionSessionActive': fusion.active,
      'motionProvisional': fusion.provisional,
      'motionReason': fusion.reason,
      'motionSpeedKmh': fusion.smoothedSpeedKmh ?? fusion.gpsSpeedKmh,
      // Speed-adaptive policy: capture/upload cadence metadata only.
      ...policy.toJson(),
      'floor': _numOrNull(() => p.floor),
    };
  }

  String _localPointKey(Position position, DateTime recordedAtUtc) {
    final device = _deviceId ?? 'unknown-device';
    return [
      AppConfig.appName,
      DeviceIdentity.platformName(),
      device,
      recordedAtUtc.millisecondsSinceEpoch,
      position.latitude.toStringAsFixed(7),
      position.longitude.toStringAsFixed(7),
    ].join(':');
  }

  void _normalizeLocalPointKey(Map<String, dynamic> point) {
    final legacy = point.remove('client_point_id')?.toString();
    final current = point['_local_point_key']?.toString();
    if ((current == null || current.isEmpty) &&
        legacy != null &&
        legacy.isNotEmpty) {
      point['_local_point_key'] = legacy;
    }
  }

  Map<String, dynamic> _apiPoint(Map<String, dynamic> point) {
    final apiPoint = Map<String, dynamic>.from(point);
    apiPoint.remove('_local_point_key');
    apiPoint.remove('client_point_id');
    apiPoint.remove('_queue_seq');
    // Legacy: never send speed-band motion as activity (fusion only).
    apiPoint.remove('speedBandMotionActivity');
    return apiPoint;
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
    if (_isFlushing) {
      if (kDebugMode && _queuedPointCount() > 0) {
        _logBatchQueueSnapshot(
          'flush_skipped',
          detail: _pendingQueueReason(force: force),
        );
      }
      return;
    }
    if (!force) {
      final nextAllowed = _nextBatchAllowedAt;
      if (nextAllowed != null && DateTime.now().isBefore(nextAllowed)) {
        if (kDebugMode && _queuedPointCount() > 0) {
          final waitSec = nextAllowed.difference(DateTime.now()).inSeconds;
          _logBatchQueueSnapshot(
            'flush_skipped',
            detail:
                'backoff_retry wait=${waitSec}s (${_pendingQueueReason(force: force)})',
          );
        }
        return;
      }
    }

    final box = _box;
    if (box != null) {
      if (box.isEmpty) return;
      if (!force && box.length < 2) {
        if (kDebugMode) {
          _logBatchQueueSnapshot(
            'flush_skipped',
            detail: _pendingQueueReason(force: force),
          );
        }
        return;
      }
      await _flushHiveBatch(box, force: force);
      return;
    }

    if (_fallbackQueueCount > 0) {
      await _flushFallbackFileBatch(force: force);
      return;
    }

    if (_memoryBatch.isEmpty) return;
    if (!force && _memoryBatch.length < 2) {
      if (kDebugMode) {
        _logBatchQueueSnapshot(
          'flush_skipped',
          detail: _pendingQueueReason(force: force),
        );
      }
      return;
    }
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

  Future<void> _flushFallbackFileBatch({bool force = false}) async {
    _isFlushing = true;
    final points = await _readFallbackQueue();
    final batch = points.take(_maxBatchSize).toList(growable: false);
    if (batch.isEmpty || (!force && batch.length < 2)) {
      _fallbackQueueCount = points.length;
      _isFlushing = false;
      return;
    }

    try {
      await _postBatch(batch);
      await _rewriteFallbackQueue(points.skip(batch.length).toList());
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> _postBatch(List<Map<String, dynamic>> batch) async {
    final apiBatch = batch.map(_apiPoint).toList(growable: false);
    final batchRun = ++_batchRunNumber;
    final uploadingIds = _formatQueueSeqLabels(batch);
    final queuedBeforeUpload = _queuedPointCount();
    if (kDebugMode) {
      _batchConsoleLog(
        'batchRun=$batchRun START upload_count=${batch.length} '
        'queued_before=$queuedBeforeUpload '
        '${_batchTotalsLabel()}',
      );
      debugPrint(
        '[BackgroundLocationUploader] flushBatch count=${apiBatch.length}',
      );
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
        data: {'points': apiBatch},
        options: options,
      );

      _consecutiveBatchFailures = 0;
      _nextBatchAllowedAt = null;
      _lastSuccessfulBatchFlushAt = DateTime.now();
      _totalBatchPointsUploaded += batch.length;

      if (kDebugMode) {
        _logBatchUploadResult(
          batchRun: batchRun,
          uploadedBatch: batch,
          responseBody: response.data,
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
        _logBatchQueueSnapshot(
          'upload_failed',
          batchRun: batchRun,
          uploadedIds: uploadingIds,
          detail: 'still queued after failure; retry in ${delay.inSeconds}s',
        );
      }
      _nextBatchAllowedAt = DateTime.now().add(delay);
      rethrow;
    }
  }

  void _assignQueueSeq(Map<String, dynamic> point) {
    if (point['_queue_seq'] is int) return;
    point['_queue_seq'] = ++_nextQueueSeqId;
  }

  int? _queueSeqFromPoint(Map<String, dynamic> point) {
    final seq = point['_queue_seq'];
    if (seq is int) return seq;
    if (seq is num) return seq.toInt();
    return null;
  }

  String _queueSeqLabel(Map<String, dynamic> point, {int? fallbackIndex}) {
    final seq = _queueSeqFromPoint(point);
    if (seq != null) return '#$seq';
    if (fallbackIndex != null) return '#q${fallbackIndex + 1}';
    return '#?';
  }

  String _formatQueueSeqLabels(List<Map<String, dynamic>> points) {
    if (points.isEmpty) return '(none)';
    return points
        .asMap()
        .entries
        .map((e) => _queueSeqLabel(e.value, fallbackIndex: e.key))
        .join(',');
  }

  String _pendingQueueReason({bool force = false}) {
    if (_isFlushing) return 'flush_in_progress';
    final nextAllowed = _nextBatchAllowedAt;
    if (!force && nextAllowed != null && DateTime.now().isBefore(nextAllowed)) {
      return 'backoff_after_failed_upload';
    }

    final count = _queuedPointCount();
    if (count == 0) return 'queue_empty';
    if (!force && count < 2) {
      if (_isBatchIntervalElapsed()) {
        return 'waiting_for_second_point';
      }
      return 'waiting_for_second_point_or_1min_interval';
    }
    if (!force && !_isBatchIntervalElapsed() && count < _maxBatchSize) {
      return 'waiting_for_1min_interval_or_full_batch';
    }
    return 'ready_to_flush';
  }

  void _batchConsoleLog(String message) {
    if (!kDebugMode) return;
    // Filter debug console by: BatchQueue
    debugPrint('[BatchQueue] $message');
  }

  String _batchTotalsLabel() {
    return 'total_queued=$_totalBatchPointsQueued '
        'total_uploaded=$_totalBatchPointsUploaded';
  }

  void _logBatchQueueSnapshot(
    String action, {
    int? batchRun,
    String? uploadedIds,
    String? newPointId,
    String? detail,
  }) {
    if (!kDebugMode) return;

    final queuedCount = _queuedPointCount();
    final reason = _pendingQueueReason();

    _batchConsoleLog(
      'action=$action batchRun=${batchRun ?? '-'} '
      'queued=$queuedCount '
      '${_batchTotalsLabel()} '
      'reason=$reason'
      '${detail == null ? '' : ' | $detail'}'
      '${uploadedIds == null ? '' : ' uploaded_count=${uploadedIds.split(',').length}'}',
    );
  }

  void _logBatchUploadResult({
    required int batchRun,
    required List<Map<String, dynamic>> uploadedBatch,
    required Object? responseBody,
  }) {
    if (!kDebugMode) return;

    final uploadedCount = uploadedBatch.length;
    final remainingCount = _queuedPointCount();
    final reason = _pendingQueueReason();

    int? serverReceived;
    int? serverHistorySaved;
    int? serverHistorySkipped;
    if (responseBody is Map) {
      final received = responseBody['received_points_count'];
      final saved = responseBody['history_saved_count'];
      final skipped = responseBody['history_skipped_count'];
      if (received is num) serverReceived = received.toInt();
      if (saved is num) serverHistorySaved = saved.toInt();
      if (skipped is num) serverHistorySkipped = skipped.toInt();
    }

    _batchConsoleLog(
      'action=upload_ok batchRun=$batchRun '
      'uploaded=$uploadedCount '
      'server_received=${serverReceived ?? '?'} '
      'server_saved=${serverHistorySaved ?? '?'} '
      'server_skipped=${serverHistorySkipped ?? '?'} '
      'remaining=$remainingCount '
      '${_batchTotalsLabel()} reason=$reason',
    );
  }
}
