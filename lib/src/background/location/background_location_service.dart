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
import 'background_location_issue_notification.dart';
import 'background_location_uploader.dart';

@pragma('vm:entry-point')
class BackgroundLocationService {
  static const String _channelId = 'smartnps360_location';
  static const int _notificationId = 9911;
  /// Kick a one-shot GPS fix if no acceptable upload for this long.
  /// Used as OEM-throttle fallback only — not a fixed BG cadence.
  static const Duration _forcePollAfter = Duration(seconds: 45);
  /// Only cancel/resubscribe the stream if no fix of any accuracy for this long.
  static const Duration _rebuildStreamAfter = Duration(minutes: 3);
  /// Stable FGS GPS cadence. Adaptive policy still decides ping vs batch;
  /// do not retune Geolocator (cancel/resubscribe) or OEM gaps appear.
  static const Duration _androidStreamInterval = Duration(seconds: 5);
  /// Renew on_duty snapshot + re-check off_duty clear while UI is frozen.
  static const Duration _dutyGateEvery = Duration(seconds: 30);

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
      debugPrint(
        '[DutyLocation] RUNNING (Android background service onStart, '
        'stable-stream v2)',
      );
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

    // Warm tokens in this isolate so BG uploads don't race an empty cache.
    try {
      await AuthRepository.instance.warmAccessTokenCache();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DutyLocation] Android FGS auth warm failed: $e');
      }
    }

    // Extend TTL immediately so UI heartbeat freeze cannot expire the gate.
    unawaited(DutyStatusSnapshot.renewIfStillOnDuty());

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
    var dutyGateInFlight = false;
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
    late final Future<void> Function() runDutyGate;

    Timer? healthTimer;
    Timer? dutyGateTimer;

    /// Keep on_duty TTL fresh while FGS is alive; stop the moment snapshot is
    /// cleared (off_duty / logout). Never recreates a cleared snapshot.
    runDutyGate = () async {
      if (stopping || dutyGateInFlight) return;
      dutyGateInFlight = true;
      try {
        // Renew first so a near-expiry snapshot is extended before the
        // validity check would clear it. renewIfStillOnDuty never recreates
        // after clear().
        await DutyStatusSnapshot.renewIfStillOnDuty();
        final stillOnDuty =
            await DutyStatusSnapshot.isValidOnDutyForCurrentUser();
        if (!stillOnDuty) {
          if (kDebugMode) {
            debugPrint(
              '[DutyLocation] Android FGS duty gate: snapshot gone → stop',
            );
          }
          await stop();
          return;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[DutyLocation] Android FGS duty gate failed: $e');
        }
      } finally {
        dutyGateInFlight = false;
      }
    };

    handlePosition = (Position pos) async {
      if (stopping) return;
      lastAnyFixAt = DateTime.now();

      // Renew before validity check so near-expiry BG sessions survive UI
      // freeze. renewIfStillOnDuty never recreates after off_duty clear().
      await DutyStatusSnapshot.renewIfStillOnDuty();
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
        // Logged out (no refresh session) → stop. Transient refresh/network
        // failure while still logged in → skip this upload, keep GPS alive.
        final refresh = await AuthRepository.instance.getRefreshToken();
        if (refresh == null || refresh.isEmpty) {
          if (kDebugMode) {
            debugPrint(
              '[DutyLocation] Android FGS stopping; no auth session',
            );
          }
          unawaited(
            BackgroundLocationIssueNotification.showIfOnDuty(
              issue: BackgroundLocationIssue.signedOut,
            ),
          );
          await stop();
          return;
        }
        if (kDebugMode) {
          debugPrint(
            '[DutyLocation] Android FGS auth transient fail; '
            'keeping GPS, skipping upload',
          );
        }
        return;
      }

      final policyDecision = policyTracker.evaluate(pos);
      // Observe for keep-gate / fusion inputs only. Never rebuild the live
      // Android stream on band/curve changes — that stopped GPS in background.
      streamController.observe(pos, policyDecision);

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
        // OEM often times out getCurrentPosition in background. Keep FGS.
        // Only resubscribe when the stream itself looks dead.
        final lastAny = lastAnyFixAt ?? startedAt;
        if (!stopping &&
            DateTime.now().difference(lastAny) > _rebuildStreamAfter) {
          unawaited(rebuildStreamIfNeeded(reason: 'force_poll_timeout'));
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
      if (now.difference(lastAccepted) > _rebuildStreamAfter) {
        unawaited(
          BackgroundLocationIssueNotification.showIfOnDuty(
            issue: BackgroundLocationIssue.gpsNotUpdating,
          ),
        );
      }

      // Only rebuild if the stream appears completely dead.
      if (now.difference(lastAny) > _rebuildStreamAfter) {
        unawaited(rebuildStreamIfNeeded(reason: 'stream_dead'));
        unawaited(
          BackgroundLocationIssueNotification.showIfOnDuty(
            issue: BackgroundLocationIssue.gpsStopped,
          ),
        );
      }
    });

    dutyGateTimer = Timer.periodic(_dutyGateEvery, (_) {
      unawaited(runDutyGate());
    });

    stop = () async {
      if (stopping) return;
      stopping = true;
      healthTimer?.cancel();
      healthTimer = null;
      dutyGateTimer?.cancel();
      dutyGateTimer = null;
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
      // One stable Android subscription for FG and BG. Adaptive bands
      // still gate ping vs batch; they must not cancel this listener.
      final settings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: _androidStreamInterval,
        timeLimit: null,
        forceLocationManager: false,
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
          unawaited(forcePoll(reason: 'stream_error'));
        },
      );
      streamController.markSettingsApplied();
      if (kDebugMode) {
        debugPrint(
          '[DutyLocation] Android GPS stream subscribed '
          '(stable ${_androidStreamInterval.inSeconds}s, no policy rebuild)',
        );
      }
    };

    streamController.onSettingsChanged = null;

    service.on('stop').listen((event) {
      unawaited(stop());
    });

    service.on('rebuild_stream').listen((event) {
      // Prefer force poll over tear-down.
      unawaited(forcePoll(reason: 'soft_recover'));
    });

    service.on('app_backgrounded').listen((event) {
      if (stopping) return;
      if (kDebugMode) {
        debugPrint(
          '[DutyLocation] app backgrounded — GPS stream kept, adaptive upload continues',
        );
      }
      // UI isolate will freeze; renew TTL. GPS stays on existing policy stream.
      unawaited(DutyStatusSnapshot.renewIfStillOnDuty());
      unawaited(runDutyGate());
    });

    service.on('app_foregrounded').listen((event) {
      if (stopping) return;
      if (kDebugMode) {
        debugPrint('[DutyLocation] app foregrounded');
      }
      unawaited(runDutyGate());
    });

    await subscribePositionStream();
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    return true;
  }
}
