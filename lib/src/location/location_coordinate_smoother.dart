import 'package:geolocator/geolocator.dart';

import 'location_path_freshness.dart';
import 'location_path_movement_mode.dart';

enum PathSmoothingMethod {
  none,
  accuracyWeightedAverage,
  measuredMedian,
}

/// Measured-only coordinate smoothing for security path points.
class LocationCoordinateSmoother {
  static const double _minAccuracyMeters = 1.0;

  int _windowSize = 3;
  PathSmoothingMethod _method = PathSmoothingMethod.accuracyWeightedAverage;
  final List<Position> _buffer = [];

  void configure(LocationPathModeSettings settings) {
    _windowSize = settings.smoothWindowSize;
    _method = settings.smoothingMethod;
    _purgeStale();
    while (_buffer.length > _windowSize) {
      _buffer.removeAt(0);
    }
  }

  void reset() {
    _buffer.clear();
    _windowSize = 3;
    _method = PathSmoothingMethod.accuracyWeightedAverage;
  }

  void observe(Position position) {
    if (_method == PathSmoothingMethod.none || _windowSize <= 0) return;
    _purgeStale(now: position.timestamp);
    _buffer.add(position);
    while (_buffer.length > _windowSize) {
      _buffer.removeAt(0);
    }
  }

  Position smooth(Position latest) {
    _purgeStale(now: latest.timestamp);
    if (_method == PathSmoothingMethod.none ||
        _windowSize <= 0 ||
        _buffer.isEmpty) {
      return latest;
    }

    return switch (_method) {
      PathSmoothingMethod.accuracyWeightedAverage =>
        _smoothAccuracyWeighted(latest),
      PathSmoothingMethod.measuredMedian => _smoothMedian(latest),
      PathSmoothingMethod.none => latest,
    };
  }

  void _purgeStale({DateTime? now}) {
    final cutoff = (now ?? DateTime.now()).toUtc().subtract(
      LocationPathFreshness.reuseMaxAge,
    );
    _buffer.removeWhere(
      (point) => point.timestamp.toUtc().isBefore(cutoff),
    );
  }

  Position _smoothAccuracyWeighted(Position latest) {
    var lat = 0.0;
    var lng = 0.0;
    var accuracy = 0.0;
    var weightSum = 0.0;
    for (var i = 0; i < _buffer.length; i++) {
      final weight = _accuracyWeightFor(_buffer[i], i);
      lat += _buffer[i].latitude * weight;
      lng += _buffer[i].longitude * weight;
      accuracy += _buffer[i].accuracy * weight;
      weightSum += weight;
    }

    return _copyPosition(
      latest,
      latitude: lat / weightSum,
      longitude: lng / weightSum,
      accuracy: accuracy / weightSum,
    );
  }

  Position _smoothMedian(Position latest) {
    final lats = _buffer.map((point) => point.latitude).toList()..sort();
    final lngs = _buffer.map((point) => point.longitude).toList()..sort();
    final accuracies = _buffer.map((point) => point.accuracy).toList()..sort();

    return _copyPosition(
      latest,
      latitude: _median(lats),
      longitude: _median(lngs),
      accuracy: _median(accuracies),
    );
  }

  double _accuracyWeightFor(Position position, int index) {
    final accuracy = position.accuracy.clamp(_minAccuracyMeters, 100.0);
    final accuracyWeight = 1.0 / (accuracy * accuracy);
    final recencyWeight = (index + 1).toDouble();
    return accuracyWeight * recencyWeight;
  }

  double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final mid = values.length ~/ 2;
    if (values.length.isOdd) return values[mid];
    return (values[mid - 1] + values[mid]) / 2;
  }

  Position _copyPosition(
    Position template, {
    required double latitude,
    required double longitude,
    required double accuracy,
  }) {
    return Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: template.timestamp,
      accuracy: accuracy,
      altitude: template.altitude,
      altitudeAccuracy: template.altitudeAccuracy,
      heading: template.heading,
      headingAccuracy: template.headingAccuracy,
      speed: template.speed,
      speedAccuracy: template.speedAccuracy,
      floor: template.floor,
      isMocked: template.isMocked,
    );
  }
}
