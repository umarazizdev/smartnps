import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

import 'foreground_settings.dart';

class AndroidSettings extends LocationSettings {
  AndroidSettings({
    this.forceLocationManager = false,
    super.accuracy,
    super.distanceFilter,
    this.intervalDuration,
    super.timeLimit,
    this.foregroundNotificationConfig,
    this.useMSLAltitude = false,
  });

  final bool forceLocationManager;

  final Duration? intervalDuration;

  final ForegroundNotificationConfig? foregroundNotificationConfig;

  final bool useMSLAltitude;

  @override
  Map<String, dynamic> toJson() {
    return super.toJson()
      ..addAll({
        'forceLocationManager': forceLocationManager,
        'timeInterval': intervalDuration?.inMilliseconds,
        'foregroundNotificationConfig': foregroundNotificationConfig?.toJson(),
        'useMSLAltitude': useMSLAltitude,
      });
  }
}
