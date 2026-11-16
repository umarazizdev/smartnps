import 'dart:math' as math;
import 'dart:ui';

import 'package:cupertino_native/cupertino_native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../utilities/app_config.dart';

class PlatformBottomTab {
  const PlatformBottomTab({
    required this.label,
    required this.index,
    this.iosSymbolName,
    this.iosSymbolPointSize,
    this.activeAssetIcon,
    this.inactiveAssetIcon,
    this.materialIcon,
    this.useThinChatIcon = false,
    this.useCalendarClockIcon = false,
    this.useTimesheetIcon = false,
  });

  final String label;
  final int index;

  final String? iosSymbolName;
  final double? iosSymbolPointSize;
  final String? activeAssetIcon;
  final String? inactiveAssetIcon;

  final IconData? materialIcon;
  final bool useThinChatIcon;
  final bool useCalendarClockIcon;
  final bool useTimesheetIcon;
}

class PlatformBottomBar extends StatelessWidget {
  const PlatformBottomBar({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
    this.tint,
    this.surface,
    this.darkSurface,
    this.isDark,
    this.heightIOS = 85,
    this.forceEdgeAttached = false,
  });

  final List<PlatformBottomTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;

  final Color? tint;
  final Color? surface;
  final Color? darkSurface;
  final bool? isDark;
  final double heightIOS;
  final bool forceEdgeAttached;

  @override
  Widget build(BuildContext context) {
    final isApplePlatform =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    final activeTint = tint ?? const Color(AppConfig.cBottomBarActive);

    if (forceEdgeAttached) {
      return _ClassicBottomBar(
        tabs: tabs,
        currentIndex: currentIndex,
        onTap: onTap,
        tint: activeTint,
        surface: surface,
        darkSurface: darkSurface,
        isDark: isDark,
        forceEdgeAttached: true,
      );
    }

    return isApplePlatform
        ? _CupertinoNativeBottomBar(
            tabs: tabs,
            currentIndex: currentIndex,
            onTap: onTap,
            tint: activeTint,
            height: heightIOS,
          )
        : _ClassicBottomBar(
            tabs: tabs,
            currentIndex: currentIndex,
            onTap: onTap,
            tint: activeTint,
            surface: surface,
            darkSurface: darkSurface,
            isDark: isDark,
          );
  }
}

class _CupertinoNativeBottomBar extends StatelessWidget {
  const _CupertinoNativeBottomBar({
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
    required this.tint,
    required this.height,
  });

  final List<PlatformBottomTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color tint;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomInset > 0 ? 6 : 10),
      child: CNTabBar(
        items: tabs
            .map(
              (tab) => CNTabBarItem(
                label: tab.label,
                icon: CNSymbol(
                  tab.iosSymbolName ?? 'circle',
                  size: tab.iosSymbolPointSize ?? 24,
                ),
              ),
            )
            .toList(),
        currentIndex: currentIndex,
        tint: tint,
        height: height,
        onTap: onTap,
      ),
    );
  }
}

class _ClassicBottomBar extends StatelessWidget {
  const _ClassicBottomBar({
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
    required this.tint,
    this.surface,
    this.darkSurface,
    this.isDark,
    this.forceEdgeAttached = false,
  });

  final List<PlatformBottomTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color tint;
  final Color? surface;
  final Color? darkSurface;
  final bool? isDark;
  final bool forceEdgeAttached;

  @override
  Widget build(BuildContext context) {
    final effectiveIsDark =
        isDark ?? Theme.of(context).brightness == Brightness.dark;
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    if (forceEdgeAttached || isAndroid) {
      return _buildAndroidBar(context, effectiveIsDark: effectiveIsDark);
    }

    return _buildLegacyFloatingBar(context, effectiveIsDark: effectiveIsDark);
  }

  Widget _buildAndroidBar(
    BuildContext context, {
    required bool effectiveIsDark,
  }) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const lightBg = Color(0xFFFFFFFF);
    final bgColor = effectiveIsDark
        ? (darkSurface ?? const Color(0xFF1A2332))
        : lightBg;
    final topHairline = effectiveIsDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0x0D000000);

    final edgeShadow = effectiveIsDark
        ? Colors.black.withValues(alpha: 0.20)
        : Colors.black.withValues(alpha: 0.035);
    final activeColor = tint;
    final inactiveColor = effectiveIsDark
        ? Colors.white.withValues(alpha: 0.72)
        : const Color(0xFF6B6B6B);

    return Material(
      color: bgColor,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(top: BorderSide(color: topHairline, width: 1)),
          boxShadow: [
            BoxShadow(
              color: edgeShadow,
              blurRadius: 6,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SizedBox(
            height: 56,
            child: Row(
              children: tabs.map((tab) {
                final isActive = currentIndex == tab.index;
                final color = isActive ? activeColor : inactiveColor;

                return Expanded(
                  child: InkWell(
                    onTap: () => onTap(tab.index),
                    splashColor: activeColor.withValues(alpha: 0.08),
                    highlightColor: activeColor.withValues(alpha: 0.04),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _TabIcon(
                          isActive: isActive,
                          tab: tab,
                          activeColor: activeColor,
                          inactiveColor: inactiveColor,
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tab.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.w500,
                            height: 1.1,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegacyFloatingBar(
    BuildContext context, {
    required bool effectiveIsDark,
  }) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final activeColor = tint;
    final inactiveColor = effectiveIsDark
        ? Colors.white
        : const Color(0xFF272527);
    final bgColor = effectiveIsDark
        ? (darkSurface ?? const Color(0xFF1A2332)).withAlpha(210)
        : (surface ?? const Color(0xFFFBFBFD)).withAlpha(245);
    final borderColor = effectiveIsDark
        ? Colors.white.withAlpha(18)
        : Colors.black.withAlpha(10);
    final activePill = effectiveIsDark
        ? Colors.white.withAlpha(18)
        : const Color(0xFFE9EAEC);

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomInset + 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: effectiveIsDark
                      ? Colors.black.withAlpha(90)
                      : Colors.black.withAlpha(18),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SizedBox(
              height: 78,
              child: Row(
                children: tabs.map((tab) {
                  final isActive = currentIndex == tab.index;

                  return Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => onTap(tab.index),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          height: 58,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isActive ? activePill : Colors.transparent,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _TabIcon(
                                isActive: isActive,
                                tab: tab,
                                activeColor: activeColor,
                                inactiveColor: inactiveColor,
                                size: 24,
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: double.infinity,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    tab.label,
                                    maxLines: 1,
                                    softWrap: false,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      height: 1.1,
                                      letterSpacing: 0.15,
                                      color: isActive
                                          ? activeColor
                                          : inactiveColor,
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
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabIcon extends StatelessWidget {
  const _TabIcon({
    required this.isActive,
    required this.tab,
    required this.activeColor,
    required this.inactiveColor,
    this.size = 24,
  });

  final bool isActive;
  final PlatformBottomTab tab;
  final Color activeColor;
  final Color inactiveColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = isActive ? tab.activeAssetIcon : tab.inactiveAssetIcon;
    final color = isActive ? activeColor : inactiveColor;

    if (tab.useTimesheetIcon) {
      return SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _TimesheetIconPainter(color)),
      );
    }

    if (tab.useCalendarClockIcon) {
      return SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _CalendarClockPainter(color)),
      );
    }

    if (tab.useThinChatIcon) {
      return SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _ThinChatIconPainter(color: color)),
      );
    }

    if (asset == null || asset.isEmpty) {
      return Icon(
        tab.materialIcon ?? (isActive ? Icons.circle : Icons.circle_outlined),
        color: color,
        size: size,
      );
    }

    return Image.asset(asset, color: color, height: size, width: size);
  }
}

class _ThinChatIconPainter extends CustomPainter {
  const _ThinChatIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24;
    final sy = size.height / 24;
    final path = Path()
      ..moveTo(6 * sx, 3.25 * sy)
      ..lineTo(18 * sx, 3.25 * sy)
      ..quadraticBezierTo(21 * sx, 3.25 * sy, 21 * sx, 6.25 * sy)
      ..lineTo(21 * sx, 13.9 * sy)
      ..quadraticBezierTo(21 * sx, 17 * sy, 17.9 * sx, 17 * sy)
      ..lineTo(10.2 * sx, 17 * sy)
      ..lineTo(5.15 * sx, 20.75 * sy)
      ..lineTo(6.15 * sx, 16.85 * sy)
      ..quadraticBezierTo(3 * sx, 16.5 * sy, 3 * sx, 13.5 * sy)
      ..lineTo(3 * sx, 6.25 * sy)
      ..quadraticBezierTo(3 * sx, 3.25 * sy, 6 * sx, 3.25 * sy)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25 * math.min(sx, sy)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _ThinChatIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _TimesheetIconPainter extends CustomPainter {
  const _TimesheetIconPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(2.5, 3.5, 18, 17),
        const Radius.circular(2),
      ),
      pen,
    );
    canvas.drawLine(const Offset(2.5, 7.5), const Offset(20.5, 7.5), pen);
    for (final x in [7.0, 16.0]) {
      canvas.drawLine(Offset(x, 1.8), Offset(x, 5.2), pen);
    }
    // Six open date cells keep the grid legible at the 24 px tab size.
    for (final y in [11.5, 16.5]) {
      for (final x in [6.5, 11.5, 16.5]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(x, y), width: 2, height: 2),
            const Radius.circular(.35),
          ),
          pen,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimesheetIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _CalendarClockPainter extends CustomPainter {
  const _CalendarClockPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Leave the lower right open for the clock, avoiding overlapping strokes.
    final frame = Path()
      ..moveTo(10.5, 20.5)
      ..lineTo(4.5, 20.5)
      ..quadraticBezierTo(2.5, 20.5, 2.5, 18.5)
      ..lineTo(2.5, 5)
      ..quadraticBezierTo(2.5, 3.5, 4, 3.5)
      ..lineTo(18, 3.5)
      ..quadraticBezierTo(20, 3.5, 20, 5.5)
      ..lineTo(20, 10);
    canvas.drawPath(frame, pen);
    canvas.drawLine(const Offset(2.5, 7.5), const Offset(20, 7.5), pen);
    for (final x in [7.0, 15.5]) {
      canvas.drawLine(Offset(x, 1.8), Offset(x, 5.2), pen);
    }
    final datePaint = Paint()
      ..color = color
      ..isAntiAlias = true;
    for (final y in [11.0, 15.0]) {
      for (final x in [6.5, 10.0]) {
        canvas.drawCircle(Offset(x, y), .7, datePaint);
      }
    }
    canvas.drawCircle(const Offset(17.5, 17.3), 4.8, pen);
    canvas.drawPath(
      Path()
        ..moveTo(17.5, 14.6)
        ..lineTo(17.5, 17.3)
        ..lineTo(19.5, 18.4),
      pen,
    );
  }

  @override
  bool shouldRepaint(covariant _CalendarClockPainter oldDelegate) =>
      oldDelegate.color != color;
}
