import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../auth/auth_repository.dart';
import '../location/mock_location_detection.dart';
import '../location/mock_location_guard.dart';
import '../location/speed_adaptive_gps_policy.dart';
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
  static DateTime? _lastLocationAt;
  static DateTime? _lastUploadAt;
  static DateTime? _startedAt;
  static DateTime? _lastForcedBatchFlushAttemptAt;
  static bool _running = false;
  static bool _stopping = false;
  static bool _recoverInFlight = false;
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

    unawaited(
      IosBackgroundLocationNotification.show().catchError((Object e) {
        if (kDebugMode) {
          debugPrint('[IosDutyLocationPinger] notification failed: $e');
        }
      }),
    );

    final permission = await Geolocator.checkPermission();
    final allowBackground = permission == LocationPermission.always;

    final settings = AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
      allowBackgroundLocationUpdates: allowBackground,
    );

    try {
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
    } catch (e) {
      await stop();
      rethrow;
    }

    _running = true;
    _stopping = false;
    _startedAt = DateTime.now();
    unawaited(_startSignificantLocationChanges());
    _startPeriodicPing();
    if (kDebugMode) {
      debugPrint(
        '[IosDutyLocationPinger] started '
        '(allowBackground=$allowBackground permission=$permission)',
      );
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

  /// iOS may not emit stream events when the device is stationary (simulator).
  /// Poll explicitly so ping/batch keep running on the duty ping interval.
  static void _startPeriodicPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(BackgroundLocationUploader.pingInterval, (_) {
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
    if (token == null || token.isEmpty) {
      await stop();
      return;
    }

    final now = DateTime.now();
    final policyDecision = _policyTracker.evaluate(pos);
    final last = _lastLocationAt;
    if (last != null &&
        now.difference(last) < policyDecision.band.uploadInterval) {
      return;
    }
    _lastLocationAt = now;

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
        'uploadEvery=${policyDecision.band.uploadInterval.inSeconds}s '
        'mocked=${mockFlags.isMocked} simulated=${mockFlags.isSimulatedBySoftware}',
      );
    }

    final uploader = _uploader;
    if (uploader == null) return;

    try {
      await uploader.pingNow(pos, policyDecision: policyDecision);
      await uploader.add(pos, policyDecision: policyDecision);
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
    await IosSignificantLocationChangeService.stop(drainPending: true);
    await _subscription?.cancel();
    _subscription = null;
    await _uploader?.stop();
    _uploader = null;
    _lastLocationAt = null;
    _lastUploadAt = null;
    _startedAt = null;
    _lastForcedBatchFlushAttemptAt = null;

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

    _running = false;
    _pingTimer?.cancel();
    _pingTimer = null;
    await IosSignificantLocationChangeService.stop();
    await _subscription?.cancel();
    _subscription = null;
    await _uploader?.stopCollectingOnly();
    _uploader = null;
    _lastLocationAt = null;
    _lastUploadAt = null;
    _startedAt = null;
    _lastForcedBatchFlushAttemptAt = null;

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
  }
}
