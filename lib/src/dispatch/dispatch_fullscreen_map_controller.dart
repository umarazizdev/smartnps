import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'dispatch_active_session.dart';
import 'dispatch_google_navigation_screen.dart';
import 'dispatch_request_data.dart';
import 'google_maps_config.dart';

class DispatchMapsRouteOption {
  const DispatchMapsRouteOption({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.summary = '',
  });

  final List<LatLng> points;
  final double distanceMeters;
  final int durationSeconds;
  final String summary;

  double get distanceMiles => distanceMeters / 1609.344;

  int get arrivalMinutes =>
      durationSeconds > 0 ? (durationSeconds / 60).ceil().clamp(1, 999) : 1;
}

class DispatchFullscreenMapController extends GetxController {
  DispatchFullscreenMapController({
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
    required bool accepted,
    required bool showResponseActions,
  })  : accepted = accepted.obs,
        showResponseActions = (showResponseActions && !accepted).obs;

  static const String tag = 'dispatch-fullscreen-map';

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

  final RxBool accepted;
  final RxBool showResponseActions;
  final mapReady = false.obs;
  final routing = true.obs;
  final selectedRouteIndex = 0.obs;
  final mapType = MapType.normal.obs;
  final trafficEnabled = false.obs;
  final showLayersMenu = false.obs;
  final routes = <DispatchMapsRouteOption>[].obs;
  final markers = <Marker>{}.obs;
  final polylines = <Polyline>{}.obs;
  final errorMessage = RxnString();

  static const List<MapType> layerOptions = [
    MapType.normal,
    MapType.satellite,
    MapType.terrain,
    MapType.hybrid,
  ];

  void toggleLayersMenu() {
    showLayersMenu.value = !showLayersMenu.value;
  }

  void closeLayersMenu() {
    showLayersMenu.value = false;
  }

  void setMapType(MapType type) {
    mapType.value = type;
    showLayersMenu.value = false;
  }

  void setTrafficEnabled(bool enabled) {
    trafficEnabled.value = enabled;
  }

  void toggleTraffic() {
    trafficEnabled.value = !trafficEnabled.value;
  }

  String labelForMapType(MapType type) {
    return switch (type) {
      MapType.normal => 'Default',
      MapType.satellite => 'Satellite',
      MapType.terrain => 'Terrain',
      MapType.hybrid => 'Hybrid',
      MapType.none => 'None',
    };
  }

  IconData iconForMapType(MapType type) {
    return switch (type) {
      MapType.normal => Icons.map_rounded,
      MapType.satellite => Icons.satellite_alt_rounded,
      MapType.terrain => Icons.terrain_rounded,
      MapType.hybrid => Icons.layers_rounded,
      MapType.none => Icons.hide_source_rounded,
    };
  }

  GoogleMapController? _mapController;
  bool _closingForExpire = false;
  VoidCallback? onExpireClose;
  LatLng? _origin;

  LatLng get cameraTarget => _origin ?? initialOrigin ?? site;

  DispatchMapsRouteOption? get selectedRoute {
    if (routes.isEmpty) return null;
    final index = selectedRouteIndex.value.clamp(0, routes.length - 1);
    return routes[index];
  }

  @override
  void onInit() {
    super.onInit();
    _origin = initialOrigin;
    responseSecondsLeft?.addListener(_onResponseSecondsChanged);
    _seedMarkers();
    _seedProvisionalRoute();
    unawaited(_bootstrap());
  }

  bool get shouldResumeNavigation =>
      accepted.value &&
      DispatchActiveSessionStore.active.value?.navigationStarted == true;

  @override
  void onClose() {
    responseSecondsLeft?.removeListener(_onResponseSecondsChanged);
    _mapController = null;
    super.onClose();
  }

  void _seedMarkers() {
    final origin = _origin;
    markers.assignAll({
      if (origin != null)
        Marker(
          markerId: const MarkerId('origin'),
          position: origin,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'Your location'),
          consumeTapEvents: false,
        ),
      Marker(
        markerId: const MarkerId('site'),
        position: site,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: siteName?.trim().isNotEmpty == true
              ? siteName!.trim()
              : 'Dispatch site',
          snippet: siteSubtitle,
        ),
        consumeTapEvents: false,
      ),
    });
  }

  void _seedProvisionalRoute() {
    if (initialRoutePoints.length < 2) return;
    routes.assignAll([
      DispatchMapsRouteOption(
        points: List<LatLng>.from(initialRoutePoints),
        distanceMeters: _pathMeters(initialRoutePoints),
        durationSeconds:
            ((_pathMeters(initialRoutePoints) / 1609.344) / 25 * 3600).round(),
        summary: 'Current route',
      ),
    ]);
    selectedRouteIndex.value = 0;
    _rebuildPolylines();
  }

  Future<void> _bootstrap() async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await WidgetsBinding.instance.endOfFrame;
    if (isClosed) return;
    mapReady.value = true;
    _onResponseSecondsChanged();
    await loadRoutes();
  }

  Future<void> loadRoutes() async {
    routing.value = true;
    errorMessage.value = null;

    var origin = _origin;
    if (origin == null) {
      origin = await _resolveOrigin();
      if (isClosed) return;
      if (origin != null) {
        _origin = origin;
        _seedMarkers();
      }
    }

    if (origin == null) {
      if (routes.isEmpty) {
        errorMessage.value = 'Waiting for GPS to load routes';
      }
      routing.value = false;
      return;
    }

    final result = await _fetchGoogleDirectionsAlternatives(origin, site);
    if (isClosed) return;
    if (result.options.isNotEmpty) {
      routes.assignAll(result.options);
      selectedRouteIndex.value = 0;
      errorMessage.value = null;
    } else if (routes.isEmpty && initialRoutePoints.length > 1) {
      _seedProvisionalRoute();
      errorMessage.value =
          result.error ?? 'Could not load alternate routes';
    } else if (result.options.isEmpty) {
      errorMessage.value =
          result.error ?? 'Could not load alternate routes';
    }
    _rebuildPolylines();
    routing.value = false;
    await _fitToRoutes();
  }

  Future<LatLng?> _resolveOrigin() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          return null;
        }
      }
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return LatLng(last.latitude, last.longitude);
      }
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );
      return LatLng(current.latitude, current.longitude);
    } catch (_) {
      return null;
    }
  }

  void selectRoute(int index) {
    if (index < 0 || index >= routes.length) return;
    selectedRouteIndex.value = index;
    _rebuildPolylines();
    unawaited(_fitToRoutes());
  }

  void onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    unawaited(_fitToRoutes());
    unawaited(_revealMapToolbar());
  }

  Future<void> _revealMapToolbar() async {
    final controller = _mapController;
    if (controller == null) return;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (isClosed) return;
      await controller.showMarkerInfoWindow(const MarkerId('site'));
    } catch (_) {
      return;
    }
  }

  void _rebuildPolylines() {
    final selected = selectedRouteIndex.value;
    final routeColor =
        isDark ? const Color(0xFF56B7FF) : const Color(0xFF087CF4);
    final altColor =
        isDark ? const Color(0xFF8A9BB0) : const Color(0xFF8E9AAB);
    final ordered = <int>[
      for (var i = 0; i < routes.length; i++)
        if (i != selected) i,
      if (routes.isNotEmpty) selected,
    ];
    polylines.assignAll({
      for (final i in ordered)
        Polyline(
          polylineId: PolylineId('route_$i'),
          points: routes[i].points,
          color: i == selected ? routeColor : altColor,
          width: i == selected ? 8 : 5,
          zIndex: i == selected ? 3 : 1,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          consumeTapEvents: true,
          onTap: () => selectRoute(i),
        ),
    });
  }

  Future<void> _fitToRoutes() async {
    final controller = _mapController;
    if (controller == null) return;
    final points = <LatLng>[
      site,
      if (_origin != null) _origin!,
      ...routes.expand((route) => route.points),
    ];
    if (points.isEmpty) return;
    try {
      if (points.length == 1) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(points.first, 15),
        );
        return;
      }
      var minLat = points.first.latitude;
      var maxLat = points.first.latitude;
      var minLng = points.first.longitude;
      var maxLng = points.first.longitude;
      for (final point in points) {
        minLat = point.latitude < minLat ? point.latitude : minLat;
        maxLat = point.latitude > maxLat ? point.latitude : maxLat;
        minLng = point.longitude < minLng ? point.longitude : minLng;
        maxLng = point.longitude > maxLng ? point.longitude : maxLng;
      }
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          72,
        ),
      );
    } catch (_) {
      return;
    }
  }

  Future<({List<DispatchMapsRouteOption> options, String? error})>
      _fetchGoogleDirectionsAlternatives(
    LatLng origin,
    LatLng destination,
  ) async {
    final url =
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&mode=driving'
        '&alternatives=true'
        '&departure_time=now'
        '&traffic_model=best_guess'
        '&key=${GoogleMapsConfig.apiKey}';
    try {
      final response = await Dio().get<dynamic>(
        url,
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      if (response.statusCode != 200 || response.data == null) {
        return (options: const <DispatchMapsRouteOption>[], error: 'Route request failed');
      }
      final body = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : Map<String, dynamic>.from(response.data as Map);
      final status = body['status'] as String? ?? 'UNKNOWN';
      if (status != 'OK') {
        final message = body['error_message'] as String?;
        return (
          options: const <DispatchMapsRouteOption>[],
          error: message == null || message.isEmpty
              ? 'Directions unavailable ($status)'
              : message,
        );
      }
      final routesJson = body['routes'] as List<dynamic>?;
      if (routesJson == null || routesJson.isEmpty) {
        return (
          options: const <DispatchMapsRouteOption>[],
          error: 'No driving routes found',
        );
      }
      final options = <DispatchMapsRouteOption>[];
      for (final raw in routesJson) {
        final route = Map<String, dynamic>.from(raw as Map);
        final legs = route['legs'] as List<dynamic>?;
        var meters = 0.0;
        var seconds = 0;
        final detailedPoints = <LatLng>[];
        if (legs != null) {
          for (final legRaw in legs) {
            final leg = Map<String, dynamic>.from(legRaw as Map);
            meters +=
                ((leg['distance'] as Map?)?['value'] as num?)?.toDouble() ??
                    0;
            final trafficSeconds =
                ((leg['duration_in_traffic'] as Map?)?['value'] as num?)
                    ?.toInt();
            final baseSeconds =
                ((leg['duration'] as Map?)?['value'] as num?)?.toInt() ?? 0;
            seconds += trafficSeconds ?? baseSeconds;
            final steps = leg['steps'] as List<dynamic>?;
            if (steps == null) continue;
            for (final stepRaw in steps) {
              final step = Map<String, dynamic>.from(stepRaw as Map);
              final poly = step['polyline'] as Map<String, dynamic>?;
              final encoded = poly?['points'] as String?;
              if (encoded == null || encoded.isEmpty) continue;
              final decoded = _decodePolyline(encoded);
              if (detailedPoints.isNotEmpty && decoded.isNotEmpty) {
                final last = detailedPoints.last;
                final first = decoded.first;
                if ((last.latitude - first.latitude).abs() < 1e-8 &&
                    (last.longitude - first.longitude).abs() < 1e-8) {
                  detailedPoints.addAll(decoded.skip(1));
                  continue;
                }
              }
              detailedPoints.addAll(decoded);
            }
          }
        }
        var points = detailedPoints;
        if (points.length < 2) {
          final overview =
              route['overview_polyline'] as Map<String, dynamic>?;
          final encoded = overview?['points'] as String?;
          if (encoded == null || encoded.isEmpty) continue;
          points = _decodePolyline(encoded);
        }
        if (points.length < 2) continue;
        options.add(
          DispatchMapsRouteOption(
            points: points,
            distanceMeters: meters > 0 ? meters : _pathMeters(points),
            durationSeconds: seconds,
            summary: (route['summary'] as String?)?.trim() ?? '',
          ),
        );
      }
      return (options: options, error: null);
    } catch (_) {
      return (
        options: const <DispatchMapsRouteOption>[],
        error: 'Could not load alternate routes',
      );
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

  void _onResponseSecondsChanged() {
    if (!DispatchRequestConfig.openExpiredOnTimerEnd) return;
    final seconds = responseSecondsLeft?.value;
    if (seconds == null || seconds > 0 || _closingForExpire || isClosed) {
      return;
    }
    _closingForExpire = true;
    final close = onExpireClose;
    if (close != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isClosed) close();
      });
    }
  }

  Future<void> handleAccept(BuildContext context) async {
    closeLayersMenu();
    if (accepted.value) {
      await openGoogleNavigation(context);
      return;
    }
    accepted.value = true;
    showResponseActions.value = false;
    final accept = onAccept;
    if (accept != null) {
      await accept();
    }
    if (isClosed || !context.mounted) return;
    Navigator.of(context).maybePop(true);
  }

  Future<void> openGoogleNavigation(BuildContext context) async {
    closeLayersMenu();
    if (!context.mounted) return;
    await DispatchActiveSessionStore.markNavigationStarted();
    if (!context.mounted) return;
    await DispatchGoogleNavigationScreen.open(
      context,
      site: site,
      siteName: siteName,
      siteSubtitle: siteSubtitle,
      initialOrigin: _origin ?? initialOrigin,
      isDark: isDark || Theme.of(context).brightness == Brightness.dark,
      replace: true,
    );
  }

  Future<void> handleDecline(BuildContext context) async {
    closeLayersMenu();
    final decline = onDecline;
    await Navigator.of(context).maybePop(false);
    if (decline != null) {
      await decline();
    }
  }

  void closeMap(BuildContext context) {
    closeLayersMenu();
    Navigator.of(context).maybePop(accepted.value);
  }
}
