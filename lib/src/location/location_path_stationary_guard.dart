import 'package:geolocator/geolocator.dart';

import '../motion/vehicle_session_fusion.dart';
import 'location_path_motion_gate.dart';
import 'location_path_movement_mode.dart';
import 'speed_adaptive_gps_policy.dart';

class _RecentPathSample {
  const _RecentPathSample({required this.position, required this.at});

  final Position position;
  final DateTime at;
}

/// Hard-stops path uploads while stationary or GPS is drifting on a desk.
/// Driving sessions stay soft through brief signal stops.
class LocationPathStationaryGuard {
  static const double unlockDisplacementMeters = 35;
  static const double drivingUnlockDisplacementMeters = 12;
  static const int unlockMovingSamplesRequired = 2;
  static const int motionConfirmSamplesRequired = 2;
  static const int drivingMotionConfirmSamplesRequired = 1;
  static const Duration driftWindow = Duration(minutes: 2);
  static const int minDriftSamples = 3;
  static const double minDriftPathMeters = 25;
  static const double driftPathRatio = 1.6;

  bool _locked = true;
  Position? _anchor;
  int _confirmedMovingSamples = 0;
  int _motionConfirmSamples = 0;
  final List<_RecentPathSample> _recent = [];

  void reset() {
    _locked = true;
    _anchor = null;
    _confirmedMovingSamples = 0;
    _motionConfirmSamples = 0;
    _recent.clear();
  }

  void observe({
    required Position position,
    required LocationPathMovementMode mode,
    required VehicleSessionSnapshot fusion,
    required SpeedAdaptiveGpsPolicyDecision policy,
  }) {
    _recordSample(position);

    // Driving (incl. red-light / driving_stopped): never hard-lock like a desk stop.
    if (mode == LocationPathMovementMode.driving) {
      _observeDriving(
        position: position,
        fusion: fusion,
        policy: policy,
      );
      return;
    }

    if (_isPhysicallyStill(fusion) || mode == LocationPathMovementMode.stopped) {
      _engageLock(position);
      return;
    }

    if (_detectDriftZigZag()) {
      _engageLock(position);
      return;
    }

    if (LocationPathMotionGate.hasConfirmedMotion(
      fusion: fusion,
      policy: policy,
    )) {
      _motionConfirmSamples++;
    } else {
      _motionConfirmSamples = 0;
    }

    if (!_locked) return;

    final anchor = _anchor;
    if (anchor == null) {
      return;
    }

    final distMeters = Geolocator.distanceBetween(
      anchor.latitude,
      anchor.longitude,
      position.latitude,
      position.longitude,
    );

    if (distMeters >= unlockDisplacementMeters &&
        _motionConfirmSamples >= motionConfirmSamplesRequired) {
      _confirmedMovingSamples++;
      if (_confirmedMovingSamples >= unlockMovingSamplesRequired) {
        _unlock();
      }
    } else {
      _confirmedMovingSamples = 0;
    }
  }

  void _observeDriving({
    required Position position,
    required VehicleSessionSnapshot fusion,
    required SpeedAdaptiveGpsPolicyDecision policy,
  }) {
    final moving = LocationPathMotionGate.hasConfirmedMotion(
          fusion: fusion,
          policy: policy,
        ) ||
        LocationPathMotionGate.isVehicleSessionMoving(
          fusion: fusion,
          policy: policy,
        );

    // Desk-like zigzag while claiming driving is still locked.
    if (!moving && _detectDriftZigZag()) {
      _engageLock(position);
      return;
    }

    if (moving) {
      _motionConfirmSamples++;
    } else {
      // Red light / brief stop: keep an unlocked driving session open.
      if (!_locked) return;
      return;
    }

    if (!_locked) return;

    final anchor = _anchor ?? position;
    _anchor ??= position;
    final distMeters = Geolocator.distanceBetween(
      anchor.latitude,
      anchor.longitude,
      position.latitude,
      position.longitude,
    );

    if (distMeters >= drivingUnlockDisplacementMeters &&
        _motionConfirmSamples >= drivingMotionConfirmSamplesRequired) {
      _confirmedMovingSamples++;
      if (_confirmedMovingSamples >= 1) {
        _unlock();
      }
    }
  }

  /// Once unlocked, brief signal stops must not block path again.
  bool get blocksPathUpload {
    if (!_locked) return false;
    return _motionConfirmSamples < motionConfirmSamplesRequired;
  }

  void markBatchAccepted(Position position) {
    if (!_locked) {
      _anchor = position;
    }
  }

  void _unlock() {
    _locked = false;
    _anchor = null;
    _confirmedMovingSamples = 0;
    _recent.clear();
  }

  void _engageLock(Position position) {
    _locked = true;
    _anchor ??= position;
    _confirmedMovingSamples = 0;
    _motionConfirmSamples = 0;
  }

  void _recordSample(Position position) {
    final now = DateTime.now();
    _recent.add(_RecentPathSample(position: position, at: now));
    while (_recent.length > 16) {
      _recent.removeAt(0);
    }
    final cutoff = now.subtract(driftWindow);
    _recent.removeWhere((sample) => sample.at.isBefore(cutoff));
  }

  bool _detectDriftZigZag() {
    if (_recent.length < minDriftSamples) return false;

    var pathMeters = 0.0;
    for (var i = 1; i < _recent.length; i++) {
      final prev = _recent[i - 1].position;
      final curr = _recent[i].position;
      pathMeters += Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        curr.latitude,
        curr.longitude,
      );
    }

    final first = _recent.first.position;
    final last = _recent.last.position;
    final displacementMeters = Geolocator.distanceBetween(
      first.latitude,
      first.longitude,
      last.latitude,
      last.longitude,
    );

    if (pathMeters < minDriftPathMeters) return false;
    if (displacementMeters <= 0) return true;
    return pathMeters >= displacementMeters * driftPathRatio;
  }

  static bool _isPhysicallyStill(VehicleSessionSnapshot fusion) {
    final native = fusion.nativeActivity.toLowerCase().trim();
    final fused = fusion.fusedState.toLowerCase().trim();
    return native == 'still' ||
        native == 'stationary' ||
        fused == 'stationary' ||
        fused == 'still';
  }
}
