import 'dart:math' as math;

import 'package:flutter/material.dart';

List<double> generateDecorativeVoiceWaveLevels({int barCount = 28}) {
  final last = math.max(barCount - 1, 1);
  return List<double>.generate(barCount, (index) {
    final t = index / last;
    final primary = math.sin(t * math.pi * 5.2).abs();
    final secondary = math.sin((t + 0.21) * math.pi * 12.5).abs();
    final pulse = index.isEven ? 0.07 : -0.025;
    return (0.16 + (0.42 * primary) + (0.25 * secondary) + pulse).clamp(
      0.12,
      1.0,
    );
  });
}

class VoiceWaveform extends StatelessWidget {
  const VoiceWaveform({
    super.key,
    required this.levels,
    required this.color,
    this.progress,
    this.showKnob = true,
  });

  final List<double> levels;
  final Color color;
  final double? progress;
  final bool showKnob;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: VoiceWaveformPainter(
        levels: levels,
        color: color,
        progress: progress,
        showKnob: showKnob,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class VoiceWaveformPainter extends CustomPainter {
  VoiceWaveformPainter({
    required this.levels,
    required this.color,
    this.progress,
    this.showKnob = true,
  });

  final List<double> levels;
  final Color color;
  final double? progress;
  final bool showKnob;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final barCount = levels.isEmpty ? 24 : levels.length;
    final gap = 2.0;
    final barWidth = ((size.width - (gap * (barCount - 1))) / barCount).clamp(
      2.0,
      5.0,
    );
    final totalWidth = (barWidth * barCount) + (gap * (barCount - 1));
    final startX = (size.width - totalWidth) / 2;
    final centerY = size.height / 2;
    final paint = Paint()..style = PaintingStyle.fill;
    final playedThrough = progress;

    for (var i = 0; i < barCount; i++) {
      final level = i < levels.length ? levels[i].clamp(0.10, 1.0) : 0.16;
      final barHeight = (size.height * level).clamp(4.0, size.height * 0.94);
      final x = startX + (i * (barWidth + gap));
      final barProgress = barCount <= 1 ? 1.0 : i / (barCount - 1);
      final isPlayed = playedThrough == null
          ? true
          : barProgress <= playedThrough;
      paint.color = isPlayed
          ? color.withValues(alpha: 0.72 + (0.24 * level))
          : color.withValues(alpha: 0.20 + (0.18 * level));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x + barWidth / 2, centerY),
            width: barWidth,
            height: barHeight,
          ),
          const Radius.circular(3),
        ),
        paint,
      );
    }

    if (showKnob && playedThrough != null) {
      final knobX = (startX + (totalWidth * playedThrough)).clamp(
        startX,
        startX + totalWidth,
      );
      paint.color = color;
      canvas.drawCircle(Offset(knobX, centerY), 3.8, paint);
      paint.color = Colors.white.withValues(alpha: 0.88);
      canvas.drawCircle(Offset(knobX, centerY), 1.4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant VoiceWaveformPainter oldDelegate) {
    if (oldDelegate.color != color) return true;
    if (oldDelegate.progress != progress) return true;
    if (oldDelegate.showKnob != showKnob) return true;
    if (oldDelegate.levels.length != levels.length) return true;
    for (var i = 0; i < levels.length; i++) {
      if (oldDelegate.levels[i] != levels[i]) return true;
    }
    return false;
  }
}
