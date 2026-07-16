import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../background/background_location_permissions.dart';
import '../background/clock_in_gate_service.dart';
import '../background/duty_tracking_preferences.dart';
import '../background/location_disclosure_consent.dart';
import 'app_version_info.dart';

/// Clears stale post-update flags and re-syncs location readiness from the OS.
///
/// Runs on both Android (Play / sideload updates) and iOS (TestFlight / App Store).
class AppUpgradeReconciler {
  AppUpgradeReconciler._();

  static const _storage = FlutterSecureStorage();
  static const _kLastSeenBuild = 'app.last_seen_build';

  static bool _storageReconcileDone = false;
  static bool _osReconcileDone = false;

  /// Call from [main] before [runApp].
  ///
  /// Safe without the native MethodChannel: migrates disclosure storage and
  /// clears stale duty flags after a build change on Android and iOS.
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
      if (kDebugMode) {
        debugPrint(
          '[AppUpgradeReconciler] build changed $lastSeenBuild -> $currentBuild '
          '(${Platform.isAndroid ? 'android' : 'ios'})',
        );
      }
    }

    await LocationDisclosureConsent.ensureMigrated();

    if (lastSeenBuild != currentBuild) {
      await _storage.write(key: _kLastSeenBuild, value: currentBuild);
    }
  }

  /// Call once the Flutter engine / Activity is ready (e.g. WebViewShell).
  ///
  /// On Android the settings MethodChannel is only available after
  /// [MainActivity.configureFlutterEngine], so OS permission reconcile
  /// must not run from [main].
  ///
  /// Safe to call repeatedly from resume; storage writes are idempotent.
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
