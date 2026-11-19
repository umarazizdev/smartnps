import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../push/notifications/push_notification_service.dart';
import 'dispatch_active_session.dart';
import 'dispatch_google_navigation_screen.dart';
import 'dispatch_request_data.dart';
import 'dispatch_route_metrics.dart';

class DispatchRequestController extends GetxController {
  DispatchRequestController({required this.request});

  static const String tag = 'dispatch-request';

  final DispatchRequestData request;

  final secondsLeft = 0.obs;
  final arrivalMinutes = 0.obs;
  final distanceMiles = 0.0.obs;
  final expired = false.obs;
  final declining = false.obs;
  final accepted = false.obs;
  final openingNavigation = false.obs;

  LatLng? routeOrigin;
  List<LatLng> routePoints = const [];

  Timer? _timer;
  bool _exitingAccepted = false;
  late final ValueNotifier<int> secondsLeftListenable;
  Worker? _secondsLeftWorker;

  @override
  void onInit() {
    super.onInit();
    secondsLeft.value = request.responseSeconds;
    arrivalMinutes.value = request.arrivalMinutes;
    distanceMiles.value = request.distanceMiles;
    secondsLeftListenable = ValueNotifier(request.responseSeconds);
    _secondsLeftWorker = ever<int>(secondsLeft, (value) {
      if (secondsLeftListenable.value != value) {
        secondsLeftListenable.value = value;
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isClosed) return;
      if (secondsLeft.value <= 1) {
        _timer?.cancel();
        secondsLeft.value = 0;
        unawaited(stopDispatchAlert());
        if (DispatchRequestConfig.openExpiredOnTimerEnd) {
          expired.value = true;
        }
      } else {
        secondsLeft.value--;
      }
    });
    unawaited(startDispatchAlert());
  }

  @override
  void onClose() {
    _timer?.cancel();
    _secondsLeftWorker?.dispose();
    secondsLeftListenable.dispose();
    unawaited(stopDispatchAlert());
    super.onClose();
  }

  Future<void> startDispatchAlert() async {
    try {
      final address = request.address.trim();
      await PushNotificationService.instance.startDispatchRequestAlert(
        title: 'Dispatch request',
        body: address.isEmpty
            ? 'New response request. Accept or decline now.'
            : 'Respond now: $address',
      );
    } catch (_) {}
  }

  Future<void> stopDispatchAlert() async {
    try {
      await PushNotificationService.instance.stopDispatchRequestAlert();
    } catch (_) {}
  }

  void applyMetrics(DispatchRouteMetrics metrics) {
    arrivalMinutes.value = metrics.arrivalMinutes;
    distanceMiles.value = metrics.distanceMiles;
  }

  void applyRouteSnapshot(LatLng? origin, List<LatLng> points) {
    routeOrigin = origin;
    routePoints = points;
  }

  Future<void> decline() async {
    _timer?.cancel();
    unawaited(stopDispatchAlert());
    declining.value = true;
  }

  Future<void> acceptAndOpenMap({
    required BuildContext context,
    bool launchNavigation = false,
    bool deferDashboardExit = false,
  }) async {
    if (!accepted.value) {
      _timer?.cancel();
      unawaited(stopDispatchAlert());
      accepted.value = true;
    }
    openingNavigation.value = launchNavigation || deferDashboardExit;
    await DispatchActiveSessionStore.save(
      request: request,
      origin: routeOrigin,
      routePoints: routePoints,
    );
    if (isClosed || !launchNavigation) return;
    if (!context.mounted) return;

    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      return;
    }

    await DispatchGoogleNavigationScreen.open(
      context,
      site: request.site,
      siteName: request.address,
      siteSubtitle: request.city,
      initialOrigin: routeOrigin,
      isDark: Theme.of(context).brightness == Brightness.dark,
      replace: true,
    );
  }

  bool consumeExitToDashboard() {
    if (!accepted.value ||
        declining.value ||
        expired.value ||
        openingNavigation.value) {
      return false;
    }
    if (_exitingAccepted) return true;
    _exitingAccepted = true;
    return true;
  }
}
