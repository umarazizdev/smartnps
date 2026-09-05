import 'package:geolocator/geolocator.dart';

class BackgroundLocationAccuracy {
  BackgroundLocationAccuracy._();

  static const double maxSpeedTrustMeters = 50.0;
  static const double maxPingMeters = 100.0;
  static const double maxPathMeters = 25.0;

  static bool isValidReading(Position position) {
    final accuracy = position.accuracy;
    return !accuracy.isNaN && !accuracy.isInfinite && accuracy > 0;
  }

  static bool isAcceptableForPing(Position position) =>
      isValidReading(position) && position.accuracy <= maxPingMeters;

  static bool isAcceptableForPath(Position position) =>
      isValidReading(position) && position.accuracy <= maxPathMeters;

  static bool isTrustedForSpeed(Position position) =>
      isValidReading(position) && position.accuracy <= maxSpeedTrustMeters;

  static bool isAcceptable(Position position) => isValidReading(position);
}
