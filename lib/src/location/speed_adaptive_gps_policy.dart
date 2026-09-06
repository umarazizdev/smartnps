import 'package:geolocator/geolocator.dart';

import '../background/location/background_location_accuracy.dart';

class SpeedAdaptiveGpsPolicyBand {
  const SpeedAdaptiveGpsPolicyBand({
    required this.minKmh,
    required this.maxKmh,
    required this.label,
    required this.state,
    required this.motionActivity,
    required this.captureInterval,
    required this.uploadInterval,
    required this.distanceFilterMeters,
  });

  final double minKmh;
  final double? maxKmh;
  final String label;
  final String state;
  final String motionActivity;
  final Duration captureInterval;
  final Duration uploadInterval;
  final int distanceFilterMeters;

  static const bands = [
    SpeedAdaptiveGpsPolicyBand(
      minKmh: 0,
      maxKmh: 2,
      label: '0-2 km/h',
      state: 'Stationary / standing',
      motionActivity: 'stationary',
      captureInterval: Duration(seconds: 30),
      uploadInterval: Duration(seconds: 30),
      distanceFilterMeters: 10,
    ),
    SpeedAdaptiveGpsPolicyBand(
      minKmh: 2,
      maxKmh: 8,
      label: '2-8 km/h',
      state: 'Walking / patrol',
      motionActivity: 'walking',
      captureInterval: Duration(seconds: 10),
      uploadInterval: Duration(seconds: 10),
      distanceFilterMeters: 5,
    ),
    SpeedAdaptiveGpsPolicyBand(
      minKmh: 8,
      maxKmh: 30,
      label: '8-30 km/h',
      state: 'Slow / urban vehicle',

      motionActivity: 'automotive',
      captureInterval: Duration(seconds: 5),
      uploadInterval: Duration(seconds: 5),
      distanceFilterMeters: 5,
    ),
    SpeedAdaptiveGpsPolicyBand(
      minKmh: 30,
      maxKmh: 60,
      label: '30-60 km/h',
      state: 'Vehicle movement',
      motionActivity: 'automotive',
      captureInterval: Duration(seconds: 3),
      uploadInterval: Duration(seconds: 3),
      distanceFilterMeters: 3,
    ),
    SpeedAdaptiveGpsPolicyBand(
      minKmh: 60,
      maxKmh: 100,
      label: '60-100 km/h',
      state: 'Fast vehicle',
      motionActivity: 'automotive',
      captureInterval: Duration(seconds: 2),
      uploadInterval: Duration(seconds: 2),
      distanceFilterMeters: 3,
    ),
    SpeedAdaptiveGpsPolicyBand(
      minKmh: 100,
      maxKmh: null,
      label: '100+ km/h',
      state: 'High-speed vehicle',
      motionActivity: 'automotive',
      captureInterval: Duration(seconds: 1),
      uploadInterval: Duration(seconds: 1),
      distanceFilterMeters: 0,
    ),
  ];

  static SpeedAdaptiveGpsPolicyBand forSpeedKmh(double speedKmh) {
    for (final band in bands) {
      final max = band.maxKmh;
      if (speedKmh >= band.minKmh && (max == null || speedKmh < max)) {
        return band;
      }
    }
    return bands.first;
  }
}

class SpeedAdaptiveGpsPolicyDecision {
  const SpeedAdaptiveGpsPolicyDecision({
    required this.band,
    required this.rawSpeedKmh,
    required this.smoothedSpeedKmh,
    required this.speedAccuracyMetersPerSecond,
    required this.isTrusted,
  });

  final SpeedAdaptiveGpsPolicyBand band;
  final double? rawSpeedKmh;
  final double? smoothedSpeedKmh;
  final double? speedAccuracyMetersPerSecond;
  final bool isTrusted;

  bool get shouldQueueForBatch {
    if (band.motionActivity == 'stationary') return false;
    final maxKmh = band.maxKmh;
    if (maxKmh != null && maxKmh <= 2) return false;
    final speedKmh = smoothedSpeedKmh ?? rawSpeedKmh;
    if (speedKmh != null && speedKmh < 2) return false;
    return true;
  }

  Map<String, dynamic> toJson() {
    return {
      'speedBand': band.label,
      'speedState': band.state,
      'speedKmh': rawSpeedKmh,
      'smoothedSpeedKmh': smoothedSpeedKmh,
      'gpsSpeedTrusted': isTrusted,
      'captureIntervalSeconds': band.captureInterval.inSeconds,
      'uploadIntervalSeconds': band.uploadInterval.inSeconds,
      'distanceFilterMeters': band.distanceFilterMeters,
    };
  }
}

class SpeedAdaptiveGpsPolicyTracker {
  final List<double> _recentTrustedSpeedsKmh = [];
  SpeedAdaptiveGpsPolicyBand _currentBand =
      SpeedAdaptiveGpsPolicyBand.bands.first;
  double? _lastSmoothedSpeedKmh;

  SpeedAdaptiveGpsPolicyDecision evaluate(Position position) {
    final rawSpeedKmh = _readSpeedKmh(position);
    final speedAccuracy = readSpeedAccuracyMetersPerSecond(position);
    final trusted =
        rawSpeedKmh != null &&
        BackgroundLocationAccuracy.isAcceptable(position) &&
        (speedAccuracy == null || speedAccuracy <= 5);

    if (trusted) {
      _recentTrustedSpeedsKmh.add(rawSpeedKmh);
      if (_recentTrustedSpeedsKmh.length > 5) {
        _recentTrustedSpeedsKmh.removeAt(0);
      }
      _lastSmoothedSpeedKmh = _median(_recentTrustedSpeedsKmh);
      _currentBand = SpeedAdaptiveGpsPolicyBand.forSpeedKmh(
        _lastSmoothedSpeedKmh!,
      );
    }

    return SpeedAdaptiveGpsPolicyDecision(
      band: _currentBand,
      rawSpeedKmh: rawSpeedKmh,
      smoothedSpeedKmh: _lastSmoothedSpeedKmh,
      speedAccuracyMetersPerSecond: speedAccuracy,
      isTrusted: trusted,
    );
  }

  static double? readSpeedAccuracyMetersPerSecond(Position position) {
    try {
      final dynamic dynamicPosition = position;
      final value = dynamicPosition.speedAccuracy;
      if (value is num && !value.isNaN && !value.isInfinite) {
        return value.toDouble();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  double? _readSpeedKmh(Position position) {
    final speedMetersPerSecond = position.speed;
    final speedKmh = speedMetersPerSecond * 3.6;
    if (speedKmh.isNaN || speedKmh.isInfinite || speedKmh < 0) return null;
    return speedKmh;
  }

  double _median(List<double> values) {
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }
}
