import 'package:geolocator/geolocator.dart';

import 'location_path_movement_mode.dart';

/// Turn-aware path sampling used by fleet apps (Uber/Strava pattern):
/// keep straight-line spacing, densify only when bearing changes on a real move.
class LocationPathCornerDecision {
  const LocationPathCornerDecision({
    required this.isCornerSample,
    required this.effectiveMinDisplacementMeters,
  });

  final bool isCornerSample;
  final double effectiveMinDisplacementMeters;
}

class LocationPathCornerSampler {
  static const double walkingCornerDegrees = 20;
  static const double drivingCornerDegrees = 12;
  static const double walkingCornerMinDisplacementMeters = 10;
  static const double drivingCornerMinDisplacementMeters = 8;
  static const double walkingMinSegmentMetersForBearing = 5;
  static const double drivingMinSegmentMetersForBearing = 3;
  static const Duration walkingCornerBoostWindow = Duration(seconds: 15);
  static const Duration drivingCornerBoostWindow = Duration(seconds: 20);

  Position? _lastAccepted;
  double? _lastSegmentBearingDegrees;
  DateTime? _cornerBoostUntil;

  void reset() {
    _lastAccepted = null;
    _lastSegmentBearingDegrees = null;
    _cornerBoostUntil = null;
  }

  LocationPathCornerDecision displacementRequirement({
    required Position candidate,
    required LocationPathMovementMode mode,
    required double straightMinDisplacementMeters,
  }) {
    if (mode == LocationPathMovementMode.stopped) {
      return LocationPathCornerDecision(
        isCornerSample: false,
        effectiveMinDisplacementMeters: straightMinDisplacementMeters,
      );
    }

    final lastAccepted = _lastAccepted;
    if (lastAccepted == null) {
      return LocationPathCornerDecision(
        isCornerSample: false,
        effectiveMinDisplacementMeters: straightMinDisplacementMeters,
      );
    }

    final distanceMeters = Geolocator.distanceBetween(
      lastAccepted.latitude,
      lastAccepted.longitude,
      candidate.latitude,
      candidate.longitude,
    );

    final segmentBearing = Geolocator.bearingBetween(
      lastAccepted.latitude,
      lastAccepted.longitude,
      candidate.latitude,
      candidate.longitude,
    );

    final isDriving = mode == LocationPathMovementMode.driving;
    final cornerDegrees =
        isDriving ? drivingCornerDegrees : walkingCornerDegrees;
    final cornerMinMeters = isDriving
        ? drivingCornerMinDisplacementMeters
        : walkingCornerMinDisplacementMeters;
    final minSegmentMeters = isDriving
        ? drivingMinSegmentMetersForBearing
        : walkingMinSegmentMetersForBearing;
    final boostWindow =
        isDriving ? drivingCornerBoostWindow : walkingCornerBoostWindow;

    final prevBearing = _lastSegmentBearingDegrees;
    final headingDelta =
        prevBearing == null || distanceMeters < minSegmentMeters
            ? 0.0
            : _bearingDeltaDegrees(prevBearing, segmentBearing);

    final now = DateTime.now();
    final inBoostWindow =
        _cornerBoostUntil != null && now.isBefore(_cornerBoostUntil!);

    final turnDetected = headingDelta >= cornerDegrees;
    if (turnDetected) {
      _cornerBoostUntil = now.add(boostWindow);
    }

    final useCornerSpacing = inBoostWindow || turnDetected;
    final effectiveMin = useCornerSpacing
        ? cornerMinMeters
        : straightMinDisplacementMeters;

    final isCornerSample =
        useCornerSpacing && distanceMeters >= cornerMinMeters;

    return LocationPathCornerDecision(
      isCornerSample: isCornerSample,
      effectiveMinDisplacementMeters: effectiveMin,
    );
  }

  void markAccepted(Position position) {
    final lastAccepted = _lastAccepted;
    if (lastAccepted != null) {
      final distanceMeters = Geolocator.distanceBetween(
        lastAccepted.latitude,
        lastAccepted.longitude,
        position.latitude,
        position.longitude,
      );
      if (distanceMeters >= drivingMinSegmentMetersForBearing) {
        _lastSegmentBearingDegrees = Geolocator.bearingBetween(
          lastAccepted.latitude,
          lastAccepted.longitude,
          position.latitude,
          position.longitude,
        );
      }
    }
    _lastAccepted = position;
  }

  static double _bearingDeltaDegrees(double from, double to) {
    var delta = (to - from).abs() % 360;
    if (delta > 180) delta = 360 - delta;
    return delta;
  }
}
