import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../utilities/overlay_prompt_guard.dart';

enum GlassActionDialogVariant { normal, error }

enum GlassDialogActionTone { primary, neutral, destructive }

class GlassDialogAction<T> {
  const GlassDialogAction({
    required this.label,
    required this.value,
    this.tone = GlassDialogActionTone.neutral,
  });

  final String label;
  final T value;
  final GlassDialogActionTone tone;
}

class GlassActionDialog extends StatelessWidget {
  const GlassActionDialog({
    super.key,
    required this.icon,
    required this.title,
    this.message = '',
    this.content,
    this.secondaryLabel,
    this.primaryLabel,
    this.actions,
    this.iconColor = const Color(0xFF2563EB),
    this.variant = GlassActionDialogVariant.normal,
    this.destructiveSecondary = false,
    this.messageMaxHeightFactor = _defaultMessageMaxHeightFactor,
    this.insetPadding = const EdgeInsets.symmetric(horizontal: 28),
    this.maxWidth,
    this.compact = false,
    this.barrierDismissible = false,
    this.showCloseButton = false,
    this.onPrimaryPressed,
    this.iconWidget,
    this.titleColor,
  });

  static const Color _errorColor = Color(0xFFE53935);
  static const double _defaultMessageMaxHeightFactor = 0.38;
  static const Color _darkSurface = Color(0xFF172033);
  static const Color _lightSurface = Color(0xFFF9FBFF);

  final IconData icon;
  final String title;
  final String message;

  final Widget? content;
  final String? secondaryLabel;
  final String? primaryLabel;
  final List<GlassDialogAction<Object?>>? actions;
  final Color iconColor;
  final GlassActionDialogVariant variant;
  final bool destructiveSecondary;
  final double messageMaxHeightFactor;
  final EdgeInsets insetPadding;
  final double? maxWidth;

  final bool compact;
  final bool barrierDismissible;
  final bool showCloseButton;

  final Future<bool> Function()? onPrimaryPressed;

  final Widget? iconWidget;
  final Color? titleColor;

  static Future<bool?> show({
    required BuildContext context,
    required IconData icon,
    required String title,
    String message = '',
    Widget? content,
    String? secondaryLabel,
    String? primaryLabel,
    Color iconColor = const Color(0xFF2563EB),
    GlassActionDialogVariant variant = GlassActionDialogVariant.normal,
    bool destructiveSecondary = false,
    bool barrierDismissible = false,
    bool showCloseButton = false,
    Future<bool> Function()? onPrimaryPressed,
    double messageMaxHeightFactor = _defaultMessageMaxHeightFactor,
    EdgeInsets insetPadding = const EdgeInsets.symmetric(horizontal: 28),
    double? maxWidth,
    bool compact = false,
    bool useRootNavigator = true,
    Widget? iconWidget,
    Color? titleColor,
  }) {
    if (!context.mounted) return Future<bool?>.value(null);

    OverlayPromptGuard.registerBlockingOverlay();
    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      builder: (_) => GlassActionDialog(
        icon: icon,
        title: title,
        message: message,
        content: content,
        secondaryLabel: secondaryLabel,
        primaryLabel: primaryLabel,
        iconColor: iconColor,
        variant: variant,
        destructiveSecondary: destructiveSecondary,
        messageMaxHeightFactor: messageMaxHeightFactor,
        insetPadding: insetPadding,
        maxWidth: maxWidth,
        compact: compact,
        barrierDismissible: barrierDismissible,
        showCloseButton: showCloseButton,
        onPrimaryPressed: onPrimaryPressed,
        iconWidget: iconWidget,
        titleColor: titleColor,
      ),
    ).whenComplete(OverlayPromptGuard.unregisterBlockingOverlay);
  }

  static Future<T?> showWithActions<T>({
    required BuildContext context,
    required IconData icon,
    required String title,
    required List<GlassDialogAction<T>> actions,
    String message = '',
    Widget? content,
    Color iconColor = const Color(0xFF2563EB),
    GlassActionDialogVariant variant = GlassActionDialogVariant.normal,
    bool barrierDismissible = false,
    bool showCloseButton = false,
    double messageMaxHeightFactor = _defaultMessageMaxHeightFactor,
    EdgeInsets insetPadding = const EdgeInsets.symmetric(horizontal: 28),
    double? maxWidth,
    bool useRootNavigator = true,
    Widget? iconWidget,
    Color? titleColor,
  }) {
    if (!context.mounted) return Future<T?>.value(null);

    OverlayPromptGuard.registerBlockingOverlay();
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      builder: (_) => GlassActionDialog(
        icon: icon,
        title: title,
        message: message,
        content: content,
        actions: [
          for (final action in actions)
            GlassDialogAction<Object?>(
              label: action.label,
              value: action.value,
              tone: action.tone,
            ),
        ],
        iconColor: iconColor,
        variant: variant,
        messageMaxHeightFactor: messageMaxHeightFactor,
        insetPadding: insetPadding,
        maxWidth: maxWidth,
        barrierDismissible: barrierDismissible,
        showCloseButton: showCloseButton,
        iconWidget: iconWidget,
        titleColor: titleColor,
      ),
    ).whenComplete(OverlayPromptGuard.unregisterBlockingOverlay);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isError = variant == GlassActionDialogVariant.error;
    final effectiveIconColor = isError ? _errorColor : iconColor;
    final surfaceColor = isDark
        ? _darkSurface.withValues(alpha: 0.94)
        : _lightSurface.withValues(alpha: 0.96);
    final borderColor = isError
        ? _errorColor.withValues(alpha: isDark ? 0.38 : 0.28)
        : isDark
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFCBD5E1).withValues(alpha: 0.78);
    final shadowColor = Colors.black.withValues(alpha: isDark ? 0.42 : 0.16);
    final effectiveTitleColor =
        titleColor ?? (isDark ? Colors.white : const Color(0xFF171717));
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.78)
        : const Color(0xFF475467);
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

    final body =
        content ??
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: bodyColor,
            fontSize: 15,
            height: 1.48,
            fontWeight: FontWeight.w500,
          ),
        );

    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final compactChrome = keyboardInset > 0 || compact;
    final visibleHeight = (media.size.height - keyboardInset)
        .clamp(0.0, media.size.height)
        .toDouble();
    final heightFactor =
        (keyboardInset > 0
                ? 0.95
                : compact
                ? 0.92
                : (0.55 + messageMaxHeightFactor * 0.5).clamp(0.65, 0.92))
            .toDouble();
    final rawMaxHeight =
        (visibleHeight - media.padding.vertical - insetPadding.vertical)
            .toDouble();
    final preferredCap = visibleHeight * heightFactor;
    final minDialogHeight = preferredCap < 160 ? 0.0 : 160.0;
    final heightLower = minDialogHeight < preferredCap
        ? minDialogHeight
        : preferredCap;
    final heightUpper = minDialogHeight > preferredCap
        ? minDialogHeight
        : preferredCap;
    final maxDialogHeight = rawMaxHeight
        .clamp(heightLower, heightUpper)
        .toDouble();

    double keyboardAwareInset(double value) {
      if (keyboardInset <= 0 || value <= 0) return value;
      final shrunk = value * 0.35;
      return shrunk.clamp(0.0, value).toDouble();
    }

    double compactVerticalInset(double value) {
      // Default dialog padding is often horizontal-only (top/bottom = 0).
      // Avoid clamp(4, 0) which throws ArgumentError.
      if (value <= 0) return 4.0;
      final half = value * 0.5;
      if (value < 4.0) return half.clamp(0.0, value).toDouble();
      return half.clamp(4.0, value).toDouble();
    }

    final effectiveInset = EdgeInsets.only(
      left: insetPadding.left,
      right: insetPadding.right,
      top: compact
          ? compactVerticalInset(insetPadding.top)
          : keyboardAwareInset(insetPadding.top),
      bottom: compact
          ? compactVerticalInset(insetPadding.bottom)
          : keyboardAwareInset(insetPadding.bottom),
    );

    final boxConstraints = maxWidth == null
        ? BoxConstraints(maxHeight: maxDialogHeight)
        : BoxConstraints(
            maxHeight: maxDialogHeight,
            maxWidth: maxWidth!,
          );

    final customActions = actions;
    final actionButtons = customActions != null && customActions.isNotEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < customActions.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _buildToneButton(
                  context: context,
                  action: customActions[i],
                  isDark: isDark,
                ),
              ],
            ],
          )
        : primaryLabel == null
        ? null
        : LayoutBuilder(
            builder: (context, constraints) {
              final primary = primaryLabel!;
              final primaryButton = _ActionButton(
                label: primary,
                onPressed: () async {
                  if (onPrimaryPressed != null) {
                    final shouldClose = await onPrimaryPressed!();
                    if (!shouldClose) return;
                    if (!context.mounted) return;
                  }
                  Navigator.of(context).pop(true);
                },
                filled: true,
                foregroundColor: primaryButtonFg,
                borderColor: primaryButtonBg,
                backgroundColor: primaryButtonBg,
                dense: compact,
              );

              final secondary = secondaryLabel;
              if (secondary == null) {
                return primaryButton;
              }

              final stackVertically = _shouldStackActionsVertically(
                secondaryLabel: secondary,
                primaryLabel: primary,
                maxWidth: constraints.maxWidth,
              );

              final secondaryButton = _ActionButton(
                label: secondary,
                onPressed: () => Navigator.of(context).pop(false),
                filled: false,
                foregroundColor: secondaryFg,
                borderColor: secondaryBorder,
                backgroundColor: Colors.transparent,
                dense: compact,
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
          );

    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: MediaQuery.removeViewInsets(
        removeBottom: true,
        context: context,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (barrierDismissible)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const SizedBox.expand(),
                ),
              ),
            SafeArea(
              child: Center(
                child: GestureDetector(
                  onTap: () {},
                  child: Dialog(
                    elevation: 0,
                    backgroundColor: Colors.transparent,
                    insetPadding: effectiveInset,
                    child: ConstrainedBox(
                      constraints: boxConstraints,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          compactChrome ? 20 : 26,
                        ),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            padding: EdgeInsets.fromLTRB(
                              compact ? 14 : (compactChrome ? 18 : 24),
                              compact ? 10 : (compactChrome ? 14 : 24),
                              compact ? 14 : (compactChrome ? 18 : 24),
                              compact ? 10 : (compactChrome ? 12 : 18),
                            ),
                            decoration: BoxDecoration(
                              color: surfaceColor,
                              borderRadius: BorderRadius.circular(
                                compactChrome ? 20 : 26,
                              ),
                              border: Border.all(
                                color: borderColor,
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: shadowColor,
                                  blurRadius: 34,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      fit: FlexFit.loose,
                                      child: SingleChildScrollView(
                                        keyboardDismissBehavior:
                                            ScrollViewKeyboardDismissBehavior
                                                .onDrag,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (compact)
                                              _buildCompactHeader(
                                                effectiveIconColor:
                                                    effectiveIconColor,
                                                effectiveTitleColor:
                                                    effectiveTitleColor,
                                                isDark: isDark,
                                                reserveCloseSpace:
                                                    showCloseButton,
                                              )
                                            else ...[
                                              Container(
                                                height: compactChrome ? 40 : 58,
                                                width: compactChrome ? 40 : 58,
                                                decoration: BoxDecoration(
                                                  color: isDark
                                                      ? effectiveIconColor
                                                            .withValues(
                                                              alpha: 0.15,
                                                            )
                                                      : effectiveIconColor
                                                            .withValues(
                                                              alpha: 0.10,
                                                            ),
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: effectiveIconColor
                                                        .withValues(
                                                          alpha: isDark
                                                              ? 0.22
                                                              : 0.18,
                                                        ),
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: effectiveIconColor
                                                          .withValues(
                                                            alpha: isDark
                                                                ? 0.18
                                                                : 0.10,
                                                          ),
                                                      blurRadius: 18,
                                                      offset: const Offset(
                                                        0,
                                                        8,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: Center(
                                                  child:
                                                      iconWidget ??
                                                      Icon(
                                                        icon,
                                                        color:
                                                            effectiveIconColor,
                                                        size: compactChrome
                                                            ? 20
                                                            : 28,
                                                      ),
                                                ),
                                              ),
                                              SizedBox(
                                                height: compactChrome ? 8 : 18,
                                              ),
                                              Text(
                                                title,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: effectiveTitleColor,
                                                  fontSize: compactChrome
                                                      ? 17
                                                      : 21,
                                                  height: 1.15,
                                                  letterSpacing: 0,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              SizedBox(
                                                height: compactChrome ? 8 : 10,
                                              ),
                                            ],
                                            body,
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (actionButtons != null) ...[
                                      SizedBox(height: compact ? 8 : (compactChrome ? 10 : 16)),
                                      actionButtons,
                                    ] else
                                      const SizedBox(height: 6),
                                  ],
                                ),
                                if (showCloseButton)
                                  Positioned(
                                    top: -4,
                                    right: -4,
                                    child: Material(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.10)
                                          : Colors.white,
                                      shape: CircleBorder(
                                        side: BorderSide(
                                          color: isDark
                                              ? Colors.white.withValues(
                                                  alpha: 0.18,
                                                )
                                              : const Color(0xFFCBD5E1),
                                        ),
                                      ),
                                      elevation: isDark ? 0 : 3,
                                      shadowColor: Colors.black.withValues(
                                        alpha: 0.12,
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: () =>
                                            Navigator.of(context).maybePop(),
                                        child: SizedBox(
                                          width: 34,
                                          height: 34,
                                          child: Icon(
                                            Icons.close_rounded,
                                            size: 20,
                                            color: isDark
                                                ? Colors.white.withValues(
                                                    alpha: 0.88,
                                                  )
                                                : const Color(0xFF111827),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactHeader({
    required Color effectiveIconColor,
    required Color effectiveTitleColor,
    required bool isDark,
    required bool reserveCloseSpace,
  }) {
    return Padding(
      padding: EdgeInsets.only(right: reserveCloseSpace ? 28 : 0, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: effectiveIconColor.withValues(alpha: isDark ? 0.15 : 0.10),
              shape: BoxShape.circle,
              border: Border.all(
                color: effectiveIconColor.withValues(
                  alpha: isDark ? 0.22 : 0.18,
                ),
              ),
            ),
            child: Center(
              child: iconWidget ??
                  Icon(icon, color: effectiveIconColor, size: 17),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: effectiveTitleColor,
                fontSize: 16,
                height: 1.15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToneButton({
    required BuildContext context,
    required GlassDialogAction<Object?> action,
    required bool isDark,
  }) {
    switch (action.tone) {
      case GlassDialogActionTone.primary:
        final bg = isDark ? const Color(0xFF4F8DF7) : const Color(0xFF2563EB);
        return _ActionButton(
          label: action.label,
          onPressed: () => Navigator.of(context).pop(action.value),
          filled: true,
          foregroundColor: Colors.white,
          borderColor: bg,
          backgroundColor: bg,
          dense: compact,
        );
      case GlassDialogActionTone.destructive:
        return _ActionButton(
          label: action.label,
          onPressed: () => Navigator.of(context).pop(action.value),
          filled: false,
          foregroundColor: _errorColor,
          borderColor: _errorColor.withValues(alpha: 0.55),
          backgroundColor: _errorColor.withValues(alpha: isDark ? 0.12 : 0.06),
          dense: compact,
        );
      case GlassDialogActionTone.neutral:
        final bg = isDark ? const Color(0xFF303B4E) : const Color(0xFFE8EEF7);
        final fg = isDark ? Colors.white : const Color(0xFF253047);
        return _ActionButton(
          label: action.label,
          onPressed: () => Navigator.of(context).pop(action.value),
          filled: true,
          foregroundColor: fg,
          borderColor: bg,
          backgroundColor: bg,
          dense: compact,
        );
    }
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
    this.dense = false,
  });

  final String label;
  final FutureOr<void> Function() onPressed;
  final bool filled;
  final Color foregroundColor;
  final Color borderColor;
  final Color backgroundColor;
  final bool dense;

  static const _labelStyle = TextStyle(
    fontSize: 15.5,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: 0,
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
        style: _labelStyle.copyWith(
          color: foregroundColor,
          fontSize: dense ? 14.5 : 15.5,
        ),
      ),
    );

    return SizedBox(
      height: dense ? 42 : 54,
      width: double.infinity,
      child: filled
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                elevation: 1.5,
                shadowColor: backgroundColor.withValues(alpha: 0.30),
                backgroundColor: backgroundColor,
                foregroundColor: foregroundColor,
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: child,
            ),
    );
  }
}
