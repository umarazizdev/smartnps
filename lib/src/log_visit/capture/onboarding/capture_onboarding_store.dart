import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utilities/app_version_info.dart';

class CaptureOnboardingStore {
  CaptureOnboardingStore._();

  static final CaptureOnboardingStore instance = CaptureOnboardingStore._();

  static const String prefsKey = 'capture.onboarding.completed_version';

  static const List<String> _legacyBoolKeys = <String>[
    'capture.onboarding.completed.v1',
    'capture.onboarding.completed.v2',
  ];

  Future<SharedPreferences>? _prefsFuture;
  String? _cachedCompletedVersion;

  Future<SharedPreferences> _prefs() {
    return _prefsFuture ??= SharedPreferences.getInstance();
  }

  Future<String> _currentVersionToken() async {
    await AppVersionInfo.init();
    return '${AppVersionInfo.version}+${AppVersionInfo.buildNumber}';
  }

  Future<bool> shouldShow() async {
    try {
      final token = await _currentVersionToken();
      if (_cachedCompletedVersion == token) return false;

      final prefs = await _prefs();
      await _clearLegacyFlags(prefs);

      final stored = prefs.getString(prefsKey);
      final completed = stored == token;
      if (completed) {
        _cachedCompletedVersion = token;
      }
      return !completed;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[CaptureOnboarding] shouldShow failed: $error');
      }
      return false;
    }
  }

  Future<void> markCompleted() async {
    try {
      final token = await _currentVersionToken();
      if (_cachedCompletedVersion == token) return;

      final prefs = await _prefs();
      await prefs.setString(prefsKey, token);
      await _clearLegacyFlags(prefs);
      _cachedCompletedVersion = token;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[CaptureOnboarding] markCompleted failed: $error');
      }
    }
  }

  Future<void> reset() async {
    try {
      final prefs = await _prefs();
      await prefs.remove(prefsKey);
      await _clearLegacyFlags(prefs);
      _cachedCompletedVersion = null;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[CaptureOnboarding] reset failed: $error');
      }
    }
  }

  Future<void> _clearLegacyFlags(SharedPreferences prefs) async {
    for (final key in _legacyBoolKeys) {
      if (prefs.containsKey(key)) {
        await prefs.remove(key);
      }
    }
  }
}
