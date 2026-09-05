import '../motion/vehicle_session_fusion.dart';
import 'location_coordinate_smoother.dart';
import 'speed_adaptive_gps_policy.dart';

enum LocationPathMovementMode { stopped, walking, driving }

class LocationPathModeSettings {
  const LocationPathModeSettings({
    required this.mode,
    required this.maxPathAccuracyMeters,
    required this.minBatchDisplacementMeters,
    required this.smoothWindowSize,
    required this.smoothingMethod,
    this.pathHeartbeat,
    this.heartbeatMinDisplacementMeters = 0,
    this.maxAccuracyBoostMeters = 40,
  });

  final LocationPathMovementMode mode;
  final double maxPathAccuracyMeters;
  final double minBatchDisplacementMeters;
  final int smoothWindowSize;
  final PathSmoothingMethod smoothingMethod;

  /// Driving-only: force a path point after this interval if still moving.
  final Duration? pathHeartbeat;
  final double heartbeatMinDisplacementMeters;
  final double maxAccuracyBoostMeters;
}

class LocationPathMovementModePolicy {
  LocationPathMovementModePolicy._();

  static const double stoppedMaxSpeedKmh = 3;
  static const double drivingMinSpeedKmh = 8;
  static const double highwaySpeedKmh = 30;

  static const double walkingStraightMeters = 25;
  static const double cityDrivingStraightMeters = 12;
  static const double highwayDrivingStraightMeters = 18;

  static LocationPathMovementMode resolve({
    required SpeedAdaptiveGpsPolicyDecision policy,
    required VehicleSessionSnapshot fusion,
  }) {
    final fusedState = fusion.fusedState.toLowerCase().trim();
    final nativeActivity = fusion.nativeActivity.toLowerCase().trim();
    final speedKmh = _bestSpeedKmh(policy: policy, fusion: fusion) ?? 0;

    // Keep driving mode through red lights / traffic stops.
    final inVehicleSession = fusion.apiMotionActivity == 'automotive' ||
        fusedState == 'driving' ||
        fusedState == 'driving_stopped' ||
        nativeActivity == 'automotive' ||
        nativeActivity == 'in_vehicle' ||
        nativeActivity == 'driving';
    if (inVehicleSession) {
      return LocationPathMovementMode.driving;
    }

    if (fusion.apiMotionActivity == 'stationary' ||
        fusedState == 'stationary' ||
        fusedState == 'still') {
      return LocationPathMovementMode.stopped;
    }

    if (nativeActivity == 'still' || nativeActivity == 'stationary') {
      return LocationPathMovementMode.stopped;
    }

    if (nativeActivity == 'unknown' && speedKmh < 5) {
      return LocationPathMovementMode.stopped;
    }
    if (speedKmh < stoppedMaxSpeedKmh) {
      return LocationPathMovementMode.stopped;
    }

    if (speedKmh >= drivingMinSpeedKmh) {
      return LocationPathMovementMode.driving;
    }

    return LocationPathMovementMode.walking;
  }

  static LocationPathModeSettings settingsFor(
    LocationPathMovementMode mode, {
    double? speedKmh,
  }) {
    switch (mode) {
      case LocationPathMovementMode.stopped:
        return const LocationPathModeSettings(
          mode: LocationPathMovementMode.stopped,
          maxPathAccuracyMeters: 0,
          minBatchDisplacementMeters: 0,
          smoothWindowSize: 0,
          smoothingMethod: PathSmoothingMethod.none,
        );
      case LocationPathMovementMode.walking:
        return const LocationPathModeSettings(
          mode: LocationPathMovementMode.walking,
          maxPathAccuracyMeters: 20,
          minBatchDisplacementMeters: walkingStraightMeters,
          smoothWindowSize: 3,
          smoothingMethod: PathSmoothingMethod.accuracyWeightedAverage,
        );
      case LocationPathMovementMode.driving:
        return LocationPathModeSettings(
          mode: LocationPathMovementMode.driving,
          maxPathAccuracyMeters: 25,
          minBatchDisplacementMeters: drivingStraightMetersForSpeed(speedKmh),
          smoothWindowSize: 3,
          smoothingMethod: PathSmoothingMethod.measuredMedian,
          pathHeartbeat: const Duration(seconds: 3),
          heartbeatMinDisplacementMeters: 5,
          maxAccuracyBoostMeters: 12,
        );
    }
  }

  static double drivingStraightMetersForSpeed(double? speedKmh) {
    if (speedKmh != null && speedKmh >= highwaySpeedKmh) {
      return highwayDrivingStraightMeters;
    }
    return cityDrivingStraightMeters;
  }

  static bool isPathAccuracyAcceptable({
    required LocationPathMovementMode mode,
    required double accuracyMeters,
  }) {
    if (mode == LocationPathMovementMode.stopped) return false;
    if (accuracyMeters.isNaN ||
        accuracyMeters.isInfinite ||
        accuracyMeters <= 0) {
      return false;
    }
    return accuracyMeters <= settingsFor(mode).maxPathAccuracyMeters;
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
