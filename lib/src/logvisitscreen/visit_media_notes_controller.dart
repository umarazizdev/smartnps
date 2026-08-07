import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'visit_media_draft_store.dart';
import 'visit_video_flow_controller.dart';

enum VisitMediaNoteKind { text, voice }

typedef NotesConfirmCallback =
    Future<bool> Function({
      required String title,
      required String message,
      String primaryLabel,
      bool destructive,
    });

class VisitMediaNotesController extends GetxController {
  VisitMediaNotesController({
    this.mediaPath = '',
    required this.kind,
    this.replacingOther = false,
    this.batchMode = false,
  });

  final String mediaPath;
  final VisitMediaNoteKind kind;

  final bool batchMode;

  bool replacingOther;

  NotesConfirmCallback? confirm;

  final textController = TextEditingController();
  final voiceNotePath = Rxn<String>();
  final isRecording = false.obs;
  final isPlaying = false.obs;
  final isBusy = false.obs;
  final recordSeconds = 0.obs;
  final errorMessage = Rxn<String>();
  final waveLevels = <double>[].obs;
  final hasTextNote = false.obs;
  final playbackProgress = 0.0.obs;
  final hasChanges = false.obs;

  List<double> get displayWaveLevels {
    if (_recordedWaveLevels.isNotEmpty) return _recordedWaveLevels;
    if (voiceNotePath.value != null) return _fallbackWaveLevels();
    return const <double>[];
  }

  static const _maxWaveBars = 32;

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  Timer? _recordTimer;
  Timer? _playbackWaveTimer;
  StreamSubscription? _playerCompleteSub;
  StreamSubscription? _playerPositionSub;
  StreamSubscription<Amplitude>? _amplitudeSub;
  List<double> _recordedWaveLevels = <double>[];
  Duration _playbackDuration = Duration.zero;
  bool _sourceLoaded = false;

  String _initialText = '';
  String? _initialVoicePath;
  final Set<String> _tempVoicePaths = <String>{};
  bool _committed = false;

  late final VisitVideoFlowController _flowController;

  bool get isTextMode => kind == VisitMediaNoteKind.text;

  @override
  void onInit() {
    super.onInit();
    _flowController = Get.find<VisitVideoFlowController>();

    if (batchMode) {
      _initFromBatchNote();
    } else {
      _initFromMediaItem();
    }
    _refreshHasChanges();

    _playerCompleteSub = _player.onPlayerComplete.listen((_) {
      isPlaying.value = false;
      playbackProgress.value = 0;
      _sourceLoaded = false;
      _stopPlaybackWave();
    });
    _playerPositionSub = _player.onPositionChanged.listen((position) {
      if (!isPlaying.value) return;
      final totalMs = _playbackDuration.inMilliseconds;
      if (totalMs <= 0) return;
      playbackProgress.value = (position.inMilliseconds / totalMs).clamp(
        0.0,
        1.0,
      );
      _updatePlaybackWave(playbackProgress.value);
    });
  }

  void _initFromBatchNote() {
    final note = _flowController.batchNote.value;
    if (isTextMode) {
      _initialVoicePath = note.voiceNotePath;
      if (note.hasVoiceNote && replacingOther) {
        _initialText = '';
        textController.text = '';
        hasTextNote.value = false;
      } else {
        _initialText = note.textNote;
        textController.text = _initialText;
        hasTextNote.value = _initialText.trim().isNotEmpty;
      }
      voiceNotePath.value = null;
    } else if (note.hasVoiceNote) {
      _initialVoicePath = note.voiceNotePath;
      voiceNotePath.value = note.voiceNotePath;
      _initialText = '';
      textController.text = '';
      hasTextNote.value = false;
      _recordedWaveLevels = _fallbackWaveLevels();
      waveLevels.assignAll(_recordedWaveLevels);
    } else {
      _initialText = note.textNote;
      textController.text = '';
      hasTextNote.value = false;
      _initialVoicePath = null;
      voiceNotePath.value = null;
    }
  }

  void _initFromMediaItem() {
    VisitMediaItem? item;
    for (final e in _flowController.mediaItems) {
      if (e.path == mediaPath) {
        item = e;
        break;
      }
    }

    if (isTextMode) {
      _initialVoicePath = item?.voiceNotePath;
      if (item != null && item.hasVoiceNote && replacingOther) {
        _initialText = '';
        textController.text = '';
        hasTextNote.value = false;
      } else {
        _initialText = item?.textNote ?? '';
        textController.text = _initialText;
        hasTextNote.value = _initialText.trim().isNotEmpty;
      }
      voiceNotePath.value = null;
    } else if (item != null && item.hasVoiceNote) {
      _initialVoicePath = item.voiceNotePath;
      voiceNotePath.value = item.voiceNotePath;
      _initialText = '';
      textController.text = '';
      hasTextNote.value = false;
      _recordedWaveLevels = _fallbackWaveLevels();
      waveLevels.assignAll(_recordedWaveLevels);
    } else {
      _initialText = item?.textNote ?? '';
      textController.text = '';
      hasTextNote.value = false;
      _initialVoicePath = null;
      voiceNotePath.value = null;
    }
  }

  @override
  void onClose() {
    _recordTimer?.cancel();
    _playbackWaveTimer?.cancel();
    _amplitudeSub?.cancel();
    _playerCompleteSub?.cancel();
    _playerPositionSub?.cancel();
    unawaited(_stopRecordingInternal(keepDraft: false));
    unawaited(_player.stop());
    unawaited(_player.dispose());
    unawaited(_recorder.dispose());
    if (!_committed) {
      _discardTempVoices();
    }
    textController.dispose();
    super.onClose();
  }

  void _refreshHasChanges() {
    if (isTextMode) {
      hasChanges.value = textController.text.trim() != _initialText.trim();
      return;
    }
    hasChanges.value = voiceNotePath.value != _initialVoicePath;
  }

  Future<bool> _askConfirm({
    required String title,
    required String message,
    String primaryLabel = 'Confirm',
    bool destructive = false,
  }) async {
    final cb = confirm;
    if (cb == null) return true;
    return cb(
      title: title,
      message: message,
      primaryLabel: primaryLabel,
      destructive: destructive,
    );
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) return true;
    errorMessage.value = 'Microphone permission is required for voice notes.';
    return false;
  }

  Future<void> onTextChanged(String value) async {
    if (isClosed) return;
    errorMessage.value = null;
    hasTextNote.value = value.trim().isNotEmpty;
    _refreshHasChanges();
  }

  Future<void> switchToTextNote({bool skipConfirm = false}) async {
    if (isClosed) return;
    if (isRecording.value) {
      errorMessage.value = 'Stop recording before switching to a text note.';
      return;
    }
    if (voiceNotePath.value == null) return;

    if (!skipConfirm) {
      final ok = await _askConfirm(
        title: 'Replace voice note?',
        message:
            'Switching to a text note will remove the current voice note. Continue?',
        primaryLabel: 'Replace',
        destructive: true,
      );
      if (!ok || isClosed) return;
    }

    await _clearVoiceDraft(deleteFile: true);
    textController.clear();
    hasTextNote.value = false;
    errorMessage.value = null;
    _refreshHasChanges();
  }

  Future<void> clearTextDraftForVoice({bool skipConfirm = false}) async {
    if (isClosed) return;
    if (!hasTextNote.value && textController.text.trim().isEmpty) return;

    if (!skipConfirm) {
      final ok = await _askConfirm(
        title: 'Replace text note?',
        message:
            'Recording a voice note will remove the current text note. Continue?',
        primaryLabel: 'Replace',
        destructive: true,
      );
      if (!ok || isClosed) return;
    }

    await _clearTextDraft();
    errorMessage.value = null;
  }

  Future<void> _clearVoiceDraft({required bool deleteFile}) async {
    if (isRecording.value) {
      await _stopRecordingInternal(keepDraft: false);
    }
    if (isPlaying.value) {
      await _player.stop();
      isPlaying.value = false;
    }
    _sourceLoaded = false;
    playbackProgress.value = 0;
    final path = voiceNotePath.value;
    voiceNotePath.value = null;
    _clearVoiceWaveState();
    if (deleteFile && path != null && path != _initialVoicePath) {
      _deleteQuietly(path);
      _tempVoicePaths.remove(path);
    }
    _refreshHasChanges();
  }

  Future<void> _clearTextDraft() async {
    if (textController.text.trim().isEmpty && !hasTextNote.value) return;
    textController.clear();
    hasTextNote.value = false;
    _refreshHasChanges();
  }

  Future<void> toggleRecording() async {
    if (isBusy.value) return;
    if (isRecording.value) {
      await stopRecording();
      return;
    }
    await startRecording();
  }

  Future<void> startRecording() async {
    if (isRecording.value || isBusy.value) return;
    errorMessage.value = null;

    if (!await _ensureMicPermission()) return;

    if (hasTextNote.value || textController.text.trim().isNotEmpty) {
      if (!replacingOther) {
        final ok = await _askConfirm(
          title: 'Replace text note?',
          message:
              'Recording a voice note will remove the current text note. Continue?',
          primaryLabel: 'Replace',
          destructive: true,
        );
        if (!ok) return;
      }
      await _clearTextDraft();
    }

    try {
      isBusy.value = true;
      if (isPlaying.value) {
        await _player.stop();
        isPlaying.value = false;
      }

      final canRecord = await _recorder.hasPermission();
      if (!canRecord) {
        errorMessage.value =
            'Microphone permission is required for voice notes.';
        return;
      }

      final filePath = await VisitMediaDraftStore.instance
          .createVoiceRecordingPath();

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      isRecording.value = true;
      recordSeconds.value = 0;
      waveLevels
        ..clear()
        ..addAll(List<double>.filled(8, 0.12));
      _startWaveform();

      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        recordSeconds.value += 1;
      });
    } catch (_) {
      errorMessage.value = 'Unable to start voice recording.';
      isRecording.value = false;
      _stopWaveform();
    } finally {
      isBusy.value = false;
    }
  }

  void _startWaveform() {
    _amplitudeSub?.cancel();
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 70))
        .listen((amplitude) {
          final db = amplitude.current;
          final normalized = ((db + 55) / 55).clamp(0.08, 1.0);
          final eased = math.pow(normalized, 0.85).toDouble();
          if (waveLevels.length >= _maxWaveBars) {
            waveLevels.removeAt(0);
          }
          waveLevels.add(eased);
        });
  }

  void _stopWaveform() {
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
  }

  void _clearVoiceWaveState() {
    _stopPlaybackWave();
    _recordedWaveLevels = <double>[];
    waveLevels.clear();
    playbackProgress.value = 0;
  }

  List<double> _fallbackWaveLevels() {
    return List<double>.generate(_maxWaveBars, (index) {
      final t = index / (_maxWaveBars - 1);
      final primary = math.sin(t * math.pi * 5.4).abs();
      final secondary = math.sin((t + 0.18) * math.pi * 13.0).abs();
      final pulse = index.isEven ? 0.08 : -0.03;
      return (0.18 + (0.42 * primary) + (0.26 * secondary) + pulse).clamp(
        0.12,
        1.0,
      );
    });
  }

  void _updatePlaybackWave(double progress) {
    final source = _recordedWaveLevels.isNotEmpty
        ? _recordedWaveLevels
        : _fallbackWaveLevels();
    if (source.isEmpty) return;

    final window = math.min(_maxWaveBars, source.length);
    final maxStart = math.max(0, source.length - window);
    final start = (progress * maxStart).floor().clamp(0, maxStart);
    final slice = source.sublist(start, start + window);
    waveLevels
      ..clear()
      ..addAll(slice);
  }

  void _stopPlaybackWave() {
    _playbackWaveTimer?.cancel();
    _playbackWaveTimer = null;
    if (!isRecording.value) {
      if (_recordedWaveLevels.isNotEmpty) {
        waveLevels
          ..clear()
          ..addAll(_recordedWaveLevels);
      } else if (voiceNotePath.value != null) {
        waveLevels
          ..clear()
          ..addAll(_fallbackWaveLevels());
      } else {
        waveLevels.clear();
      }
    }
  }

  Future<void> stopRecording() async {
    await _stopRecordingInternal(keepDraft: true);
  }

  Future<void> _stopRecordingInternal({required bool keepDraft}) async {
    _recordTimer?.cancel();
    _recordTimer = null;
    _stopWaveform();

    final recording = isRecording.value || await _recorder.isRecording();
    if (!recording) {
      isRecording.value = false;
      if (!keepDraft) waveLevels.clear();
      return;
    }

    try {
      final capturedWave = List<double>.from(waveLevels);
      final path = await _recorder.stop();
      isRecording.value = false;
      recordSeconds.value = 0;

      if (!keepDraft) {
        waveLevels.clear();
        if (path != null) _deleteQuietly(path);
        return;
      }

      if (path == null || path.trim().isEmpty) {
        waveLevels.clear();
        errorMessage.value = 'Voice note was not saved.';
        return;
      }

      final previous = voiceNotePath.value;
      if (previous != null &&
          previous != path &&
          previous != _initialVoicePath) {
        _deleteQuietly(previous);
        _tempVoicePaths.remove(previous);
      }

      _recordedWaveLevels = capturedWave.length >= 8
          ? capturedWave
          : _fallbackWaveLevels();
      waveLevels
        ..clear()
        ..addAll(_recordedWaveLevels);

      textController.clear();
      hasTextNote.value = false;
      voiceNotePath.value = path;
      _tempVoicePaths.add(path);
      _refreshHasChanges();
    } catch (_) {
      isRecording.value = false;
      waveLevels.clear();
      if (keepDraft) {
        errorMessage.value = 'Unable to save voice note.';
      }
    }
  }

  Future<void> togglePlayback() async {
    final path = voiceNotePath.value;
    if (path == null || path.isEmpty) return;
    if (!File(path).existsSync()) {
      errorMessage.value = 'Voice note file is missing.';
      voiceNotePath.value = null;
      _clearVoiceWaveState();
      _refreshHasChanges();
      return;
    }

    try {
      if (isPlaying.value) {
        await _player.pause();
        isPlaying.value = false;
        _playbackWaveTimer?.cancel();
        _playbackWaveTimer = null;
        _updatePlaybackWave(playbackProgress.value);
        return;
      }

      if (isRecording.value) {
        await stopRecording();
      }

      final playerState = _player.state;
      final canResume =
          _sourceLoaded &&
          playerState == PlayerState.paused &&
          playbackProgress.value > 0 &&
          playbackProgress.value < 0.999;

      if (canResume) {
        await _player.resume();
      } else {
        await _player.stop();
        await _player.play(DeviceFileSource(path));
        _sourceLoaded = true;
        _playbackDuration = await _player.getDuration() ?? Duration.zero;
        playbackProgress.value = 0;
        if (_recordedWaveLevels.isEmpty) {
          _recordedWaveLevels = _fallbackWaveLevels();
        }
        _updatePlaybackWave(0);
      }

      isPlaying.value = true;
      _startPlaybackProgressTimer();
    } catch (_) {
      isPlaying.value = false;
      _sourceLoaded = false;
      _stopPlaybackWave();
      errorMessage.value = 'Unable to play voice note.';
    }
  }

  void _startPlaybackProgressTimer() {
    _playbackWaveTimer?.cancel();
    _playbackWaveTimer = Timer.periodic(const Duration(milliseconds: 90), (
      _,
    ) async {
      if (!isPlaying.value) return;
      final position = await _player.getCurrentPosition();
      final totalMs = _playbackDuration.inMilliseconds;
      if (position == null || totalMs <= 0) return;
      final progress = (position.inMilliseconds / totalMs)
          .clamp(0.0, 1.0)
          .toDouble();
      playbackProgress.value = progress;
      _updatePlaybackWave(progress);
    });
  }

  Future<void> seekPlayback(double progress) async {
    final path = voiceNotePath.value;
    if (path == null || path.isEmpty || isRecording.value) return;

    try {
      if (!_sourceLoaded || _playbackDuration == Duration.zero) {
        await _player.setSource(DeviceFileSource(path));
        _sourceLoaded = true;
        _playbackDuration = await _player.getDuration() ?? Duration.zero;
      }

      final totalMs = _playbackDuration.inMilliseconds;
      if (totalMs <= 0) return;

      final clamped = progress.clamp(0.0, 1.0).toDouble();
      playbackProgress.value = clamped;
      _updatePlaybackWave(clamped);
      await _player.seek(Duration(milliseconds: (clamped * totalMs).round()));

      if (isPlaying.value) {
        if (_player.state != PlayerState.playing) {
          await _player.resume();
        }
      }
    } catch (_) {
      errorMessage.value = 'Unable to seek voice note.';
    }
  }

  Future<void> deleteVoiceNote() async {
    if (voiceNotePath.value == null && !isRecording.value) return;

    final ok = await _askConfirm(
      title: 'Delete voice note?',
      message: 'This will remove the voice note from this draft. Continue?',
      primaryLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;

    if (isPlaying.value) {
      await _player.stop();
      isPlaying.value = false;
    }
    await _clearVoiceDraft(deleteFile: true);
  }

  Future<void> commitDraft() async {
    if (isClosed) return;

    if (isTextMode) {
      final text = textController.text.trim();
      if (replacingOther && _initialVoicePath != null && text.isEmpty) {
        return;
      }
      _committed = true;
      if (batchMode) {
        await _flowController.updateBatchTextNote(text);
      } else {
        await _flowController.updateTextNote(
          mediaPath: mediaPath,
          textNote: text,
        );
      }
      hasChanges.value = false;
      return;
    }

    final voice = voiceNotePath.value;
    if (replacingOther &&
        _initialText.trim().isNotEmpty &&
        (voice == null || voice.trim().isEmpty) &&
        _initialVoicePath == null) {
      return;
    }

    _committed = true;
    if (voice != null && voice.trim().isNotEmpty) {
      if (batchMode) {
        await _flowController.updateBatchVoiceNote(voice);
      } else {
        await _flowController.updateVoiceNote(
          mediaPath: mediaPath,
          voiceNotePath: voice,
        );
      }
      _tempVoicePaths.remove(voice);
    } else if (_initialVoicePath != null) {
      if (batchMode) {
        await _flowController.updateBatchVoiceNote(null);
      } else {
        await _flowController.updateVoiceNote(
          mediaPath: mediaPath,
          voiceNotePath: null,
        );
      }
    }

    for (final path in _tempVoicePaths.toList()) {
      if (path != voice) {
        _deleteQuietly(path);
        _tempVoicePaths.remove(path);
      }
    }
    hasChanges.value = false;
  }

  void discardDraft() {
    if (_committed || isClosed) return;
    unawaited(_stopRecordingInternal(keepDraft: false));
    _discardTempVoices();
  }

  void _discardTempVoices() {
    for (final path in _tempVoicePaths.toList()) {
      if (path != _initialVoicePath) {
        _deleteQuietly(path);
      }
    }
    _tempVoicePaths.clear();
  }

  void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}
