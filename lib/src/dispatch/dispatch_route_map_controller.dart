import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../location/duty_live_location_hub.dart';
import 'dispatch_fullscreen_map_screen.dart';
import 'dispatch_live_marker_style_store.dart';
import 'dispatch_route_metrics.dart';
import 'dispatch_scale.dart';
import 'google_maps_config.dart';
import 'live_map_marker_bitmap.dart';
import 'live_map_marker_style.dart';

class DispatchRouteMapController extends GetxController {
  DispatchRouteMapController({
    required LatLng site,
    required bool isDark,
    String? siteName,
    String? siteSubtitle,
    ValueChanged<DispatchRouteMetrics>? onMetrics,
    ValueChanged<bool>? onRoutingChanged,
    required bool interactive,
    bool showExpandButton = true,
    LatLng? initialOrigin,
    List<LatLng> initialRoutePoints = const [],
    Future<void> Function()? onAccept,
    Future<void> Function()? onDecline,
    void Function(LatLng? origin, List<LatLng> points)? onRouteSnapshot,
    ValueListenable<int>? responseSecondsLeft,
    int responseTotalSeconds = 30,
  })  : _site = site,
        _isDark = isDark,
        _siteName = siteName,
        _siteSubtitle = siteSubtitle,
        onMetrics = onMetrics,
        onRoutingChanged = onRoutingChanged,
        interactive = interactive,
        showExpandButton = showExpandButton,
        initialOrigin = initialOrigin,
        initialRoutePoints = initialRoutePoints,
        onAccept = onAccept,
        onDecline = onDecline,
        onRouteSnapshot = onRouteSnapshot,
        responseSecondsLeft = responseSecondsLeft,
        responseTotalSeconds = responseTotalSeconds,
        reserveResponsePanel = onAccept != null || onDecline != null;

  LatLng _site;
  bool _isDark;
  String? _siteName;
  String? _siteSubtitle;
  ValueChanged<DispatchRouteMetrics>? onMetrics;
  ValueChanged<bool>? onRoutingChanged;
  final bool interactive;
  final bool showExpandButton;
  final LatLng? initialOrigin;
  final List<LatLng> initialRoutePoints;
  Future<void> Function()? onAccept;
  Future<void> Function()? onDecline;
  void Function(LatLng? origin, List<LatLng> points)? onRouteSnapshot;
  ValueListenable<int>? responseSecondsLeft;
  int responseTotalSeconds;
  bool reserveResponsePanel;

  bool Function() _isMounted = () => false;
  BuildContext? _context;

  void bind(BuildContext context, {required bool Function() isMounted}) {
    _context = context;
    _isMounted = isMounted;
  }

  BuildContext get context {
    final ctx = _context;
    if (ctx == null) throw StateError('context not bound');
    return ctx;
  }

  void bindAnimationControllers({
    required AnimationController markerMove,
    required AnimationController markerRotate,
  }) {
    _markerMoveController = markerMove;
    _markerRotateController = markerRotate;
  }

  void _patch(VoidCallback fn) {
    fn();
    _notifyMap();
  }

  void _notifyMap() {
    if (!isClosed) update(['map']);
  }

  static String tagForInstance({required bool interactive, required int instanceId}) {
    return 'dispatch_route_map_${interactive ? 'interactive' : 'preview'}_$instanceId';
  }

  Key mapViewKey = UniqueKey();
  GoogleMapController? mapController;
  LatLng? get origin => _origin;
  LatLng? _origin;
  List<LatLng> get routePoints => _routePoints;
  List<LatLng> _routePoints = const [];
  Set<Marker> get markers => _markers;
  Set<Marker> _markers = {};
  Set<Polyline> get polylines => _polylines;
  Set<Polyline> _polylines = {};
  String? get error => _error;
  String? _error;
  bool get routing => _routing;
  bool _routing = true;
  bool get mapVisible => _mapVisible;
  bool _mapVisible = false;
  bool get showMarkerPicker => _showMarkerPicker;
  bool _showMarkerPicker = false;
  LiveMapMarkerStyle get selectedMarkerStyle => _selectedMarkerStyle;
  LiveMapMarkerStyle _selectedMarkerStyle =
      DispatchLiveMarkerStyleStore.current;
  bool _fitted = false;
  bool _openingFullscreen = false;
  int _loadGeneration = 0;
  BitmapDescriptor? _youAreHereIcon;
  BitmapDescriptor? _gapDotIcon;
  Timer? _locationPulseTimer;
  AnimationController? _markerMoveController;
  AnimationController? _markerRotateController;
  LatLng? _markerAnimFrom;
  LatLng? _markerAnimTo;
  List<LatLng> _markerAnimPath = const [];
  double _markerBearing = 0;
  double _markerBearingFrom = 0;
  double _markerBearingTo = 0;
  static final Map<String, BitmapDescriptor> _youAreHereCache = {};
  static final Map<String, List<BitmapDescriptor>> _pulseFrames = {};
  static final Map<String, BitmapDescriptor> _gapDotCache = {};
  static const double _liveMoveMeters = 3;

  void applyWidgetConfig({
    required LatLng site,
    required bool isDark,
    String? siteName,
    String? siteSubtitle,
    ValueChanged<DispatchRouteMetrics>? onMetrics,
    ValueChanged<bool>? onRoutingChanged,
    Future<void> Function()? onAccept,
    Future<void> Function()? onDecline,
    void Function(LatLng? origin, List<LatLng> points)? onRouteSnapshot,
    ValueListenable<int>? responseSecondsLeft,
    int? responseTotalSeconds,
    bool? reserveResponsePanel,
  }) {
    _site = site;
    _isDark = isDark;
    _siteName = siteName;
    _siteSubtitle = siteSubtitle;
    this.onMetrics = onMetrics;
    this.onRoutingChanged = onRoutingChanged;
    this.onAccept = onAccept;
    this.onDecline = onDecline;
    this.onRouteSnapshot = onRouteSnapshot;
    this.responseSecondsLeft = responseSecondsLeft;
    if (responseTotalSeconds != null) {
      this.responseTotalSeconds = responseTotalSeconds;
    }
    final nextReserve = reserveResponsePanel ??
        (onAccept != null || onDecline != null);
    if (this.reserveResponsePanel != nextReserve) {
      this.reserveResponsePanel = nextReserve;
      _notifyMap();
    } else {
      this.reserveResponsePanel = nextReserve;
    }
  }

  void onWidgetUpdated({
    required LatLng oldSite,
    required bool oldIsDark,
    required LatLng site,
    required bool isDark,
    String? siteName,
    String? siteSubtitle,
    ValueChanged<DispatchRouteMetrics>? onMetrics,
    ValueChanged<bool>? onRoutingChanged,
    Future<void> Function()? onAccept,
    Future<void> Function()? onDecline,
    void Function(LatLng? origin, List<LatLng> points)? onRouteSnapshot,
    ValueListenable<int>? responseSecondsLeft,
    int responseTotalSeconds = 30,
    bool? reserveResponsePanel,
  }) {
    applyWidgetConfig(
      site: site,
      isDark: isDark,
      siteName: siteName,
      siteSubtitle: siteSubtitle,
      onMetrics: onMetrics,
      onRoutingChanged: onRoutingChanged,
      onAccept: onAccept,
      onDecline: onDecline,
      onRouteSnapshot: onRouteSnapshot,
      responseSecondsLeft: responseSecondsLeft,
      responseTotalSeconds: responseTotalSeconds,
      reserveResponsePanel: reserveResponsePanel,
    );
    if (oldSite != site || oldIsDark != isDark) {
      _fitted = false;
      _markers = _buildMarkers(_origin);
      unawaited(_bootstrap());
    }
  }

  @override
  void onInit() {
    super.onInit();
    _mapVisible = interactive;
    _markers = {_siteMarker()};
    final seedOrigin = initialOrigin;
    final seedRoute = initialRoutePoints;
    if (seedOrigin != null) {
      _origin = seedOrigin;
      if (_isDrivingRoute(seedRoute)) {
        _routePoints = seedRoute;
        _trimPassedRoute(seedOrigin);
        _routing = false;
      } else if (!interactive) {
        _polylines = {_previewPolyline(seedOrigin)};
      }
      _syncMarkerHeading(seedOrigin);
      _markers = _buildMarkers(seedOrigin, routePoints: _routePoints);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isMounted()) return;
        _emitRouteSnapshot();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_isMounted()) return;
      await DispatchLiveMarkerStyleStore.ensureLoaded();
      if (!_isMounted()) return;
      if (_selectedMarkerStyle != DispatchLiveMarkerStyleStore.current) {
        _selectedMarkerStyle = DispatchLiveMarkerStyleStore.current;
        _notifyMap();
      }
      onRoutingChanged?.call(_routing);
      final logicalSize = _markerLogicalSize();
      final dpr = _markerDevicePixelRatio();
      unawaited(
        LiveMapMarkerBitmap.prefetchAll(
          logicalSize: logicalSize,
          devicePixelRatio: dpr,
        ),
      );
      unawaited(
        _ensureYouAreHereIcon().then((_) {
          if (!_isMounted() || _origin == null) return;
          _patch(() {
            _markers = _buildMarkers(_origin, routePoints: _routePoints);
          });
        }),
      );
      if (!interactive) {
        await Future<void>.delayed(const Duration(milliseconds: 160));
        if (!_isMounted() || _openingFullscreen) return;
        _patch(() {
          mapViewKey = UniqueKey();
          _mapVisible = true;
        });
      }
    });
    DispatchLiveMarkerStyleStore.listenable.addListener(_onStoredMarkerStyle);
    _startDutyLiveLocation();
    unawaited(_bootstrap());
  }

  void _onStoredMarkerStyle() {
    final style = DispatchLiveMarkerStyleStore.current;
    if (isClosed || _selectedMarkerStyle == style) return;
    _selectedMarkerStyle = style;
    if (!style.rotatesWithBearing) {
      _markerBearing = 0;
    } else if (_origin != null) {
      _syncMarkerHeading(_origin!);
    }
    _notifyMap();
    unawaited(_loadSelectedMarkerIcon());
  }

  @override
  void onClose() {
    DispatchLiveMarkerStyleStore.listenable.removeListener(_onStoredMarkerStyle);
    _stopDutyLiveLocation();
    _stopLocationPulse();
    mapController = null;
    super.onClose();
  }

  String get _iconCacheKey =>
      '${_isDark}-${interactive ? 'full' : 'preview'}';

  Color get _routeColor =>
      _isDark ? const Color(0xFF56B7FF) : const Color(0xFF087CF4);

    double _markerLogicalSize() {
    if (!_isMounted()) return LiveMapMarkerStyle.baseLogicalSize;
    return DispatchScale.of(context).markerSize;
  }

  double _markerDevicePixelRatio() {
    if (!_isMounted()) return 2;
    return MediaQuery.devicePixelRatioOf(context).clamp(1.0, 4.0);
  }

  void _startDutyLiveLocation() {
    DutyLiveLocationHub.seedFromDutyIfAvailable();
    DutyLiveLocationHub.latest.addListener(_onDutyLiveLocation);
  }

  void _stopDutyLiveLocation() {
    DutyLiveLocationHub.latest.removeListener(_onDutyLiveLocation);
  }

  void _onDutyLiveLocation() {
    if (!_isMounted() || _routing || _showMarkerPicker) return;
    final fix = DutyLiveLocationHub.current;
    if (fix == null || !fix.isFresh()) return;
    final next = LatLng(fix.latitude, fix.longitude);
    final current = _markerAnimTo ?? _origin;
    if (current != null &&
        Geolocator.distanceBetween(
              current.latitude,
              current.longitude,
              next.latitude,
              next.longitude,
            ) <
            _liveMoveMeters) {
      return;
    }
    _animateMarkerTo(next);
  }

  void _pauseMarkerMotion() {
    if (_markerMoveController!.isAnimating) {
      _markerMoveController!.stop();
      _markerAnimFrom = null;
      _markerAnimTo = null;
      _markerAnimPath = const [];
    }
    if (_markerRotateController!.isAnimating) {
      _markerRotateController!.stop();
    }
  }

  void _animateMarkerTo(LatLng next) {
    if (_showMarkerPicker) return;
    final from = _origin ?? next;
    final path = _animationPath(from, next);
    final meters = _pathLengthMeters(path).clamp(1.0, 5000.0);
    _markerAnimFrom = from;
    _markerAnimTo = next;
    _markerAnimPath = path;
    final ms = (800 + (meters * 20)).round().clamp(800, 1200);
    _markerMoveController!
      ..stop()
      ..duration = Duration(milliseconds: ms)
      ..forward(from: 0);

    final travelBearing = Geolocator.bearingBetween(
      from.latitude,
      from.longitude,
      next.latitude,
      next.longitude,
    );
    final pathBearing = _bearingAtPathProgress(path, 0.02);
    final routeBearing = pathBearing ??
        _routeBearingNear(from) ??
        _routeBearingNear(next);
    _animateMarkerBearingTo(routeBearing ?? travelBearing);
  }

  void _animateMarkerBearingTo(double targetDegrees) {
    if (!_selectedMarkerStyle.rotatesWithBearing) {
      _markerBearing = 0;
      _markerBearingFrom = 0;
      _markerBearingTo = 0;
      return;
    }
    _markerBearingFrom = _markerBearing;
    _markerBearingTo = targetDegrees;
    _markerRotateController!
      ..stop()
      ..duration = const Duration(milliseconds: 400)
      ..forward(from: 0);
  }

  void onMarkerMoveTick() {
    final from = _markerAnimFrom;
    final to = _markerAnimTo;
    if (!_isMounted() || from == null || to == null) return;
    final t = Curves.easeInOut.transform(
      _markerMoveController!.value.clamp(0.0, 1.0),
    );
    final path = _markerAnimPath.isEmpty ? <LatLng>[from, to] : _markerAnimPath;
    final mid = _pointAlongPath(path, t);
    _origin = mid;
    if (_selectedMarkerStyle.rotatesWithBearing &&
        _markerRotateController!.status != AnimationStatus.forward) {
      final bearing = _bearingAtPathProgress(path, math.min(1.0, t + 0.02));
      if (bearing != null) {
        final delta = ((bearing - _markerBearing + 540) % 360) - 180;
        if (delta.abs() > 8) {
          _animateMarkerBearingTo(bearing);
        } else {
          _markerBearing = bearing;
        }
      }
    }
    final completed = _markerMoveController!.status == AnimationStatus.completed;
    final tip = completed ? to : mid;
    _origin = tip;
    _trimPassedRoute(tip, emitMetrics: completed);
    _markers = _buildMarkers(tip);
    if (completed) {
      _markerAnimFrom = null;
      _markerAnimTo = null;
      _markerAnimPath = const [];
      _emitRouteSnapshot();
    }
    _notifyMap();
  }

  List<LatLng> _animationPath(LatLng from, LatLng to) {
    final route = _routePoints;
    if (!_isDrivingRoute(route)) return [from, to];
    final start = _nearestOnPath(from, route);
    final end = _nearestOnPath(to, route);
    if (_metersBetween(start, from) > 60 || _metersBetween(end, to) > 60) {
      return [from, to];
    }
    final startIndex = _nearestVertexIndex(start, route);
    final endIndex = _nearestVertexIndex(end, route);
    if (startIndex < 0 || endIndex < 0) return [from, to];
    final vertices = <LatLng>[start];
    if (startIndex <= endIndex) {
      for (var i = startIndex + 1; i < endIndex; i++) {
        vertices.add(route[i]);
      }
    } else {
      for (var i = startIndex - 1; i > endIndex; i--) {
        vertices.add(route[i]);
      }
    }
    vertices.add(end);
    return _dedupePath(vertices);
  }

  List<LatLng> _dedupePath(List<LatLng> path) {
    if (path.length < 2) return path;
    final out = <LatLng>[path.first];
    for (var i = 1; i < path.length; i++) {
      if (_metersBetween(out.last, path[i]) > 0.4) {
        out.add(path[i]);
      }
    }
    return out;
  }

  int _nearestVertexIndex(LatLng point, List<LatLng> path) {
    if (path.isEmpty) return -1;
    var bestIndex = 0;
    var bestMeters = _metersBetween(point, path.first);
    for (var i = 1; i < path.length; i++) {
      final meters = _metersBetween(point, path[i]);
      if (meters < bestMeters) {
        bestMeters = meters;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  double _pathLengthMeters(List<LatLng> path) {
    if (path.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < path.length; i++) {
      total += _metersBetween(path[i - 1], path[i]);
    }
    return total;
  }

  LatLng _pointAlongPath(List<LatLng> path, double t) {
    if (path.isEmpty) return _origin ?? _site;
    if (path.length == 1) return path.first;
    final clamped = t.clamp(0.0, 1.0);
    final total = _pathLengthMeters(path);
    if (total <= 0) return path.last;
    final target = total * clamped;
    var walked = 0.0;
    for (var i = 1; i < path.length; i++) {
      final a = path[i - 1];
      final b = path[i];
      final seg = _metersBetween(a, b);
      if (walked + seg >= target || i == path.length - 1) {
        final local = seg <= 0 ? 1.0 : ((target - walked) / seg).clamp(0.0, 1.0);
        return LatLng(
          a.latitude + ((b.latitude - a.latitude) * local),
          a.longitude + ((b.longitude - a.longitude) * local),
        );
      }
      walked += seg;
    }
    return path.last;
  }

  double? _bearingAtPathProgress(List<LatLng> path, double t) {
    if (path.length < 2) return null;
    final here = _pointAlongPath(path, t.clamp(0.0, 1.0));
    final ahead = _pointAlongPath(path, (t + 0.04).clamp(0.0, 1.0));
    if (_metersBetween(here, ahead) < 0.3) {
      for (var i = 1; i < path.length; i++) {
        if (_metersBetween(path[i - 1], path[i]) > 0.3) {
          return Geolocator.bearingBetween(
            path[i - 1].latitude,
            path[i - 1].longitude,
            path[i].latitude,
            path[i].longitude,
          );
        }
      }
      return null;
    }
    return Geolocator.bearingBetween(
      here.latitude,
      here.longitude,
      ahead.latitude,
      ahead.longitude,
    );
  }

  void onMarkerRotateTick() {
    if (!_isMounted()) return;
    final t = Curves.easeInOut.transform(
      _markerRotateController!.value.clamp(0.0, 1.0),
    );
    _markerBearing = _lerpBearing(_markerBearingFrom, _markerBearingTo, t);
    if (_origin != null) {
      _markers = _buildMarkers(_origin);
      _notifyMap();
    }
  }

  double _lerpBearing(double from, double to, double t) {
    var delta = (to - from) % 360;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    return from + (delta * t);
  }

  double? _routeBearingNear(LatLng point) {
    final points = _routePoints;
    if (!_isDrivingRoute(points)) return null;
    var bestMeters = double.infinity;
    var bestBearing = 0.0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final projected = _projectOnSegment(point, a, b);
      final meters = _metersBetween(point, projected);
      if (meters < bestMeters) {
        bestMeters = meters;
        bestBearing = Geolocator.bearingBetween(
          a.latitude,
          a.longitude,
          b.latitude,
          b.longitude,
        );
      }
    }
    if (bestMeters > 50) return null;
    return bestBearing;
  }

  Future<void> _loadSelectedMarkerIcon() async {
    if (!_isMounted()) return;
    if (_selectedMarkerStyle.usesPulse) {
      await _startLocationPulse();
      return;
    }
    _stopLocationPulse();
    final icon = await LiveMapMarkerBitmap.forStyle(
      _selectedMarkerStyle,
      logicalSize: _markerLogicalSize(),
      devicePixelRatio: _markerDevicePixelRatio(),
    );
    if (!_isMounted()) return;
    _patch(() {
      _youAreHereIcon = icon;
      if (_origin != null) {
        _markers = _buildMarkers(_origin);
      }});
  }

  Future<void> _selectMarkerStyle(LiveMapMarkerStyle style) async {
    _patch(() {
      _selectedMarkerStyle = style;
      _showMarkerPicker = false;
      if (!style.rotatesWithBearing) {
        _markerBearing = 0;
      } else if (_origin != null) {
        _syncMarkerHeading(_origin!);
      }
    });
    await DispatchLiveMarkerStyleStore.set(style);
    if (!_isMounted()) return;
    await _loadSelectedMarkerIcon();
    if (!_isMounted()) return;
    if (_selectedMarkerStyle.usesPulse) {
      unawaited(_startLocationPulse());
    }
  }

  void _stopLocationPulse() {
    _locationPulseTimer?.cancel();
    _locationPulseTimer = null;
  }

  Future<BitmapDescriptor> _buildYouAreHereDot({
    required Color fill,
    required double logicalSize,
    required double devicePixelRatio,
    double pulse = 0,
  }) async {
    final pad = LiveMapMarkerBitmap.tapPadding * devicePixelRatio;
    final visual = logicalSize * devicePixelRatio;
    final size = visual + (pad * 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    final outer = visual * 0.46;
    final mid = visual * 0.30;
    final inner = visual * 0.20;

    canvas.drawCircle(
      center,
      outer * (.65 + .35 * pulse),
      Paint()..color = fill.withValues(alpha: .30 * (1 - pulse)),
    );
    canvas.drawCircle(center, mid, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      mid,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = visual * 0.05
        ..color = fill.withValues(alpha: .35),
    );
    canvas.drawCircle(center, inner, Paint()..color = fill);

    final image = await recorder.endRecording().toImage(
      size.ceil(),
      size.ceil(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: devicePixelRatio,
    );
  }

  Future<void> _startLocationPulse() async {
    if (_locationPulseTimer != null) return;
    if (!_isMounted()) return;
    final logicalSize = _markerLogicalSize();
    final dpr = _markerDevicePixelRatio();
    final key =
        '$_iconCacheKey-${logicalSize.toStringAsFixed(1)}-${dpr.toStringAsFixed(2)}-pad${LiveMapMarkerBitmap.tapPadding}';
    var frames = _pulseFrames[key];
    if (frames == null) {
      frames = await Future.wait(
        List.generate(
          18,
          (index) => _buildYouAreHereDot(
            fill: _routeColor,
            logicalSize: logicalSize,
            devicePixelRatio: dpr,
            pulse: index / 18,
          ),
        ),
      );
      _pulseFrames[key] = frames;
    }
    if (!_isMounted()) return;
    if (!_selectedMarkerStyle.usesPulse) return;
    if (_locationPulseTimer != null) return;
    final icons = frames;
    var index = 0;
    _youAreHereIcon = icons.first;
    _youAreHereCache[key] = icons.first;
    if (_origin != null) {
      _patch(() { _markers = _buildMarkers(_origin); });
    }
    _locationPulseTimer = Timer.periodic(const Duration(milliseconds: 160), (_) {
      if (!_isMounted() ||
          _origin == null ||
          !_selectedMarkerStyle.usesPulse ||
          _showMarkerPicker ||
          _markerMoveController!.isAnimating ||
          !TickerMode.valuesOf(context).enabled ||
          MediaQuery.disableAnimationsOf(context)) {
        return;
      }
      _patch(() {
        _youAreHereIcon = icons[index++ % icons.length];
        _markers = _buildMarkers(_origin);
      });});
  }

  void _setRouting(bool routing) {
    if (_routing == routing) {
      onRoutingChanged?.call(routing);
      return;
    }
    _patch(() { _routing = routing; });
    onRoutingChanged?.call(routing);
  }

      Marker _siteMarker() {
    final title = (_siteName ?? '').trim();
    final snippet = (_siteSubtitle ?? '').trim();
    return Marker(
      markerId: const MarkerId('_site'),
      position: _site,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(
        title: title.isEmpty ? 'Site' : title,
        snippet: snippet.isEmpty ? null : snippet,
      ),
      zIndexInt: 2,
    );
  }

  Marker _originMarker(LatLng origin) {
    return Marker(
      markerId: const MarkerId('origin'),
      position: origin,
      icon:
          _youAreHereIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      anchor: const Offset(0.5, 0.5),
      flat: true,
      rotation: _selectedMarkerStyle.rotatesWithBearing ? _markerBearing : 0,
      consumeTapEvents: interactive,
      onTap: interactive ? _openMarkerPicker : null,
      infoWindow: InfoWindow.noText,
      zIndexInt: 3,
    );
  }

  void _openMarkerPicker() {
    if (!_isMounted() || !interactive) return;
    if (_showMarkerPicker) return;
    _pauseMarkerMotion();
    _patch(() { _showMarkerPicker = true; });
  }

  void _closeMarkerPicker() {
    if (!_isMounted() || !_showMarkerPicker) return;
    _patch(() { _showMarkerPicker = false; });
  }

  bool _isDrivingRoute(List<LatLng> points) => points.length > 2;

  Future<void> _bootstrap() async {
    final generation = ++_loadGeneration;
    _patch(() { _error = null; });

    final iconFuture = _ensureYouAreHereIcon();
    final seededOrigin = _origin;
    final seededRoute = List<LatLng>.from(_routePoints);

    if (seededOrigin != null && _isDrivingRoute(seededRoute)) {
      _setRouting(false);
      _syncMarkerHeading(seededOrigin);
      if (_isMounted()) {
        _patch(() {
          _markers = _buildMarkers(seededOrigin, routePoints: _routePoints);
        });
      }
      unawaited(
        _fitCamera(
          [seededOrigin, _site, ..._routePoints],
          animate: true,
          duration: const Duration(milliseconds: 700),
        ),
      );
      await iconFuture;
      return;
    }

    _setRouting(true);
    final quickOrigin = seededOrigin ??
        await _resolveOrigin(preferLastKnown: true);
    if (!_isMounted() || generation != _loadGeneration) return;

    if (quickOrigin == null) {
      await iconFuture;
      if (!_isMounted() || generation != _loadGeneration) return;
      _patch(() {
        _origin = null;
        _markers = {_siteMarker()};
        _polylines = {};
        _error = 'Location unavailable';
      });
      _setRouting(false);
      await _fitCamera([_site]);
      return;
    }

    _fitted = false;
    _applyPreview(quickOrigin);
    unawaited(_fitCamera([quickOrigin, _site]));

    final results = await Future.wait<Object?>([
      _fetchRoute(quickOrigin, _site),
      _resolveOrigin(preferLastKnown: false),
      iconFuture,
    ]);
    if (!_isMounted() || generation != _loadGeneration) return;

    final route = (results[0] as List<LatLng>?) ?? const <LatLng>[];
    final freshOrigin = results[1] as LatLng?;
    final origin = freshOrigin ?? quickOrigin;
    final points = !_isDrivingRoute(route)
        ? const <LatLng>[]
        : (freshOrigin == null || _near(freshOrigin, quickOrigin)
              ? route
              : await _fetchRoute(origin, _site));
    if (!_isMounted() || generation != _loadGeneration) return;

    if (!_isDrivingRoute(points)) {
      _applyPreview(origin);
      _patch(() { _error = 'Could not load driving route'; });
      _setRouting(false);
      return;
    }

    _publishRoute(origin: origin, points: points);
  }

  Polyline _previewPolyline(LatLng origin) {
    return Polyline(
      polylineId: const PolylineId('preview'),
      points: [origin, _site],
      color: _routeColor.withValues(alpha: .55),
      width: 4,
      patterns: [PatternItem.dash(18), PatternItem.gap(10)],
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
    );
  }

  void _applyPreview(LatLng origin) {
    _patch(() {
      _origin = origin;
      _routePoints = const [];
      _syncMarkerHeading(origin);
      _markers = {_originMarker(origin), _siteMarker()};
      _polylines = interactive ? {} : {_previewPolyline(origin)};
      _error = null;});
    _emitStraightMetrics(origin, _site);
  }

  void _emitRouteSnapshot() {
    onRouteSnapshot?.call(_origin, List<LatLng>.from(_routePoints));
  }

  void _publishRoute({
    required LatLng origin,
    required List<LatLng> points,
    bool emitMetrics = true,
  }) {
    _patch(() {
      _origin = origin;
      _routePoints = points;
      _gapDotIcon = _gapDotCache['$_iconCacheKey-16'] ?? _gapDotIcon;
      _trimPassedRoute(origin, emitMetrics: false);
      _syncMarkerHeading(origin);
      _markers = _buildMarkers(origin, routePoints: _routePoints);
      _error = null;
      _fitted = false;});
    _emitRouteSnapshot();
    _setRouting(false);
    unawaited(_ensureGapDotIcon().then((_) {
      if (!_isMounted() || _origin == null) return;
      _patch(() {
        _markers = _buildMarkers(_origin, routePoints: _routePoints);
      });
    }));

    if (emitMetrics) {
      final meters = _pathMeters(_routePoints);
      final miles = meters / 1609.344;
      onMetrics?.call(
        DispatchRouteMetrics(
          distanceMiles: double.parse(miles.toStringAsFixed(1)),
          arrivalMinutes: math.max(1, (miles / 25 * 60).round()),
        ),
      );
    }
    unawaited(
      _fitCamera(
        [origin, _site, ..._routePoints],
        animate: true,
        duration: const Duration(milliseconds: 750),
      ),
    );
  }

  void _syncMarkerHeading(LatLng origin) {
    if (!_selectedMarkerStyle.rotatesWithBearing) {
      _markerBearing = 0;
      _markerBearingFrom = 0;
      _markerBearingTo = 0;
      return;
    }
    final heading = _overviewHeading(origin);
    _markerBearing = heading;
    _markerBearingFrom = heading;
    _markerBearingTo = heading;
  }

  double _overviewHeading(LatLng origin) {
    final alongRoute = _routeBearingNear(origin) ??
        (_isDrivingRoute(_routePoints)
            ? _bearingAtPathProgress(_routePoints, 0.02)
            : null);
    if (alongRoute != null) return alongRoute;
    return Geolocator.bearingBetween(
      origin.latitude,
      origin.longitude,
      _site.latitude,
      _site.longitude,
    );
  }

  Future<void> _openFullscreen() async {
    if (_openingFullscreen || interactive) return;
    final origin = _origin;
    final routePoints = List<LatLng>.from(_routePoints);
    _openingFullscreen = true;
    _patch(() {
      _mapVisible = false;
      mapController = null;
      _fitted = false;
      _showMarkerPicker = false;});
    await Future<void>.delayed(const Duration(milliseconds: 280));
    await WidgetsBinding.instance.endOfFrame;
    if (!_isMounted()) {
      _openingFullscreen = false;
      return;
    }

    final exitDispatch = await DispatchFullscreenMapScreen.open(
      context,
      site: _site,
      isDark: _isDark,
      siteName: _siteName,
      siteSubtitle: _siteSubtitle,
      initialOrigin: origin,
      initialRoutePoints: routePoints,
      onAccept: onAccept,
      onDecline: onDecline,
      responseSecondsLeft: responseSecondsLeft,
      responseTotalSeconds: responseTotalSeconds,
      accepted: onAccept == null && onDecline == null,
      showResponseActions: onAccept != null || onDecline != null,
    );

    if (!_isMounted()) {
      _openingFullscreen = false;
      return;
    }
    if (exitDispatch == true) {
      _openingFullscreen = false;
      if (!_isMounted() || !context.mounted) return;
      Navigator.of(context).maybePop();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await WidgetsBinding.instance.endOfFrame;
    if (!_isMounted()) {
      _openingFullscreen = false;
      return;
    }
    _patch(() {
      mapViewKey = UniqueKey();
      _mapVisible = true;
      _fitted = false;});
    _openingFullscreen = false;
  }

  Future<void> _zoomBy(double delta) async {
    final controller = mapController;
    if (controller == null) return;
    try {
      final zoom = await controller.getZoomLevel();
      await controller.animateCamera(
        CameraUpdate.zoomTo((zoom + delta).clamp(3.0, 20.0)),
      );
    } catch (_) {}
  }

  Future<void> _fitToRoute() async {
    await _fitCamera(
      [?_origin, _site, ..._routePoints],
      animate: true,
      duration: const Duration(milliseconds: 700),
    );
  }

  Future<void> _manualRefreshLocation() async {
    if (_routing) return;
    final generation = ++_loadGeneration;
    final origin = await _resolveOrigin(
      preferLastKnown: false,
      allowDutyHub: false,
    );
    if (!_isMounted() || generation != _loadGeneration) return;
    if (origin == null) {
      _patch(() { _error = 'Location unavailable'; });
      return;
    }

    _patch(() {
      _origin = origin;
      _markers = _buildMarkers(origin);
      _error = null;});

    await _rerouteFrom(origin, generation: generation);
  }

  Future<void> _manualReroute() async {
    if (_routing) return;
    final generation = ++_loadGeneration;
    var origin = _origin;
    origin ??= await _resolveOrigin(preferLastKnown: false);
    if (!_isMounted() || generation != _loadGeneration) return;
    if (origin == null) {
      _patch(() { _error = 'Location unavailable'; });
      return;
    }
    await _rerouteFrom(origin, generation: generation);
  }

  Future<void> _rerouteFrom(LatLng origin, {required int generation}) async {
    final cachedRoute = List<LatLng>.from(_routePoints);
    final hasCache = _isDrivingRoute(cachedRoute);

    _setRouting(true);
    _patch(() {
      _origin = origin;
      _markers = _buildMarkers(origin, routePoints: cachedRoute);
      _error = null;
      if (hasCache) {
        _routePoints = cachedRoute;
        _trimPassedRoute(origin);
        _markers = _buildMarkers(origin, routePoints: _routePoints);
      } else if (!interactive) {
        _polylines = {_previewPolyline(origin)};
      }});

    final route = await _fetchRoute(origin, _site);
    if (!_isMounted() || generation != _loadGeneration) return;
    if (!_isDrivingRoute(route)) {
      _patch(() {
        _origin = origin;
        if (hasCache) {
          _routePoints = cachedRoute;
          _trimPassedRoute(origin);
          _markers = _buildMarkers(origin, routePoints: _routePoints);
        } else if (!interactive) {
          _routePoints = const [];
          _polylines = {_previewPolyline(origin)};
          _markers = {_originMarker(origin), _siteMarker()};
        } else {
          _routePoints = const [];
          _polylines = {};
          _markers = {_originMarker(origin), _siteMarker()};
        }
        _error = 'Could not load driving route';
      });
      _setRouting(false);
      return;
    }
    _publishRoute(origin: origin, points: route);
  }

  void _emitStraightMetrics(LatLng origin, LatLng destination) {
    final meters = Geolocator.distanceBetween(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );
    final miles = meters / 1609.344;
    onMetrics?.call(
      DispatchRouteMetrics(
        distanceMiles: double.parse(miles.toStringAsFixed(1)),
        arrivalMinutes: math.max(1, (miles / 25 * 60).round()),
      ),
    );
  }

  bool _near(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
          a.latitude,
          a.longitude,
          b.latitude,
          b.longitude,
        ) <
        40;
  }

  Future<void> _ensureYouAreHereIcon() async {
    await _ensureGapDotIcon();
    await _loadSelectedMarkerIcon();
  }

  Future<void> _ensureGapDotIcon() async {
    final key = '$_iconCacheKey-16';
    final cached = _gapDotCache[key];
    if (cached != null) {
      _gapDotIcon = cached;
      return;
    }
    final icon = await _buildGapDot(fill: _routeColor, size: 16);
    _gapDotCache[key] = icon;
    _gapDotIcon = icon;
  }

  Future<BitmapDescriptor> _buildGapDot({
    required Color fill,
    required double size,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    canvas.drawCircle(center, size * 0.42, Paint()..color = Colors.white);
    canvas.drawCircle(center, size * 0.30, Paint()..color = fill);
    final image = await recorder.endRecording().toImage(
      size.ceil(),
      size.ceil(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  Future<LatLng?> _resolveOrigin({
    required bool preferLastKnown,
    bool allowDutyHub = true,
  }) async {
    if (allowDutyHub) {
      final duty = DutyLiveLocationHub.freshFix();
      if (duty != null) {
        return LatLng(duty.latitude, duty.longitude);
      }
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    if (preferLastKnown) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return LatLng(last.latitude, last.longitude);
      }
    }

    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: preferLastKnown
              ? LocationAccuracy.medium
              : LocationAccuracy.high,
          timeLimit: Duration(seconds: preferLastKnown ? 3 : 6),
        ),
      );
      DutyLiveLocationHub.publishPosition(current, source: 'map_oneshot');
      return LatLng(current.latitude, current.longitude);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) return null;
      return LatLng(last.latitude, last.longitude);
    }
  }

  Future<List<LatLng>> _fetchRoute(LatLng origin, LatLng destination) async {
    final googlePoints = await _fetchGoogleDirections(origin, destination);
    if (googlePoints.isNotEmpty) return googlePoints;
    return _fetchOsrmRoute(origin, destination);
  }

  Future<List<LatLng>> _fetchGoogleDirections(
    LatLng origin,
    LatLng destination,
  ) async {
    final url =
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&mode=driving'
        '&key=${GoogleMapsConfig.apiKey}';
    try {
      final response = await Dio().get<dynamic>(
        url,
        options: Options(
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
        ),
      );
      if (response.statusCode != 200 || response.data == null) {
        return const [];
      }
      final body = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : Map<String, dynamic>.from(response.data as Map);
      if (body['status'] != 'OK') return const [];
      final routes = body['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return const [];
      final overview =
          routes.first['overview_polyline'] as Map<String, dynamic>?;
      final encoded = overview?['points'] as String?;
      if (encoded == null || encoded.isEmpty) return const [];
      return _decodePolyline(encoded);
    } catch (_) {
      return const [];
    }
  }

  Future<List<LatLng>> _fetchOsrmRoute(LatLng origin, LatLng destination) async {
    final url =
        'https://router.project-osrm.org/route/v1/driving/'
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson';
    try {
      final response = await Dio().get<dynamic>(
        url,
        options: Options(
          headers: {'User-Agent': 'SmartNPS360/1.0'},
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
        ),
      );
      if (response.statusCode != 200 || response.data == null) {
        return const [];
      }
      final body = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : Map<String, dynamic>.from(response.data as Map);
      if (body['code'] != 'Ok') return const [];
      final routes = body['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return const [];
      final geometry = routes.first['geometry'] as Map<String, dynamic>?;
      final coords = geometry?['coordinates'] as List<dynamic>?;
      if (coords == null || coords.isEmpty) return const [];
      return coords
          .map((point) {
            final pair = point as List<dynamic>;
            return LatLng(
              (pair[1] as num).toDouble(),
              (pair[0] as num).toDouble(),
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      final deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += deltaLat;

      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      final deltaLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += deltaLng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  double _pathMeters(List<LatLng> points) {
    if (points.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += Geolocator.distanceBetween(
        points[i - 1].latitude,
        points[i - 1].longitude,
        points[i].latitude,
        points[i].longitude,
      );
    }
    return total;
  }

  static const double _gapConnectorMeters = 5;
  static const double _gapDotSpacingMeters = 8;

  List<LatLng> _remainingRoutePoints(LatLng origin, List<LatLng> points) {
    if (points.length < 2) return points;

    var bestMeters = double.infinity;
    var bestSeg = 0;
    var bestPoint = points.first;
    for (var i = 1; i < points.length; i++) {
      final projected = _projectOnSegment(origin, points[i - 1], points[i]);
      final meters = _metersBetween(origin, projected);
      if (meters < bestMeters) {
        bestMeters = meters;
        bestSeg = i;
        bestPoint = projected;
      }
    }

    if (bestMeters > 80) {
      return points;
    }

    final remaining = <LatLng>[bestPoint];
    for (var i = bestSeg; i < points.length; i++) {
      if (_metersBetween(remaining.last, points[i]) > 0.4) {
        remaining.add(points[i]);
      }
    }
    if (remaining.length < 2) {
      return [bestPoint, points.last];
    }
    return remaining;
  }

  void _trimPassedRoute(LatLng origin, {bool emitMetrics = false}) {
    if (!_isDrivingRoute(_routePoints)) {
      _polylines = {};
      return;
    }

    final remaining = _remainingRoutePoints(origin, _routePoints);
    final beforeMeters = _pathMeters(_routePoints);
    final afterMeters = _pathMeters(remaining);
    if (afterMeters <= beforeMeters + 0.5) {
      _routePoints = remaining;
    }
    _polylines = _routePolylines(origin: origin, points: _routePoints);

    if (emitMetrics && _isDrivingRoute(_routePoints)) {
      final meters = _pathMeters(_routePoints);
      final miles = meters / 1609.344;
      onMetrics?.call(
        DispatchRouteMetrics(
          distanceMiles: double.parse(miles.toStringAsFixed(1)),
          arrivalMinutes: math.max(1, (miles / 25 * 60).round()),
        ),
      );
    }
  }

  Set<Polyline> _routePolylines({
    required LatLng origin,
    required List<LatLng> points,
  }) {
    final remaining = _remainingRoutePoints(origin, points);
    if (remaining.length < 2) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: remaining,
        color: _routeColor,
        width: interactive ? 6 : 5,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        zIndex: 1,
      ),
    };
  }

  Set<Marker> _buildMarkers(LatLng? origin, {List<LatLng>? routePoints}) {
    final points = routePoints ?? _routePoints;
    return {
      if (origin != null) _originMarker(origin),
      _siteMarker(),
      if (origin != null && _isDrivingRoute(points))
        ..._gapDotMarkers(origin: origin, points: points),
    };
  }

  LatLng _bestGapJoin(
    LatLng point,
    List<LatLng> points, {
    required bool preferEnd,
  }) {
    final nearest = _nearestOnPath(point, points);
    final end = preferEnd ? points.last : points.first;
    return _metersBetween(point, end) <= _metersBetween(point, nearest) + 8
        ? end
        : nearest;
  }

  Set<Marker> _gapDotMarkers({
    required LatLng origin,
    required List<LatLng> points,
  }) {
    final icon = _gapDotIcon;
    if (icon == null || points.isEmpty) return {};

    final originDots = _gapDotPositions(
      origin,
      _bestGapJoin(origin, points, preferEnd: false),
    );
    final siteDots = _gapDotPositions(
      _site,
      _bestGapJoin(_site, points, preferEnd: true),
    );

    return {
      for (var i = 0; i < originDots.length; i++)
        Marker(
          markerId: MarkerId('gap-origin-$i'),
          position: originDots[i],
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          consumeTapEvents: true,
          infoWindow: InfoWindow.noText,
          zIndexInt: 1,
        ),
      for (var i = 0; i < siteDots.length; i++)
        Marker(
          markerId: MarkerId('gap-_site-$i'),
          position: siteDots[i],
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          consumeTapEvents: true,
          infoWindow: InfoWindow.noText,
          zIndexInt: 1,
        ),
    };
  }

  List<LatLng> _gapDotPositions(LatLng from, LatLng to) {
    final meters = _metersBetween(from, to);
    if (meters < _gapConnectorMeters) return const [];
    final count = math.min(
      60,
      math.max(3, (meters / _gapDotSpacingMeters).ceil()),
    );
    return [
      for (var i = 1; i <= count; i++)
        LatLng(
          from.latitude + ((to.latitude - from.latitude) * (i / (count + 1))),
          from.longitude +
              ((to.longitude - from.longitude) * (i / (count + 1))),
        ),
    ];
  }

  double _metersBetween(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
  }

  LatLng _nearestOnPath(LatLng point, List<LatLng> path) {
    if (path.isEmpty) return point;
    if (path.length == 1) return path.first;

    var best = path.first;
    var bestMeters = _metersBetween(point, best);
    for (var i = 1; i < path.length; i++) {
      final projected = _projectOnSegment(point, path[i - 1], path[i]);
      final meters = _metersBetween(point, projected);
      if (meters < bestMeters) {
        bestMeters = meters;
        best = projected;
      }
    }
    return best;
  }

  LatLng _projectOnSegment(LatLng point, LatLng start, LatLng end) {
    final ax = start.longitude;
    final ay = start.latitude;
    final bx = end.longitude;
    final by = end.latitude;
    final px = point.longitude;
    final py = point.latitude;
    final dx = bx - ax;
    final dy = by - ay;
    if (dx == 0 && dy == 0) return start;
    final t = (((px - ax) * dx) + ((py - ay) * dy)) / ((dx * dx) + (dy * dy));
    final clamped = t.clamp(0.0, 1.0);
    return LatLng(ay + (dy * clamped), ax + (dx * clamped));
  }

  Future<void> _fitCamera(
    List<LatLng> points, {
    bool animate = false,
    Duration? duration,
  }) async {
    final controller = mapController;
    if (controller == null) return;

    final focus = <LatLng>[
      ...points,
      ?_origin,
      _site,
      ..._routePoints,
    ];
    if (focus.isEmpty) return;

    await Future<void>.delayed(Duration.zero);
    if (!_isMounted() || !identical(mapController, controller)) return;

    final origin = _origin;
    if (origin != null) {
      _syncMarkerHeading(origin);
      _markers = _buildMarkers(origin, routePoints: _routePoints);
      if (_isMounted()) _notifyMap();
    }

    final update = _cameraUpdateFor(focus);
    final shouldAnimate = animate || !_fitted;
    final fitDuration = duration ?? const Duration(milliseconds: 650);
    try {
      if (shouldAnimate) {
        await controller.animateCamera(update, duration: fitDuration);
      } else {
        await controller.moveCamera(update);
      }
      _fitted = true;
    } catch (_) {
      try {
        final fallback = _fallbackCameraUpdate(focus);
        if (shouldAnimate) {
          await controller.animateCamera(fallback, duration: fitDuration);
        } else {
          await controller.moveCamera(fallback);
        }
        _fitted = true;
      } catch (_) {}
    }
  }

  double _controlsBottomInset(DispatchScale scale) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    if (!interactive) return safeBottom + scale.s(20);
    return safeBottom + scale.s(reserveResponsePanel ? 188 : 28);
  }

  CameraUpdate _cameraUpdateFor(List<LatLng> points) {
    if (points.length == 1) {
      final origin = _origin;
      final bearing = origin == null ? 0.0 : _overviewHeading(origin);
      return CameraUpdate.newCameraPosition(
        CameraPosition(
          target: points.first,
          zoom: 15.5,
          bearing: bearing,
          tilt: 0,
        ),
      );
    }
    return _fallbackCameraUpdate(points);
  }

  CameraUpdate _fallbackCameraUpdate(List<LatLng> points) {
    final bounds = _expandedBounds(points);
    final center = LatLng(
      (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
      (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
    );
    final meters = Geolocator.distanceBetween(
      bounds.southwest.latitude,
      bounds.southwest.longitude,
      bounds.northeast.latitude,
      bounds.northeast.longitude,
    );
    final origin = _origin;
    final bearing = origin == null ? 0.0 : _overviewHeading(origin);
    return CameraUpdate.newCameraPosition(
      CameraPosition(
        target: center,
        zoom: _zoomForMeters(meters * 1.35),
        bearing: bearing,
        tilt: 0,
      ),
    );
  }

  double _zoomForMeters(double meters) {
    if (meters < 180) return 16.2;
    if (meters < 350) return 15.4;
    if (meters < 700) return 14.6;
    if (meters < 1400) return 13.8;
    if (meters < 2800) return 13;
    if (meters < 5500) return 12.2;
    if (meters < 11000) return 11.4;
    if (meters < 22000) return 10.6;
    if (meters < 45000) return 9.8;
    return 9.2;
  }

  LatLngBounds _expandedBounds(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    var latSpan = math.max(maxLat - minLat, 0.0016);
    var lngSpan = math.max(maxLng - minLng, 0.0016);
    latSpan *= 1.18;
    lngSpan *= 1.18;

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    return LatLngBounds(
      southwest: LatLng(centerLat - latSpan / 2, centerLng - lngSpan / 2),
      northeast: LatLng(centerLat + latSpan / 2, centerLng + lngSpan / 2),
    );
  }

  void closeMarkerPicker() => _closeMarkerPicker();

  void openMarkerPicker() => _openMarkerPicker();

  Future<void> selectMarkerStyle(LiveMapMarkerStyle style) =>
      _selectMarkerStyle(style);

  Future<void> openFullscreen() => _openFullscreen();

  Future<void> fitToRoute() => _fitToRoute();

  Future<void> zoomBy(double delta) => _zoomBy(delta);

  Future<void> manualRefreshLocation() => _manualRefreshLocation();

  Future<void> manualReroute() => _manualReroute();

  double controlsBottomInset(DispatchScale scale) => _controlsBottomInset(scale);

  void handleMapCreated(GoogleMapController controller) {
    mapController = controller;
    final points = <LatLng>[
      ?origin,
      _site,
      ...routePoints,
      ...polylines.expand((line) => line.points),
    ];
    unawaited(
      _fitCamera(
        points,
        animate: true,
        duration: const Duration(milliseconds: 700),
      ),
    );
  }
}
