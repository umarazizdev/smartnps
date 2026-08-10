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
import 'background_location_accuracy.dart';
import 'background_location_uploader.dart';
import 'location_sharing_status_notification.dart';

@pragma('vm:entry-point')
class BackgroundLocationService {
  static const String _channelId = 'smartnps360_location';
  static const int _notificationId = 9911;

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
      await _stopIfRunningWithoutDutyGate();
    } finally {
      if (identical(_configureFuture, future)) {
        _configureFuture = null;
      }
    }
  }

  static Future<void> _stopIfRunningWithoutDutyGate() async {
    try {
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) return;
      if (kDebugMode) {
        debugPrint(
          '[DutyLocation] cold start: stopping leftover Android FGS '
          'until duty heartbeat confirms on_duty',
        );
      }
      service.invoke('stop');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DutyLocation] cold start leftover stop failed: $e');
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
      debugPrint('[DutyLocation] RUNNING (Android background service onStart)');
    }

    final uploader = BackgroundLocationUploader();
    await uploader.init();
    uploader.start();

    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }

    StreamSubscription<Position>? sub;
    var stopping = false;
    var streamRebuildInFlight = false;
    final policyTracker = SpeedAdaptiveGpsPolicyTracker();
    final keepPointGate = LocationKeepPointGate();
    final streamController = AdaptiveGpsStreamController();
    unawaited(MotionActivityFusionController.instance.acquire());

    late final Future<void> Function({
      required LocationSharingStopReason? announceReason,
    }) stop;
    late final Future<void> Function({required String reason})
        rebuildStreamIfNeeded;
    late final Future<void> Function() subscribePositionStream;

    stop = ({required LocationSharingStopReason? announceReason}) async {
      if (stopping) return;
      stopping = true;
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

      if (announceReason != null) {
        try {
          await LocationSharingStatusNotification.showStopped(
            reason: announceReason,
          );
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '[DutyLocation] stopped notification failed before stopSelf: $e',
            );
          }
        }
      }

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

        }
        await subscribePositionStream();
      } catch (e) {
        if (kDebugMode) {

        }
      } finally {
        streamRebuildInFlight = false;
      }
    };

    subscribePositionStream = () async {
      final settings = streamController.buildLocationSettings(
        allowBackgroundLocationUpdates: true,
      );
      await sub?.cancel();
      sub = Geolocator.getPositionStream(locationSettings: settings).listen(
        (pos) async {
          if (stopping) return;

          if (!BackgroundLocationAccuracy.isAcceptable(pos)) {
            if (kDebugMode) {

            }
            return;
          }

          final token = await AuthRepository.instance.ensureValidAccessToken();
          if (stopping) return;
          if (token == null || token.isEmpty) {
            await stop(announceReason: null);
            return;
          }

          final policyDecision = policyTracker.evaluate(pos);
          final settingsChanged =
              streamController.observe(pos, policyDecision);
          if (settingsChanged) {
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

          if (kDebugMode) {

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
          } catch (e) {
            if (kDebugMode) {

            }
          }
        },
        onError: (Object error) {
          if (kDebugMode) {

          }
        },
      );
      streamController.markSettingsApplied();
    };

    streamController.onSettingsChanged = () {
      unawaited(rebuildStreamIfNeeded(reason: 'settings_changed'));
    };

    service.on('stop').listen((event) {
      final announceReason = LocationSharingStatusNotification.reasonFromWire(
        event?['announceReason'],
      );
      final legacyShiftEnded = event?['announceShiftEnded'] == true;
      unawaited(
        stop(
          announceReason: announceReason ??
              (legacyShiftEnded ? LocationSharingStopReason.shiftEnded : null),
        ),
      );
    });

    await subscribePositionStream();
    if (kDebugMode) {

    }
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {

    return true;
  }
}
