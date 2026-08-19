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
  static const Duration _forcePollAfter = Duration(seconds: 45);
  static const Duration _rebuildStreamAfter = Duration(minutes: 3);
  static const Duration _androidStreamInterval = Duration(seconds: 5);
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
    if (kDebugMode) {
      debugPrint(
        '[DutyLocation] RUNNING (Android background service onStart, '
        'stable-stream v2)',
      );
    }

    if (!await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) {
      if (kDebugMode) {
        debugPrint(
          '[DutyLocation] Android FGS start aborted; no valid on_duty snapshot',
        );
      }
      service.stopSelf();
      return;
    }

    try {
      await AuthRepository.instance.warmAccessTokenCache();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DutyLocation] Android FGS auth warm failed: $e');
      }
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
        final refresh = await AuthRepository.instance.getRefreshToken();
        if (refresh == null || refresh.isEmpty) {
          if (kDebugMode) {
            debugPrint(
              '[DutyLocation] Android FGS stopping; no auth session',
            );
          }
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
      unawaited(forcePoll(reason: 'soft_recover'));
    });

    service.on('app_backgrounded').listen((event) {
      if (stopping) return;
      if (kDebugMode) {
        debugPrint(
          '[DutyLocation] app backgrounded — GPS stream kept, adaptive upload continues',
        );
      }
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
