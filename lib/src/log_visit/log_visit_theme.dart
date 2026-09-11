import 'dart:math' as math;

import 'package:flutter/material.dart';

const Color cPrimary = Color(0xFF022A67);
const Color cOrange = Color(0xFFE48E15);
const Color cRed = Color(0xFFDC2626);
final Color cMainBg = const Color(0xFFF9FAFB);
const Color cDarkText = Color(0xFF0D1A33);
const Color cDarkBackground = Color(0xFF0F1729);
const Color cDarkCardColor = Color(0xFF1A2332);
const Color cDarkTextPrimary = Color(0xFFF1F5F9);
const Color cDarkTextSecondary = Color(0xFFCBD5E1);
const Color cDarkIconColor = Color(0xFF94A3B8);
const Color cDarkBorderColor = Color(0xFF334155);
const Color cDarkInputFillColor = Color(0xFF1E293B);
const Color cSurface = Color(0xFFFBFBFD);

class VisitPageBackground extends StatelessWidget {
  const VisitPageBackground({super.key, required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1724) : const Color(0xFFF3F7FB),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF0F1724), Color(0xFF172033), Color(0xFF111827)]
              : const [Color(0xFFF7FAFC), Color(0xFFEAF2F8), Color(0xFFF8FAFC)],
        ),
      ),
    );
  }
}

BoxDecoration getCardDecoration(BuildContext context, {Color? customColor}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return BoxDecoration(
    color: customColor ?? (isDark ? const Color(0xFF182334) : cSurface),
    borderRadius: BorderRadius.circular(12),
    border: isDark
        ? Border.all(color: Colors.white.withAlpha(18), width: 1)
        : null,
    boxShadow: [
      BoxShadow(
        color: isDark ? Colors.black.withAlpha(45) : Colors.black.withAlpha(13),
        blurRadius: isDark ? 16 : 10,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

String formatMMSS(int totalSeconds) {
  if (totalSeconds < 0) totalSeconds = 0;
  final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final s = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

class VisitDeleteIcon extends StatelessWidget {
  const VisitDeleteIcon({
    super.key,
    this.size = 22,
    this.color = cRed,
  });

  static const assetPath = 'assets/delete.png';

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      ),
    );
  }
}

class VisitDottedRoundedRectPainter extends CustomPainter {
  const VisitDottedRoundedRectPainter({
    required this.color,
    required this.radius,
    this.strokeWidth = 1.2,
    this.dashLength = 5,
    this.gapLength = 4,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant VisitDottedRoundedRectPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.gapLength != gapLength;
  }
}
