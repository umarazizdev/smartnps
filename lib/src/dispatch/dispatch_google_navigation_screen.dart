import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import 'dispatch_google_navigation_controller.dart';
import 'dispatch_scale.dart';
import 'live_map_marker_style.dart';

class DispatchGoogleNavigationScreen extends StatefulWidget {
  const DispatchGoogleNavigationScreen({super.key});

  static const String controllerTag = 'dispatch-google-navigation';

  static Future<void> open(
    BuildContext context, {
    required gmaps.LatLng site,
    String? siteName,
    String? siteSubtitle,
    gmaps.LatLng? initialOrigin,
    bool isDark = false,
    bool replace = false,
  }) async {
    final dark =
        isDark || Theme.of(context).brightness == Brightness.dark;
    _ensureController(
      site: site,
      siteName: siteName,
      siteSubtitle: siteSubtitle,
      initialOrigin: initialOrigin,
      isDark: dark,
    );
    final route = MaterialPageRoute<void>(
      builder: (_) => const DispatchGoogleNavigationScreen(),
    );
    final navigator = Navigator.of(context);
    if (replace) {
      await navigator.pushReplacement(route);
    } else {
      await navigator.push(route);
    }
  }

  static void _ensureController({
    required gmaps.LatLng site,
    String? siteName,
    String? siteSubtitle,
    gmaps.LatLng? initialOrigin,
    bool isDark = false,
  }) {
    if (Get.isRegistered<DispatchGoogleNavigationController>(
      tag: controllerTag,
    )) {
      Get.delete<DispatchGoogleNavigationController>(
        tag: controllerTag,
        force: true,
      );
    }
    Get.put(
      DispatchGoogleNavigationController(
        site: site,
        siteName: siteName,
        siteSubtitle: siteSubtitle,
        initialOrigin: initialOrigin,
        isDark: isDark,
      ),
      tag: controllerTag,
    );
  }

  @override
  State<DispatchGoogleNavigationScreen> createState() =>
      _DispatchGoogleNavigationScreenState();
}

class _DispatchGoogleNavigationScreenState
    extends State<DispatchGoogleNavigationScreen> {
  late final DispatchGoogleNavigationController controller;
  Worker? _closeWorker;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    controller = Get.find<DispatchGoogleNavigationController>(
      tag: DispatchGoogleNavigationScreen.controllerTag,
    );
    _closeWorker = ever<bool>(controller.shouldClose, (close) {
      if (!close || _closing || !mounted) return;
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).maybePop();
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final padding = MediaQuery.viewPaddingOf(context);
    final scale = DispatchScale.of(context);
    final sdkPadding = EdgeInsets.only(
      top: padding.top,
      bottom: padding.bottom,
      left: scale.s(44),
      right: scale.s(72),
    );
    unawaited(controller.updateSafePadding(sdkPadding));
  }

  @override
  void dispose() {
    _closeWorker?.dispose();
    _closeWorker = null;
    if (Get.isRegistered<DispatchGoogleNavigationController>(
      tag: DispatchGoogleNavigationScreen.controllerTag,
    )) {
      Get.delete<DispatchGoogleNavigationController>(
        tag: DispatchGoogleNavigationScreen.controllerTag,
        force: true,
      );
    }
    super.dispose();
  }

  SystemUiOverlayStyle get _overlayStyle {
    if (controller.isDark) {
      return const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF0B1C2C),
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      );
    }
    return const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFFF5F7FA),
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final background =
        controller.isDark ? const Color(0xFF0B1C2C) : const Color(0xFFF5F7FA);
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 4.0);
    final markerSize = scale.markerSize;
    final sdkPadding = EdgeInsets.only(
      top: viewPadding.top,
      bottom: viewPadding.bottom,
      left: scale.s(44),
      right: scale.s(72),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _overlayStyle,
      child: Scaffold(
        backgroundColor: background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Obx(() {
                if (!controller.sessionReady.value) {
                  return ColoredBox(
                    color: background,
                    child: const Center(child: CircularProgressIndicator()),
                  );
                }
                return GoogleMapsNavigationView(
                  onViewCreated: (viewController) {
                    unawaited(
                      controller.onViewCreated(
                        viewController,
                        safePadding: sdkPadding,
                        devicePixelRatio: dpr,
                        markerLogicalSize: markerSize,
                      ),
                    );
                  },
                  initialNavigationUIEnabledPreference:
                      NavigationUIEnabledPreference.automatic,
                  initialForceNightMode: controller.forceNightMode,
                  initialMapColorScheme: controller.mapColorScheme,
                  initialPadding: sdkPadding,
                  initialCameraPosition: CameraPosition(
                    target: controller.initialCameraTarget,
                    zoom: 16,
                  ),
                  initialZoomControlsEnabled: false,
                  initialMapToolbarEnabled: false,
                );
              }),
            ),
            Positioned(
              top: viewPadding.top,
              left: viewPadding.left,
              right: viewPadding.right,
              bottom: viewPadding.bottom,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final railBottom = scale.s(150);
                  final railTop = scale.s(120);
                  return Stack(
                    children: [
                      Positioned(
                        right: scale.s(12),
                        bottom: railBottom,
                        top: railTop,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Obx(() {
                            final soundOn = controller.soundEnabled.value;
                            final selectedStyle =
                                controller.selectedMarkerStyle.value;
                            final pickerOpen =
                                controller.showMarkerPicker.value;
                            final gap = SizedBox(height: scale.s(6));
                            return Material(
                              color: Colors.black.withValues(alpha: 0.58),
                              borderRadius: BorderRadius.circular(scale.s(28)),
                              elevation: 3,
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: scale.s(8),
                                  horizontal: scale.s(6),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _NavChromeButton(
                                      tooltip: 'End navigation',
                                      icon: Icons.close_rounded,
                                      onTap: () =>
                                          Navigator.of(context).maybePop(),
                                    ),
                                    gap,
                                    _NavChromeButton(
                                      tooltip: soundOn
                                          ? 'Mute voice guidance'
                                          : 'Unmute voice guidance',
                                      icon: soundOn
                                          ? Icons.volume_up_rounded
                                          : Icons.volume_off_rounded,
                                      onTap: () =>
                                          unawaited(controller.toggleSound()),
                                      active: soundOn,
                                    ),
                                    gap,
                                    _NavChromeButton(
                                      key: ValueKey<String>(
                                        'nav-pin-${selectedStyle.id}',
                                      ),
                                      tooltip: selectedStyle.label,
                                      icon: Icons.person_pin_circle_rounded,
                                      assetPath: selectedStyle.assetPath,
                                      onTap: controller.toggleMarkerPicker,
                                      active: pickerOpen,
                                    ),
                                    gap,
                                    _NavChromeButton(
                                      tooltip: 'Route overview',
                                      icon: Icons.route_rounded,
                                      onTap: () => unawaited(
                                        controller.showRouteOverview(),
                                      ),
                                    ),
                                    gap,
                                    _NavChromeButton(
                                      tooltip: 'Recenter',
                                      icon: Icons.my_location_rounded,
                                      onTap: () =>
                                          unawaited(controller.recenter()),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      Obx(() {
                        final selectedStyle =
                            controller.selectedMarkerStyle.value;
                        if (!controller.showMarkerPicker.value) {
                          return const SizedBox.shrink();
                        }
                        return Positioned(
                          left: scale.s(12),
                          right: scale.s(72),
                          bottom: railBottom,
                          child: _NavMarkerStylePicker(
                            key: ValueKey<String>(
                              'nav-picker-${selectedStyle.id}',
                            ),
                            isDark: controller.isDark,
                            selected: selectedStyle,
                            onSelected: (style) => unawaited(
                              controller.selectMarkerStyle(style),
                            ),
                            onClose: controller.closeMarkerPicker,
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
            ),
            Obx(() {
              final error = controller.errorMessage.value;
              if (error == null) return const SizedBox.shrink();
              return Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(scale.s(16)),
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(scale.s(12)),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          scale.s(14),
                          scale.s(12),
                          scale.s(14),
                          scale.s(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              error,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: scale.sp(14),
                              ),
                            ),
                            SizedBox(height: scale.s(10)),
                            TextButton(
                              onPressed: () => unawaited(controller.retry()),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _NavChromeButton extends StatelessWidget {
  const _NavChromeButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.active = false,
    this.assetPath,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final String? assetPath;

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    final side = scale.s(44);
    final asset = assetPath;
    return Material(
      color: active
          ? const Color(0xFF2F6FED).withValues(alpha: 0.92)
          : Colors.white.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: side,
            height: side,
            child: Center(
              child: asset == null
                  ? Icon(icon, color: Colors.white, size: scale.s(22))
                  : SizedBox(
                      width: side * 0.78,
                      height: side * 0.78,
                      child: SvgPicture.asset(
                        asset,
                        key: ValueKey<String>(asset),
                        fit: BoxFit.contain,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavMarkerStylePicker extends StatelessWidget {
  const _NavMarkerStylePicker({
    super.key,
    required this.isDark,
    required this.selected,
    required this.onSelected,
    required this.onClose,
  });

  final bool isDark;
  final LiveMapMarkerStyle selected;
  final ValueChanged<LiveMapMarkerStyle> onSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    final bg = isDark ? const Color(0xF0122D43) : Colors.white;
    final fg = isDark ? Colors.white : const Color(0xFF10234E);
    return Material(
      color: bg.withValues(alpha: 0.96),
      elevation: 4,
      borderRadius: BorderRadius.circular(scale.s(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: scale.s(280)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            scale.s(10),
            scale.s(8),
            scale.s(8),
            scale.s(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose your marker',
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w800,
                        fontSize: scale.sp(13),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: onClose,
                    icon: Icon(
                      Icons.close_rounded,
                      color: fg,
                      size: scale.s(18),
                    ),
                  ),
                ],
              ),
              SizedBox(height: scale.s(8)),
              Wrap(
                spacing: scale.s(8),
                runSpacing: scale.s(8),
                children: [
                  for (final style in LiveMapMarkerStyle.values)
                    SizedBox(
                      width: scale.s(60),
                      height: scale.s(72),
                      child: InkWell(
                        onTap: () => onSelected(style),
                        borderRadius: BorderRadius.circular(scale.s(12)),
                        child: Container(
                          padding: EdgeInsets.all(scale.s(6)),
                          decoration: BoxDecoration(
                            color: style == selected
                                ? (isDark
                                    ? const Color(0xFF1A4A6E)
                                    : const Color(0xFFDDEBFF))
                                : (isDark
                                    ? const Color(0xFF16344A)
                                    : const Color(0xFFF3F6FB)),
                            borderRadius: BorderRadius.circular(scale.s(12)),
                            border: Border.all(
                              color: style == selected
                                  ? const Color(0xFF3569F6)
                                  : Colors.transparent,
                              width: scale.s(1.5),
                            ),
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: SvgPicture.asset(
                                  style.assetPath,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              SizedBox(height: scale.s(4)),
                              Text(
                                style.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: fg,
                                  fontSize: scale.sp(9),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
