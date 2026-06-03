import 'dart:ui';

import 'package:flutter/material.dart';

class MockLocationDialog extends StatelessWidget {
  const MockLocationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark
        ? const Color(0xFF1A2332).withValues(alpha: 0.86)
        : Colors.white.withValues(alpha: 0.72);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.62);
    final shadowColor = Colors.black.withValues(alpha: isDark ? 0.34 : 0.12);
    final titleColor = isDark ? Colors.white : const Color(0xFF171717);
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.72)
        : const Color(0xFF5D6168);
    final buttonBgColor = isDark ? Colors.white : const Color(0xFF111827);
    final buttonFgColor = isDark ? const Color(0xFF111827) : Colors.white;

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_off_rounded,
                    color: Color(0xFFE53935),
                    size: 27,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Mock location detected',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'Your device appears to be using a fake/mock GPS location. '
                  'Please disable mock location and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: bodyColor,
                    fontSize: 14,
                    height: 1.45,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      elevation: 0,
                      backgroundColor: buttonBgColor,
                      foregroundColor: buttonFgColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
