import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'dispatch_active_session.dart';
import 'dispatch_live_marker_style_store.dart';
import 'live_map_marker_bitmap.dart';
import 'live_map_marker_style.dart';

class DispatchGoogleNavigationController extends GetxController {
  DispatchGoogleNavigationController({
    required this.site,
    this.siteName,
    this.siteSubtitle,
    this.initialOrigin,
    this.isDark = false,
  });

  static const double arrivalRadiusMeters = 50;

  final gmaps.LatLng site;
  final String? siteName;
  final String? siteSubtitle;
  final gmaps.LatLng? initialOrigin;
  final bool isDark;

  NavigationForceNightMode get forceNightMode => isDark
      ? NavigationForceNightMode.forceNight
      : NavigationForceNightMode.forceDay;

  MapColorScheme get mapColorScheme =>
      isDark ? MapColorScheme.dark : MapColorScheme.light;

  final sessionReady = false.obs;
  final guidanceStarted = false.obs;
  final soundEnabled = true.obs;
  final showMarkerPicker = false.obs;
  final selectedMarkerStyle = DispatchLiveMarkerStyleStore.current.obs;
  final errorMessage = RxnString();
  final shouldClose = false.obs;

  GoogleNavigationViewController? _viewController;
  StreamSubscription<RoadSnappedLocationUpdatedEvent>? _locationSub;
  StreamSubscription<OnArrivalEvent>? _arrivalSub;
  bool _startingRoute = false;
  bool _hasFix = false;
  bool _finishingArrival = false;
  EdgeInsets _safePadding = EdgeInsets.zero;
  double _devicePixelRatio = 2;
  double _markerLogicalSize = LiveMapMarkerStyle.baseLogicalSize;

  ImageDescriptor? _selfIcon;
  Marker? _selfMarker;
  LatLng? _lastSelfLocation;
  double _selfBearing = 0;

  LatLng get initialCameraTarget {
    final origin = initialOrigin;
    if (origin == null) {
      return LatLng(latitude: site.latitude, longitude: site.longitude);
    }
    return LatLng(latitude: origin.latitude, longitude: origin.longitude);
  }

  String get destinationTitle {
    final name = siteName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Dispatch site';
  }

  bool get _useCustomSelfPin =>
      selectedMarkerStyle.value != LiveMapMarkerStyle.gpsDot;

  @override
  void onInit() {
    super.onInit();
    unawaited(bootstrap());
  }

  @override
  void onClose() {
    unawaited(_locationSub?.cancel());
    _locationSub = null;
    unawaited(_arrivalSub?.cancel());
    _arrivalSub = null;
    unawaited(_clearCustomMarkers());
    _viewController = null;
    if (sessionReady.value && !_finishingArrival) {
      unawaited(_cleanupSession());
    }
    super.onClose();
  }

  Future<void> _cleanupSession() async {
    try {
      await GoogleMapsNavigator.cleanup();
    } on SessionNotInitializedException {
      return;
    } catch (_) {
      return;
    } finally {
      sessionReady.value = false;
      guidanceStarted.value = false;
    }
  }

  Future<void> _listenForArrival() async {
    await _arrivalSub?.cancel();
    _arrivalSub = GoogleMapsNavigator.setOnArrivalListener((_) {
      unawaited(completeArrival());
    });
  }

  Future<void> completeArrival() async {
    if (_finishingArrival || isClosed || shouldClose.value) return;
    _finishingArrival = true;
    showMarkerPicker.value = false;

    await DispatchActiveSessionStore.clear();
    if (isClosed) return;

    try {
      await GoogleMapsNavigator.stopGuidance();
    } catch (_) {}
    try {
      await GoogleMapsNavigator.clearDestinations();
    } catch (_) {}
    await _clearCustomMarkers();
    await _cleanupSession();
    if (isClosed) return;
    shouldClose.value = true;
  }

  Future<void> bootstrap() async {
    errorMessage.value = null;
    guidanceStarted.value = false;
    _hasFix = false;
    await DispatchLiveMarkerStyleStore.ensureLoaded();
    if (isClosed) return;
    selectedMarkerStyle.value = DispatchLiveMarkerStyleStore.current;
    final location = await Permission.locationWhenInUse.request();
    if (isClosed) return;
    if (!location.isGranted) {
      errorMessage.value = 'Location permission is required for navigation.';
      return;
    }

    try {
      final termsOk = await GoogleMapsNavigator.areTermsAccepted() ||
          await GoogleMapsNavigator.showTermsAndConditionsDialog(
            'SmartNPS360 Navigation',
            'SmartNPS360',
          );
      if (isClosed) return;
      if (!termsOk) {
        errorMessage.value = 'Navigation terms were not accepted.';
        return;
      }

      if (!sessionReady.value) {
        await GoogleMapsNavigator.initializeNavigationSession(
          taskRemovedBehavior: TaskRemovedBehavior.continueService,
        );
        if (isClosed) return;
        sessionReady.value = true;
      }
      await _listenForArrival();
      if (isClosed) return;
      errorMessage.value = null;
      await _waitForLocationThenRoute();
    } catch (e) {
      if (isClosed) return;
      errorMessage.value = 'Could not start navigation: $e';
    }
  }

  Future<void> retry() async {
    errorMessage.value = null;
    await bootstrap();
  }

  Future<void> _waitForLocationThenRoute() async {
    if (guidanceStarted.value || _startingRoute) return;
    _startingRoute = true;
    try {
      await _locationSub?.cancel();
      final ready = Completer<void>();
      _locationSub =
          await GoogleMapsNavigator.setRoadSnappedLocationUpdatedListener((
            event,
          ) {
            _hasFix = true;
            unawaited(_onRoadSnappedLocation(event.location));
            if (!ready.isCompleted) ready.complete();
          });
      if (!_hasFix) {
        await ready.future.timeout(const Duration(seconds: 20));
      }
      if (isClosed) return;
      await _startGuidanceToSite();
    } on TimeoutException {
      if (isClosed) return;
      errorMessage.value = 'Waiting for GPS timed out. Try again.';
    } catch (e) {
      if (isClosed) return;
      errorMessage.value = 'Could not acquire location: $e';
    } finally {
      _startingRoute = false;
    }
  }

  Destinations _siteDestinations() {
    return Destinations(
      waypoints: [
        NavigationWaypoint.withLatLngTarget(
          title: destinationTitle,
          target: LatLng(
            latitude: site.latitude,
            longitude: site.longitude,
          ),
        ),
      ],
      displayOptions: NavigationDisplayOptions(
        showDestinationMarkers: true,
      ),
    );
  }

  Future<void> _startGuidanceToSite() async {
    if (guidanceStarted.value) return;
    var status = await GoogleMapsNavigator.setDestinations(_siteDestinations());
    if (isClosed) return;
    if (status == NavigationRouteStatus.locationUnavailable) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (isClosed) return;
      status = await GoogleMapsNavigator.setDestinations(_siteDestinations());
      if (isClosed) return;
    }
    if (status != NavigationRouteStatus.statusOk) {
      errorMessage.value = 'Route failed (${status.name}).';
      return;
    }
    await GoogleMapsNavigator.startGuidance();
    await _enableNavigationUi(follow: true);
    await _ensureCustomPins();
    if (isClosed) return;
    guidanceStarted.value = true;
    errorMessage.value = null;
    await _refreshNavigationChrome();
  }

  Future<void> _refreshNavigationChrome() async {
    final controller = _viewController;
    if (controller == null || isClosed) return;
    try {
      await controller.setNavigationFooterEnabled(true);
      await controller.setNavigationHeaderEnabled(true);
      await _applySafePadding();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (isClosed || _viewController == null) return;
      await _viewController!.setNavigationFooterEnabled(true);
      await _applySafePadding();
    } catch (_) {
      return;
    }
  }

  Future<void> onViewCreated(
    GoogleNavigationViewController controller, {
    required EdgeInsets safePadding,
    required double devicePixelRatio,
    required double markerLogicalSize,
  }) async {
    _viewController = controller;
    _safePadding = safePadding;
    _devicePixelRatio = devicePixelRatio;
    _markerLogicalSize = markerLogicalSize;
    try {
      await _applySafePadding();
      await controller.setForceNightMode(forceNightMode);
      await controller.setMapColorScheme(mapColorScheme);
      await _enableNavigationUi(follow: guidanceStarted.value);
      await _ensureCustomPins();
    } catch (_) {
      return;
    }
  }

  Future<void> updateSafePadding(EdgeInsets padding) async {
    if (_safePadding == padding) return;
    _safePadding = padding;
    await _applySafePadding();
  }

  Future<void> _applySafePadding() async {
    final controller = _viewController;
    if (controller == null) return;
    try {
      await controller.setPadding(_safePadding);
    } catch (_) {
      return;
    }
  }

  Future<void> _enableNavigationUi({required bool follow}) async {
    final controller = _viewController;
    if (controller == null) return;
    await controller.setNavigationUIEnabled(true);
    await controller.setNavigationHeaderEnabled(true);
    await controller.setNavigationFooterEnabled(true);
    await controller.setNavigationTripProgressBarEnabled(false);
    await controller.setSpeedometerEnabled(true);
    await controller.setSpeedLimitIconEnabled(true);
    await controller.setRecenterButtonEnabled(false);
    await controller.setTrafficIncidentCardsEnabled(true);
    await controller.setTrafficPromptsEnabled(true);
    await controller.setReportIncidentButtonEnabled(false);
    await controller.settings.setMyLocationButtonEnabled(false);
    try {
      await controller.settings.setZoomControlsEnabled(false);
    } catch (_) {}
    await controller.settings.setCompassEnabled(false);
    await controller.setMyLocationEnabled(!_useCustomSelfPin);
    await controller.setForceNightMode(forceNightMode);
    await _applyAudioGuidance();
    await _applySafePadding();
    if (follow) {
      await controller.followMyLocation(CameraPerspective.tilted);
    }
  }

  Future<void> toggleSound() async {
    soundEnabled.value = !soundEnabled.value;
    await _applyAudioGuidance();
  }

  Future<void> _applyAudioGuidance() async {
    try {
      await GoogleMapsNavigator.setAudioGuidance(
        NavigationAudioGuidanceSettings(
          guidanceType: soundEnabled.value
              ? NavigationAudioGuidanceType.alertsAndGuidance
              : NavigationAudioGuidanceType.silent,
          isVibrationEnabled: soundEnabled.value,
        ),
      );
    } catch (_) {
      return;
    }
  }

  void toggleMarkerPicker() {
    showMarkerPicker.value = !showMarkerPicker.value;
  }

  void closeMarkerPicker() {
    showMarkerPicker.value = false;
  }

  Future<void> selectMarkerStyle(LiveMapMarkerStyle style) async {
    selectedMarkerStyle.value = style;
    selectedMarkerStyle.refresh();
    await DispatchLiveMarkerStyleStore.set(style);
    if (isClosed) return;
    _selfIcon = null;
    await _ensureCustomPins(forceReloadSelfIcon: true);
    if (isClosed) return;
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (isClosed) return;
    showMarkerPicker.value = false;
  }

  Future<ImageDescriptor> _registerStyleIcon(LiveMapMarkerStyle style) async {
    final bytes = await LiveMapMarkerBitmap.pngBytesForStyle(
      style,
      logicalSize: _markerLogicalSize,
      devicePixelRatio: _devicePixelRatio,
    );
    return registerBitmapImage(
      bitmap: ByteData.sublistView(bytes),
      imagePixelRatio: _devicePixelRatio.clamp(1.0, 4.0),
      width: _markerLogicalSize + (LiveMapMarkerBitmap.tapPadding * 2),
    );
  }

  Future<void> _ensureCustomPins({bool forceReloadSelfIcon = false}) async {
    final controller = _viewController;
    if (controller == null || isClosed) return;

    try {
      if (!_useCustomSelfPin) {
        await _removeSelfMarker();
        await controller.setMyLocationEnabled(true);
        return;
      }

      await controller.setMyLocationEnabled(false);
      if (_selfIcon == null || forceReloadSelfIcon) {
        _selfIcon = await _registerStyleIcon(selectedMarkerStyle.value);
      }

      final origin = _lastSelfLocation ??
          (initialOrigin == null
              ? null
              : LatLng(
                  latitude: initialOrigin!.latitude,
                  longitude: initialOrigin!.longitude,
                ));
      if (origin == null) return;

      if (_selfMarker == null) {
        final added = await controller.addMarkers([
          MarkerOptions(
            position: origin,
            icon: _selfIcon!,
            anchor: const MarkerAnchor(u: 0.5, v: 0.5),
            flat: true,
            rotation: selectedMarkerStyle.value.rotatesWithBearing
                ? _selfBearing
                : 0,
            zIndex: 3,
            consumeTapEvents: true,
          ),
        ]);
        if (added.isNotEmpty) _selfMarker = added.first;
      } else if (forceReloadSelfIcon) {
        final updated = _selfMarker!.copyWith(
          options: _selfMarker!.options.copyWith(
            icon: _selfIcon,
            rotation: selectedMarkerStyle.value.rotatesWithBearing
                ? _selfBearing
                : 0,
          ),
        );
        final result = await controller.updateMarkers([updated]);
        if (result.isNotEmpty) _selfMarker = result.first;
      }
    } catch (_) {
      return;
    }
  }

  Future<void> _onRoadSnappedLocation(LatLng location) async {
    final previous = _lastSelfLocation;
    if (previous != null &&
        selectedMarkerStyle.value.rotatesWithBearing) {
      final bearing = _bearingBetween(previous, location);
      if (bearing != null) _selfBearing = bearing;
    }
    _lastSelfLocation = location;
    if (guidanceStarted.value &&
        !_finishingArrival &&
        _metersToSite(location) <= arrivalRadiusMeters) {
      unawaited(completeArrival());
      return;
    }
    if (!_useCustomSelfPin) return;
    final controller = _viewController;
    final marker = _selfMarker;
    final icon = _selfIcon;
    if (controller == null || marker == null || icon == null) {
      await _ensureCustomPins();
      return;
    }
    try {
      final updated = marker.copyWith(
        options: marker.options.copyWith(
          position: location,
          icon: icon,
          rotation:
              selectedMarkerStyle.value.rotatesWithBearing ? _selfBearing : 0,
        ),
      );
      final result = await controller.updateMarkers([updated]);
      if (result.isNotEmpty) _selfMarker = result.first;
    } catch (_) {
      _selfMarker = null;
      await _ensureCustomPins();
    }
  }

  double _metersToSite(LatLng location) {
    return _metersBetween(
      location,
      LatLng(latitude: site.latitude, longitude: site.longitude),
    );
  }

  double _metersBetween(LatLng from, LatLng to) {
    const earthRadius = 6371000.0;
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLat = (to.latitude - from.latitude) * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double? _bearingBetween(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    if (_metersBetween(from, to) < 2) return null;
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  Future<void> _removeSelfMarker() async {
    final controller = _viewController;
    final marker = _selfMarker;
    if (controller == null || marker == null) {
      _selfMarker = null;
      return;
    }
    try {
      await controller.removeMarkers([marker]);
    } catch (_) {
      return;
    } finally {
      _selfMarker = null;
    }
  }

  Future<void> _clearCustomMarkers() async {
    final controller = _viewController;
    if (controller == null) return;
    try {
      await controller.clearMarkers();
    } catch (_) {
      return;
    } finally {
      _selfMarker = null;
    }
  }

  Future<void> showRouteOverview() async {
    final controller = _viewController;
    if (controller == null) return;
    try {
      await controller.showRouteOverview();
    } catch (_) {
      return;
    }
  }

  Future<void> recenter() async {
    final controller = _viewController;
    if (controller == null) return;
    try {
      await controller.followMyLocation(CameraPerspective.tilted);
    } catch (_) {
      return;
    }
  }
}
