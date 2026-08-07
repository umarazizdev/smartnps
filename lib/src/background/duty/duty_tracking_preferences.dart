import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'location_disclosure_consent.dart';

class DutyTrackingPreferences {
  DutyTrackingPreferences._();

  static const _storage = FlutterSecureStorage();

  static const _kSettingsPromptDeferred = 'duty.settings_prompt_deferred';
  static const _kBgLocationReady = 'duty.bg_location_ready';

  static Future<bool> isDisclosureAccepted() {
    return LocationDisclosureConsent.isDutyAccepted();
  }

  static Future<void> setDisclosureAccepted() {
    return LocationDisclosureConsent.markDutyAccepted();
  }

  static Future<bool> isSettingsPromptDeferred() async {
    return (await _storage.read(key: _kSettingsPromptDeferred)) == '1';
  }

  static Future<void> setSettingsPromptDeferred() async {
    await _storage.write(key: _kSettingsPromptDeferred, value: '1');
    if (kDebugMode) {
      debugPrint('[DutyTrackingPreferences] settings prompt deferred (stored)');
    }
  }

  static Future<void> clearSettingsPromptDeferred() async {
    await _storage.delete(key: _kSettingsPromptDeferred);
  }

  static Future<bool> isBgLocationReady() async {
    return (await _storage.read(key: _kBgLocationReady)) == '1';
  }

  static Future<void> setBgLocationReady() async {
    if (await isBgLocationReady()) return;
    await _storage.write(key: _kBgLocationReady, value: '1');
    await clearSettingsPromptDeferred();
    if (kDebugMode) {
      debugPrint('[DutyTrackingPreferences] bg location ready (stored)');
    }
  }

  static Future<void> clearBgLocationReady() async {
    await _storage.delete(key: _kBgLocationReady);
    if (kDebugMode) {
      debugPrint('[DutyTrackingPreferences] bg location ready cleared');
    }
  }

  static Future<void> clearOnOffDuty() async {
    await _storage.delete(key: _kSettingsPromptDeferred);
    await _storage.delete(key: _kBgLocationReady);
    if (kDebugMode) {
      debugPrint('[DutyTrackingPreferences] cleared per-shift state on off duty');
    }
  }
}
