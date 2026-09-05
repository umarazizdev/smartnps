import 'package:geolocator/geolocator.dart';

import '../background/location/background_location_uploader.dart';
import '../debug/location_path_curve_debug_log.dart';
import '../motion/vehicle_session_fusion.dart';
import 'location_keep_point_gate.dart';
import 'location_path_batch_policy.dart';
import 'speed_adaptive_gps_policy.dart';

class DutyLocationUploadCoordinator {
  DutyLocationUploadCoordinator._();

  static Future<void> uploadKeptPoint({
    required BackgroundLocationUploader uploader,
    required Position position,
    required LocationKeepPointDecision keepDecision,
    required SpeedAdaptiveGpsPolicyDecision policyDecision,
    required VehicleSessionSnapshot motionFusion,
  }) async {
    await uploader.pingNow(
      position,
      policyDecision: policyDecision,
      motionFusion: motionFusion,
    );

    if (!LocationPathBatchPolicy.shouldQueue(
      policy: policyDecision,
      fusion: motionFusion,
      keepTrigger: keepDecision.trigger,
    )) {
      LocationPathCurveDebugLog.instance.record(
        outcome: 'ping_only',
        reason: keepDecision.trigger == LocationKeepPointTrigger.stationaryPing
            ? 'stationary-ping'
            : 'coordinator-batch-policy',
        mode: '',
        accuracyM: position.accuracy,
        lat: position.latitude,
        lng: position.longitude,
        speedKmh:
            policyDecision.smoothedSpeedKmh ?? policyDecision.rawSpeedKmh,
        nativeMotion: motionFusion.nativeActivity,
        fusedMotion: motionFusion.fusedState,
        keepTrigger: keepDecision.trigger?.name ?? '',
      );
      return;
    }

    await uploader.add(
      position,
      policyDecision: policyDecision,
      motionFusion: motionFusion,
      keepTrigger: keepDecision.trigger,
    );
  }
}
