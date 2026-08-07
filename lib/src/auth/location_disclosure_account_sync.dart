import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../background/duty/clock_in_gate_service.dart';
import '../background/duty/location_disclosure_consent.dart';
import '../log_visit/flow/visit_gps_session.dart';
import '../log_visit/flow/visit_video_flow_controller.dart';

class LocationDisclosureAccountSync {
  LocationDisclosureAccountSync._();

  static Future<void>? _onLoginResolvedFuture;
  static Future<void>? _reconcileDisclosureFuture;

  static Future<void> onLoginResolved() async {
    final inFlight = _onLoginResolvedFuture;
    if (inFlight != null) return inFlight;

    final future = _onLoginResolvedImpl();
    _onLoginResolvedFuture = future;
    try {
      await future;
    } finally {
      if (identical(_onLoginResolvedFuture, future)) {
        _onLoginResolvedFuture = null;
      }
    }
  }

  static Future<void> reconcileDisclosureFromOs() async {
    final inFlight = _reconcileDisclosureFuture;
    if (inFlight != null) return inFlight;

    final future = _reconcileDisclosureFromOsImpl();
    _reconcileDisclosureFuture = future;
    try {
      await future;
    } finally {
      if (identical(_reconcileDisclosureFuture, future)) {
        _reconcileDisclosureFuture = null;
      }
    }
  }

  static Future<void> _onLoginResolvedImpl() async {
    await reconcileDisclosureFromOs();
    if (Get.isRegistered<VisitVideoFlowController>()) {
      await Get.find<VisitVideoFlowController>().reloadForAccountChange();
    }
    if (kDebugMode) {
      debugPrint('[VisitDraft] drafts reloaded after login');
    }
  }

  static Future<void> _reconcileDisclosureFromOsImpl() async {
    await LocationDisclosureConsent.ensureMigrated();
    await LocationDisclosureConsent.reconcileFromOsIfBackgroundReady();
  }

  static void onLoggedOut() {
    unawaited(VisitGpsSession.instance.stop());
    ClockInGateService.instance.clearGeoUnlock();
    unawaitedLogoutDraftReset();
  }

  static void unawaitedLogoutDraftReset() {
    Future<void>(() async {
      try {
        if (Get.isRegistered<VisitVideoFlowController>()) {
          await Get.find<VisitVideoFlowController>().resetForLogout();
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[VisitDraft] logout reset failed: $e');
        }
      }
    });
  }
}
