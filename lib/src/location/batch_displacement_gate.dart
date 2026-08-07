import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

class BatchDisplacementGate {

  static const double minDisplacementMeters = 20;

  static const double maxAccuracyBoostMeters = 40;

  Position? _lastQueued;

  void reset() {
    _lastQueued = null;
  }

  bool shouldQueue(Position position) {
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
    return distanceMeters >= _requiredMeters(position);
  }

  void markQueued(Position position) {
    _lastQueued = position;
  }

  double requiredMetersFor(Position position) => _requiredMeters(position);

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

  double _requiredMeters(Position position) {
    final accuracy = position.accuracy;
    final accuracyBoost =
        (accuracy.isFinite && accuracy > 0) ? accuracy : 0.0;
    return math.max(
      minDisplacementMeters,
      math.min(accuracyBoost, maxAccuracyBoostMeters),
    );
  }
}
