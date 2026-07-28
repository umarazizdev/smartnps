import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../auth/auth_repository.dart';
import '../location/adaptive_gps_stream_controller.dart';
import '../location/location_keep_point_gate.dart';
import '../location/mock_location_detection.dart';
import '../location/mock_location_guard.dart';
import '../location/speed_adaptive_gps_policy.dart';
import '../motion/motion_activity_fusion_controller.dart';
import 'background_location_accuracy.dart';
import 'background_location_uploader.dart';
import 'ios_background_location_notification.dart';
import 'ios_significant_location_change_service.dart';

/// iOS live location pings run on the main isolate. Background service isolates
/// cannot safely use flutter_local_notifications (objective_c crash).
class IosDutyLocationPinger {
  IosDutyLocationPinger._();

  static StreamSubscription<Position>? _subscription;
  static Timer? _pingTimer;
  static BackgroundLocationUploader? _uploader;
  static DateTime? _lastUploadAt;
  static final LocationKeepPointGate _keepPointGate = LocationKeepPointGate();
  static final AdaptiveGpsStreamController _streamController =
      AdaptiveGpsStreamController();
  static DateTime? _startedAt;
  static DateTime? _lastForcedBatchFlushAttemptAt;
  static bool _running = false;
  static bool _stopping = false;
  static bool _recoverInFlight = false;
  static bool _streamRebuildInFlight = false;
  static final SpeedAdaptiveGpsPolicyTracker _policyTracker =
      SpeedAdaptiveGpsPolicyTracker();

  static const Duration _recoverDelay = Duration(seconds: 2);
  static const Duration _staleLocationThreshold = Duration(minutes: 2);
  static const Duration _forcedBatchFlushEvery = Duration(seconds: 30);

  /// True only when the position stream subscription is active.
  static bool get isRunning => _running && _subscription != null;

  /// True when the stream is alive but has not produced a ping recently.
  static bool get needsRecovery {
    if (!Platform.isIOS || !isRunning) return false;
    final last = _lastUploadAt;
    if (last == null) {
      final started = _startedAt;
      if (started == null) return false;
      return DateTime.now().difference(started) > _staleLocationThreshold;
    }
    return DateTime.now().difference(last) > _staleLocationThreshold;
  }

  static Future<void> start() async {
    if (!Platform.isIOS) return;
    if (_running && _subscription != null) return;
    if (_running) {
      await stop();
    }

    try {
      _uploader = BackgroundLocationUploader();
      await _uploader!.init();
      _uploader!.start();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IosDutyLocationPinger] uploader init failed: $e');
      }
      rethrow;
    }

    unawaited(MotionActivityFusionController.instance.acquire());

    unawaited(
      IosBackgroundLocationNotification.show().catchError((Object e) {
        if (kDebugMode) {
          debugPrint('[IosDutyLocationPinger] notification failed: $e');
        }
      }),
    );

    _streamController
      ..reset()
      ..onSettingsChanged = () {
        unawaited(_rebuildStreamIfNeeded(reason: 'settings_changed'));
      };

    try {
      await _subscribePositionStream();
    } catch (e) {
      await stop();
      rethrow;
    }

    _running = true;
    _stopping = false;
    _startedAt = DateTime.now();
    unawaited(_startSignificantLocationChanges());
    _restartPeriodicPing();
    if (kDebugMode) {
      final permission = await Geolocator.checkPermission();
      debugPrint(
        '[IosDutyLocationPinger] started '
        '(interval=${_streamController.interval.inSeconds}s '
        'distanceFilter=${_streamController.distanceFilterMeters}m '
        'permission=$permission)',
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
          _onPosition,
          onError: (Object error) {
            if (kDebugMode) {
              debugPrint('[IosDutyLocationPinger] stream error: $error');
            }
            unawaited(_onStreamError(error));
          },
        );
    _streamController.markSettingsApplied();
  }

  static Future<void> _rebuildStreamIfNeeded({required String reason}) async {
    if (!_running || _stopping || _streamRebuildInFlight) return;
    _streamRebuildInFlight = true;
    try {
      if (kDebugMode) {
        debugPrint(
          '[IosDutyLocationPinger] rebuild stream reason=$reason '
          'interval=${_streamController.interval.inSeconds}s '
          'distanceFilter=${_streamController.distanceFilterMeters}m '
          'curveBoost=${_streamController.isCurveBoosting}',
        );
      }
      await _subscribePositionStream();
      _restartPeriodicPing();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IosDutyLocationPinger] stream rebuild failed: $e');
      }
    } finally {
      _streamRebuildInFlight = false;
    }
  }

  static Future<void> _startSignificantLocationChanges() async {
    try {
      final result = await IosSignificantLocationChangeService.start(
        onLocation: _onSignificantLocationWake,
      );
      if (kDebugMode) {
        debugPrint('[IosDutyLocationPinger] SLC start result: $result');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IosDutyLocationPinger] SLC start failed: $e');
      }
    }
  }

  /// Poll at the adaptive cadence so quiet streams still produce fixes.
  static void _restartPeriodicPing() {
    _pingTimer?.cancel();
    final every = _streamController.pollInterval;
    _pingTimer = Timer.periodic(every, (_) {
      unawaited(_pollCurrentPosition());
    });
    unawaited(_pollCurrentPosition());
  }

  static Future<void> _pollCurrentPosition() async {
    if (_stopping || !_running || _uploader == null) return;

    final pos = await _fetchPrecisePosition();
    if (pos != null) {
      await _onPosition(pos);
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
      // One-shot precise fetch — not the adaptive duty stream.
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
        debugPrint(
          '[IosDutyLocationPinger] precise fetch timed out; '
          'best acc=${fallback.accuracy}m rejected',
        );
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IosDutyLocationPinger] precise fetch failed: $e');
      }
      return null;
    } finally {
      await sub?.cancel();
    }
  }

  /// SLC is wake-only: do not upload coarse SLC fixes; fetch precise GPS instead.
  static Future<void> _onSignificantLocationWake(Position pos) async {
    if (_stopping) return;

    if (kDebugMode) {
      debugPrint(
        '[IosDutyLocationPinger] SLC wake acc=${pos.accuracy}m; '
        'requesting precise GPS (SLC coords not uploaded)',
      );
    }

    if (!isRunning) {
      if (_running) {
        unawaited(recoverIfNeeded());
      }
      return;
    }

    unawaited(_pollCurrentPosition());
  }

  /// Restarts the stream after permission changes or CoreLocation errors.
  static Future<void> recoverIfNeeded() async {
    if (!Platform.isIOS || _recoverInFlight) return;
    if (isRunning && !needsRecovery) return;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _recoverInFlight = true;
    try {
      if (kDebugMode) {
        debugPrint('[IosDutyLocationPinger] scheduling recovery');
      }
      await Future<void>.delayed(_recoverDelay);
      if (isRunning && !needsRecovery) return;

      await stop();
      await start();
      if (kDebugMode) {
        debugPrint('[IosDutyLocationPinger] recovery complete');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IosDutyLocationPinger] recovery failed: $e');
      }
    } finally {
      _recoverInFlight = false;
    }
  }

  static Future<void> _onStreamError(Object error) async {
    await _subscription?.cancel();
    _subscription = null;
    _running = false;

    if (kDebugMode) {
      debugPrint('[IosDutyLocationPinger] stream stopped after error');
    }

    unawaited(recoverIfNeeded());
  }

  static Future<void> _onPosition(Position pos) async {
    if (_stopping) return;

    if (!BackgroundLocationAccuracy.isAcceptable(pos)) {
      if (kDebugMode) {
        debugPrint(
          '[IosDutyLocationPinger] skipped inaccurate fix acc=${pos.accuracy}m',
        );
      }
      return;
    }

    final token = await AuthRepository.instance.ensureValidAccessToken();
    if (_stopping) return;
    if (token == null || token.isEmpty) {
      await stop();
      return;
    }

    final policyDecision = _policyTracker.evaluate(pos);
    final settingsChanged = _streamController.observe(pos, policyDecision);
    if (settingsChanged) {
      unawaited(_rebuildStreamIfNeeded(reason: 'policy_or_curve'));
    }

    final keepDecision = _keepPointGate.evaluate(
      pos,
      policyDecision,
      streamInterval: _streamController.interval,
    );
    if (!keepDecision.shouldKeep) {
      return;
    }
    if (_stopping) return;

    final motionFusion =
        await MotionActivityFusionController.instance.evaluatePosition(pos);
    if (_stopping) return;

    final mockFlags = MockLocationDetection.flagsFor(pos);
    if (mockFlags.isDetected) {
      MockLocationGuard.maybeShowDialog(
        isMocked: mockFlags.isMocked,
        isSimulatedBySoftware: mockFlags.isSimulatedBySoftware,
      );
    }

    if (kDebugMode) {
      debugPrint(
        '[IosDutyLocationPinger] location '
        'acc=${pos.accuracy} '
        'speedBand=${policyDecision.band.label} '
        'motion=${motionFusion.apiMotionActivity} '
        'fused=${motionFusion.fusedState} '
        'session=${motionFusion.active} '
        'reason=${motionFusion.reason} '
        'streamEvery=${_streamController.interval.inSeconds}s '
        'distanceFilter=${_streamController.distanceFilterMeters}m '
        'curveBoost=${_streamController.isCurveBoosting} '
        'trigger=${keepDecision.trigger?.name} '
        'dist=${keepDecision.distanceMeters?.toStringAsFixed(1)}m '
        'mocked=${mockFlags.isMocked} simulated=${mockFlags.isSimulatedBySoftware}',
      );
    }

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
      if (kDebugMode) {
        debugPrint('[IosDutyLocationPinger] upload failed: $e');
      }
    }
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
      // Drains pending SLC payloads through the wake handler (no SLC uploads).
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
    _streamController
      ..onSettingsChanged = null
      ..reset();
    await IosSignificantLocationChangeService.stop(drainPending: true);
    await _subscription?.cancel();
    _subscription = null;
    await _uploader?.stop();
    _uploader = null;
    _lastUploadAt = null;
    _startedAt = null;
    _lastForcedBatchFlushAttemptAt = null;
    _keepPointGate.reset();
    await MotionActivityFusionController.instance.release();

    try {
      await IosBackgroundLocationNotification.dismiss();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IosDutyLocationPinger] dismiss notification failed: $e');
      }
    }

    if (kDebugMode) {
      debugPrint('[IosDutyLocationPinger] stopped');
    }

    _stopping = false;
  }

  /// Stops GPS collection immediately without waiting for batch flush.
  static Future<void> stopCollectingOnly() async {
    if (!Platform.isIOS) return;
    if (!_running && _subscription == null && _uploader == null) return;

    _stopping = true;
    _running = false;
    _pingTimer?.cancel();
    _pingTimer = null;
    _streamController
      ..onSettingsChanged = null
      ..reset();
    await IosSignificantLocationChangeService.stop();
    await _subscription?.cancel();
    _subscription = null;
    await _uploader?.stopCollectingOnly();
    _uploader = null;
    _lastUploadAt = null;
    _startedAt = null;
    _lastForcedBatchFlushAttemptAt = null;
    _keepPointGate.reset();
    await MotionActivityFusionController.instance.release();

    try {
      await IosBackgroundLocationNotification.dismiss();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IosDutyLocationPinger] dismiss notification failed: $e');
      }
    }

    if (kDebugMode) {
      debugPrint('[IosDutyLocationPinger] stopped collecting (instant logout)');
    }

    _stopping = false;
  }
}
