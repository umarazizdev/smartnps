import '../background/clock_in_gate_service.dart';
import '../background/duty_heartbeat_service.dart';
import '../background/location_disclosure_consent.dart';

/// Keeps in-memory disclosure state aligned with the logged-in officer account.
class LocationDisclosureAccountSync {
  LocationDisclosureAccountSync._();

  static Future<void> onLoginResolved() async {
    if (await LocationDisclosureConsent.resolveActiveOfficerAccount()) {
      _resetInMemoryDisclosureState();
    }
  }

  static void onLoggedOut() {
    LocationDisclosureConsent.clearActiveOfficerAccount();
    _resetInMemoryDisclosureState();
  }

  static void _resetInMemoryDisclosureState() {
    DutyHeartbeatService.instance.resetLocationDisclosureMemory();
    ClockInGateService.instance.resetLocationDisclosureMemory();
  }
}
