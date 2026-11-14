import 'package:flutter/material.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final double? height;
  final double? width;
  final BorderRadius? borderRadius;
  final List<Color> gradientColors;
  final TextStyle? textStyle;
  final List<BoxShadow>? boxShadow;

  const GradientButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.height = 56,
    this.width,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.gradientColors = const [Color(0xFF022A67), Color(0xFF005BFF)],
    this.textStyle,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      onTap: onPressed,
      borderRadius: borderRadius,
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow:
              boxShadow ??
              [
                BoxShadow(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.black.withAlpha(77)
                      : Colors.black.withAlpha(38),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
        ),
        child: Center(
          child: Text(
            text.toUpperCase(),
            style:
                textStyle ??
                textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
          ),
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final double? height;
  final double? width;
  final BorderRadius? borderRadius;
  final Color color;
  final TextStyle? textStyle;

  const PrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.height = 56,
    this.width,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.color = cWhite,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      onTap: onPressed,
      borderRadius: borderRadius,
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(borderRadius: borderRadius, color: color),
        child: Center(
          child: Text(
            text.toUpperCase(),
            style:
                textStyle ??
                textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: cPrimary,
                ),
          ),
        ),
      ),
    );
  }
}
