import 'dart:math' as math;

import 'package:flutter/material.dart';

@immutable
class DispatchScale {
  const DispatchScale._({
    required this.factor,
    required this.size,
    required this.padding,
    required this.textScale,
  });

  factory DispatchScale.of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final textScale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, 1.25);
    final widthFactor = size.width / 390;
    final heightFactor = size.height / 844;
    final factor = ((widthFactor * 0.7) + (heightFactor * 0.3)).clamp(
      0.82,
      1.18,
    );
    return DispatchScale._(
      factor: factor,
      size: size,
      padding: padding,
      textScale: textScale,
    );
  }

  final double factor;
  final Size size;
  final EdgeInsets padding;
  final double textScale;

  double s(double value) => value * factor;

  double sp(double value) => value * factor * textScale;

  double get sheetHeight {
    final usable = size.height - padding.top;
    return usable - s(8);
  }

  double get mapHeight =>
      math.min(s(165), size.height * 0.20).clamp(s(135), s(185));

  double get sheetRadius => s(28);

  EdgeInsets get sheetPadding => EdgeInsets.fromLTRB(s(20), 0, s(20), s(16));

  double get handleWidth => s(36);

  double get handleHeight => s(4);

  double get buttonHeight => s(49);

  double get sectionGap => s(15);

  double get metricsToCountdownGap => s(16);

  double get countdownToButtonsGap => s(12);

  double get bottomSafePadding => s(14);

  double get cardRadius => s(14);

  double get markerSize => s(56);
}
