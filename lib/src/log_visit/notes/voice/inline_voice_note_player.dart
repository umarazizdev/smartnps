import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'voice_waveform_painter.dart';

class InlineVoiceNotePlayer extends StatefulWidget {
  const InlineVoiceNotePlayer({
    super.key,
    required this.path,
    required this.isDark,
    required this.accent,
    this.compact = false,
    this.enableSeek = true,
  });

  final String path;
  final bool isDark;
  final Color accent;
  final bool compact;
  final bool enableSeek;

  @override
  State<InlineVoiceNotePlayer> createState() => _InlineVoiceNotePlayerState();
}

class _InlineVoiceNotePlayerState extends State<InlineVoiceNotePlayer> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _completeSub;
  StreamSubscription<Duration>? _positionSub;
  var _isPlaying = false;
  var _progress = 0.0;
  var _duration = Duration.zero;

  static final List<double> _waveLevels = generateDecorativeVoiceWaveLevels();

  @override
  void initState() {
    super.initState();
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _progress = 0;
      });
    });
    _positionSub = _player.onPositionChanged.listen((position) {
      final totalMs = _duration.inMilliseconds;
      if (!mounted || totalMs <= 0) return;
      setState(() {
        _progress = (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
      });
    });
  }

  @override
  void didUpdateWidget(covariant InlineVoiceNotePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path == widget.path) return;
    unawaited(_player.stop());
    _duration = Duration.zero;
    _isPlaying = false;
    _progress = 0;
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    _positionSub?.cancel();
    unawaited(_player.stop());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!File(widget.path).existsSync()) return;

    if (_isPlaying) {
      await _player.pause();
      if (!mounted) return;
      setState(() => _isPlaying = false);
      return;
    }

    if (_player.state == PlayerState.paused && _progress > 0) {
      await _player.resume();
    } else {
      await _player.stop();
      await _player.play(DeviceFileSource(widget.path));
      _duration = await _player.getDuration() ?? Duration.zero;
      _progress = 0;
    }

    if (!mounted) return;
    setState(() => _isPlaying = true);
  }

  Future<void> _seekAt(double progress) async {
    if (!widget.enableSeek) return;
    if (!File(widget.path).existsSync()) return;
    final clamped = progress.clamp(0.0, 1.0).toDouble();

    if (_duration == Duration.zero) {
      await _player.setSource(DeviceFileSource(widget.path));
      _duration = await _player.getDuration() ?? Duration.zero;
    }

    final totalMs = _duration.inMilliseconds;
    if (totalMs <= 0) return;

    await _player.seek(Duration(milliseconds: (clamped * totalMs).round()));
    if (!mounted) return;
    setState(() => _progress = clamped);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final buttonSize = widget.compact ? 24.0 : 26.0;
    final iconSize = widget.compact ? 15.0 : 17.0;
    final waveHeight = widget.compact ? 24.0 : 28.0;

    final wave = VoiceWaveform(
      levels: _waveLevels,
      color: accent,
      progress: _progress,
    );

    return Row(
      children: [
        Material(
          color: accent.withValues(alpha: widget.isDark ? 0.18 : 0.12),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _toggle,
            child: SizedBox.square(
              dimension: buttonSize,
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: iconSize,
                color: accent,
              ),
            ),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: SizedBox(
            height: waveHeight,
            child: widget.enableSeek
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      void seekAt(double dx) {
                        final width = constraints.maxWidth;
                        if (width <= 0) return;
                        unawaited(_seekAt(dx / width));
                      }

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) =>
                            seekAt(details.localPosition.dx),
                        onHorizontalDragStart: (details) =>
                            seekAt(details.localPosition.dx),
                        onHorizontalDragUpdate: (details) =>
                            seekAt(details.localPosition.dx),
                        child: wave,
                      );
                    },
                  )
                : wave,
          ),
        ),
      ],
    );
  }
}
