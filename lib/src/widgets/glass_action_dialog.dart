import 'dart:ui';

import 'package:flutter/material.dart';

enum GlassActionDialogVariant { normal, error }

class GlassActionDialog extends StatelessWidget {
  const GlassActionDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.secondaryLabel,
    required this.primaryLabel,
    this.iconColor = const Color(0xFF2563EB),
    this.variant = GlassActionDialogVariant.normal,
    this.destructiveSecondary = false,
    this.messageMaxHeightFactor = _defaultMessageMaxHeightFactor,
  });

  static const Color _errorColor = Color(0xFFE53935);
  static const double _defaultMessageMaxHeightFactor = 0.38;

  final IconData icon;
  final String title;
  final String message;
  final String secondaryLabel;
  final String primaryLabel;
  final Color iconColor;
  final GlassActionDialogVariant variant;
  final bool destructiveSecondary;
  final double messageMaxHeightFactor;

  static Future<bool?> show({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String message,
    required String secondaryLabel,
    required String primaryLabel,
    Color iconColor = const Color(0xFF2563EB),
    GlassActionDialogVariant variant = GlassActionDialogVariant.normal,
    bool destructiveSecondary = false,
    bool barrierDismissible = false,
    double messageMaxHeightFactor = _defaultMessageMaxHeightFactor,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => GlassActionDialog(
        icon: icon,
        title: title,
        message: message,
        secondaryLabel: secondaryLabel,
        primaryLabel: primaryLabel,
        iconColor: iconColor,
        variant: variant,
        destructiveSecondary: destructiveSecondary,
        messageMaxHeightFactor: messageMaxHeightFactor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isError = variant == GlassActionDialogVariant.error;
    final effectiveIconColor = isError ? _errorColor : iconColor;
    final surfaceColor = isDark
        ? const Color(0xFF1A2332).withValues(alpha: 0.86)
        : Colors.white.withValues(alpha: 0.72);
    final borderColor = isError
        ? _errorColor.withValues(alpha: isDark ? 0.38 : 0.28)
        : isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.62);
    final shadowColor = Colors.black.withValues(alpha: isDark ? 0.34 : 0.12);
    final titleColor = isDark ? Colors.white : const Color(0xFF171717);
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.72)
        : const Color(0xFF5D6168);
    final primaryButtonBg = isError
        ? _errorColor
        : isDark
            ? Colors.white
            : const Color(0xFF111827);
    final primaryButtonFg = isError
        ? Colors.white
        : isDark
            ? const Color(0xFF111827)
            : Colors.white;
    final secondaryFg = destructiveSecondary
        ? _errorColor
        : isDark
            ? Colors.white
            : const Color(0xFF111827);
    final secondaryBorder = destructiveSecondary
        ? _errorColor.withValues(alpha: 0.55)
        : isError
            ? _errorColor.withValues(alpha: 0.35)
            : isDark
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.black.withValues(alpha: 0.12);

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
                    color: effectiveIconColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: effectiveIconColor,
                    size: 27,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height *
                        messageMaxHeightFactor,
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: bodyColor,
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stackVertically = _shouldStackActionsVertically(
                      secondaryLabel: secondaryLabel,
                      primaryLabel: primaryLabel,
                      maxWidth: constraints.maxWidth,
                    );

                    final secondaryButton = _ActionButton(
                      label: secondaryLabel,
                      onPressed: () => Navigator.of(context).pop(false),
                      filled: false,
                      foregroundColor: secondaryFg,
                      borderColor: secondaryBorder,
                      backgroundColor: Colors.transparent,
                    );

                    final primaryButton = _ActionButton(
                      label: primaryLabel,
                      onPressed: () => Navigator.of(context).pop(true),
                      filled: true,
                      foregroundColor: primaryButtonFg,
                      borderColor: primaryButtonBg,
                      backgroundColor: primaryButtonBg,
                    );

                    if (stackVertically) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          primaryButton,
                          const SizedBox(height: 10),
                          secondaryButton,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: secondaryButton),
                        const SizedBox(width: 12),
                        Expanded(child: primaryButton),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool _shouldStackActionsVertically({
    required String secondaryLabel,
    required String primaryLabel,
    required double maxWidth,
  }) {
    const gap = 12.0;
    const buttonPadding = 36.0;
    final halfSlot = (maxWidth - gap) / 2;
    return _labelWidth(secondaryLabel) + buttonPadding > halfSlot ||
        _labelWidth(primaryLabel) + buttonPadding > halfSlot;
  }

  static double _labelWidth(String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onPressed,
    required this.filled,
    required this.foregroundColor,
    required this.borderColor,
    required this.backgroundColor,
  });

  final String label;
  final VoidCallback onPressed;
  final bool filled;
  final Color foregroundColor;
  final Color borderColor;
  final Color backgroundColor;

  static const _labelStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    final child = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
        style: _labelStyle.copyWith(color: foregroundColor),
      ),
    );

    return SizedBox(
      height: 48,
      width: double.infinity,
      child: filled
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                elevation: 0,
                backgroundColor: backgroundColor,
                foregroundColor: foregroundColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: child,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                elevation: 0,
                foregroundColor: foregroundColor,
                side: BorderSide(color: borderColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: child,
            ),
    );
  }
}
