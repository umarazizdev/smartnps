import 'package:geolocator/geolocator.dart';

import 'speed_adaptive_gps_policy.dart';

enum LocationKeepPointTrigger { first, stream }

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

  Position? _lastKept;
  DateTime? _lastKeptAt;

  void reset() {
    _lastKept = null;
    _lastKeptAt = null;
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
      _lastKept = position;
      _lastKeptAt = now;
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

    _lastKept = position;
    _lastKeptAt = now;
    return LocationKeepPointDecision.keep(
      trigger: LocationKeepPointTrigger.stream,
      uploadInterval: uploadInterval,
      distanceMeters: distanceMeters,
    );
  }
}
