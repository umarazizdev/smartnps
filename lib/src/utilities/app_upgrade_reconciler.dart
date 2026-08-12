import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../background/location/background_location_permissions.dart';
import '../background/duty/clock_in_gate_service.dart';
import '../background/duty/duty_tracking_preferences.dart';
import '../background/duty/location_disclosure_consent.dart';
import 'app_version_info.dart';

class AppUpgradeReconciler {
  AppUpgradeReconciler._();

  static const _storage = FlutterSecureStorage();
  static const _kLastSeenBuild = 'app.last_seen_build';

  static const Duration postUpgradeAuthGrace = Duration(minutes: 15);

  static bool _storageReconcileDone = false;
  static bool _osReconcileDone = false;
  static DateTime? _suppressRefreshLogoutUntil;

  static bool get shouldSuppressRefreshSessionLogout {
    final until = _suppressRefreshLogoutUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _suppressRefreshLogoutUntil = null;
    return false;
  }

  static void beginPostUpgradeAuthGrace() {
    _suppressRefreshLogoutUntil = DateTime.now().add(postUpgradeAuthGrace);
  }

  static void endPostUpgradeAuthGrace() {
    _suppressRefreshLogoutUntil = null;
  }

  static Future<void> reconcileIfNeeded() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_storageReconcileDone) return;
    _storageReconcileDone = true;

    final currentBuild = AppVersionInfo.buildNumber;
    final lastSeenBuild = await _storage.read(key: _kLastSeenBuild);
    final buildChanged =
        lastSeenBuild != null &&
        lastSeenBuild.isNotEmpty &&
        lastSeenBuild != currentBuild;

    if (buildChanged) {
      await DutyTrackingPreferences.clearBgLocationReady();
      await DutyTrackingPreferences.clearSettingsPromptDeferred();
      ClockInGateService.instance.clearGeoUnlock();
      beginPostUpgradeAuthGrace();
      if (kDebugMode) {
        debugPrint(
          '[AppUpgradeReconciler] build changed $lastSeenBuild -> $currentBuild '
          '(${Platform.isAndroid ? 'android' : 'ios'}; '
          'soft re-auth prompt suppressed for ${postUpgradeAuthGrace.inMinutes}m)',
        );
      }
    }

    await LocationDisclosureConsent.ensureMigrated();

    if (lastSeenBuild != currentBuild) {
      await _storage.write(key: _kLastSeenBuild, value: currentBuild);
    }
  }

  static Future<void> reconcileOsAfterEngineReady() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    await LocationDisclosureConsent.ensureMigrated();
    await BackgroundLocationPermissions.refreshPermissionStateFromOs();
    await LocationDisclosureConsent.reconcileFromOsIfBackgroundReady();
    if (!_osReconcileDone && kDebugMode) {
      debugPrint(
        '[AppUpgradeReconciler] OS disclose reconcile done '
        '(${Platform.isAndroid ? 'android' : 'ios'})',
      );
    }
    _osReconcileDone = true;
  }
}
