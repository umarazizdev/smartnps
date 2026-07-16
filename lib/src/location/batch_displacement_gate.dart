import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

/// Decides whether a fix moved far enough to be worth `/api/gps/batch`.
///
/// Ping is unaffected. This only suppresses queueing GPS-drift points while
/// the officer is standing still (typical urban jitter of ~5–25m).
class BatchDisplacementGate {
  /// Floor so good-accuracy fixes still need a real walk/drive, not noise.
  static const double minDisplacementMeters = 20;

  /// Cap so a single bad accuracy reading does not demand an unrealistic move.
  static const double maxAccuracyBoostMeters = 40;

  Position? _lastQueued;

  void reset() {
    _lastQueued = null;
  }

  /// Returns whether [position] should be queued for batch.
  ///
  /// The first accepted call seeds the anchor and allows one queue so a trail
  /// can start; later calls require meaningful displacement from that anchor.
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

  /// Call only after a point is successfully accepted into the batch queue.
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
