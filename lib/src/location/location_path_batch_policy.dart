import '../motion/vehicle_session_fusion.dart';
import 'location_keep_point_gate.dart';
import 'location_path_motion_gate.dart';
import 'speed_adaptive_gps_policy.dart';

/// Fleet-style path eligibility: confirmed motion required, ping unaffected.
class LocationPathBatchPolicy {
  LocationPathBatchPolicy._();

  static const double minPathSpeedKmh = 3;

  static const Set<String> _stationaryFusedStates = {
    'stationary',
    'still',
  };

  static bool shouldQueue({
    required SpeedAdaptiveGpsPolicyDecision policy,
    required VehicleSessionSnapshot fusion,
    LocationKeepPointTrigger? keepTrigger,
  }) {
    if (keepTrigger == LocationKeepPointTrigger.stationaryPing) {
      return false;
    }
    if (!LocationPathMotionGate.hasConfirmedMotion(
      fusion: fusion,
      policy: policy,
    )) {
      return false;
    }
    if (!policy.shouldQueueForBatch) return false;

    final fusedState = fusion.fusedState.toLowerCase().trim();
    if (_stationaryFusedStates.contains(fusedState)) {
      return false;
    }

    final native = fusion.nativeActivity.toLowerCase().trim();
    if (native == 'still' || native == 'stationary') {
      return false;
    }

    if (fusedState == 'driving_stopped') {
      final speedKmh = _bestSpeedKmh(policy: policy, fusion: fusion);
      if (speedKmh != null && speedKmh < minPathSpeedKmh) {
        return false;
      }
    }

    return true;
  }

  static double? _bestSpeedKmh({
    required SpeedAdaptiveGpsPolicyDecision policy,
    required VehicleSessionSnapshot fusion,
  }) {
    return fusion.smoothedSpeedKmh ??
        fusion.gpsSpeedKmh ??
        policy.smoothedSpeedKmh ??
        policy.rawSpeedKmh;
  }
}
