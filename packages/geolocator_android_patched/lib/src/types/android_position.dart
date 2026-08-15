
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:meta/meta.dart';

@immutable
class AndroidPosition extends Position {
  const AndroidPosition({
    required this.satelliteCount,
    required this.satellitesUsedInFix,
    required longitude,
    required latitude,
    required timestamp,
    required accuracy,
    required altitude,
    required altitudeAccuracy,
    required heading,
    required headingAccuracy,
    required speed,
    required speedAccuracy,
    super.floor,
    isMocked = false,
  }) : super(
          longitude: longitude,
          latitude: latitude,
          timestamp: timestamp,
          accuracy: accuracy,
          altitude: altitude,
          altitudeAccuracy: altitudeAccuracy,
          heading: heading,
          headingAccuracy: headingAccuracy,
          speed: speed,
          speedAccuracy: speedAccuracy,
          isMocked: isMocked,
        );

  final double satelliteCount;

  final double satellitesUsedInFix;

  @override
  bool operator ==(Object other) {
    var areEqual = other is AndroidPosition &&
        super == other &&
        other.satelliteCount == satelliteCount &&
        other.satellitesUsedInFix == satellitesUsedInFix;
    return areEqual;
  }

  @override
  int get hashCode =>
      satelliteCount.hashCode ^ satellitesUsedInFix.hashCode ^ super.hashCode;

  static AndroidPosition fromMap(dynamic message) {
    final Map<dynamic, dynamic> positionMap = message;
    final position = Position.fromMap(positionMap);

    return AndroidPosition(
      satelliteCount: positionMap['gnss_satellite_count'] ?? 0.0,
      satellitesUsedInFix: positionMap['gnss_satellites_used_in_fix'] ?? 0.0,
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: position.timestamp,
      accuracy: position.accuracy,
      altitude: position.altitude,
      altitudeAccuracy: position.altitudeAccuracy,
      heading: position.heading,
      headingAccuracy: position.headingAccuracy,
      speed: position.speed,
      speedAccuracy: position.speedAccuracy,
      floor: position.floor,
      isMocked: position.isMocked,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return super.toJson()
      ..addAll({
        'gnss_satellite_count': satelliteCount,
        'gnss_satellites_used_in_fix': satellitesUsedInFix,
      });
  }
}
