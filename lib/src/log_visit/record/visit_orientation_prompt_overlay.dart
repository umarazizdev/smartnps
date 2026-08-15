import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/dialogs/glass_action_dialog.dart';

enum VisitOrientationPromptMode { landscape, portrait }

class VisitOrientationPromptOverlay extends StatelessWidget {
  const VisitOrientationPromptOverlay({
    super.key,
    required this.mode,
  });

  final VisitOrientationPromptMode mode;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final towardLandscape = mode == VisitOrientationPromptMode.landscape;
    final title =
        towardLandscape ? 'Use Landscape Mode' : 'Use Portrait Mode';
    final message = towardLandscape
        ? 'Please rotate your device to landscape to capture photos and videos clearly.'
        : 'Please rotate your device to portrait to review and manage your visit media.';
    const accent = Color(0xFFE48E15);

    return AbsorbPointer(
      child: Material(
        color: isDark
            ? Colors.black.withValues(alpha: 0.45)
            : Colors.black.withValues(alpha: 0.28),
        child: GlassActionDialog(
          icon: Icons.screen_rotation_rounded,
          iconWidget: VisitAnimatedOrientationHintIcon(
            color: accent,
            towardLandscape: towardLandscape,
          ),
          title: title,
          message: message,
          iconColor: accent,
        ),
      ),
    );
  }
}

class VisitOrientationPromptLayer extends StatelessWidget {
  const VisitOrientationPromptLayer({
    super.key,
    required this.blocked,
    required this.mode,
  });

  final bool blocked;
  final VisitOrientationPromptMode mode;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedOpacity(
        opacity: blocked ? 1 : 0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: IgnorePointer(
          ignoring: !blocked,
          child: VisitOrientationPromptOverlay(mode: mode),
        ),
      ),
    );
  }
}

class VisitAnimatedOrientationHintIcon extends StatefulWidget {
  const VisitAnimatedOrientationHintIcon({
    super.key,
    required this.color,
    this.towardLandscape = true,
  });

  final Color color;
  final bool towardLandscape;

  @override
  State<VisitAnimatedOrientationHintIcon> createState() =>
      _VisitAnimatedOrientationHintIconState();
}

class _VisitAnimatedOrientationHintIconState
    extends State<VisitAnimatedOrientationHintIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _rotation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    if (widget.towardLandscape) {
      _rotation = TweenSequence<double>([
        TweenSequenceItem(
          tween: ConstantTween<double>(0),
          weight: 12,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: 0, end: -math.pi / 2)
              .chain(CurveTween(curve: Curves.easeInOutCubic)),
          weight: 38,
        ),
        TweenSequenceItem(
          tween: ConstantTween<double>(-math.pi / 2),
          weight: 24,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: -math.pi / 2, end: 0)
              .chain(CurveTween(curve: Curves.easeInOutCubic)),
          weight: 26,
        ),
      ]).animate(_controller);
    } else {
      _rotation = TweenSequence<double>([
        TweenSequenceItem(
          tween: ConstantTween<double>(-math.pi / 2),
          weight: 12,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: -math.pi / 2, end: 0)
              .chain(CurveTween(curve: Curves.easeInOutCubic)),
          weight: 38,
        ),
        TweenSequenceItem(
          tween: ConstantTween<double>(0),
          weight: 24,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: 0, end: -math.pi / 2)
              .chain(CurveTween(curve: Curves.easeInOutCubic)),
          weight: 26,
        ),
      ]).animate(_controller);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _rotation,
      builder: (context, child) {
        return Transform.rotate(
          angle: _rotation.value,
          child: child,
        );
      },
      child: Icon(
        Icons.screen_rotation_rounded,
        color: widget.color,
        size: 28,
      ),
    );
  }
}
