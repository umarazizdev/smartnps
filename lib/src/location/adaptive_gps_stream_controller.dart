import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import 'speed_adaptive_gps_policy.dart';

/// Effective GPS stream settings driven by speed-adaptive policy, with a short
/// high-rate boost when a road curve/corner is detected from bearing change.
///
/// Curve handling lives here (stream), not in ping/batch keep-point logic.
class AdaptiveGpsStreamController {
  AdaptiveGpsStreamController({this.onSettingsChanged});

  /// Fired when [interval] / [distanceFilterMeters] change (rebuild stream).
  void Function()? onSettingsChanged;

  static const Duration curveBoostDuration = Duration(seconds: 12);
  static const Duration curveBoostInterval = Duration(seconds: 1);
  static const int curveBoostDistanceFilterMeters = 0;

  /// Same thresholds previously used by [LocationKeepPointGate] bearing keep.
  static const double minCornerBearingDegrees = 12;
  static const double minBearingDistanceMeters = 2;

  SpeedAdaptiveGpsPolicyBand _band = SpeedAdaptiveGpsPolicyBand.bands.first;
  DateTime? _curveBoostUntil;
  Timer? _boostEndTimer;

  Position? _lastObserved;
  double? _lastSegmentBearingDegrees;

  Duration? _appliedInterval;
  int? _appliedDistanceFilterMeters;

  SpeedAdaptiveGpsPolicyBand get band => _band;

  bool get isCurveBoosting {
    final until = _curveBoostUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _curveBoostUntil = null;
    return false;
  }

  Duration get interval =>
      isCurveBoosting ? curveBoostInterval : _band.captureInterval;

  int get distanceFilterMeters => isCurveBoosting
      ? curveBoostDistanceFilterMeters
      : _band.distanceFilterMeters;

  /// Interval to use for the fallback poll timer (matches stream cadence).
  Duration get pollInterval => interval;

  void reset() {
    _boostEndTimer?.cancel();
    _boostEndTimer = null;
    _band = SpeedAdaptiveGpsPolicyBand.bands.first;
    _curveBoostUntil = null;
    _lastObserved = null;
    _lastSegmentBearingDegrees = null;
    _appliedInterval = null;
    _appliedDistanceFilterMeters = null;
  }

  /// Updates band + curve boost from [position]. Returns whether stream
  /// settings changed and the subscription should be rebuilt.
  bool observe(
    Position position,
    SpeedAdaptiveGpsPolicyDecision policyDecision,
  ) {
    _band = policyDecision.band;

    final curveHit = _detectCurveAndAdvance(position);
    if (curveHit) {
      _curveBoostUntil = DateTime.now().add(curveBoostDuration);
      _scheduleBoostEndNotification();
    }

    return _settingsDifferFromApplied();
  }

  /// Call after (re)subscribing so the next observe only rebuilds on real change.
  void markSettingsApplied() {
    _appliedInterval = interval;
    _appliedDistanceFilterMeters = distanceFilterMeters;
  }

  LocationSettings buildLocationSettings({
    required bool allowBackgroundLocationUpdates,
  }) {
    final filter = distanceFilterMeters;
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: filter,
        intervalDuration: interval,
        timeLimit: null,
        forceLocationManager: false,
      );
    }
    return AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: filter,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
      allowBackgroundLocationUpdates: allowBackgroundLocationUpdates,
    );
  }

  bool _settingsDifferFromApplied() {
    return _appliedInterval != interval ||
        _appliedDistanceFilterMeters != distanceFilterMeters;
  }

  void _scheduleBoostEndNotification() {
    _boostEndTimer?.cancel();
    final until = _curveBoostUntil;
    if (until == null) return;
    final remaining = until.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _curveBoostUntil = null;
      if (_settingsDifferFromApplied()) {
        onSettingsChanged?.call();
      }
      return;
    }
    _boostEndTimer = Timer(remaining, () {
      _curveBoostUntil = null;
      if (_settingsDifferFromApplied()) {
        onSettingsChanged?.call();
      }
    });
  }

  /// Returns true when a corner/curve is detected between last and current fix.
  bool _detectCurveAndAdvance(Position position) {
    final last = _lastObserved;
    if (last == null) {
      _lastObserved = position;
      _lastSegmentBearingDegrees = null;
      return false;
    }

    final distanceMeters = Geolocator.distanceBetween(
      last.latitude,
      last.longitude,
      position.latitude,
      position.longitude,
    );

    final segmentBearing = Geolocator.bearingBetween(
      last.latitude,
      last.longitude,
      position.latitude,
      position.longitude,
    );

    var curve = false;
    final prevBearing = _lastSegmentBearingDegrees;
    if (prevBearing != null &&
        distanceMeters >= minBearingDistanceMeters) {
      final delta = _bearingDeltaDegrees(prevBearing, segmentBearing);
      if (delta >= minCornerBearingDegrees) {
        curve = true;
      }
    }

    // Always advance segment tracking so the next leg can detect a turn.
    if (distanceMeters >= minBearingDistanceMeters) {
      _lastSegmentBearingDegrees = segmentBearing;
    }
    _lastObserved = position;
    return curve;
  }

  static double _bearingDeltaDegrees(double from, double to) {
    var delta = (to - from).abs() % 360;
    if (delta > 180) delta = 360 - delta;
    return delta;
  }
}
