import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import 'speed_adaptive_gps_policy.dart';

class AdaptiveGpsStreamController {
  AdaptiveGpsStreamController({this.onSettingsChanged});

  void Function()? onSettingsChanged;

  static const int iosLockedDistanceFilterMeters = 5;

  static const Duration curveBoostDuration = Duration(seconds: 12);
  static const Duration curveBoostInterval = Duration(seconds: 1);
  static const int curveBoostDistanceFilterMeters = 0;

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
    if (Platform.isIOS) return false;
    final until = _curveBoostUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _curveBoostUntil = null;
    return false;
  }

  Duration get interval =>
      isCurveBoosting ? curveBoostInterval : _band.captureInterval;

  int get distanceFilterMeters {
    if (Platform.isIOS) return iosLockedDistanceFilterMeters;
    return isCurveBoosting
        ? curveBoostDistanceFilterMeters
        : _band.distanceFilterMeters;
  }

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

  bool observe(
    Position position,
    SpeedAdaptiveGpsPolicyDecision policyDecision,
  ) {
    _band = policyDecision.band;

    if (Platform.isIOS) {
      return false;
    }

    final curveHit = _detectCurveAndAdvance(position);
    if (curveHit) {
      _curveBoostUntil = DateTime.now().add(curveBoostDuration);
      _scheduleBoostEndNotification();
    }

    return _settingsDifferFromApplied();
  }

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
      activityType: ActivityType.otherNavigation,
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
