import '../background/clock_in_gate_service.dart';
import '../background/location_disclosure_consent.dart';

/// Keeps disclosure storage migrated; disclosure is device-wide (not per account).
class LocationDisclosureAccountSync {
  LocationDisclosureAccountSync._();

  static Future<void> onLoginResolved() async {
    await LocationDisclosureConsent.ensureMigrated();
    await LocationDisclosureConsent.reconcileFromOsIfBackgroundReady();
  }

  static void onLoggedOut() {
    ClockInGateService.instance.clearGeoUnlock();
  }
}
