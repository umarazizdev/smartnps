import 'package:flutter/material.dart';

import '../utilities/app_config.dart';

/// Shared palette for Debug Environment screens.
class DebugEnvColors {
  const DebugEnvColors({
    required this.background,
    required this.card,
    required this.cardBorder,
    required this.title,
    required this.subtitle,
    required this.label,
    required this.fieldBg,
    required this.border,
    required this.divider,
    required this.outline,
    required this.error,
    required this.warningBg,
    required this.warningBorder,
    required this.warningFg,
    required this.badgeBg,
    required this.badgeFg,
  });

  final Color background;
  final Color card;
  final Color cardBorder;
  final Color title;
  final Color subtitle;
  final Color label;
  final Color fieldBg;
  final Color border;
  final Color divider;
  final Color outline;
  final Color error;
  final Color warningBg;
  final Color warningBorder;
  final Color warningFg;
  final Color badgeBg;
  final Color badgeFg;

  static DebugEnvColors of(bool isDark) {
    if (isDark) {
      return DebugEnvColors(
        background: const Color(0xFF0F1724),
        card: const Color(AppConfig.cDarkCardColor),
        cardBorder: const Color(0xFF2A3548),
        title: Colors.white,
        subtitle: Colors.white.withValues(alpha: 0.65),
        label: Colors.white.withValues(alpha: 0.75),
        fieldBg: const Color(0xFF121A27),
        border: const Color(0xFF2A3548),
        divider: const Color(0xFF243044),
        outline: const Color(0xFF3B4A63),
        error: const Color(0xFFF87171),
        warningBg: const Color(0xFF2A2212),
        warningBorder: const Color(0xFF78520F),
        warningFg: const Color(0xFFFBBF24),
        badgeBg: const Color(0xFF1E3A5F),
        badgeFg: const Color(0xFF93C5FD),
      );
    }

    return const DebugEnvColors(
      background: Color(0xFFF5F7FB),
      card: Color(0xFFFFFFFF),
      cardBorder: Color(0xFFE8ECF2),
      title: Color(0xFF0F172A),
      subtitle: Color(0xFF667085),
      label: Color(0xFF344054),
      fieldBg: Color(0xFFFFFFFF),
      border: Color(0xFFD0D5DD),
      divider: Color(0xFFEAECF0),
      outline: Color(0xFFD0D5DD),
      error: Color(0xFFDC2626),
      warningBg: Color(0xFFFFFBEB),
      warningBorder: Color(0xFFFDE68A),
      warningFg: Color(0xFF92400E),
      badgeBg: Color(0xFFEEF2FF),
      badgeFg: Color(0xFF1D4ED8),
    );
  }
}
