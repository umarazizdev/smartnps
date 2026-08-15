import 'package:geolocator/geolocator.dart';

import 'speed_adaptive_gps_policy.dart';

enum LocationKeepPointTrigger { first, stream, heading, indoor, heartbeat }

class LocationKeepPointDecision {
  const LocationKeepPointDecision._({
    required this.shouldKeep,
    this.trigger,
    this.uploadInterval,
    this.distanceMeters,
  });

  const LocationKeepPointDecision.skip()
    : shouldKeep = false,
      trigger = null,
      uploadInterval = null,
      distanceMeters = null;

  factory LocationKeepPointDecision.keep({
    required LocationKeepPointTrigger trigger,
    required Duration uploadInterval,
    double? distanceMeters,
  }) {
    return LocationKeepPointDecision._(
      shouldKeep: true,
      trigger: trigger,
      uploadInterval: uploadInterval,
      distanceMeters: distanceMeters,
    );
  }

  final bool shouldKeep;
  final LocationKeepPointTrigger? trigger;
  final Duration? uploadInterval;
  final double? distanceMeters;
}

class LocationKeepPointGate {
  static const Duration minKeepInterval = Duration(seconds: 1);

  static const double pathDistanceMeters = 5;
  static const double headingMinDistanceMeters = 4;
  static const double headingMinDegrees = 15;
  static const double indoorMinDistanceMeters = 3;
  static const double movingSpeedKmh = 2;
  static const double accuracyWorseDeltaMeters = 10;

  Position? _lastKept;
  DateTime? _lastKeptAt;
  double? _lastKeptAccuracy;
  double? _lastKeptBearingDegrees;
  bool _lastKeptMoving = false;

  void reset() {
    _lastKept = null;
    _lastKeptAt = null;
    _lastKeptAccuracy = null;
    _lastKeptBearingDegrees = null;
    _lastKeptMoving = false;
  }

  LocationKeepPointDecision evaluate(
    Position position,
    SpeedAdaptiveGpsPolicyDecision policyDecision, {
    Duration? streamInterval,
  }) {
    final now = DateTime.now();
    final uploadInterval = streamInterval ?? policyDecision.band.uploadInterval;
    final lastKept = _lastKept;
    final lastKeptAt = _lastKeptAt;

    if (lastKept == null || lastKeptAt == null) {
      return _keep(
        position: position,
        trigger: LocationKeepPointTrigger.first,
        uploadInterval: uploadInterval,
        policyDecision: policyDecision,
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

    final speedKmh =
        policyDecision.smoothedSpeedKmh ?? policyDecision.rawSpeedKmh ?? 0;
    final isMoving = speedKmh >= movingSpeedKmh;

    final segmentBearing = Geolocator.bearingBetween(
      lastKept.latitude,
      lastKept.longitude,
      position.latitude,
      position.longitude,
    );
    final prevBearing = _lastKeptBearingDegrees;
    final headingDelta = prevBearing == null
        ? 0.0
        : _bearingDeltaDegrees(prevBearing, segmentBearing);

    final lastAccuracy = _lastKeptAccuracy ?? position.accuracy;
    final accuracyWorse =
        position.accuracy - lastAccuracy >= accuracyWorseDeltaMeters;
    final enteredStationary = _lastKeptMoving && !isMoving;

    LocationKeepPointTrigger? trigger;
    if (elapsed >= uploadInterval) {
      trigger = LocationKeepPointTrigger.heartbeat;
    } else if (distanceMeters >= pathDistanceMeters) {
      trigger = LocationKeepPointTrigger.stream;
    } else if (isMoving &&
        distanceMeters >= headingMinDistanceMeters &&
        headingDelta >= headingMinDegrees) {
      trigger = LocationKeepPointTrigger.heading;
    } else if (distanceMeters >= indoorMinDistanceMeters &&
        (accuracyWorse || enteredStationary)) {
      trigger = LocationKeepPointTrigger.indoor;
    }

    if (trigger == null) {
      return const LocationKeepPointDecision.skip();
    }

    return _keep(
      position: position,
      trigger: trigger,
      uploadInterval: uploadInterval,
      policyDecision: policyDecision,
      distanceMeters: distanceMeters,
      segmentBearing: distanceMeters >= headingMinDistanceMeters
          ? segmentBearing
          : prevBearing,
    );
  }

  LocationKeepPointDecision _keep({
    required Position position,
    required LocationKeepPointTrigger trigger,
    required Duration uploadInterval,
    required SpeedAdaptiveGpsPolicyDecision policyDecision,
    double? distanceMeters,
    double? segmentBearing,
  }) {
    final speedKmh =
        policyDecision.smoothedSpeedKmh ?? policyDecision.rawSpeedKmh ?? 0;
    _lastKept = position;
    _lastKeptAt = DateTime.now();
    _lastKeptAccuracy = position.accuracy;
    _lastKeptMoving = speedKmh >= movingSpeedKmh;
    if (segmentBearing != null) {
      _lastKeptBearingDegrees = segmentBearing;
    }
    return LocationKeepPointDecision.keep(
      trigger: trigger,
      uploadInterval: uploadInterval,
      distanceMeters: distanceMeters,
    );
  }

  static double _bearingDeltaDegrees(double from, double to) {
    var delta = (to - from).abs() % 360;
    if (delta > 180) delta = 360 - delta;
    return delta;
  }
}
