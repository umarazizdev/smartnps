import 'package:geolocator/geolocator.dart';

import 'location_path_movement_mode.dart';
import '../background/location/background_location_accuracy.dart';

enum LocationPathOutlierReason {
  accuracyTooPoor,
  accuracySpike,
  accuracySpikePause,
  jumpOutlier,
  driftJump,
}

class LocationPathOutlierDecision {
  const LocationPathOutlierDecision.accept()
    : shouldQueue = true,
      reason = null;

  const LocationPathOutlierDecision.reject(LocationPathOutlierReason this.reason)
    : shouldQueue = false;

  final bool shouldQueue;
  final LocationPathOutlierReason? reason;
}

/// Rejects batch/path points during accuracy collapse or impossible jumps.
/// Live ping is unaffected — admin still sees approximate location.
class LocationPathOutlierGate {
  static const double accuracySpikeDeltaMeters = 10;
  static const double accuracyRecoveryMarginMeters = 5;
  static const double drivingAccuracyRecoveryMarginMeters = 20;

  static const double walkingJumpMultiplier = 1.2;
  static const double drivingJumpMultiplier = 2.5;
  static const double maxWalkingJumpMeters = 20;
  static const double minDrivingJumpMeters = 60;
  static const double maxDrivingJumpMeters = 250;
  static const double drivingJumpSpeedSlack = 1.6;
  static const double maxImpliedDriftSpeedKmh = 15;
  static const int drivingJumpRejectsBeforeReset = 3;

  Position? _lastAccepted;
  double? _bestRecentAccuracy;
  bool _pausedForAccuracySpike = false;
  int _consecutiveDrivingJumpRejects = 0;

  void reset() {
    _lastAccepted = null;
    _bestRecentAccuracy = null;
    _pausedForAccuracySpike = false;
    _consecutiveDrivingJumpRejects = 0;
  }

  LocationPathOutlierDecision evaluate(
    Position position, {
    LocationPathMovementMode mode = LocationPathMovementMode.walking,
    double? speedKmh,
  }) {
    if (!BackgroundLocationAccuracy.isAcceptableForPath(position)) {
      return const LocationPathOutlierDecision.reject(
        LocationPathOutlierReason.accuracyTooPoor,
      );
    }

    final accuracy = position.accuracy;
    if (_pausedForAccuracySpike) {
      final best = _bestRecentAccuracy;
      final recoveryMargin = mode == LocationPathMovementMode.driving
          ? drivingAccuracyRecoveryMarginMeters
          : accuracyRecoveryMarginMeters;
      final recoveredToPathCap =
          mode == LocationPathMovementMode.driving &&
          accuracy <=
              LocationPathMovementModePolicy.settingsFor(mode)
                  .maxPathAccuracyMeters;
      if ((best != null && accuracy <= best + recoveryMargin) ||
          recoveredToPathCap) {
        _pausedForAccuracySpike = false;
      } else {
        return const LocationPathOutlierDecision.reject(
          LocationPathOutlierReason.accuracySpikePause,
        );
      }
    }

    final last = _lastAccepted;
    if (last != null) {
      final lastAccuracy = last.accuracy;
      if (accuracy - lastAccuracy >= accuracySpikeDeltaMeters) {
        _pausedForAccuracySpike = true;
        return const LocationPathOutlierDecision.reject(
          LocationPathOutlierReason.accuracySpike,
        );
      }

      final jumpMeters = Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        position.latitude,
        position.longitude,
      );
      final elapsedSeconds = position.timestamp
              .difference(last.timestamp)
              .inMilliseconds /
          1000.0;
      final maxJumpMeters = _maxAllowedJumpMeters(
        mode: mode,
        lastAccuracy: lastAccuracy,
        accuracy: accuracy,
        speedKmh: speedKmh,
        elapsedSeconds: elapsedSeconds,
      );
      if (jumpMeters > maxJumpMeters) {
        if (mode == LocationPathMovementMode.driving &&
            (speedKmh ?? 0) >= LocationPathMovementModePolicy.drivingMinSpeedKmh) {
          _consecutiveDrivingJumpRejects++;
          // Stuck cascade: last accepted never moves, so every later fix fails.
          if (_consecutiveDrivingJumpRejects >= drivingJumpRejectsBeforeReset) {
            _lastAccepted = position;
            _consecutiveDrivingJumpRejects = 0;
            _pausedForAccuracySpike = false;
            return const LocationPathOutlierDecision.accept();
          }
        } else {
          _consecutiveDrivingJumpRejects = 0;
        }
        return const LocationPathOutlierDecision.reject(
          LocationPathOutlierReason.jumpOutlier,
        );
      }

      if (elapsedSeconds > 0 &&
          mode != LocationPathMovementMode.driving &&
          jumpMeters > maxWalkingJumpMeters * 0.5) {
        final impliedSpeedKmh = (jumpMeters / elapsedSeconds) * 3.6;
        final reportedSpeedKmh = speedKmh ?? 0;
        if (impliedSpeedKmh > maxImpliedDriftSpeedKmh &&
            reportedSpeedKmh <
                LocationPathMovementModePolicy.drivingMinSpeedKmh) {
          return const LocationPathOutlierDecision.reject(
            LocationPathOutlierReason.driftJump,
          );
        }
      }
    }

    _consecutiveDrivingJumpRejects = 0;
    return const LocationPathOutlierDecision.accept();
  }

  double _maxAllowedJumpMeters({
    required LocationPathMovementMode mode,
    required double lastAccuracy,
    required double accuracy,
    double? speedKmh,
    double elapsedSeconds = 0,
  }) {
    final combined = lastAccuracy + accuracy;
    if (mode == LocationPathMovementMode.driving) {
      final accuracyScaled = drivingJumpMultiplier * combined;
      final safeElapsed = elapsedSeconds.isFinite && elapsedSeconds > 0
          ? elapsedSeconds.clamp(1.0, 30.0)
          : 3.0;
      final speed = (speedKmh ?? 0).clamp(0, 160);
      final speedBasedMeters =
          (speed / 3.6) * safeElapsed * drivingJumpSpeedSlack + combined;
      final allowed = [
        minDrivingJumpMeters,
        accuracyScaled,
        speedBasedMeters,
      ].reduce((a, b) => a > b ? a : b);
      return allowed.clamp(minDrivingJumpMeters, maxDrivingJumpMeters);
    }

    final scaled = walkingJumpMultiplier * combined;
    return scaled.clamp(0, maxWalkingJumpMeters);
  }

  void markAccepted(Position position) {
    _lastAccepted = position;
    _consecutiveDrivingJumpRejects = 0;
    final accuracy = position.accuracy;
    final best = _bestRecentAccuracy;
    if (best == null || accuracy < best) {
      _bestRecentAccuracy = accuracy;
    }
  }
}
