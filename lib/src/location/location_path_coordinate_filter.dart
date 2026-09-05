import 'package:geolocator/geolocator.dart';

import '../motion/vehicle_session_fusion.dart';
import 'location_coordinate_smoother.dart';
import 'location_path_movement_mode.dart';
import 'speed_adaptive_gps_policy.dart';

/// Measured-only path coordinate filter for security trail uploads.
class LocationPathCoordinateFilter {
  final LocationCoordinateSmoother _smoother = LocationCoordinateSmoother();
  LocationPathMovementMode? _activeMode;

  void reset() {
    _activeMode = null;
    _smoother.reset();
  }

  Position filter({
    required Position raw,
    required LocationPathMovementMode mode,
  }) {
    if (mode == LocationPathMovementMode.stopped) {
      reset();
      return raw;
    }

    final settings = LocationPathMovementModePolicy.settingsFor(mode);
    if (_activeMode != mode) {
      _smoother.configure(settings);
      _activeMode = mode;
    }

    _smoother.observe(raw);
    return _smoother.smooth(raw);
  }

  LocationPathMovementMode resolveMode({
    required SpeedAdaptiveGpsPolicyDecision policy,
    required VehicleSessionSnapshot fusion,
  }) {
    return LocationPathMovementModePolicy.resolve(policy: policy, fusion: fusion);
  }
}
