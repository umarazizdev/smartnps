import 'dart:async';
import 'dart:io';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import '../../location/adaptive_gps_stream_controller.dart';
import '../../location/location_keep_point_gate.dart';
import '../../location/mock_location_detection.dart';
import '../../location/speed_adaptive_gps_policy.dart';
import '../../auth/auth_repository.dart';
import '../../motion/motion_activity_fusion_controller.dart';
import '../duty/clock_in_engine_warm_snapshot.dart';
import '../duty/duty_status_snapshot.dart';
import 'android_duty_location_health.dart';
import 'background_location_accuracy.dart';
import 'background_location_uploader.dart';
import '../../utilities/app_debug_log.dart';

@pragma('vm:entry-point')
class BackgroundLocationService {
  static const String _channelId = 'smartnps360_location';
  static const int _notificationId = 9911;
  static const Duration _forcePollAfter = Duration(seconds: 45);
  static const Duration _rebuildStreamAfter = Duration(minutes: 3);
  static const Duration _androidStreamInterval = Duration(seconds: 5);
  static const Duration _dutyGateEvery = Duration(seconds: 30);
  static const Duration _warmGateEvery = Duration(seconds: 15);
  static const String _activateTrackingEvent = 'activate_tracking';
  static const String _cancelWarmEvent = 'cancel_warm';

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
      await _reconcileLeftoverFgsWithDutySnapshot();
    } finally {
      if (identical(_configureFuture, future)) {
        _configureFuture = null;
      }
    }
  }

  static Future<void> reconcileStaleClockInWarm() async {
    if (!Platform.isAndroid) return;
    if (await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) return;

    final warmPending = await ClockInEngineWarmSnapshot.isValidPending();
    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (!warmPending && !running) return;

    if (warmPending) {
      await ClockInEngineWarmSnapshot.clear();
      locationDebugLog(
        '[DutyLocation] cleared stale clock-in warm (app relaunch/resume)',
      );
    }

    if (running) {
      locationDebugLog(
        '[DutyLocation] stopping orphaned warm FGS (not on duty)',
      );
      service.invoke(_cancelWarmEvent);
      service.invoke('stop');
      AndroidDutyLocationHealth.markStopped();
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
        locationDebugLog(
          '[DutyLocation] cold start: keeping leftover Android FGS '
          '(valid on_duty snapshot)',
        );
        return;
      }

      if (await ClockInEngineWarmSnapshot.isValidPending()) {
        await ClockInEngineWarmSnapshot.clear();
        locationDebugLog(
          '[DutyLocation] cold start: cleared stale clock-in warm pending',
        );
      }

      locationDebugLog(
        '[DutyLocation] cold start: stopping leftover Android FGS '
        '(no valid on_duty snapshot)',
      );
      service.invoke('stop');
      AndroidDutyLocationHealth.markStopped();
    } catch (e) {
      locationDebugLog(
        '[DutyLocation] cold start leftover reconcile failed: $e',
      );
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

  static Future<void> preWarmForClockIn() async {
    if (!Platform.isAndroid) return;
    await ensureConfigured();

    if (await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) return;

    await ClockInEngineWarmSnapshot.markPending();

    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      locationDebugLog(
        '[DutyLocation] Android FGS warm refresh (engine already running)',
      );
      return;
    }

    locationDebugLog('[DutyLocation] Android FGS engine pre-warm starting…');
    await service.startService();
  }

  static Future<void> cancelClockInWarm() async {
    if (!Platform.isAndroid) return;
    await ClockInEngineWarmSnapshot.clear();

    if (await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) return;

    final service = FlutterBackgroundService();
    if (!await service.isRunning()) return;

    locationDebugLog('[DutyLocation] Android FGS warm cancel requested');
    service.invoke(_cancelWarmEvent);
  }

  static Future<void> activateFromClockInWarm() async {
    if (!Platform.isAndroid) return;

    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      await configureAndStart();
      return;
    }

    if (!await ClockInEngineWarmSnapshot.isValidPending()) return;

    locationDebugLog(
      '[DutyLocation] Android FGS warm → activate_tracking requested',
    );
    service.invoke(_activateTrackingEvent);
  }

  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) async {
    locationDebugLog(
      '[DutyLocation] RUNNING (Android background service onStart, '
      'stable-stream v2)',
    );

    if (await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) {
      await ClockInEngineWarmSnapshot.clear();
      await _runDutyTracking(service);
      return;
    }

    if (await ClockInEngineWarmSnapshot.isValidPending()) {
      await _runIdleWarm(service);
      return;
    }

    locationDebugLog(
      '[DutyLocation] Android FGS start aborted; '
      'no valid on_duty snapshot or warm pending',
    );
    service.stopSelf();
  }

  static Future<void> _runIdleWarm(ServiceInstance service) async {
    locationDebugLog(
      '[DutyLocation] Android FGS idle warm (engine only, no GPS)',
    );

    var stopping = false;
    Timer? warmGateTimer;

    Future<void> stopWarm({required String reason}) async {
      if (stopping) return;
      stopping = true;
      warmGateTimer?.cancel();
      warmGateTimer = null;
      await ClockInEngineWarmSnapshot.clear();
      locationDebugLog(
        '[DutyLocation] Android FGS idle warm stopped ($reason)',
      );
      service.stopSelf();
    }

    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }

    warmGateTimer = Timer.periodic(_warmGateEvery, (_) async {
      if (stopping) return;
      if (!await ClockInEngineWarmSnapshot.isValidPending()) {
        await stopWarm(reason: 'warm_expired');
      }
    });

    service.on('stop').listen((event) {
      unawaited(stopWarm(reason: 'stop'));
    });

    service.on(_cancelWarmEvent).listen((event) {
      unawaited(stopWarm(reason: 'cancel_warm'));
    });

    service.on(_activateTrackingEvent).listen((event) async {
      if (stopping) return;
      if (!await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) {
        locationDebugLog(
          '[DutyLocation] activate_tracking blocked; no on_duty snapshot',
        );
        return;
      }
      stopping = true;
      warmGateTimer?.cancel();
      warmGateTimer = null;
      await ClockInEngineWarmSnapshot.clear();
      locationDebugLog(
        '[DutyLocation] Android FGS warm → activating GPS tracking',
      );
      await _runDutyTracking(service);
    });
  }

  static Future<void> _runDutyTracking(ServiceInstance service) async {
    try {
      await AuthRepository.instance.warmAccessTokenCache();
    } catch (e) {
      locationDebugLog('[DutyLocation] Android FGS auth warm failed: $e');
    }

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

    runDutyGate = () async {
      if (stopping || dutyGateInFlight) return;
      dutyGateInFlight = true;
      try {
        await DutyStatusSnapshot.renewIfStillOnDuty();
        final stillOnDuty =
            await DutyStatusSnapshot.isValidOnDutyForCurrentUser();
        if (!stillOnDuty) {
          locationDebugLog(
            '[DutyLocation] Android FGS duty gate: snapshot gone → stop',
          );
          await stop();
          return;
        }
      } catch (e) {
        locationDebugLog('[DutyLocation] Android FGS duty gate failed: $e');
      } finally {
        dutyGateInFlight = false;
      }
    };

    handlePosition = (Position pos) async {
      if (stopping) return;
      lastAnyFixAt = DateTime.now();

      await DutyStatusSnapshot.renewIfStillOnDuty();
      if (!await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) {
        locationDebugLog(
          '[DutyLocation] Android FGS stopping; on_duty snapshot gone',
        );
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
        final refresh = await AuthRepository.instance.getRefreshToken();
        if (refresh == null || refresh.isEmpty) {
          locationDebugLog(
            '[DutyLocation] Android FGS stopping; no auth session',
          );
          await stop();
          return;
        }
        locationDebugLog(
          '[DutyLocation] Android FGS auth transient fail; '
          'keeping GPS, skipping upload',
        );
        return;
      }

      final policyDecision = policyTracker.evaluate(pos);
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

      final motionFusion = await MotionActivityFusionController.instance
          .evaluatePosition(pos);
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
        locationDebugLog(
          '[DutyLocation] Android upload ok '
          'acc=${pos.accuracy.toStringAsFixed(1)}m',
        );
      } catch (e) {
        locationDebugLog('[DutyLocation] Android upload failed: $e');
      }
    };

    forcePoll = ({required String reason}) async {
      if (stopping || forcePollInFlight) return;
      forcePollInFlight = true;
      try {
        locationDebugLog('[DutyLocation] Android force GPS poll ($reason)');
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
        locationDebugLog('[DutyLocation] Android force poll failed: $e');
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

      if (now.difference(lastAccepted) > _forcePollAfter) {
        unawaited(forcePoll(reason: 'stale_accepted_fix'));
      }

      if (now.difference(lastAny) > _rebuildStreamAfter) {
        unawaited(rebuildStreamIfNeeded(reason: 'stream_dead'));
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
      locationDebugLog('[DutyLocation] STOPPED (Android background service)');
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
        locationDebugLog(
          '[DutyLocation] rebuilding Android GPS stream ($reason)',
        );
        await subscribePositionStream();
      } catch (e) {
        locationDebugLog('[DutyLocation] Android stream rebuild failed: $e');
      } finally {
        streamRebuildInFlight = false;
      }
    };

    subscribePositionStream = () async {
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
          locationDebugLog('[DutyLocation] Android GPS stream error: $error');
          unawaited(forcePoll(reason: 'stream_error'));
        },
      );
      streamController.markSettingsApplied();
      locationDebugLog(
        '[DutyLocation] Android GPS stream subscribed '
        '(stable ${_androidStreamInterval.inSeconds}s, no policy rebuild)',
      );
    };

    streamController.onSettingsChanged = null;

    service.on('stop').listen((event) {
      unawaited(stop());
    });

    service.on('rebuild_stream').listen((event) {
      unawaited(forcePoll(reason: 'soft_recover'));
    });

    service.on('app_backgrounded').listen((event) {
      if (stopping) return;
      locationDebugLog(
        '[DutyLocation] app backgrounded — GPS stream kept, adaptive upload continues',
      );
      unawaited(DutyStatusSnapshot.renewIfStillOnDuty());
      unawaited(runDutyGate());
    });

    service.on('app_foregrounded').listen((event) {
      if (stopping) return;
      locationDebugLog('[DutyLocation] app foregrounded');
      unawaited(runDutyGate());
    });

    await subscribePositionStream();
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    return true;
  }
}
