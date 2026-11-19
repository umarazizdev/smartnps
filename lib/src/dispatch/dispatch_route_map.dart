import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'dispatch_route_map_controller.dart';
import 'dispatch_scale.dart';
import 'live_map_marker_style.dart';
import 'map_control_icon.dart';

import 'dispatch_route_metrics.dart';

export 'dispatch_route_metrics.dart';

class DispatchRouteMap extends StatefulWidget {
  const DispatchRouteMap({
    super.key,
    required this.site,
    required this.isDark,
    this.siteName,
    this.siteSubtitle,
    this.onMetrics,
    this.onRoutingChanged,
    this.height,
    this.interactive = false,
    this.showExpandButton = true,
    this.initialOrigin,
    this.initialRoutePoints = const [],
    this.onAccept,
    this.onDecline,
    this.onRouteSnapshot,
    this.responseSecondsLeft,
    this.responseTotalSeconds = 30,
    this.reserveResponsePanel,
  });

  final LatLng site;
  final bool isDark;
  final String? siteName;
  final String? siteSubtitle;
  final ValueChanged<DispatchRouteMetrics>? onMetrics;
  final ValueChanged<bool>? onRoutingChanged;
  final double? height;
  final bool interactive;
  final bool showExpandButton;
  final LatLng? initialOrigin;
  final List<LatLng> initialRoutePoints;
  final Future<void> Function()? onAccept;
  final Future<void> Function()? onDecline;
  final void Function(LatLng? origin, List<LatLng> points)? onRouteSnapshot;
  final ValueListenable<int>? responseSecondsLeft;
  final int responseTotalSeconds;
  final bool? reserveResponsePanel;

  @override
  State<DispatchRouteMap> createState() => _DispatchRouteMapState();
}

class _DispatchRouteMapState extends State<DispatchRouteMap>
    with TickerProviderStateMixin {
  late final String _tag;
  late final DispatchRouteMapController _c;
  late final AnimationController _markerMoveController;
  late final AnimationController _markerRotateController;

  @override
  void initState() {
    super.initState();
    _tag = DispatchRouteMapController.tagForInstance(
      interactive: widget.interactive,
      instanceId: identityHashCode(this),
    );
    _c = Get.put(
      DispatchRouteMapController(
        site: widget.site,
        isDark: widget.isDark,
        siteName: widget.siteName,
        siteSubtitle: widget.siteSubtitle,
        onMetrics: widget.onMetrics,
        onRoutingChanged: widget.onRoutingChanged,
        interactive: widget.interactive,
        showExpandButton: widget.showExpandButton,
        initialOrigin: widget.initialOrigin,
        initialRoutePoints: widget.initialRoutePoints,
        onAccept: widget.onAccept,
        onDecline: widget.onDecline,
        onRouteSnapshot: widget.onRouteSnapshot,
        responseSecondsLeft: widget.responseSecondsLeft,
        responseTotalSeconds: widget.responseTotalSeconds,
      ),
      tag: _tag,
    );
    _markerMoveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(_c.onMarkerMoveTick);
    _markerRotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addListener(_c.onMarkerRotateTick);
    _c.bindAnimationControllers(
      markerMove: _markerMoveController,
      markerRotate: _markerRotateController,
    );
  }

  @override
  void didUpdateWidget(covariant DispatchRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _c.onWidgetUpdated(
      oldSite: oldWidget.site,
      oldIsDark: oldWidget.isDark,
      site: widget.site,
      isDark: widget.isDark,
      siteName: widget.siteName,
      siteSubtitle: widget.siteSubtitle,
      onMetrics: widget.onMetrics,
      onRoutingChanged: widget.onRoutingChanged,
      onAccept: widget.onAccept,
      onDecline: widget.onDecline,
      onRouteSnapshot: widget.onRouteSnapshot,
      responseSecondsLeft: widget.responseSecondsLeft,
      responseTotalSeconds: widget.responseTotalSeconds,
      reserveResponsePanel: widget.reserveResponsePanel,
    );
  }

  @override
  void dispose() {
    _markerMoveController
      ..removeListener(_c.onMarkerMoveTick)
      ..dispose();
    _markerRotateController
      ..removeListener(_c.onMarkerRotateTick)
      ..dispose();
    Get.delete<DispatchRouteMapController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _c.bind(context, isMounted: () => mounted);
    return GetBuilder<DispatchRouteMapController>(
      id: 'map',
      tag: _tag,
      builder: (c) {
    final scale = DispatchScale.of(context);
    final topInset = widget.interactive
        ? MediaQuery.paddingOf(context).top + scale.s(58)
        : scale.s(10);
    final mapStack = Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
              child: c.mapVisible
              ? GoogleMap(
                      key: c.mapViewKey,
                  initialCameraPosition: CameraPosition(
                        target: c.origin ?? widget.site,
                    zoom: 13,
                  ),
                      markers: c.markers,
                      polylines: c.polylines,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: widget.interactive,
                  rotateGesturesEnabled: widget.interactive,
                  scrollGesturesEnabled: true,
                  tiltGesturesEnabled: widget.interactive,
                  zoomGesturesEnabled: true,
                  liteModeEnabled: false,
                  gestureRecognizers:
                      <Factory<OneSequenceGestureRecognizer>>{
                        Factory<EagerGestureRecognizer>(
                          EagerGestureRecognizer.new,
                        ),
                        Factory<ScaleGestureRecognizer>(
                          ScaleGestureRecognizer.new,
                        ),
                      },
                  mapType: MapType.normal,
                  style: widget.isDark ? _darkMapStyle : null,
                  padding: widget.interactive
                      ? EdgeInsets.only(
                          top: topInset,
                          right: scale.s(64),
                              bottom: c.controlsBottomInset(scale),
                        )
                      : EdgeInsets.zero,
                      onTap: (_) => c.closeMarkerPicker(),
                      onMapCreated: c.handleMapCreated,
                )
              : ColoredBox(
                  color: widget.isDark
                      ? const Color(0xFF0B2436)
                      : const Color(0xFFE8EEF5),
                ),
        ),
            if (widget.interactive && c.showMarkerPicker)
          Positioned(
            top: MediaQuery.paddingOf(context).top + scale.s(56),
            left: scale.s(12),
            right: scale.s(76),
            child: _MarkerStylePicker(
              isDark: widget.isDark,
                  selected: c.selectedMarkerStyle,
                  onSelected: (style) => unawaited(c.selectMarkerStyle(style)),
                  onClose: c.closeMarkerPicker,
            ),
          ),
        if (!widget.interactive)
          Positioned(
            top: scale.s(10),
            right: scale.s(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.showExpandButton)
                  _MapFab(
                    isDark: widget.isDark,
                    icon: Icons.fullscreen_rounded,
                    tooltip: 'Open full map',
                    size: scale.s(40),
                        onTap: () => unawaited(c.openFullscreen()),
                  ),
                if (widget.showExpandButton) SizedBox(height: scale.s(8)),
                _MapFab(
                  isDark: widget.isDark,
                  icon: Icons.zoom_out_map_rounded,
                  tooltip: 'Fit site and my location',
                  size: scale.s(40),
                      onTap: () => unawaited(c.fitToRoute()),
                ),
              ],
            ),
          ),
        if (widget.interactive)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
            right: scale.s(12),
                bottom: c.controlsBottomInset(scale),
            child: _FullscreenMapControls(
              isDark: widget.isDark,
                  busy: c.routing,
                  selectedMarkerStyle: c.selectedMarkerStyle,
                  onZoomIn: () => unawaited(c.zoomBy(1)),
                  onZoomOut: () => unawaited(c.zoomBy(-1)),
                  onMyLocation: () => unawaited(c.manualRefreshLocation()),
                  onReroute: () => unawaited(c.manualReroute()),
                  onFitRoute: () => unawaited(c.fitToRoute()),
                  onChangePin: c.openMarkerPicker,
                ),
              ),
            if (c.routing && !widget.interactive)
          Positioned(
            left: scale.s(12),
            right: scale.s(12),
            bottom: scale.s(10),
            child: _RoutingChip(isDark: widget.isDark),
          ),
            if (c.error != null && !c.routing)
          Positioned(
            left: scale.s(12),
            right: widget.interactive ? scale.s(72) : scale.s(12),
            top: widget.interactive
                ? MediaQuery.paddingOf(context).top + scale.s(64)
                : null,
            bottom: widget.interactive ? null : scale.s(10),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: scale.s(10),
                vertical: scale.s(7),
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(scale.s(10)),
              ),
              child: Text(
                    c.error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: scale.sp(12),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );

    if (widget.interactive) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final height = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height;
          return SizedBox(width: width, height: height, child: mapStack);
        },
      );
    }

    return SizedBox(
      height: widget.height ?? scale.mapHeight,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(scale.cardRadius),
        child: mapStack,
      ),
        );
      },
    );
  }
}

class _MarkerStylePicker extends StatelessWidget {
  const _MarkerStylePicker({
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
    final styles = LiveMapMarkerStyle.values;
    return Material(
      color: bg.withValues(alpha: .96),
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(scale.s(16)),
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
                    'Choose your marker',
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w800,
                      fontSize: scale.sp(13),
                    ),
                  ),
                ),
                InkWell(
                  onTap: onClose,
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: EdgeInsets.all(scale.s(4)),
                    child: Icon(
                      Icons.close_rounded,
                      size: scale.s(18),
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: scale.s(8)),
            LayoutBuilder(
              builder: (context, constraints) {
                const columns = 4;
                final gap = scale.s(8);
                final tileWidth =
                    (constraints.maxWidth - (gap * (columns - 1))) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final style in styles)
                      SizedBox(
                        width: tileWidth,
                        child: _MarkerStyleTile(
                          style: style,
                          isDark: isDark,
                          selected: style == selected,
                          foreground: fg,
                          onTap: () => onSelected(style),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkerStyleTile extends StatelessWidget {
  const _MarkerStyleTile({
    required this.style,
    required this.isDark,
    required this.selected,
    required this.foreground,
    required this.onTap,
  });

  final LiveMapMarkerStyle style;
  final bool isDark;
  final bool selected;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(scale.s(12)),
      child: Container(
        height: scale.s(72),
        padding: EdgeInsets.all(scale.s(6)),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? const Color(0xFF1A4A6E) : const Color(0xFFDDEBFF))
              : (isDark ? const Color(0xFF16344A) : const Color(0xFFF3F6FB)),
          borderRadius: BorderRadius.circular(scale.s(12)),
          border: Border.all(
            color: selected ? const Color(0xFF3569F6) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: SvgPicture.asset(style.assetPath, fit: BoxFit.contain),
            ),
            SizedBox(height: scale.s(4)),
            Text(
              style.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: foreground,
                fontSize: scale.sp(9),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullscreenMapControls extends StatelessWidget {
  const _FullscreenMapControls({
    required this.isDark,
    required this.busy,
    required this.selectedMarkerStyle,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onMyLocation,
    required this.onReroute,
    required this.onFitRoute,
    required this.onChangePin,
  });

  final bool isDark;
  final bool busy;
  final LiveMapMarkerStyle selectedMarkerStyle;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onMyLocation;
  final VoidCallback onReroute;
  final VoidCallback onFitRoute;
  final VoidCallback onChangePin;

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MapFab(
          isDark: isDark,
          icon: Icons.add_rounded,
          tooltip: 'Zoom in',
          onTap: onZoomIn,
        ),
        SizedBox(height: scale.s(8)),
        _MapFab(
          isDark: isDark,
          icon: Icons.remove_rounded,
          tooltip: 'Zoom out',
          onTap: onZoomOut,
        ),
        SizedBox(height: scale.s(8)),
        _MapFab(
          isDark: isDark,
          icon: Icons.zoom_out_map_rounded,
          tooltip: 'Fit route',
          onTap: onFitRoute,
        ),
        SizedBox(height: scale.s(14)),
        _MapFab(
          isDark: isDark,
          icon: Icons.pin_drop_rounded,
          assetPath: selectedMarkerStyle.assetPath,
          tooltip: 'Change pin',
          onTap: onChangePin,
        ),
        SizedBox(height: scale.s(8)),
        _MapFab(
          isDark: isDark,
          icon: Icons.my_location_rounded,
          tooltip: 'Refresh my location',
          onTap: busy ? null : onMyLocation,
        ),
        SizedBox(height: scale.s(8)),
        _MapFab(
          isDark: isDark,
          icon: Icons.alt_route_rounded,
          tooltip: 'Re-route',
          onTap: busy ? null : onReroute,
        ),
      ],
    );
  }
}

class _MapFab extends StatelessWidget {
  const _MapFab({
    required this.isDark,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size,
    this.assetPath,
  });

  final bool isDark;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double? size;
  final String? assetPath;

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    final enabled = onTap != null;
    final side = size ?? scale.s(46);
    final asset = assetPath;
    return Material(
      color: isDark
          ? Color(enabled ? 0xE0122D43 : 0x99122D43)
          : Colors.white.withValues(alpha: enabled ? .94 : .55),
      shape: const CircleBorder(),
      elevation: enabled ? 4 : 0,
      shadowColor: const Color(0xFF213959).withValues(alpha: .20),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: side,
            height: side,
            child: Center(
              child: asset == null
                  ? MapControlIcon(
                icon: icon,
                size: side * 0.48,
                color: isDark
                    ? (enabled ? Colors.white : Colors.white54)
                    : (enabled
                          ? const Color(0xFF10234E)
                                : const Color(0xFF10234E)
                                    .withValues(alpha: .35)),
                    )
                  : Opacity(
                      opacity: enabled ? 1 : 0.45,
                      child: SizedBox(
                        width: side * 0.72,
                        height: side * 0.72,
                        child: SvgPicture.asset(
                          asset,
                          fit: BoxFit.contain,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoutingChip extends StatelessWidget {
  const _RoutingChip({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    final blue = isDark ? const Color(0xFF8CCBFF) : const Color(0xFF3569F6);
    return Material(
      color: isDark
          ? const Color(0xE0122D43)
          : Colors.white.withValues(alpha: .94),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: .18),
      borderRadius: BorderRadius.circular(scale.s(12)),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: scale.s(12),
          vertical: scale.s(10),
        ),
        child: Row(
          children: [
            SizedBox(
              width: scale.s(16),
              height: scale.s(16),
              child: CircularProgressIndicator(
                strokeWidth: scale.s(2),
                color: blue,
              ),
            ),
            SizedBox(width: scale.s(10)),
            Expanded(
              child: Text(
                'Finding the best driving route…',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF10234E),
                  fontSize: scale.sp(12.5),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const String _darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#1d2c4d"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8ec3b9"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1a3646"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#304a7d"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1626"}]}
]
''';
