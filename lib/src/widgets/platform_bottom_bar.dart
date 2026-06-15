import 'package:cupertino_native/cupertino_native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:ui';

class PlatformBottomTab {
  const PlatformBottomTab({
    required this.label,
    required this.index,
    this.iosSymbolName,
    this.activeAssetIcon,
    this.inactiveAssetIcon,
  });

  final String label;
  final int index;

  final String? iosSymbolName;
  final String? activeAssetIcon;
  final String? inactiveAssetIcon;
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

    return isApplePlatform
        ? _CupertinoNativeBottomBar(
            tabs: tabs,
            currentIndex: currentIndex,
            onTap: onTap,
            tint: tint ?? Theme.of(context).colorScheme.primary,
            height: heightIOS,
          )
        : _ClassicBottomBar(
            tabs: tabs,
            currentIndex: currentIndex,
            onTap: onTap,
            tint: tint ?? Theme.of(context).colorScheme.primary,
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

    final activeColor = effectiveIsDark ? Colors.white : tint;

    final inactiveColor = effectiveIsDark
        ? Colors.white.withAlpha(isAndroid ? 160 : 140)
        : isAndroid
        ? const Color(0xFF8D96A6)
        : const Color.fromARGB(255, 177, 175, 175);

    final bgColor = effectiveIsDark
        ? (darkSurface ?? const Color(0xFF1A2332)).withAlpha(
            isAndroid ? 225 : 210,
          )
        : (surface ??
                  (isAndroid
                      ? const Color(0xFFE6ECF4)
                      : const Color(0xFFFBFBFD)))
              .withAlpha(isAndroid ? 242 : 245);

    final borderColor = effectiveIsDark
        ? Colors.white.withAlpha(isAndroid ? 24 : 18)
        : Colors.black.withAlpha(isAndroid ? 28 : 10);

    final activePill = effectiveIsDark
        ? Colors.white.withAlpha(isAndroid ? 28 : 18)
        : isAndroid
        ? const Color(0xFFD3E2F6)
        : const Color(0xFFE8EDF6);

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
                      : Colors.black.withAlpha(isAndroid ? 24 : 18),
                  blurRadius: isAndroid ? 24 : 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SizedBox(
              height: isAndroid ? 72 : 78,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: tabs.map((tab) {
                  final isActive = currentIndex == tab.index;

                  return InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => onTap(tab.index),
                    child: AnimatedContainer(
                      duration: isAndroid
                          ? const Duration(milliseconds: 320)
                          : const Duration(milliseconds: 180),
                      curve: isAndroid ? Curves.easeInOut : Curves.easeOut,
                      width: isAndroid ? 66 : 70,
                      height: isAndroid ? 54 : 58,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isActive ? activePill : Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _TabIcon(
                            isActive: isActive,
                            tab: tab,
                            activeColor: activeColor,
                            inactiveColor: inactiveColor,
                          ),
                          const SizedBox(height: 4),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                tab.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      color: isActive
                                          ? activeColor
                                          : inactiveColor,
                                      fontSize: 11.5,
                                      fontWeight: isActive
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                              ),
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
  });

  final bool isActive;
  final PlatformBottomTab tab;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    final asset = isActive ? tab.activeAssetIcon : tab.inactiveAssetIcon;

    if (asset == null || asset.isEmpty) {
      return Icon(
        isActive ? Icons.circle : Icons.circle_outlined,
        color: isActive ? activeColor : inactiveColor,
        size: 24,
      );
    }

    return Image.asset(
      asset,
      color: isActive ? activeColor : inactiveColor,
      height: 24,
    );
  }
}
