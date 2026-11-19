import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'dispatch_fullscreen_map_controller.dart';
import 'dispatch_request_data.dart';
import 'dispatch_response_panel.dart';
import 'dispatch_scale.dart';
import 'map_control_icon.dart';

class DispatchFullscreenMapScreen extends StatefulWidget {
  const DispatchFullscreenMapScreen({
    super.key,
    required this.site,
    required this.isDark,
    this.siteName,
    this.siteSubtitle,
    this.initialOrigin,
    this.initialRoutePoints = const [],
    this.onAccept,
    this.onDecline,
    this.responseSecondsLeft,
    this.responseTotalSeconds = 30,
    this.accepted = false,
    this.showResponseActions = true,
  });

  final LatLng site;
  final bool isDark;
  final String? siteName;
  final String? siteSubtitle;
  final LatLng? initialOrigin;
  final List<LatLng> initialRoutePoints;
  final Future<void> Function()? onAccept;
  final Future<void> Function()? onDecline;
  final ValueListenable<int>? responseSecondsLeft;
  final int responseTotalSeconds;
  final bool accepted;
  final bool showResponseActions;

  static Future<bool?> open(
    BuildContext context, {
    required LatLng site,
    required bool isDark,
    String? siteName,
    String? siteSubtitle,
    LatLng? initialOrigin,
    List<LatLng> initialRoutePoints = const [],
    Future<void> Function()? onAccept,
    Future<void> Function()? onDecline,
    ValueListenable<int>? responseSecondsLeft,
    int responseTotalSeconds = 30,
    bool accepted = false,
    bool showResponseActions = true,
  }) {
    _ensureController(
      site: site,
      isDark: isDark,
      siteName: siteName,
      siteSubtitle: siteSubtitle,
      initialOrigin: initialOrigin,
      initialRoutePoints: initialRoutePoints,
      onAccept: onAccept,
      onDecline: onDecline,
      responseSecondsLeft: responseSecondsLeft,
      responseTotalSeconds: responseTotalSeconds,
      accepted: accepted,
      showResponseActions: showResponseActions,
    );
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (routeContext) {
          Get.find<DispatchFullscreenMapController>(
            tag: DispatchFullscreenMapController.tag,
          ).onExpireClose = () {
            Navigator.of(routeContext).maybePop(false);
          };
          return DispatchFullscreenMapScreen(
            site: site,
            isDark: isDark,
            siteName: siteName,
            siteSubtitle: siteSubtitle,
            initialOrigin: initialOrigin,
            initialRoutePoints: initialRoutePoints,
            onAccept: onAccept,
            onDecline: onDecline,
            responseSecondsLeft: responseSecondsLeft,
            responseTotalSeconds: responseTotalSeconds,
            accepted: accepted,
            showResponseActions: showResponseActions,
          );
        },
      ),
    );
  }

  static void _ensureController({
    required LatLng site,
    required bool isDark,
    String? siteName,
    String? siteSubtitle,
    LatLng? initialOrigin,
    List<LatLng> initialRoutePoints = const [],
    Future<void> Function()? onAccept,
    Future<void> Function()? onDecline,
    ValueListenable<int>? responseSecondsLeft,
    int responseTotalSeconds = 30,
    bool accepted = false,
    bool showResponseActions = true,
  }) {
    if (Get.isRegistered<DispatchFullscreenMapController>(
      tag: DispatchFullscreenMapController.tag,
    )) {
      Get.delete<DispatchFullscreenMapController>(
        tag: DispatchFullscreenMapController.tag,
        force: true,
      );
    }
    Get.put(
      DispatchFullscreenMapController(
        site: site,
        isDark: isDark,
        siteName: siteName,
        siteSubtitle: siteSubtitle,
        initialOrigin: initialOrigin,
        initialRoutePoints: initialRoutePoints,
        onAccept: onAccept,
        onDecline: onDecline,
        responseSecondsLeft: responseSecondsLeft,
        responseTotalSeconds: responseTotalSeconds,
        accepted: accepted,
        showResponseActions: showResponseActions,
      ),
      tag: DispatchFullscreenMapController.tag,
    );
  }

  @override
  State<DispatchFullscreenMapScreen> createState() =>
      _DispatchFullscreenMapScreenState();
}

class _DispatchFullscreenMapScreenState
    extends State<DispatchFullscreenMapScreen> {
  late final DispatchFullscreenMapController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.find<DispatchFullscreenMapController>(
      tag: DispatchFullscreenMapController.tag,
    );
    if (controller.shouldResumeNavigation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(controller.openGoogleNavigation(context));
      });
    }
  }

  @override
  void dispose() {
    if (Get.isRegistered<DispatchFullscreenMapController>(
      tag: DispatchFullscreenMapController.tag,
    )) {
      Get.delete<DispatchFullscreenMapController>(
        tag: DispatchFullscreenMapController.tag,
        force: true,
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    final isDark = controller.isDark;
    final background = isDark
        ? const Color(0xFF071F2F)
        : const Color(0xFFFDFEFF);
    final secondsListenable = controller.responseSecondsLeft;
    return Theme(
      data: ThemeData(
        brightness: isDark ? Brightness.dark : Brightness.light,
        useMaterial3: true,
      ),
      child: Scaffold(
        backgroundColor: background,
        body: SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Obx(() {
                  if (!controller.mapReady.value) {
                    return ColoredBox(color: background);
                  }
                  final showRoutes = controller.routes.isNotEmpty &&
                      !controller.showLayersMenu.value;
                  final showNavCta = controller.accepted.value &&
                      !controller.showResponseActions.value;
                  final topInset =
                      MediaQuery.paddingOf(context).top + scale.s(64);
                  final bottomInset = MediaQuery.paddingOf(context).bottom +
                      (controller.showResponseActions.value
                          ? scale.s(200)
                          : (showNavCta ? scale.s(72) : scale.s(20))) +
                      (showRoutes ? scale.s(92) : 0);
                  return GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: controller.cameraTarget,
                      zoom: 13,
                    ),
                    markers: Set<Marker>.from(controller.markers),
                    polylines: Set<Polyline>.from(controller.polylines),
                    mapType: controller.mapType.value,
                    trafficEnabled: controller.trafficEnabled.value,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    zoomControlsEnabled: false,
                    compassEnabled: true,
                    mapToolbarEnabled: true,
                    rotateGesturesEnabled: true,
                    scrollGesturesEnabled: true,
                    tiltGesturesEnabled: true,
                    zoomGesturesEnabled: true,
                    liteModeEnabled: false,
                    padding: EdgeInsets.only(
                      top: topInset,
                      bottom: bottomInset,
                      right: scale.s(12),
                    ),
                    onMapCreated: controller.onMapCreated,
                  );
                }),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      scale.s(12),
                      scale.s(8),
                      scale.s(12),
                      scale.s(8),
                    ),
                    child: Row(
                      children: [
                        _MapChromeButton(
                          icon: Icons.close_rounded,
                          tooltip: 'Close map',
                          isDark: isDark,
                          onTap: () => controller.closeMap(context),
                        ),
                        SizedBox(width: scale.s(8)),
                        Obx(
                          () => _MapChromeButton(
                            icon: Icons.layers_rounded,
                            tooltip: 'Map layers',
                            isDark: isDark,
                            onTap: controller.toggleLayersMenu,
                            active: controller.showLayersMenu.value,
                          ),
                        ),
                        const Spacer(),
                        Obx(
                          () => _MapChromeLabel(
                            isDark: isDark,
                            routing: controller.routing.value,
                            accepted: controller.accepted.value,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Obx(() {
                if (!controller.showLayersMenu.value) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  top: MediaQuery.paddingOf(context).top + scale.s(64),
                  left: scale.s(12),
                  child: _MapLayersMenu(
                    isDark: isDark,
                    selected: controller.mapType.value,
                    trafficEnabled: controller.trafficEnabled.value,
                    onSelected: controller.setMapType,
                    onTrafficChanged: controller.setTrafficEnabled,
                    onClose: controller.closeLayersMenu,
                    labelFor: controller.labelForMapType,
                    iconFor: controller.iconForMapType,
                  ),
                );
              }),
              Obx(() {
                final error = controller.errorMessage.value;
                if (error == null || controller.showLayersMenu.value) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  left: scale.s(12),
                  right: scale.s(12),
                  top: MediaQuery.paddingOf(context).top + scale.s(72),
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(scale.s(12)),
                    child: Padding(
                      padding: EdgeInsets.all(scale.s(12)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              error,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: scale.sp(13),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => unawaited(controller.loadRoutes()),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              Obx(() {
                final options = controller.routes.toList(growable: false);
                final showLayers = controller.showLayersMenu.value;
                final showActions = controller.showResponseActions.value;
                final showNavCta =
                    controller.accepted.value && !showActions;
                final showRoutes = options.isNotEmpty && !showLayers;
                if (!showRoutes && !showActions && !showNavCta) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        scale.s(12),
                        0,
                        scale.s(12),
                        scale.s(8),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showRoutes) ...[
                            if (controller.routing.value)
                              Padding(
                                padding: EdgeInsets.only(bottom: scale.s(8)),
                                child: Text(
                                  'Finding alternate routes…',
                                  style: TextStyle(
                                    color: isDark
                                        ? const Color(0xFFB7C7D8)
                                        : const Color(0xFF52647D),
                                    fontWeight: FontWeight.w700,
                                    fontSize: scale.sp(12),
                                  ),
                                ),
                              ),
                            SizedBox(
                              height: scale.s(74),
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: options.length,
                                separatorBuilder: (_, __) =>
                                    SizedBox(width: scale.s(8)),
                                itemBuilder: (context, index) {
                                  final option = options[index];
                                  final selected = controller
                                          .selectedRouteIndex.value ==
                                      index;
                                  final title = options.length == 1
                                      ? 'Best route'
                                      : (index == 0
                                          ? 'Fastest'
                                          : 'Route ${index + 1}');
                                  final eta =
                                      '${option.arrivalMinutes} min · ${option.distanceMiles.toStringAsFixed(1)} mi';
                                  return _RouteOptionChip(
                                    isDark: isDark,
                                    selected: selected,
                                    title: title,
                                    subtitle: option.summary.isEmpty
                                        ? eta
                                        : '${option.summary} · $eta',
                                    onTap: () =>
                                        controller.selectRoute(index),
                                  );
                                },
                              ),
                            ),
                            SizedBox(height: scale.s(10)),
                          ],
                          if (showActions)
                            secondsListenable == null
                                ? DispatchResponsePanel(
                                    elevated: true,
                                    secondsLeft:
                                        controller.responseTotalSeconds,
                                    totalSeconds:
                                        controller.responseTotalSeconds,
                                    onAccept: controller.onAccept == null
                                        ? null
                                        : () => controller
                                            .handleAccept(context),
                                    onDecline: controller.onDecline == null
                                        ? null
                                        : () => controller
                                            .handleDecline(context),
                                  )
                                : ValueListenableBuilder<int>(
                                    valueListenable: secondsListenable,
                                    builder: (context, secondsLeft, _) {
                                      final enabled = secondsLeft > 0 ||
                                          !DispatchRequestConfig
                                              .openExpiredOnTimerEnd;
                                      return DispatchResponsePanel(
                                        elevated: true,
                                        secondsLeft: secondsLeft,
                                        totalSeconds: controller
                                            .responseTotalSeconds,
                                        onAccept: enabled &&
                                                controller.onAccept != null
                                            ? () => controller
                                                .handleAccept(context)
                                            : null,
                                        onDecline: enabled &&
                                                controller.onDecline != null
                                            ? () => controller
                                                .handleDecline(context)
                                            : null,
                                      );
                                    },
                                  )
                          else if (showNavCta)
                            FilledButton.icon(
                              onPressed: () => unawaited(
                                controller.openGoogleNavigation(context),
                              ),
                              icon: const Icon(Icons.navigation_rounded),
                              label: const Text('Start Google Navigation'),
                              style: FilledButton.styleFrom(
                                minimumSize: Size.fromHeight(scale.s(52)),
                                backgroundColor: const Color(0xFF1A73E8),
                                foregroundColor: Colors.white,
                                textStyle: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: scale.sp(15),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteOptionChip extends StatelessWidget {
  const _RouteOptionChip({
    required this.isDark,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool isDark;
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    final bg = selected
        ? (isDark ? const Color(0xFF1A4A6E) : const Color(0xFFDDEBFF))
        : (isDark ? const Color(0xE0122D43) : Colors.white.withValues(alpha: .94));
    final fg = isDark ? Colors.white : const Color(0xFF10234E);
    final chipHeight = scale.s(74);
    return Material(
      color: bg,
      elevation: selected ? 3 : 1,
      borderRadius: BorderRadius.circular(scale.s(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(scale.s(14)),
        child: Container(
          width: scale.s(168),
          height: chipHeight,
          padding: EdgeInsets.symmetric(
            horizontal: scale.s(12),
            vertical: scale.s(8),
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(scale.s(14)),
            border: Border.all(
              color: selected
                  ? const Color(0xFF3569F6)
                  : Colors.transparent,
              width: scale.s(1.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: scale.sp(13),
                  height: 1.15,
                ),
              ),
              SizedBox(height: scale.s(2)),
              Flexible(
                child: Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFFB7C7D8)
                        : const Color(0xFF52647D),
                    fontWeight: FontWeight.w600,
                    fontSize: scale.sp(11),
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapChromeLabel extends StatelessWidget {
  const _MapChromeLabel({
    required this.isDark,
    required this.routing,
    this.accepted = false,
  });

  final bool isDark;
  final bool routing;
  final bool accepted;

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    final blue = isDark ? const Color(0xFF8CCBFF) : const Color(0xFF3569F6);
    final label = routing
        ? 'Loading route…'
        : (accepted ? 'Navigating to site' : 'Route to site');
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: scale.s(12),
        vertical: scale.s(10),
      ),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xE0122D43)
            : Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(scale.s(14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .12),
            blurRadius: scale.s(10),
            offset: Offset(0, scale.s(3)),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (routing)
            SizedBox(
              width: scale.s(18),
              height: scale.s(18),
              child: CircularProgressIndicator(
                strokeWidth: scale.s(2),
                color: blue,
              ),
            )
          else
            Container(
              width: scale.s(22),
              height: scale.s(22),
              padding: EdgeInsets.all(scale.s(3.5)),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1A3A55)
                    : const Color(0xFFDDEBFF),
                borderRadius: BorderRadius.circular(scale.s(7)),
              ),
              child: SvgPicture.asset(
                'assets/images/dispatch_navigation.svg',
                colorFilter: isDark
                    ? const ColorFilter.mode(Color(0xFF8CCBFF), BlendMode.srcIn)
                    : null,
              ),
            ),
          SizedBox(width: scale.s(8)),
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF10234E),
              fontWeight: FontWeight.w800,
              fontSize: scale.sp(13.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapChromeButton extends StatelessWidget {
  const _MapChromeButton({
    required this.icon,
    required this.tooltip,
    required this.isDark,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final bool isDark;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    final color = active
        ? (isDark ? const Color(0xFF1A4A6E) : const Color(0xFFDDEBFF))
        : (isDark
            ? const Color(0xE0122D43)
            : Colors.white.withValues(alpha: .94));
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: scale.s(42),
            height: scale.s(42),
            child: Center(
              child: MapControlIcon(
                icon: icon,
                size: scale.s(22),
                color: isDark ? Colors.white : const Color(0xFF10234E),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapLayersMenu extends StatelessWidget {
  const _MapLayersMenu({
    required this.isDark,
    required this.selected,
    required this.trafficEnabled,
    required this.onSelected,
    required this.onTrafficChanged,
    required this.onClose,
    required this.labelFor,
    required this.iconFor,
  });

  final bool isDark;
  final MapType selected;
  final bool trafficEnabled;
  final ValueChanged<MapType> onSelected;
  final ValueChanged<bool> onTrafficChanged;
  final VoidCallback onClose;
  final String Function(MapType) labelFor;
  final IconData Function(MapType) iconFor;

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
        constraints: BoxConstraints(maxWidth: scale.s(220)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            scale.s(10),
            scale.s(8),
            scale.s(8),
            scale.s(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Map type',
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
              for (final type in DispatchFullscreenMapController.layerOptions)
                Padding(
                  padding: EdgeInsets.only(top: scale.s(4)),
                  child: Material(
                    color: type == selected
                        ? (isDark
                            ? const Color(0xFF1A4A6E)
                            : const Color(0xFFDDEBFF))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(scale.s(12)),
                    child: InkWell(
                      onTap: () => onSelected(type),
                      borderRadius: BorderRadius.circular(scale.s(12)),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: scale.s(10),
                          vertical: scale.s(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              iconFor(type),
                              size: scale.s(20),
                              color: fg,
                            ),
                            SizedBox(width: scale.s(10)),
                            Expanded(
                              child: Text(
                                labelFor(type),
                                style: TextStyle(
                                  color: fg,
                                  fontWeight: FontWeight.w700,
                                  fontSize: scale.sp(13),
                                ),
                              ),
                            ),
                            if (type == selected)
                              Icon(
                                Icons.check_rounded,
                                size: scale.s(18),
                                color: const Color(0xFF3569F6),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.only(top: scale.s(8)),
                child: Divider(
                  height: scale.s(1),
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.symmetric(horizontal: scale.s(4)),
                dense: true,
                value: trafficEnabled,
                onChanged: onTrafficChanged,
                secondary: Icon(
                  Icons.traffic_rounded,
                  size: scale.s(20),
                  color: fg,
                ),
                title: Text(
                  'Traffic',
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: scale.sp(13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}