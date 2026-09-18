import 'package:cupertino_native/cupertino_native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:ui';

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
  });

  final String label;
  final int index;

  final String? iosSymbolName;
  final double? iosSymbolPointSize;
  final String? activeAssetIcon;
  final String? inactiveAssetIcon;

  final IconData? materialIcon;
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
  });

  final List<PlatformBottomTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;

  final Color? tint;
  final Color? surface;
  final Color? darkSurface;
  final bool? isDark;
  final double heightIOS;

  @override
  Widget build(BuildContext context) {
    final isApplePlatform =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    final activeTint =
        tint ?? const Color(AppConfig.cBottomBarActive);

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
  });

  final List<PlatformBottomTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color tint;
  final Color? surface;
  final Color? darkSurface;
  final bool? isDark;

  @override
  Widget build(BuildContext context) {
    final effectiveIsDark =
        isDark ?? Theme.of(context).brightness == Brightness.dark;
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    if (isAndroid) {
      return _buildAndroidBar(context, effectiveIsDark: effectiveIsDark);
    }

    return _buildLegacyFloatingBar(
      context,
      effectiveIsDark: effectiveIsDark,
    );
  }

  /// Flat edge-to-edge Android bar (no glass / no floating pill).
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
    // Match web header: soft elevation edge (header casts down; bar casts up).
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
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.w500,
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

  /// Previous floating glass bar (non-Android platforms).
  Widget _buildLegacyFloatingBar(
    BuildContext context, {
    required bool effectiveIsDark,
  }) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final activeColor = tint;
    final inactiveColor =
        effectiveIsDark ? Colors.white : const Color(0xFF272527);
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

    if (asset == null || asset.isEmpty) {
      return Icon(
        tab.materialIcon ?? (isActive ? Icons.circle : Icons.circle_outlined),
        color: isActive ? activeColor : inactiveColor,
        size: size,
      );
    }

    return Image.asset(
      asset,
      color: isActive ? activeColor : inactiveColor,
      height: size,
      width: size,
    );
  }
}
