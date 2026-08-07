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
