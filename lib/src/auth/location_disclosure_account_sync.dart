import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../background/clock_in_gate_service.dart';
import '../background/location_disclosure_consent.dart';
import '../logvisitscreen/visit_gps_session.dart';
import '../logvisitscreen/visit_video_flow_controller.dart';

class LocationDisclosureAccountSync {
  LocationDisclosureAccountSync._();

  static Future<void> onLoginResolved() async {
    await LocationDisclosureConsent.ensureMigrated();
    await LocationDisclosureConsent.reconcileFromOsIfBackgroundReady();
    if (Get.isRegistered<VisitVideoFlowController>()) {
      await Get.find<VisitVideoFlowController>().reloadForAccountChange();
    }
    if (kDebugMode) {
      debugPrint('[VisitDraft] drafts reloaded after login');
    }
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
