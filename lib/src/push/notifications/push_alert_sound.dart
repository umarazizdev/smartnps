import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class PushAlertSound {
  PushAlertSound._();

  static const String assetPath = 'assets/sounds/alert_urgent.mp3';
  static const Duration soundDuration = Duration(seconds: 9);

  static AudioPlayer? _player;
  static bool _playing = false;

  static bool get isPlaying => _playing;

  static Future<void> playLoop() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await stop();
    final player = AudioPlayer();
    _player = player;
    _playing = true;
    try {
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(1);
      await player.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.mixWithOthers,
              AVAudioSessionOptions.duckOthers,
            },
          ),
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notificationRingtone,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ),
      );
      await player.play(AssetSource('sounds/alert_urgent.mp3'));
    } catch (error) {
      _playing = false;
      await player.dispose();
      if (identical(_player, player)) {
        _player = null;
      }
      if (kDebugMode) {
        debugPrint('[PushAlertSound] playLoop failed: $error');
      }
    }
  }

  static Future<void> stop() async {
    final player = _player;
    _player = null;
    _playing = false;
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {}
    try {
      await player.dispose();
    } catch (_) {}
  }
}
