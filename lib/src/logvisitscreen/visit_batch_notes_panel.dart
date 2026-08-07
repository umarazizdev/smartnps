import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'visit_media_notes_sheet.dart';
import 'visit_video_flow_controller.dart';

class VisitBatchNotesPanel extends StatelessWidget {
  const VisitBatchNotesPanel({
    super.key,
    required this.flow,
    required this.isDark,
  });

  final VisitVideoFlowController flow;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    const attentionRed = Color(0xFFDC2626);
    final titleColor = attentionRed;
    final border = attentionRed.withValues(alpha: isDark ? 0.42 : 0.28);
    final cardBg = attentionRed.withValues(alpha: isDark ? 0.16 : 0.08);
    final accent = isDark ? const Color(0xFF93C5FD) : const Color(0xFF4F46E5);
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.82)
        : const Color(0xFF374151);

    return Obx(() {
      final note = flow.batchNote.value;
      final enabled = note.enabled;

      return Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(10, 4, 6, enabled ? 8 : 4),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 28,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Attention needed',
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.62,
                    alignment: Alignment.centerRight,
                    child: Switch.adaptive(
                      value: enabled,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      activeTrackColor: attentionRed.withValues(alpha: 0.45),
                      activeThumbColor: attentionRed,
                      onChanged: (value) {
                        unawaited(flow.setBatchNotesEnabled(value));
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (enabled) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _NoteActionButton(
                      icon: Icons.sticky_note_2_outlined,
                      label: note.hasTextNote ? 'Edit text' : 'Text note',
                      active: note.hasTextNote,
                      isDark: isDark,
                      accent: accent,
                      onTap: () => openVisitBatchNotesSheet(
                        context: context,
                        kind: VisitMediaNoteKind.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _NoteActionButton(
                      icon: Icons.mic_none_rounded,
                      label: note.hasVoiceNote ? 'Edit voice' : 'Voice note',
                      active: note.hasVoiceNote,
                      isDark: isDark,
                      accent: accent,
                      onTap: () => openVisitBatchNotesSheet(
                        context: context,
                        kind: VisitMediaNoteKind.voice,
                      ),
                    ),
                  ),
                ],
              ),
              if (note.hasTextNote) ...[
                const SizedBox(height: 6),
                _SavedTextNote(
                  text: note.textNote.trim(),
                  isDark: isDark,
                  bodyColor: bodyColor,
                  accent: accent,
                ),
              ] else if (note.hasVoiceNote) ...[
                const SizedBox(height: 6),
                _SavedVoiceNote(
                  path: note.voiceNotePath!,
                  isDark: isDark,
                  accent: accent,
                ),
              ],
            ],
          ],
        ),
      );
    });
  }
}

class _SavedTextNote extends StatelessWidget {
  const _SavedTextNote({
    required this.text,
    required this.isDark,
    required this.bodyColor,
    required this.accent,
  });

  final String text;
  final bool isDark;
  final Color bodyColor;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.sticky_note_2_outlined, size: 14, color: accent),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: bodyColor,
                fontSize: 12.5,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedVoiceNote extends StatelessWidget {
  const _SavedVoiceNote({
    required this.path,
    required this.isDark,
    required this.accent,
  });

  final String path;
  final bool isDark;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(6, 5, 8, 5),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: _BatchInlineVoicePlayer(
        path: path,
        isDark: isDark,
        accent: accent,
      ),
    );
  }
}

class _BatchInlineVoicePlayer extends StatefulWidget {
  const _BatchInlineVoicePlayer({
    required this.path,
    required this.isDark,
    required this.accent,
  });

  final String path;
  final bool isDark;
  final Color accent;

  @override
  State<_BatchInlineVoicePlayer> createState() =>
      _BatchInlineVoicePlayerState();
}

class _BatchInlineVoicePlayerState extends State<_BatchInlineVoicePlayer> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _completeSub;
  StreamSubscription<Duration>? _positionSub;
  var _isPlaying = false;
  var _progress = 0.0;
  var _duration = Duration.zero;

  static final List<double> _waveLevels = List<double>.generate(22, (index) {
    final t = index / 21;
    final primary = math.sin(t * math.pi * 5.2).abs();
    final secondary = math.sin((t + 0.21) * math.pi * 12.5).abs();
    final pulse = index.isEven ? 0.07 : -0.025;
    return (0.16 + (0.42 * primary) + (0.25 * secondary) + pulse).clamp(
      0.12,
      1.0,
    );
  });

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
  void didUpdateWidget(covariant _BatchInlineVoicePlayer oldWidget) {
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

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: widget.accent.withValues(alpha: widget.isDark ? 0.18 : 0.12),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _toggle,
            child: SizedBox.square(
              dimension: 24,
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 15,
                color: widget.accent,
              ),
            ),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: SizedBox(
            height: 22,
            child: CustomPaint(
              painter: _BatchWavePainter(
                levels: _waveLevels,
                color: widget.accent,
                progress: _progress,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BatchWavePainter extends CustomPainter {
  _BatchWavePainter({
    required this.levels,
    required this.color,
    required this.progress,
  });

  final List<double> levels;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty || size.width <= 0 || size.height <= 0) return;
    final barWidth = size.width / (levels.length * 1.7);
    final gap = barWidth * 0.7;
    final paint = Paint()..style = PaintingStyle.fill;
    final midY = size.height / 2;

    for (var i = 0; i < levels.length; i++) {
      final x = i * (barWidth + gap);
      final h = (levels[i] * size.height).clamp(3.0, size.height);
      final active = (i / levels.length) <= progress;
      paint.color = color.withValues(alpha: active ? 0.95 : 0.28);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x + barWidth / 2, midY),
            width: barWidth,
            height: h,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BatchWavePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.levels != levels;
  }
}

class _NoteActionButton extends StatelessWidget {
  const _NoteActionButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.isDark,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool isDark;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? accent.withValues(alpha: isDark ? 0.22 : 0.12)
        : (isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.9));
    final fg = active
        ? accent
        : (isDark ? Colors.white : const Color(0xFF1F2937));
    final border = active
        ? accent.withValues(alpha: 0.45)
        : (isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
