import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PushAlertVibration {
  PushAlertVibration._();

  static const MethodChannel _settingsChannel = MethodChannel(
    'com.smartnps360.app/settings',
  );

  static const int defaultDurationMs = 30000;
  static const int maxDurationMs = 30000;

  static bool _playing = false;
  static Timer? _autoStopTimer;

  static bool get isPlaying => _playing;

  static Future<void> playLong({int durationMs = defaultDurationMs}) async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final clamped = durationMs.clamp(500, maxDurationMs);
    _autoStopTimer?.cancel();
    _playing = true;
    try {
      await _settingsChannel.invokeMethod<void>('vibrateLong', {
        'durationMs': clamped,
        'repeat': true,
      });
      _autoStopTimer = Timer(Duration(milliseconds: clamped), () {
        _playing = false;
        _autoStopTimer = null;
      });
    } catch (error) {
      _playing = false;
      if (kDebugMode) {
        debugPrint('[PushAlertVibration] vibrateLong failed: $error');
      }
    }
  }

  static Future<void> stop() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    _playing = false;
    try {
      await _settingsChannel.invokeMethod<void>('stopVibrate');
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[PushAlertVibration] stopVibrate failed: $error');
      }
    }
  }

  static Future<void> acknowledge() => stop();
}
