import 'package:geolocator/geolocator.dart';

import 'speed_adaptive_gps_policy.dart';

enum LocationKeepPointTrigger { first, time, bearing }

class LocationKeepPointDecision {
  const LocationKeepPointDecision._({
    required this.shouldKeep,
    this.trigger,
    this.uploadInterval,
    this.distanceMeters,
    this.bearingDeltaDegrees,
  });

  const LocationKeepPointDecision.skip()
    : shouldKeep = false,
      trigger = null,
      uploadInterval = null,
      distanceMeters = null,
      bearingDeltaDegrees = null;

  factory LocationKeepPointDecision.keep({
    required LocationKeepPointTrigger trigger,
    required Duration uploadInterval,
    double? distanceMeters,
    double? bearingDeltaDegrees,
  }) {
    return LocationKeepPointDecision._(
      shouldKeep: true,
      trigger: trigger,
      uploadInterval: uploadInterval,
      distanceMeters: distanceMeters,
      bearingDeltaDegrees: bearingDeltaDegrees,
    );
  }

  final bool shouldKeep;
  final LocationKeepPointTrigger? trigger;
  final Duration? uploadInterval;
  final double? distanceMeters;
  final double? bearingDeltaDegrees;
}

/// Decides when to keep/upload a GPS fix using speed-adaptive timing on
/// straight roads and bearing change on corners so curves are not chord-cut.
class LocationKeepPointGate {
  static const Duration minKeepInterval = Duration(seconds: 1);
  /// Low threshold so gentle curves, tight corners, and slow U-turns keep points.
  static const double minCornerBearingDegrees = 12;
  /// Minimum movement before bearing is evaluated (avoids GPS jitter on straights).
  static const double minBearingDistanceMeters = 2;

  Position? _lastKept;
  DateTime? _lastKeptAt;
  double? _lastSegmentBearingDegrees;

  void reset() {
    _lastKept = null;
    _lastKeptAt = null;
    _lastSegmentBearingDegrees = null;
  }

  LocationKeepPointDecision evaluate(
    Position position,
    SpeedAdaptiveGpsPolicyDecision policyDecision,
  ) {
    final now = DateTime.now();
    final uploadInterval = policyDecision.band.uploadInterval;
    final lastKept = _lastKept;
    final lastKeptAt = _lastKeptAt;

    if (lastKept == null || lastKeptAt == null) {
      _markFirstKept(position, now);
      return LocationKeepPointDecision.keep(
        trigger: LocationKeepPointTrigger.first,
        uploadInterval: uploadInterval,
      );
    }

    final elapsed = now.difference(lastKeptAt);
    if (elapsed < minKeepInterval) {
      return const LocationKeepPointDecision.skip();
    }

    final distanceMeters = Geolocator.distanceBetween(
      lastKept.latitude,
      lastKept.longitude,
      position.latitude,
      position.longitude,
    );

    final timeTriggered = elapsed >= uploadInterval;

    final segmentBearing = Geolocator.bearingBetween(
      lastKept.latitude,
      lastKept.longitude,
      position.latitude,
      position.longitude,
    );
    final bearingDelta = _lastSegmentBearingDegrees == null
        ? 0.0
        : _bearingDeltaDegrees(
            _lastSegmentBearingDegrees!,
            segmentBearing,
          );
    final bearingTriggered =
        distanceMeters >= minBearingDistanceMeters &&
        _lastSegmentBearingDegrees != null &&
        bearingDelta >= minCornerBearingDegrees;

    if (timeTriggered || bearingTriggered) {
      final trigger = timeTriggered
          ? LocationKeepPointTrigger.time
          : LocationKeepPointTrigger.bearing;

      _markKept(
        position,
        now,
        segmentBearing: segmentBearing,
      );
      return LocationKeepPointDecision.keep(
        trigger: trigger,
        uploadInterval: uploadInterval,
        distanceMeters: distanceMeters,
        bearingDeltaDegrees: bearingTriggered ? bearingDelta : null,
      );
    }

    return const LocationKeepPointDecision.skip();
  }

  void _markKept(
    Position position,
    DateTime keptAt, {
    required double segmentBearing,
  }) {
    _lastSegmentBearingDegrees = segmentBearing;
    _lastKept = position;
    _lastKeptAt = keptAt;
  }

  void _markFirstKept(Position position, DateTime keptAt) {
    _lastKept = position;
    _lastKeptAt = keptAt;
    _lastSegmentBearingDegrees = null;
  }

  static double _bearingDeltaDegrees(double from, double to) {
    var delta = (to - from).abs() % 360;
    if (delta > 180) delta = 360 - delta;
    return delta;
  }
}
