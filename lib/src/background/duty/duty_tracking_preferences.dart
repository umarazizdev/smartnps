import 'package:flutter/foundation.dart';

import '../../utilities/secure_storage_access.dart';
import 'duty_status_snapshot.dart';
import 'location_disclosure_consent.dart';

class DutyTrackingPreferences {
  DutyTrackingPreferences._();

  static const _kSettingsPromptDeferred = 'duty.settings_prompt_deferred';
  static const _kBgLocationReady = 'duty.bg_location_ready';

  static Future<bool> isDisclosureAccepted() {
    return LocationDisclosureConsent.isDutyAccepted();
  }

  static Future<void> setDisclosureAccepted() {
    return LocationDisclosureConsent.markDutyAccepted();
  }

  static Future<bool> isSettingsPromptDeferred() async {
    return (await SecureStorageAccess.read(_kSettingsPromptDeferred)) == '1';
  }

  static Future<void> setSettingsPromptDeferred() async {
    await SecureStorageAccess.write(_kSettingsPromptDeferred, '1');
    if (kDebugMode) {
      debugPrint('[DutyTrackingPreferences] settings prompt deferred (stored)');
    }
  }

  static Future<void> clearSettingsPromptDeferred() async {
    await SecureStorageAccess.delete(_kSettingsPromptDeferred);
  }

  static Future<bool> isBgLocationReady() async {
    return (await SecureStorageAccess.read(_kBgLocationReady)) == '1';
  }

  static Future<void> setBgLocationReady() async {
    if (await isBgLocationReady()) return;
    await SecureStorageAccess.write(_kBgLocationReady, '1');
    await clearSettingsPromptDeferred();
    if (kDebugMode) {
      debugPrint('[DutyTrackingPreferences] bg location ready (stored)');
    }
  }

  static Future<void> clearBgLocationReady() async {
    await SecureStorageAccess.delete(_kBgLocationReady);
    if (kDebugMode) {
      debugPrint('[DutyTrackingPreferences] bg location ready cleared');
    }
  }

  static Future<void> clearOnOffDuty() async {
    await SecureStorageAccess.delete(_kSettingsPromptDeferred);
    await SecureStorageAccess.delete(_kBgLocationReady);
    await DutyStatusSnapshot.clear();
    if (kDebugMode) {
      debugPrint('[DutyTrackingPreferences] cleared per-shift state on off duty');
    }
  }
}
