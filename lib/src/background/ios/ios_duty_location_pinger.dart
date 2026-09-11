import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../../auth/auth_repository.dart';
import '../../location/adaptive_gps_stream_controller.dart';
import '../../location/duty_location_upload_gate.dart';
import '../../location/mock_location_detection.dart';
import '../../location/mock_location_guard.dart';
import '../../location/speed_adaptive_gps_policy.dart';
import '../../motion/motion_activity_fusion_controller.dart';
import '../../utilities/device_identity.dart';
import '../duty/duty_status_snapshot.dart';
import '../location/background_location_accuracy.dart';
import '../location/background_location_uploader.dart';
import '../location/location_sharing_status_notification.dart';
import 'ios_background_location_notification.dart';
import 'ios_significant_location_change_service.dart';
import '../../utilities/app_debug_log.dart';

class IosDutyLocationPinger {
  IosDutyLocationPinger._();

  static StreamSubscription<Position>? _subscription;
  static Timer? _pingTimer;
  static bool _precisePollInFlight = false;
  static BackgroundLocationUploader? _uploader;
  static DateTime? _lastUploadAt;
  static Position? _latestAcceptedPosition;
  static final AdaptiveGpsStreamController _streamController =
      AdaptiveGpsStreamController();
  static DateTime? _lastForcedBatchFlushAttemptAt;
  static bool _running = false;
  static bool _stopping = false;
  static bool _recoverInFlight = false;
  static bool _streamRebuildInFlight = false;
  static bool? _subscribedAllowBackground;
  static Duration? _appliedPollInterval;
  static final SpeedAdaptiveGpsPolicyTracker _policyTracker =
      SpeedAdaptiveGpsPolicyTracker();
  static final DutyLocationUploadGate _uploadGate = DutyLocationUploadGate();
  static int _streamQueueCountWindow = 0;
  static DateTime? _streamQueueWindowStartedAt;
  static int _streamSkipCountWindow = 0;

  static Future<bool> Function()? confirmOnDutyBeforeStart;

  static const Duration _recoverDelay = Duration(seconds: 2);
  static const Duration _forcedBatchFlushEvery = Duration(seconds: 30);

  static bool get isRunning => _running && _subscription != null;

  static Position? get latestAcceptedPosition => _latestAcceptedPosition;

  static bool get needsRecovery {
    if (!Platform.isIOS || _stopping) return false;
    if (isRunning) return false;
    return _running && _subscription == null;
  }

  static Future<void> start() async {
    if (!Platform.isIOS) return;
    if (_running && _subscription != null) return;
    if (_running) {
      await stop();
    }

    final confirm = confirmOnDutyBeforeStart;
    if (confirm == null) {
      if (kDebugMode) {
        locationDebugLog(
          '[DutyLocation] NOT RUNNING: start blocked (no duty confirmation hook)',
        );
        locationDebugLog(
          '[IosDutyLocationPinger] start blocked; no duty confirmation hook',
        );
      }
      return;
    }
    final allowed = await confirm();
    if (!allowed) {
      if (kDebugMode) {
        locationDebugLog(
          '[DutyLocation] NOT RUNNING: start blocked (duty not on_duty)',
        );
        locationDebugLog(
          '[IosDutyLocationPinger] start blocked; heartbeat is not on_duty',
        );
      }
      await IosSignificantLocationChangeService.setOnDuty(false);
      return;
    }

    await IosSignificantLocationChangeService.setOnDuty(true);
    unawaited(() async {
      await IosSignificantLocationChangeService.syncNativeAuth(
        accessToken: await AuthRepository.instance.getAccessToken(),
        refreshToken: await AuthRepository.instance.getRefreshToken(),
        deviceId: await DeviceIdentity.getDeviceId(),
      );
    }());

    try {
      _uploader = BackgroundLocationUploader();
      await _uploader!.init();
      _uploader!.start();
    } catch (e) {
      locationDebugLog('[IosDutyLocationPinger] uploader init failed: $e');
      rethrow;
    }

    unawaited(MotionActivityFusionController.instance.acquire());

    unawaited(
      IosBackgroundLocationNotification.show().catchError((Object e) {
        locationDebugLog('[IosDutyLocationPinger] notification failed: $e');
      }),
    );

    _streamController.reset();

    _streamController.onSettingsChanged = _syncPollIntervalIfNeeded;

    try {
      await _subscribePositionStream();
    } catch (e) {
      await stop();
      rethrow;
    }

    _running = true;
    _stopping = false;
    unawaited(
      LocationSharingStatusNotification.showBgLocationStartedTestAlert()
          .catchError((Object e) {
        locationDebugLog(
          '[IosDutyLocationPinger] bg start test alert failed: $e',
        );
      }),
    );
    unawaited(_startSignificantLocationChanges());
    _restartPeriodicPing();
    if (kDebugMode) {
      final permission = await Geolocator.checkPermission();
      locationDebugLog(
        '[DutyLocation] RUNNING (iOS) '
        'lockedFilter=${AdaptiveGpsStreamController.iosLockedDistanceFilterMeters}m '
        'speedPoll=true '
        'permission=$permission '
        'bgUpdates=${permission == LocationPermission.always}',
      );
      locationDebugLog(
        '[IosDutyLocationPinger] started '
        '(lockedFilter=${AdaptiveGpsStreamController.iosLockedDistanceFilterMeters}m '
        'permission=$permission)',
      );
      locationDebugLog(
        '[IosDutyLocationPinger] RATE NOTE: distanceFilter=0 keeps the GPS '
        'stream live without rebuilds; ping+queue is gated by speed/curve '
        'captureInterval (stationary ~30s, walking ~10s, curve boost ~1s). '
        'Near-location filtering stays on backend/admin.',
      );
    }
  }

  static Future<void> _subscribePositionStream() async {
    final permission = await Geolocator.checkPermission();
    final allowBackground = permission == LocationPermission.always;
    final settings = _streamController.buildLocationSettings(
      allowBackgroundLocationUpdates: allowBackground,
    );

    await _subscription?.cancel();
    _subscription = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
          (pos) => unawaited(_onPosition(pos, source: 'flutter_stream')),
          onError: (Object error) {
            locationDebugLog('[IosDutyLocationPinger] stream error: $error');
            unawaited(_onStreamError(error));
          },
        );
    _subscribedAllowBackground = allowBackground;
    _streamController.markSettingsApplied();
  }

  static Future<void> _rebuildStreamIfNeeded({required String reason}) async {
    if (!_running || _stopping || _streamRebuildInFlight) return;
    _streamRebuildInFlight = true;
    try {
      final permission = await Geolocator.checkPermission();
      final allowBackground = permission == LocationPermission.always;
      final alreadyLive =
          _subscription != null &&
          _subscribedAllowBackground == allowBackground;
      if (alreadyLive) {
        locationDebugLog(
          '[IosDutyLocationPinger] skip rebuild reason=$reason '
          '(live stream kept, filter='
          '${AdaptiveGpsStreamController.iosLockedDistanceFilterMeters}m)',
        );
        return;
      }
      locationDebugLog(
        '[IosDutyLocationPinger] resubscribe reason=$reason '
        'allowBackground=$allowBackground',
      );
      await _subscribePositionStream();
    } catch (e) {
      locationDebugLog('[IosDutyLocationPinger] stream resubscribe failed: $e');
    } finally {
      _streamRebuildInFlight = false;
    }
  }

  static Future<void> rebuildForCurrentPermission({
    required String reason,
  }) async {
    if (!Platform.isIOS) return;
    if (!_running || _stopping) return;
    await _rebuildStreamIfNeeded(reason: reason);
  }

  static Future<void> _startSignificantLocationChanges() async {
    try {
      final result = await IosSignificantLocationChangeService.start(
        onLocation: _onNativeLocation,
      );
      locationDebugLog('[IosDutyLocationPinger] SLC start result: $result');
    } catch (e) {
      locationDebugLog('[IosDutyLocationPinger] SLC start failed: $e');
    }
  }

  static void _restartPeriodicPing() {
    _pingTimer?.cancel();
    final every = _streamController.pollInterval;
    _appliedPollInterval = every;
    _pingTimer = Timer.periodic(every, (_) {
      unawaited(_pollCurrentPosition(onlyIfQuiet: true));
    });

  }

  static void _syncPollIntervalIfNeeded() {
    final every = _streamController.pollInterval;
    if (_appliedPollInterval == every) return;
    locationDebugLog(
      '[IosDutyLocationPinger] poll interval '
      '${_appliedPollInterval?.inSeconds ?? '-'}s → ${every.inSeconds}s '
      '(speed band, stream not rebuilt)',
    );
    _restartPeriodicPing();
  }

  static Future<void> _pollCurrentPosition({bool onlyIfQuiet = false}) async {
    if (_stopping || !_running || _uploader == null || _precisePollInFlight) {
      return;
    }

    if (_subscription != null) {
      return;
    }
    if (onlyIfQuiet) {
      final last = _lastUploadAt;
      final quietFor = _streamController.pollInterval;
      if (last != null && DateTime.now().difference(last) < quietFor) {
        return;
      }
    }
    _precisePollInFlight = true;
    locationDebugLog(
      '[IosDutyLocationPinger] precise_poll START '
      'why=flutter_stream_not_subscribed '
      'pollEvery=${_streamController.pollInterval.inSeconds}s '
      'onlyIfQuiet=$onlyIfQuiet',
    );
    try {
      final pos = await _fetchPrecisePosition();
      if (pos != null) {
        await _onPosition(pos, source: 'precise_poll');
      }
    } finally {
      _precisePollInFlight = false;
    }
  }

  static Future<Position?> _fetchPrecisePosition({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (_stopping || !_running) return null;

    StreamSubscription<Position>? sub;
    Position? bestSeen;

    try {
      final permission = await Geolocator.checkPermission();
      final allowBackground = permission == LocationPermission.always;

      final settings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: allowBackground,
        timeLimit: timeout,
      );

      final completer = Completer<Position>();
      sub = Geolocator.getPositionStream(locationSettings: settings).listen(
        (position) {
          if (completer.isCompleted) return;

          if (bestSeen == null || position.accuracy < bestSeen!.accuracy) {
            bestSeen = position;
          }
          if (BackgroundLocationAccuracy.isAcceptable(position)) {
            completer.complete(position);
          }
        },
        onError: (Object error) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
      );

      return await completer.future.timeout(timeout);
    } on TimeoutException {
      final fallback = bestSeen;
      if (fallback != null &&
          BackgroundLocationAccuracy.isAcceptable(fallback)) {
        return fallback;
      }
      if (kDebugMode && fallback != null) {
        locationDebugLog(
          '[IosDutyLocationPinger] precise fetch timed out; '
          'best acc=${fallback.accuracy}m rejected',
        );
      }
      return null;
    } catch (e) {
      locationDebugLog('[IosDutyLocationPinger] precise fetch failed: $e');
      return null;
    } finally {
      await sub?.cancel();
    }
  }

  static Future<void> _onNativeLocation(Position pos, String source) async {
    if (_stopping) return;

    if (source == 'ios_slc' || source == 'ios_geofence') {
      locationDebugLog(
        '[IosDutyLocationPinger] $source wake acc=${pos.accuracy}m; '
        'polling latest GPS (wake coords not uploaded)',
      );
      if (!isRunning) {

        unawaited(recoverIfNeeded(fromLocationWake: true));
        return;
      }

      if (_subscription != null) return;
      unawaited(_pollCurrentPosition(onlyIfQuiet: true));
      return;
    }

    if (source == 'ios_gps' && isRunning) {

      return;
    }

    await _onPosition(pos, source: source);
  }

  static Future<void> recoverIfNeeded({
    bool fromLocationWake = false,
    bool dutyAlreadyConfirmed = false,
  }) async {
    if (!Platform.isIOS || _recoverInFlight) return;
    if (isRunning) return;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (fromLocationWake) {
        locationDebugLog(
          '[IosDutyLocationPinger] location wake blocked; permission=$permission',
        );
        await stop();
      }
      return;
    }

    _recoverInFlight = true;
    try {
      locationDebugLog('[IosDutyLocationPinger] scheduling recovery');
      if (!fromLocationWake) {
        await Future<void>.delayed(_recoverDelay);
        if (isRunning) return;
      }

      if (!dutyAlreadyConfirmed) {
        final confirm = confirmOnDutyBeforeStart;
        if (confirm == null) {
          locationDebugLog(
            '[IosDutyLocationPinger] recovery blocked; no duty confirmation hook',
          );
          await stop();
          return;
        }
        final allowed = await confirm();
        if (!allowed) {
          locationDebugLog(
            '[IosDutyLocationPinger] recovery blocked; heartbeat is not on_duty',
          );
          await stop();
          return;
        }
      }

      if (_running && _subscription == null) {
        await _rebuildStreamIfNeeded(reason: 'subscription_missing');
        locationDebugLog('[IosDutyLocationPinger] resubscribed dead stream');
        return;
      }

      if (_running) return;

      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final uiBackgrounded =
          lifecycle == AppLifecycleState.paused ||
          lifecycle == AppLifecycleState.hidden ||
          lifecycle == AppLifecycleState.inactive;
      if (uiBackgrounded) {
        locationDebugLog(
          '[IosDutyLocationPinger] starting after wake (UI backgrounded)',
        );
      }

      final previousConfirm = confirmOnDutyBeforeStart;
      confirmOnDutyBeforeStart = () async => true;
      try {
        await start();
      } finally {
        confirmOnDutyBeforeStart = previousConfirm;
      }
      locationDebugLog('[IosDutyLocationPinger] recovery complete');
    } catch (e) {
      locationDebugLog('[IosDutyLocationPinger] recovery failed: $e');
    } finally {
      _recoverInFlight = false;
    }
  }

  static Future<void> _onStreamError(Object error) async {
    await _subscription?.cancel();
    _subscription = null;
    _subscribedAllowBackground = null;

    locationDebugLog('[IosDutyLocationPinger] stream stopped after error');

    if (_stopping || !_running) return;
    unawaited(_rebuildStreamIfNeeded(reason: 'stream_error'));
  }

  static Future<void> _onPosition(
    Position pos, {
    String source = 'flutter_stream',
  }) async {
    if (_stopping) return;

    if (!BackgroundLocationAccuracy.isAcceptable(pos)) {
      locationDebugLog(
        '[IosDutyLocationPinger] skipped inaccurate fix acc=${pos.accuracy}m '
        'source=$source',
      );
      return;
    }
    _latestAcceptedPosition = pos;
    unawaited(DutyStatusSnapshot.renewIfStillOnDuty());

    final token = await AuthRepository.instance.ensureValidAccessToken();
    if (_stopping) return;
    if (token == null || token.isEmpty) {
      final refresh = await AuthRepository.instance.getRefreshToken();
      if (refresh == null || refresh.isEmpty) {
        await stop();
        return;
      }
      locationDebugLog(
        '[IosDutyLocationPinger] auth transient fail; keeping GPS, skipping upload',
      );
      return;
    }

    final policyDecision = _policyTracker.evaluate(pos);
    final wasCurveBoosting = _streamController.isCurveBoosting;
    _streamController.observe(pos, policyDecision);
    _syncPollIntervalIfNeeded();
    if (!wasCurveBoosting && _streamController.isCurveBoosting) {
      locationDebugLog(
        '[IosDutyLocationPinger] curve boost poll → '
        '${_streamController.pollInterval.inSeconds}s '
        '(stream not rebuilt)',
      );
    }
    if (_stopping) return;

    final motionFusion = await MotionActivityFusionController.instance
        .evaluatePosition(pos);
    if (_stopping) return;

    final mockFlags = MockLocationDetection.flagsFor(pos);
    if (mockFlags.isDetected) {
      MockLocationGuard.maybeShowDialog(
        isMocked: mockFlags.isMocked,
        isSimulatedBySoftware: mockFlags.isSimulatedBySoftware,
      );
    }

    final captureEvery = _streamController.pollInterval;
    if (!_uploadGate.tryAccept(captureEvery)) {
      _streamSkipCountWindow++;
      _noteStreamQueueRate(source, queued: false);
      return;
    }

    final why = switch (source) {
      'flutter_stream' =>
        'speed_gate_ok(captureEvery=${captureEvery.inSeconds}s)',
      'precise_poll' => 'quiet_timer_or_wake_gap_fill',
      'ios_gps' => 'native_keepalive_while_flutter_not_running',
      _ => 'native_$source',
    };

    locationDebugLog(
      '[IosDutyLocationPinger] QUEUE '
      'source=$source '
      'why=$why '
      'acc=${pos.accuracy.toStringAsFixed(1)}m '
      'band=${policyDecision.band.label} '
      'motion=${motionFusion.apiMotionActivity} '
      'fused=${motionFusion.fusedState} '
      'captureEvery=${captureEvery.inSeconds}s '
      'distanceFilter=${AdaptiveGpsStreamController.iosLockedDistanceFilterMeters}m '
      'curveBoost=${_streamController.isCurveBoosting} '
      'mocked=${mockFlags.isMocked}',
    );
    _noteStreamQueueRate(source, queued: true);

    final uploader = _uploader;
    if (uploader == null || _stopping) return;

    try {
      if (_stopping) return;
      await uploader.pingNow(
        pos,
        policyDecision: policyDecision,
        motionFusion: motionFusion,
      );
      if (_stopping) return;
      await uploader.add(
        pos,
        policyDecision: policyDecision,
        motionFusion: motionFusion,
      );
      _lastUploadAt = DateTime.now();
      await _flushBatchIfDue(uploader);
    } catch (e) {
      locationDebugLog('[IosDutyLocationPinger] upload failed: $e');
    }
  }

  static void _noteStreamQueueRate(String source, {required bool queued}) {
    if (source != 'flutter_stream') return;
    final now = DateTime.now();
    final started = _streamQueueWindowStartedAt;
    if (started == null) {
      _streamQueueWindowStartedAt = now;
      _streamQueueCountWindow = queued ? 1 : 0;
      _streamSkipCountWindow = queued ? 0 : 1;
      return;
    }
    if (queued) {
      _streamQueueCountWindow++;
    }
    final elapsed = now.difference(started);
    if (elapsed < const Duration(seconds: 10)) return;
    locationDebugLog(
      '[IosDutyLocationPinger] RATE last ${elapsed.inSeconds}s: '
      'queued=$_streamQueueCountWindow skipped=$_streamSkipCountWindow '
      'captureEvery=${_streamController.pollInterval.inSeconds}s '
      'band=${_streamController.band.label} '
      '(stream still ~1Hz; uploads gated by captureInterval)',
    );
    _streamQueueWindowStartedAt = now;
    _streamQueueCountWindow = 0;
    _streamSkipCountWindow = 0;
  }

  static Future<void> _flushBatchIfDue(
    BackgroundLocationUploader uploader,
  ) async {
    final now = DateTime.now();
    final lastAttempt = _lastForcedBatchFlushAttemptAt;
    if (lastAttempt != null &&
        now.difference(lastAttempt) < _forcedBatchFlushEvery) {
      return;
    }

    _lastForcedBatchFlushAttemptAt = now;
    await uploader.flushBatch(force: true);
  }

  static Future<void> flushPendingBatchNow({
    bool drainNativePending = true,
  }) async {
    if (!Platform.isIOS) return;

    if (drainNativePending) {
      await IosSignificantLocationChangeService.drainPendingLocations();
    }

    final uploader = _uploader;
    if (uploader != null) {
      _lastForcedBatchFlushAttemptAt = DateTime.now();
      await uploader.flushBatch(force: true);
      return;
    }

    await BackgroundLocationUploader.flushPendingBatchesStatic();
  }

  static Future<void> stop() async {
    if (!Platform.isIOS) return;
    if (_stopping) return;

    _stopping = true;
    _running = false;
    _pingTimer?.cancel();
    _pingTimer = null;
    _precisePollInFlight = false;
    _appliedPollInterval = null;
    _streamController
      ..onSettingsChanged = null
      ..reset();
    _subscribedAllowBackground = null;
    await IosSignificantLocationChangeService.stop(drainPending: true);
    await _subscription?.cancel();
    _subscription = null;
    await _uploader?.stop();
    _uploader = null;
    _lastUploadAt = null;
    _latestAcceptedPosition = null;
    _lastForcedBatchFlushAttemptAt = null;
    _streamQueueCountWindow = 0;
    _streamSkipCountWindow = 0;
    _streamQueueWindowStartedAt = null;
    _uploadGate.reset();
    await MotionActivityFusionController.instance.release();

    try {
      await LocationSharingStatusNotification.dismissSharing();
    } catch (e) {
      locationDebugLog('[IosDutyLocationPinger] dismiss sharing failed: $e');
    }

    if (kDebugMode) {
      locationDebugLog('[DutyLocation] STOPPED (iOS)');
      locationDebugLog('[IosDutyLocationPinger] stopped');
    }

    _stopping = false;
  }

  static Future<void> stopCollectingOnly() async {
    if (!Platform.isIOS) return;
    if (!_running && _subscription == null && _uploader == null) {
      await IosSignificantLocationChangeService.setOnDuty(false);
      locationDebugLog('[DutyLocation] STOPPED already (iOS collecting clear)');
      return;
    }

    _stopping = true;
    _running = false;
    _pingTimer?.cancel();
    _pingTimer = null;
    _precisePollInFlight = false;
    _appliedPollInterval = null;
    _streamController
      ..onSettingsChanged = null
      ..reset();
    _subscribedAllowBackground = null;
    await IosSignificantLocationChangeService.stop();
    await _subscription?.cancel();
    _subscription = null;
    await _uploader?.stopCollectingOnly();
    _uploader = null;
    _lastUploadAt = null;
    _latestAcceptedPosition = null;
    _lastForcedBatchFlushAttemptAt = null;
    _streamQueueCountWindow = 0;
    _streamSkipCountWindow = 0;
    _streamQueueWindowStartedAt = null;
    _uploadGate.reset();
    await MotionActivityFusionController.instance.release();

    try {
      await LocationSharingStatusNotification.dismissSharing();
    } catch (e) {
      locationDebugLog('[IosDutyLocationPinger] dismiss sharing failed: $e');
    }

    if (kDebugMode) {
      locationDebugLog(
        '[DutyLocation] STOPPED (iOS instant logout / collecting only)',
      );
      locationDebugLog(
        '[IosDutyLocationPinger] stopped collecting (instant logout)',
      );
    }

    _stopping = false;
  }
}
