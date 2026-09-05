import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

class BatchDisplacementGate {
  static const double defaultMinDisplacementMeters = 25;
  static const double maxAccuracyBoostMeters = 40;

  Position? _lastQueued;
  DateTime? _lastQueuedAt;

  void reset() {
    _lastQueued = null;
    _lastQueuedAt = null;
  }

  bool shouldQueue(
    Position position, {
    double? minDisplacementMeters,
    double? maxAccuracyBoostOverride,
    Duration? pathHeartbeat,
    double heartbeatMinDisplacementMeters = 0,
  }) {
    final last = _lastQueued;
    if (last == null) {
      return true;
    }

    final distanceMeters = Geolocator.distanceBetween(
      last.latitude,
      last.longitude,
      position.latitude,
      position.longitude,
    );

    if (pathHeartbeat != null) {
      final lastAt = _lastQueuedAt;
      if (lastAt != null &&
          DateTime.now().difference(lastAt) >= pathHeartbeat &&
          distanceMeters >= heartbeatMinDisplacementMeters) {
        return true;
      }
    }

    return distanceMeters >=
        _requiredMeters(
          position,
          minDisplacementMeters: minDisplacementMeters,
          maxAccuracyBoostOverride: maxAccuracyBoostOverride,
        );
  }

  void markQueued(Position position) {
    _lastQueued = position;
    _lastQueuedAt = DateTime.now();
  }

  double requiredMetersFor(
    Position position, {
    double? minDisplacementMeters,
    double? maxAccuracyBoostOverride,
  }) =>
      _requiredMeters(
        position,
        minDisplacementMeters: minDisplacementMeters,
        maxAccuracyBoostOverride: maxAccuracyBoostOverride,
      );

  double distanceFromLastQueuedMeters(Position position) {
    final last = _lastQueued;
    if (last == null) return 0;
    return Geolocator.distanceBetween(
      last.latitude,
      last.longitude,
      position.latitude,
      position.longitude,
    );
  }

  double _requiredMeters(
    Position position, {
    double? minDisplacementMeters,
    double? maxAccuracyBoostOverride,
  }) {
    final accuracy = position.accuracy;
    final accuracyBoost =
        (accuracy.isFinite && accuracy > 0) ? accuracy : 0.0;
    final minDisp = minDisplacementMeters ?? defaultMinDisplacementMeters;
    final boostCap = maxAccuracyBoostOverride ?? maxAccuracyBoostMeters;
    return math.max(
      minDisp,
      math.min(accuracyBoost, boostCap),
    );
  }
}
