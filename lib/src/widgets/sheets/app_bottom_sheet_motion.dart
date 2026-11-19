import 'package:flutter/material.dart';

@immutable
class AppBottomSheetMotion {
  const AppBottomSheetMotion._();

  static const Duration openDuration = Duration(milliseconds: 350);
  static const Duration closeDuration = Duration(milliseconds: 250);

  static const Curve openCurve = Curves.easeOutCubic;
  static const Curve closeCurve = Curves.easeInCubic;

  static const double scrimMaxOpacity = 0.45;

  static AnimationStyle animationStyleFor(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return AnimationStyle.noAnimation;
    }
    return animationStyle;
  }

  static const AnimationStyle animationStyle = AnimationStyle(
    duration: openDuration,
    reverseDuration: closeDuration,
    curve: openCurve,
    reverseCurve: closeCurve,
  );

  static Duration openDurationOf(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : openDuration;

  static Duration closeDurationOf(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : closeDuration;

  static Color scrimColor([double progress = 1]) {
    final opacity = (scrimMaxOpacity * progress.clamp(0.0, 1.0));
    return Colors.black.withValues(alpha: opacity);
  }
}

Future<T?> showAppModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = false,
  Color? backgroundColor,
  Color? barrierColor,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  String? barrierLabel,
  AnimationStyle? sheetAnimationStyle,
  Offset? anchorPoint,
  double? elevation,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: useSafeArea,
    backgroundColor: backgroundColor ?? Colors.transparent,
    barrierColor: barrierColor ?? AppBottomSheetMotion.scrimColor(),
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    barrierLabel: barrierLabel,
    elevation: elevation,
    anchorPoint: anchorPoint,
    sheetAnimationStyle:
        sheetAnimationStyle ?? AppBottomSheetMotion.animationStyleFor(context),
    builder: builder,
  );
}

class AppEmbeddedBottomSheetFrame extends StatefulWidget {
  const AppEmbeddedBottomSheetFrame({
    super.key,
    required this.child,
    this.showScrim = true,
    this.animateOnMount = true,
  });

  final Widget child;
  final bool showScrim;
  final bool animateOnMount;

  @override
  State<AppEmbeddedBottomSheetFrame> createState() =>
      _AppEmbeddedBottomSheetFrameState();
}

class _AppEmbeddedBottomSheetFrameState
    extends State<AppEmbeddedBottomSheetFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scrim;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppBottomSheetMotion.openDuration,
      reverseDuration: AppBottomSheetMotion.closeDuration,
    );
    _scrim = CurvedAnimation(
      parent: _controller,
      curve: AppBottomSheetMotion.openCurve,
      reverseCurve: AppBottomSheetMotion.closeCurve,
    );
    _slide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _controller,
        curve: AppBottomSheetMotion.openCurve,
        reverseCurve: AppBottomSheetMotion.closeCurve,
      ),
    );
    if (widget.animateOnMount) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _controller.duration = reduceMotion
        ? Duration.zero
        : AppBottomSheetMotion.openDuration;
    _controller.reverseDuration = reduceMotion
        ? Duration.zero
        : AppBottomSheetMotion.closeDuration;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scrimOpacity = Tween<double>(
      begin: 0,
      end: AppBottomSheetMotion.scrimMaxOpacity,
    ).animate(_scrim);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.showScrim)
          IgnorePointer(
            child: FadeTransition(
              opacity: scrimOpacity,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SlideTransition(position: _slide, child: widget.child),
        ),
      ],
    );
  }
}
