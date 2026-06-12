import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// On-duty location consent state. Persisted across app restarts until off duty.
class DutyTrackingPreferences {
  DutyTrackingPreferences._();

  static const _storage = FlutterSecureStorage();

  static const _kDisclosureState = 'duty.disclosure_state';
  static const _kSettingsPromptDeferred = 'duty.settings_prompt_deferred';
  static const _kBgLocationReady = 'duty.bg_location_ready';

  static const String disclosureAccepted = 'accepted';
  static const String disclosureDismissed = 'dismissed';

  static Future<bool> isDisclosureAccepted() async {
    final state = await _storage.read(key: _kDisclosureState);
    return state == disclosureAccepted;
  }

  static Future<bool> isDisclosureDismissed() async {
    final state = await _storage.read(key: _kDisclosureState);
    return state == disclosureDismissed;
  }

  static Future<void> setDisclosureAccepted() async {
    await _storage.write(key: _kDisclosureState, value: disclosureAccepted);
    await _storage.delete(key: _kSettingsPromptDeferred);
    if (kDebugMode) {
      debugPrint('[DutyTrackingPreferences] disclosure accepted (stored)');
    }
  }

  static Future<void> setDisclosureDismissed() async {
    await _storage.write(key: _kDisclosureState, value: disclosureDismissed);
    if (kDebugMode) {
      debugPrint('[DutyTrackingPreferences] disclosure dismissed (stored)');
    }
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

  /// True once background location is sufficient for this on-duty session.
  static Future<bool> isBgLocationReady() async {
    return (await _storage.read(key: _kBgLocationReady)) == '1';
  }

  static Future<void> setBgLocationReady() async {
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
    await _storage.delete(key: _kDisclosureState);
    await _storage.delete(key: _kSettingsPromptDeferred);
    await _storage.delete(key: _kBgLocationReady);
    if (kDebugMode) {
      debugPrint('[DutyTrackingPreferences] cleared on off duty');
    }
  }
}
