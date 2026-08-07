import 'package:flutter/services.dart';

class VisitOrientation {
  VisitOrientation._();

  static const appAllowed = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  static Future<void> enableCaptureOrientations() async {
    try {
      await SystemChrome.setPreferredOrientations(appAllowed);
    } catch (_) {}
  }
}
