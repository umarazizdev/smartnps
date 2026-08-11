import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import '../../location/adaptive_gps_stream_controller.dart';
import '../../location/location_keep_point_gate.dart';
import '../../location/mock_location_detection.dart';
import '../../location/speed_adaptive_gps_policy.dart';
import '../../auth/auth_repository.dart';
import '../../motion/motion_activity_fusion_controller.dart';
import '../duty/duty_status_snapshot.dart';
import 'android_duty_location_health.dart';
import 'background_location_accuracy.dart';
import 'background_location_uploader.dart';

@pragma('vm:entry-point')
class BackgroundLocationService {
  static const String _channelId = 'smartnps360_location';
  static const int _notificationId = 9911;
  /// Kick a one-shot GPS fix if no acceptable upload for this long.
  static const Duration _forcePollAfter = Duration(seconds: 45);
  /// Only cancel/resubscribe the stream if no fix of any accuracy for this long.
  static const Duration _rebuildStreamAfter = Duration(minutes: 3);
  static const Duration _bgForcePollEvery = Duration(seconds: 15);

  static bool _configured = false;
  static Future<void>? _configureFuture;

  static Future<void> ensureConfigured() async {
    if (_configured) return;
    final inFlight = _configureFuture;
    if (inFlight != null) return inFlight;

    final future = _configureImpl();
    _configureFuture = future;
    try {
      await future;
      _configured = true;
      // Stop leftover FGS only when off-duty (no valid snapshot). If still
      // on_duty, keep the service so hot-restart does not kill live GPS.
      await _reconcileLeftoverFgsWithDutySnapshot();
    } finally {
      if (identical(_configureFuture, future)) {
        _configureFuture = null;
      }
    }
  }

  static Future<void> _reconcileLeftoverFgsWithDutySnapshot() async {
    try {
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) return;

      final onDuty = await DutyStatusSnapshot.isValidOnDutyForCurrentUser();
      if (onDuty) {
        AndroidDutyLocationHealth.ensureListenerInstalled();
        final now = DateTime.now();
        AndroidDutyLocationHealth.markStarted(at: now);
        unawaited(AndroidDutyLocationHealth.persistStarted(now));
        unawaited(AndroidDutyLocationHealth.hydrateFromPrefs());
        if (kDebugMode) {
          debugPrint(
            '[DutyLocation] cold start: keeping leftover Android FGS '
            '(valid on_duty snapshot)',
          );
        }
        return;
      }

      if (kDebugMode) {
        debugPrint(
          '[DutyLocation] cold start: stopping leftover Android FGS '
          '(no valid on_duty snapshot)',
        );
      }
      service.invoke('stop');
      AndroidDutyLocationHealth.markStopped();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DutyLocation] cold start leftover reconcile failed: $e');
      }
    }
  }

  static Future<void> _configureImpl() async {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        foregroundServiceNotificationId: _notificationId,
        notificationChannelId: _channelId,
        foregroundServiceTypes: const [AndroidForegroundType.location],
        initialNotificationTitle: 'On Duty • Location Active',
        initialNotificationContent:
            'Your live location is being shared while you are on duty.',
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<void> configureAndStart() async {
    await ensureConfigured();
    await FlutterBackgroundService().startService();
  }

  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) async {
    // Plugins (Geolocator, motion activity, etc.) are registered by the
    // background FlutterEngine / package entrypoint. Do not call
    // DartPluginRegistrant.ensureInitialized() here — that re-inits
    // flutter_background_service_android on this isolate and throws:
    // "This class should only be used in the main isolate".
    if (kDebugMode) {
      debugPrint('[DutyLocation] RUNNING (Android background service onStart)');
    }

    // Hard gate: never collect GPS unless a valid on_duty snapshot exists.
    if (!await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) {
      if (kDebugMode) {
        debugPrint(
          '[DutyLocation] Android FGS start aborted; no valid on_duty snapshot',
        );
      }
      service.stopSelf();
      return;
    }

    final uploader = BackgroundLocationUploader();
    await uploader.init();
    uploader.start();

    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }

    service.invoke(AndroidDutyLocationHealth.startedEvent, {
      'at': DateTime.now().toIso8601String(),
    });
    unawaited(AndroidDutyLocationHealth.persistStarted(DateTime.now()));

    StreamSubscription<Position>? sub;
    var stopping = false;
    var streamRebuildInFlight = false;
    var forcePollInFlight = false;
    var appInBackground = false;
    DateTime? lastAcceptedFixAt;
    DateTime? lastAnyFixAt;
    final startedAt = DateTime.now();
    final policyTracker = SpeedAdaptiveGpsPolicyTracker();
    final keepPointGate = LocationKeepPointGate();
    final streamController = AdaptiveGpsStreamController();
    unawaited(MotionActivityFusionController.instance.acquire());

    late final Future<void> Function() stop;
    late final Future<void> Function({required String reason})
        rebuildStreamIfNeeded;
    late final Future<void> Function() subscribePositionStream;
    late final Future<void> Function(Position pos) handlePosition;
    late final Future<void> Function({required String reason}) forcePoll;

    Timer? healthTimer;
    Timer? bgForcePollTimer;

    void stopBgForcePoll() {
      bgForcePollTimer?.cancel();
      bgForcePollTimer = null;
    }

    void startBgForcePoll() {
      stopBgForcePoll();
      bgForcePollTimer = Timer.periodic(_bgForcePollEvery, (_) {
        if (stopping || !appInBackground) return;
        unawaited(forcePoll(reason: 'bg_keep_alive'));
      });
    }

    handlePosition = (Position pos) async {
      if (stopping) return;
      lastAnyFixAt = DateTime.now();

      // Off-duty / snapshot cleared → stop immediately (no fetch/upload).
      if (!await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) {
        if (kDebugMode) {
          debugPrint(
            '[DutyLocation] Android FGS stopping; on_duty snapshot gone',
          );
        }
        await stop();
        return;
      }

      if (!BackgroundLocationAccuracy.isAcceptable(pos)) {
        return;
      }
      lastAcceptedFixAt = DateTime.now();

      final token = await AuthRepository.instance.ensureValidAccessToken();
      if (stopping) return;
      if (token == null || token.isEmpty) {
        await stop();
        return;
      }

      final policyDecision = policyTracker.evaluate(pos);
      final settingsChanged = streamController.observe(pos, policyDecision);
      // Avoid stream tear-down while backgrounded — that creates multi-minute gaps.
      if (settingsChanged && !appInBackground) {
        unawaited(rebuildStreamIfNeeded(reason: 'policy_or_curve'));
      }

      final keepDecision = keepPointGate.evaluate(
        pos,
        policyDecision,
        streamInterval: streamController.interval,
      );
      if (!keepDecision.shouldKeep) {
        return;
      }
      if (stopping) return;

      final motionFusion =
          await MotionActivityFusionController.instance.evaluatePosition(pos);
      if (stopping) return;

      final mockFlags = MockLocationDetection.flagsFor(pos);
      if (mockFlags.isDetected) {
        service.invoke('mock_location', {
          'isMocked': mockFlags.isMocked,
          'isSimulatedBySoftware': mockFlags.isSimulatedBySoftware,
          'timestamp': pos.timestamp.toIso8601String(),
        });
      }

      try {
        if (stopping) return;
        await uploader.pingNow(
          pos,
          policyDecision: policyDecision,
          motionFusion: motionFusion,
        );
        if (stopping) return;
        await uploader.add(
          pos,
          policyDecision: policyDecision,
          motionFusion: motionFusion,
        );
        service.invoke(AndroidDutyLocationHealth.uploadEvent, {
          'at': DateTime.now().toIso8601String(),
        });
        unawaited(AndroidDutyLocationHealth.persistUpload(DateTime.now()));
        if (kDebugMode) {
          debugPrint(
            '[DutyLocation] Android upload ok '
            'acc=${pos.accuracy.toStringAsFixed(1)}m',
          );
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[DutyLocation] Android upload failed: $e');
        }
      }
    };

    forcePoll = ({required String reason}) async {
      if (stopping || forcePollInFlight) return;
      forcePollInFlight = true;
      try {
        if (kDebugMode) {
          debugPrint('[DutyLocation] Android force GPS poll ($reason)');
        }
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            timeLimit: const Duration(seconds: 20),
          ),
        );
        if (stopping) return;
        await handlePosition(pos);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[DutyLocation] Android force poll failed: $e');
        }
      } finally {
        forcePollInFlight = false;
      }
    };

    healthTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (stopping) return;
      final now = DateTime.now();
      final lastAccepted = lastAcceptedFixAt ?? startedAt;
      final lastAny = lastAnyFixAt ?? startedAt;

      // Prefer a one-shot poll — never tear down a live stream just because
      // acceptable uploads paused (common while the UI is backgrounded).
      if (now.difference(lastAccepted) > _forcePollAfter) {
        unawaited(forcePoll(reason: 'stale_accepted_fix'));
      }

      // Only rebuild if the stream appears completely dead.
      if (now.difference(lastAny) > _rebuildStreamAfter) {
        unawaited(rebuildStreamIfNeeded(reason: 'stream_dead'));
      }
    });

    stop = () async {
      if (stopping) return;
      stopping = true;
      healthTimer?.cancel();
      healthTimer = null;
      stopBgForcePoll();
      if (kDebugMode) {
        debugPrint('[DutyLocation] STOPPED (Android background service)');
      }
      streamController
        ..onSettingsChanged = null
        ..reset();
      await sub?.cancel();
      sub = null;

      await uploader.stopCollectingOnly();
      await MotionActivityFusionController.instance.release();
      service.stopSelf();
      unawaited(
        uploader.flushAllPendingBatchesBounded(
          timeout: BackgroundLocationUploader.logoutFlushBudget,
        ),
      );
    };

    rebuildStreamIfNeeded = ({required String reason}) async {
      if (stopping || streamRebuildInFlight) return;
      streamRebuildInFlight = true;
      try {
        if (kDebugMode) {
          debugPrint('[DutyLocation] rebuilding Android GPS stream ($reason)');
        }
        await subscribePositionStream();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[DutyLocation] Android stream rebuild failed: $e');
        }
      } finally {
        streamRebuildInFlight = false;
      }
    };

    subscribePositionStream = () async {
      // While backgrounded, use aggressive cadence so OEM throttling is less likely.
      final settings = appInBackground
          ? AndroidSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 0,
              intervalDuration: const Duration(seconds: 5),
              timeLimit: null,
              forceLocationManager: false,
            )
          : streamController.buildLocationSettings(
              allowBackgroundLocationUpdates: true,
            );
      await sub?.cancel();
      sub = Geolocator.getPositionStream(locationSettings: settings).listen(
        (pos) {
          unawaited(handlePosition(pos));
        },
        onError: (Object error) {
          if (kDebugMode) {
            debugPrint('[DutyLocation] Android GPS stream error: $error');
          }
          // Don't tear down on error while backgrounded — force-poll instead.
          if (appInBackground) {
            unawaited(forcePoll(reason: 'stream_error_bg'));
          } else {
            unawaited(rebuildStreamIfNeeded(reason: 'stream_error'));
          }
        },
      );
      streamController.markSettingsApplied();
    };

    streamController.onSettingsChanged = () {
      if (appInBackground) return;
      unawaited(rebuildStreamIfNeeded(reason: 'settings_changed'));
    };

    service.on('stop').listen((event) {
      unawaited(stop());
    });

    service.on('rebuild_stream').listen((event) {
      // Prefer force poll over tear-down.
      unawaited(forcePoll(reason: 'soft_recover'));
    });

    service.on('app_backgrounded').listen((event) {
      if (stopping) return;
      appInBackground = true;
      if (kDebugMode) {
        debugPrint('[DutyLocation] app backgrounded — BG force-poll armed');
      }
      startBgForcePoll();
      // Keep the existing stream; kick an immediate one-shot fix.
      unawaited(forcePoll(reason: 'enter_background'));
    });

    service.on('app_foregrounded').listen((event) {
      if (stopping) return;
      appInBackground = false;
      stopBgForcePoll();
      if (kDebugMode) {
        debugPrint('[DutyLocation] app foregrounded — BG force-poll cleared');
      }
      unawaited(forcePoll(reason: 'enter_foreground'));
    });

    await subscribePositionStream();
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    return true;
  }
}
