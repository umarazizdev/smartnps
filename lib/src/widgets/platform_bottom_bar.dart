import 'package:cupertino_native/cupertino_native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:ui';

import '../utilities/app_config.dart';

class PlatformBottomTab {
  const PlatformBottomTab({
    required this.label,
    required this.index,
    this.iosSymbolName,
    this.activeAssetIcon,
    this.inactiveAssetIcon,
    this.materialIcon,
  });

  final String label;
  final int index;

  final String? iosSymbolName;
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
                icon: CNSymbol(tab.iosSymbolName ?? 'circle'),
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
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    final activeColor = tint;

    final inactiveColor = effectiveIsDark
        ? Colors.white
        : const Color(0xFF272527);

    final bgColor = effectiveIsDark
        ? (darkSurface ?? const Color(0xFF1A2332)).withAlpha(
            isAndroid ? 235 : 210,
          )
        : isAndroid

        ? const Color(0xFFFFFFF8).withAlpha(252)
        : (surface ?? const Color(0xFFFBFBFD)).withAlpha(245);

    final borderColor = effectiveIsDark
        ? Colors.white.withAlpha(isAndroid ? 20 : 18)
        : Colors.black.withAlpha(isAndroid ? 16 : 10);

    final activePill = effectiveIsDark
        ? Colors.white.withAlpha(isAndroid ? 28 : 18)
        : const Color(0xFFE9EAEC);

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomInset + 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: isAndroid ? 22 : 20,
            sigmaY: isAndroid ? 22 : 20,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: effectiveIsDark
                      ? Colors.black.withAlpha(isAndroid ? 110 : 90)
                      : Colors.black.withAlpha(isAndroid ? 18 : 18),
                  blurRadius: isAndroid ? 20 : 22,
                  offset: Offset(0, isAndroid ? 8 : 10),
                ),
              ],
            ),
            child: SizedBox(
              height: isAndroid ? 72 : 78,
              child: Row(
                children: tabs.map((tab) {
                  final isActive = currentIndex == tab.index;

                  return Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => onTap(tab.index),

                      child: Center(
                        child: AnimatedContainer(
                          duration: isAndroid
                              ? const Duration(milliseconds: 320)
                              : const Duration(milliseconds: 180),
                          curve: isAndroid
                              ? Curves.easeInOut
                              : Curves.easeOut,
                          height: isAndroid ? 54 : 58,
                          padding: EdgeInsets.symmetric(
                            horizontal: isAndroid ? 14 : 16,
                            vertical: isAndroid ? 2 : 6,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? activePill
                                : Colors.transparent,
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
                              SizedBox(height: isAndroid ? 3 : 4),
                              Text(
                                tab.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
