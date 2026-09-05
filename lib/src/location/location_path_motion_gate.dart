import '../motion/vehicle_session_fusion.dart';
import 'speed_adaptive_gps_policy.dart';

/// Production-style gate: path uploads require confirmed motion, not GPS speed alone.
class LocationPathMotionGate {
  LocationPathMotionGate._();

  static const int minNativeConfidence = 50;
  static const double minDrivingSpeedKmh = 15;
  static const double vehicleSessionResumeSpeedKmh = 8;

  static const Set<String> _confirmedMovingNative = {
    'walking',
    'running',
    'cycling',
    'on_foot',
    'automotive',
    'in_vehicle',
    'driving',
  };

  static const Set<String> _vehicleNative = {
    'automotive',
    'in_vehicle',
    'driving',
  };

  static const Set<String> _vehicleFused = {
    'driving',
    'driving_stopped',
  };

  static bool hasConfirmedMotion({
    required VehicleSessionSnapshot fusion,
    required SpeedAdaptiveGpsPolicyDecision policy,
  }) {
    final native = fusion.nativeActivity.toLowerCase().trim();
    if (_confirmedMovingNative.contains(native) &&
        fusion.nativeConfidence >= minNativeConfidence) {
      return true;
    }

    final speedKmh = _bestSpeedKmh(policy: policy, fusion: fusion);
    if (speedKmh != null && speedKmh >= minDrivingSpeedKmh) {
      return true;
    }

    // Resume after signal: vehicle session + city driving speed.
    if (isVehicleSession(fusion) &&
        speedKmh != null &&
        speedKmh >= vehicleSessionResumeSpeedKmh) {
      return true;
    }

    return false;
  }

  static bool isVehicleSession(VehicleSessionSnapshot fusion) {
    final native = fusion.nativeActivity.toLowerCase().trim();
    final fused = fusion.fusedState.toLowerCase().trim();
    final api = fusion.apiMotionActivity.toLowerCase().trim();
    return _vehicleNative.contains(native) ||
        _vehicleFused.contains(fused) ||
        api == 'automotive';
  }

  static bool isVehicleSessionMoving({
    required VehicleSessionSnapshot fusion,
    required SpeedAdaptiveGpsPolicyDecision policy,
  }) {
    if (!isVehicleSession(fusion)) return false;
    final speedKmh = _bestSpeedKmh(policy: policy, fusion: fusion) ?? 0;
    return speedKmh >= vehicleSessionResumeSpeedKmh;
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
