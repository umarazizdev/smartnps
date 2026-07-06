import 'package:geolocator/geolocator.dart';

/// Minimum quality bar for background duty location uploads.
class BackgroundLocationAccuracy {
  BackgroundLocationAccuracy._();

  static const double maxAllowedMeters = 50.0;

  static bool isAcceptable(Position position) {
    final accuracy = position.accuracy;
    if (accuracy.isNaN || accuracy.isInfinite || accuracy <= 0) {
      return false;
    }
    return accuracy <= maxAllowedMeters;
  }
}
