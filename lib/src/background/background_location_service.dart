import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import '../location/adaptive_gps_stream_controller.dart';
import '../location/location_keep_point_gate.dart';
import '../location/mock_location_detection.dart';
import '../location/speed_adaptive_gps_policy.dart';
import '../auth/auth_repository.dart';
import '../motion/motion_activity_fusion_controller.dart';
import 'background_location_accuracy.dart';
import 'background_location_uploader.dart';

@pragma('vm:entry-point')
class BackgroundLocationService {
  static const String _channelId = 'smartnps360_location';
  static const int _notificationId = 9911;

  @pragma('vm:entry-point')
  static Future<void> configureAndStart() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: true,
        isForegroundMode: true,
        foregroundServiceNotificationId: _notificationId,
        notificationChannelId: _channelId,
        foregroundServiceTypes: const [AndroidForegroundType.location],
        initialNotificationTitle: 'SmartNPS360',
        initialNotificationContent: 'Sharing live location',
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: _onStart,
        // iOS background execution is limited; this is best-effort.
        onBackground: _onIosBackground,
      ),
    );

    await service.startService();
  }

  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) async {
    // Keep this isolate minimal: permissions must already be granted by UI.
    final uploader = BackgroundLocationUploader();
    await uploader.init();
    uploader.start();

    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }

    if (kDebugMode) {
      // ignore: avoid_print
      print('[BackgroundLocationService] started');
    }

    StreamSubscription<Position>? sub;
    var stopping = false;
    var streamRebuildInFlight = false;
    final policyTracker = SpeedAdaptiveGpsPolicyTracker();
    final keepPointGate = LocationKeepPointGate();
    final streamController = AdaptiveGpsStreamController();
    unawaited(MotionActivityFusionController.instance.acquire());

    late final Future<void> Function() stop;
    late final Future<void> Function({required String reason})
        rebuildStreamIfNeeded;
    late final Future<void> Function() subscribePositionStream;

    stop = () async {
      if (stopping) return;
      stopping = true;
      if (kDebugMode) {
        // ignore: avoid_print
        print('[BackgroundLocationService] stopping (GPS first, then service)');
      }
      streamController
        ..onSettingsChanged = null
        ..reset();
      await sub?.cancel();
      sub = null;
      // Stop collecting immediately; do not block stopSelf on open-network batch flush.
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
          // ignore: avoid_print
          print(
            '[BackgroundLocationService] rebuild stream reason=$reason '
            'interval=${streamController.interval.inSeconds}s '
            'distanceFilter=${streamController.distanceFilterMeters}m '
            'curveBoost=${streamController.isCurveBoosting}',
          );
        }
        await subscribePositionStream();
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[BackgroundLocationService] stream rebuild failed: $e');
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
              // ignore: avoid_print
              print(
                '[BackgroundLocationService] skipped inaccurate fix '
                'acc=${pos.accuracy}m',
              );
            }
            return;
          }

          final token = await AuthRepository.instance.ensureValidAccessToken();
          if (stopping) return;
          if (token == null || token.isEmpty) {
            await stop();
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
            // ignore: avoid_print
            print(
              '[BackgroundLocationService] location '
              'acc=${pos.accuracy} '
              'speedBand=${policyDecision.band.label} '
              'motion=${motionFusion.apiMotionActivity} '
              'fused=${motionFusion.fusedState} '
              'session=${motionFusion.active} '
              'streamEvery=${streamController.interval.inSeconds}s '
              'distanceFilter=${streamController.distanceFilterMeters}m '
              'curveBoost=${streamController.isCurveBoosting} '
              'trigger=${keepDecision.trigger?.name} '
              'dist=${keepDecision.distanceMeters?.toStringAsFixed(1)}m '
              'mocked=${mockFlags.isMocked} '
              'simulated=${mockFlags.isSimulatedBySoftware}',
            );
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
              // ignore: avoid_print
              print('[BackgroundLocationService] upload failed: $e');
            }
          }
        },
        onError: (Object error) {
          if (kDebugMode) {
            // ignore: avoid_print
            print('[BackgroundLocationService] stream error: $error');
          }
        },
      );
      streamController.markSettingsApplied();
    };

    streamController.onSettingsChanged = () {
      unawaited(rebuildStreamIfNeeded(reason: 'settings_changed'));
    };

    service.on('stop').listen((event) {
      unawaited(stop());
    });

    // Adaptive stream: speed policy interval + distance filter (+ curve boost).
    await subscribePositionStream();
    if (kDebugMode) {
      // ignore: avoid_print
      print(
        '[BackgroundLocationService] stream '
        'interval=${streamController.interval.inSeconds}s '
        'distanceFilter=${streamController.distanceFilterMeters}m '
        'platform=${Platform.isAndroid ? 'android' : 'ios'}',
      );
    }
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    // Returning true tells iOS the callback completed successfully.
    return true;
  }
}
