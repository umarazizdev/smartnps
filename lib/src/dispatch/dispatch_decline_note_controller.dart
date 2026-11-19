import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'dispatch_decline_note_input.dart';

class DispatchDeclineNoteController extends GetxController {
  DispatchDeclineNoteController({
    required this.textController,
    required this.onChanged,
    required this.onVoicePathChanged,
  });

  static const _maxWaveBars = 32;

  final TextEditingController textController;
  final VoidCallback onChanged;
  final ValueChanged<String?> onVoicePathChanged;

  final mode = DispatchDeclineNoteMode.text.obs;
  final voicePath = RxnString();
  final recording = false.obs;
  final busy = false.obs;
  final recordSeconds = 0.obs;
  final voiceError = RxnString();
  final waveLevels = <double>[].obs;

  final AudioRecorder _recorder = AudioRecorder();
  Timer? _recordTimer;
  StreamSubscription<Amplitude>? _amplitudeSub;

  bool get hasVoice {
    final path = voicePath.value;
    return path != null && path.trim().isNotEmpty && File(path).existsSync();
  }

  @override
  void onClose() {
    _recordTimer?.cancel();
    unawaited(_amplitudeSub?.cancel());
    unawaited(_safeTeardownRecorder());
    super.onClose();
  }

  Future<void> _safeTeardownRecorder() async {
    try {
      await _stopRecording(keepDraft: false);
    } catch (_) {}
    try {
      await _recorder.dispose();
    } catch (_) {}
  }

  Future<void> setMode(DispatchDeclineNoteMode next) async {
    if (mode.value == next || busy.value) return;
    if (recording.value) {
      await _stopRecording(keepDraft: true);
    }
    mode.value = next;
    voiceError.value = null;
    onChanged();
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) return true;
    voiceError.value = 'Microphone permission is required for voice notes.';
    return false;
  }

  Future<String> _createVoicePath() async {
    final dir = await getTemporaryDirectory();
    final folder = Directory('${dir.path}/dispatch_voice');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return '${folder.path}/dispatch_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
  }

  Future<void> toggleRecording() async {
    if (busy.value) return;
    if (recording.value) {
      await _stopRecording(keepDraft: true);
      return;
    }
    await _startRecording();
  }

  Future<void> _startRecording() async {
    if (recording.value || busy.value) return;
    voiceError.value = null;
    if (!await _ensureMicPermission()) return;

    try {
      busy.value = true;
      final canRecord = await _recorder.hasPermission();
      if (!canRecord) {
        voiceError.value = 'Microphone permission is required for voice notes.';
        return;
      }

      final filePath = await _createVoicePath();
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      waveLevels
        ..clear()
        ..addAll(List<double>.filled(8, 0.12));
      await _amplitudeSub?.cancel();
      _amplitudeSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 70))
          .listen((amplitude) {
            final db = amplitude.current;
            final normalized = ((db + 55) / 55).clamp(0.08, 1.0);
            final eased = math.pow(normalized, 0.85).toDouble();
            if (isClosed) return;
            if (waveLevels.length >= _maxWaveBars) {
              waveLevels.removeAt(0);
            }
            waveLevels.add(eased);
          });

      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (isClosed) return;
        recordSeconds.value++;
      });

      recording.value = true;
      recordSeconds.value = 0;
    } catch (_) {
      recording.value = false;
      voiceError.value = 'Unable to start voice recording.';
    } finally {
      if (!isClosed) busy.value = false;
    }
  }

  Future<void> _stopRecording({required bool keepDraft}) async {
    _recordTimer?.cancel();
    _recordTimer = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;

    final isRecordingNow = recording.value || await _recorder.isRecording();
    if (!isRecordingNow) {
      recording.value = false;
      if (!keepDraft) waveLevels.clear();
      return;
    }

    try {
      final path = await _recorder.stop();
      if (!keepDraft) {
        if (path != null) unawaited(_deleteQuietly(path));
        recording.value = false;
        recordSeconds.value = 0;
        waveLevels.clear();
        return;
      }

      if (path == null || path.trim().isEmpty) {
        recording.value = false;
        recordSeconds.value = 0;
        waveLevels.clear();
        voiceError.value = 'Voice note was not saved.';
        return;
      }

      final previous = voicePath.value;
      if (previous != null && previous != path) {
        unawaited(_deleteQuietly(previous));
      }

      if (isClosed) return;
      recording.value = false;
      recordSeconds.value = 0;
      voicePath.value = path;
      voiceError.value = null;
      onVoicePathChanged(path);
      onChanged();
    } catch (_) {
      recording.value = false;
      recordSeconds.value = 0;
      if (keepDraft) {
        voiceError.value = 'Unable to save voice note.';
      }
    }
  }

  Future<void> deleteVoice() async {
    if (recording.value) {
      await _stopRecording(keepDraft: false);
    }
    final path = voicePath.value;
    voicePath.value = null;
    waveLevels.clear();
    if (path != null) unawaited(_deleteQuietly(path));
    onVoicePathChanged(null);
    voiceError.value = null;
    onChanged();
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      return;
    }
  }
}
