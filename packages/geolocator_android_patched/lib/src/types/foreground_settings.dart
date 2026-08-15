import 'dart:ui';

class AndroidResource {
  final String name;

  final String defType;

  const AndroidResource({
    required this.name,
    this.defType = 'drawable',
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'defType': defType,
    };
  }
}

class ForegroundNotificationConfig {
  const ForegroundNotificationConfig({
    required this.notificationTitle,
    required this.notificationText,
    this.notificationChannelName = 'Background Location',
    this.notificationIcon =
        const AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
    this.enableWifiLock = false,
    this.enableWakeLock = false,
    this.setOngoing = false,
    this.color,
  });

  final String notificationTitle;

  final String notificationText;

  final String notificationChannelName;

  final AndroidResource notificationIcon;

  final bool enableWifiLock;

  final bool enableWakeLock;

  final bool setOngoing;

  final Color? color;

  Map<String, dynamic> toJson() {
    return {
      'enableWakeLock': enableWakeLock,
      'enableWifiLock': enableWifiLock,
      'notificationTitle': notificationTitle,
      'notificationIcon': notificationIcon.toJson(),
      'notificationText': notificationText,
      'notificationChannelName': notificationChannelName,
      'setOngoing': setOngoing,
      'color': color?.toARGB32(),
    };
  }
}
