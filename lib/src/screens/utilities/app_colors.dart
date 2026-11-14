import 'package:flutter/material.dart';

/// Application color scheme matching the HTML/CSS design
class AppColors {
  // Background colors
  static const Color bg = Color(0xFFF3F6FB);
  static const Color card = Color(0xFFFFFFFF);

  // Text colors
  static const Color text = Color(0xFF18212F);
  static const Color muted = Color(0xFF617085);

  // UI colors
  static const Color line = Color(0xFFD7DFEB);
  static const Color primary = Color(0xFF0B5CAB);
  static const Color primaryDark = Color(0xFF094781);
  static const Color success = Color(0xFF0F8F58);
  static const Color warning = Color(0xFFC67A00);
  static const Color danger = Color(0xFFC73D3D);

  // Additional colors for specific UI elements
  static const Color secondaryBg = Color(0xFFE8EFF8);
  static const Color lightBg = Color(0xFFFBFDFF);
  static const Color borderLight = Color(0xFFCBD6E6);

  // Banner colors
  static const Color infoBg = Color(0xFFF6FAFF);
  static const Color infoBorder = Color(0xFFD9E6F7);
  static const Color infoText = Color(0xFF21476F);

  static const Color warnBg = Color(0xFFFFF9EF);
  static const Color warnBorder = Color(0xFFF2DBB0);
  static const Color warnText = Color(0xFF7A5311);

  static const Color successBg = Color(0xFFF2FCF6);
  static const Color successBorder = Color(0xFFBDE1C9);
  static const Color successText = Color(0xFF125F3B);

  static const Color dangerBg = Color(0xFFFFF1F1);
  static const Color dangerBorder = Color(0xFFF1C7C7);

  // Gradients
  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFEEF4FB), Color(0xFFF7F9FC)],
  );

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D5FAE), Color(0xFF083C78)],
  );

  static const LinearGradient progressGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF0B5CAB), Color(0xFF1E8FFF)],
  );

  // Shadows
  static final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: const Color(0xFF0E233D).withValues(alpha: 0.10),
      blurRadius: 38,
      offset: const Offset(0, 14),
    ),
  ];

  static final List<BoxShadow> brandShadow = [
    BoxShadow(
      color: const Color(0xFF0E233D).withValues(alpha: 0.10),
      blurRadius: 38,
      offset: const Offset(0, 14),
    ),
  ];

  // Border radius
  static const double radius = 22.0;
  static const double radiusMedium = 16.0;
  static const double radiusSmall = 12.0;
}
