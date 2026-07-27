import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../auth/auth_repository.dart';
import '../background/background_location_permissions.dart';
import '../push/push_notification_preferences.dart';
import 'os_notification_permission.dart';
import '../utilities/app_config.dart';
import '../utilities/app_version_info.dart';
import '../utilities/device_identity.dart';

/// Store-safe OS permission snapshot for the native-app permission-status API.
///
/// Read-only: never requests permissions, only reports current OS state.
class NativePermissionStatusService {
  NativePermissionStatusService._() {
    _settingsChannel.setMethodCallHandler(_handleSettingsMethodCall);
  }

  static final NativePermissionStatusService instance =
      NativePermissionStatusService._();

  static const MethodChannel _settingsChannel = MethodChannel(
    'com.smartnps360.app/settings',
  );

  /// Legacy Keychain keys — cleared once so uninstall leftovers cannot remap.
  static const FlutterSecureStorage _legacySecureStorage =
      FlutterSecureStorage();

  /// App-local history flags (SharedPreferences). Cleared on uninstall, unlike
  /// iOS Keychain, so a fresh install reports `unknown` until the user acts.
  /// Device-wide flag: background location was granted at least once.
  /// Used so a later revoke reports API `denied` instead of `unknown`.
  static const String _kBackgroundLocationEverGranted =
      'permission.background_location.ever_granted.v1';

  /// Device-wide flag: officer declined enabling background location
  /// (e.g. Cancel on Open Settings) — even on first prompt.
  static const String _kBackgroundLocationUserDenied =
      'permission.background_location.user_denied.v1';

  /// Device-wide flag: foreground location was granted at least once
  /// (While using, Always, or Allow only this time). Revoke → API denied.
  static const String _kForegroundLocationEverGranted =
      'permission.foreground_location.ever_granted.v1';

  /// Device-wide flag: officer tapped Don't Allow on the foreground OS dialog.
  static const String _kForegroundLocationUserDenied =
      'permission.foreground_location.user_denied.v1';

  /// iOS only: whenInUse survived a real background (paused/hidden → resumed),
  /// so it is lasting "While Using" — not temporary "Allow Once".
  static const String _kIosForegroundLastingConfirmed =
      'permission.ios_foreground_lasting_confirmed.v1';
  static const String _kLegacyKeychainCleared =
      'permission.location_history.legacy_keychain_cleared.v1';
  static const Duration _appCycleDebounce = Duration(milliseconds: 350);
  static const Duration _batteryMonitorInterval = Duration(minutes: 5);

  Future<SharedPreferences>? _prefsFuture;
  bool _legacyKeychainCleanupStarted = false;

  Future<SharedPreferences> _prefs() {
    return _prefsFuture ??= SharedPreferences.getInstance();
  }

  /// Drop stale iOS Keychain history so it cannot affect a reinstall/upgrade.
  Future<void> _clearLegacyKeychainHistoryIfNeeded() async {
    if (_legacyKeychainCleanupStarted) return;
    _legacyKeychainCleanupStarted = true;
    try {
      final prefs = await _prefs();
      if (prefs.getBool(_kLegacyKeychainCleared) == true) return;
      await Future.wait([
        _legacySecureStorage.delete(key: _kBackgroundLocationEverGranted),
        _legacySecureStorage.delete(key: _kBackgroundLocationUserDenied),
        _legacySecureStorage.delete(key: _kForegroundLocationEverGranted),
        _legacySecureStorage.delete(key: _kForegroundLocationUserDenied),
      ]);
      await prefs.setBool(_kLegacyKeychainCleared, true);
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] cleared legacy Keychain location-history',
        );
      }
    } catch (error) {
      _legacyKeychainCleanupStarted = false;
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] legacy Keychain cleanup failed: $error',
        );
      }
    }
  }

  String? _lastPayloadFingerprint;
  String? _lastAppCycle;
  String? _pendingAppCycle;
  Future<bool>? _appCycleUploadInFlight;
  Timer? _batteryMonitorTimer;
  int? _lastUploadedBatteryPercentage;
  bool _batteryUploadInFlight = false;
  bool _batteryMonitoringActive = false;
  Future<void> _uploadSerial = Future<void>.value();
  bool _syncCoalescePending = false;
  bool _syncForceNext = false;
  Future<bool>? _syncInFlight;

  /// Prefer one POST: if mark-denied lands while app_cycle is queued, sync after.
  bool _deferredSyncAfterAppCycle = false;

  /// Optional listener for live OS permission changes (blocker UI).
  VoidCallback? _onOsPermissionChanged;

  void setOnOsPermissionChanged(VoidCallback? callback) {
    _onOsPermissionChanged = callback;
  }

  void resetSyncState() {
    stopBatteryMonitoring();
    _lastPayloadFingerprint = null;
    _lastAppCycle = null;
    _pendingAppCycle = null;
    _appCycleUploadInFlight = null;
    _lastUploadedBatteryPercentage = null;
    _syncCoalescePending = false;
    _syncForceNext = false;
    _syncInFlight = null;
    _deferredSyncAfterAppCycle = false;
  }

  Future<Map<String, dynamic>> buildPayload() async {
    return {
      'platform': DeviceIdentity.platformName(),
      'deviceId': await DeviceIdentity.getDeviceId(),
      'appVersion': AppVersionInfo.version,
      'build': AppVersionInfo.buildNumber,
      'battery_percentage': await _batteryPercentage(),
      'low_power_mode': await _lowPowerModeStatus(),
      'permissions': await _readPermissions(),
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<dynamic> _handleSettingsMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'lowPowerModeChanged':
        if (kDebugMode) {
          debugPrint(
            '[NativePermissionStatus] low_power_mode changed ${call.arguments}',
          );
        }
        unawaited(syncIfChanged());
        return null;
      case 'backgroundAppRefreshChanged':
        if (kDebugMode) {
          debugPrint(
            '[NativePermissionStatus] backgroundAppRefresh changed ${call.arguments}',
          );
        }
        unawaited(syncIfChanged());
        // Keep the logged-in permission blocker in sync without waiting for resume.
        // ignore: avoid_dynamic_calls — soft dependency via callback.
        _onOsPermissionChanged?.call();
        return null;
      default:
        throw MissingPluginException('No handler for ${call.method}');
    }
  }

  /// Starts conservative live battery uploads while the app is active.
  void startBatteryMonitoring({bool uploadImmediately = true}) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    unawaited(
      _startBatteryMonitoringImpl(uploadImmediately: uploadImmediately),
    );
  }

  Future<void> _startBatteryMonitoringImpl({
    required bool uploadImmediately,
  }) async {
    if (!await AuthRepository.instance.isOfficerLoggedIn()) {
      stopBatteryMonitoring();
      return;
    }

    _batteryMonitoringActive = true;
    if (_batteryMonitorTimer != null) return;

    if (uploadImmediately) {
      await _uploadBatteryIfChanged();
    }
    _batteryMonitorTimer = Timer.periodic(_batteryMonitorInterval, (_) {
      unawaited(_uploadBatteryIfChanged());
    });
  }

  void stopBatteryMonitoring() {
    _batteryMonitoringActive = false;
    _batteryMonitorTimer?.cancel();
    _batteryMonitorTimer = null;
  }

  /// App resume / Settings return: re-read live OS location flags and ensure
  /// they reach the permission-status API (via pending app_cycle or a follow-up).
  Future<bool> syncLocationPermissionsOnResume() {
    return ensureLatestPermissionsSynced(settleMs: 80);
  }

  /// Refresh OS permissions and upload if needed — without double-POST:
  /// - If an app_cycle upload is pending/in-flight, refresh now and schedule a
  ///   follow-up sync after it (only uploads when the snapshot still differs).
  /// - Otherwise syncIfChanged immediately.
  Future<bool> ensureLatestPermissionsSynced({int settleMs = 0}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    if (settleMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: settleMs));
    }
    await BackgroundLocationPermissions.refreshPermissionStateFromOs();
    if (Platform.isAndroid && kDebugMode) {
      final oneTime = await _isAndroidOneTimeLocationPermission();
      debugPrint(
        '[NativePermissionStatus] ensureLatest refresh '
        'oneTime=$oneTime foreground will map '
        '${oneTime ? 'denied' : 'from OS'}',
      );
    }

    if (_pendingAppCycle != null || _appCycleUploadInFlight != null) {
      _deferredSyncAfterAppCycle = true;
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] ensureLatest coalesced into app_cycle '
          '(follow-up sync scheduled if still changed)',
        );
      }
      return false;
    }
    return syncIfChanged();
  }

  /// Builds a fresh OS permission snapshot and uploads when it differs from
  /// the last successful upload (or always when [force] is true).
  /// Returns true when an upload was attempted and succeeded.
  ///
  /// [bypassAppCycleCoalesce] is for the post-app_cycle follow-up only — the
  /// drain task still holds `_appCycleUploadInFlight` while that runs.
  Future<bool> syncIfChanged({
    bool force = false,
    bool bypassAppCycleCoalesce = false,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    final accessToken = await _accessTokenForLoggedInOfficer();
    if (accessToken == null || accessToken.isEmpty) return false;

    // Non-forced syncs ride along with an in-flight/pending app_cycle POST
    // so resume + permission sync do not double-hit the same endpoint.
    if (!force &&
        !bypassAppCycleCoalesce &&
        (_pendingAppCycle != null || _appCycleUploadInFlight != null)) {
      _deferredSyncAfterAppCycle = true;
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] skip syncIfChanged '
          '(coalesced into app_cycle; follow-up if still changed)',
        );
      }
      await BackgroundLocationPermissions.refreshPermissionStateFromOs();
      return false;
    }

    if (force) _syncForceNext = true;

    final inFlight = _syncInFlight;
    if (inFlight != null) {
      _syncCoalescePending = true;
      if (force) _syncForceNext = true;
      return inFlight;
    }

    final task = _runSyncIfChanged();
    _syncInFlight = task;
    try {
      return await task;
    } finally {
      if (identical(_syncInFlight, task)) {
        _syncInFlight = null;
      }
    }
  }

  Future<bool> _runSyncIfChanged() async {
    var didUpload = false;
    await _serialized(() async {
      do {
        _syncCoalescePending = false;
        final force = _syncForceNext;
        _syncForceNext = false;

        // Always sample the latest OS state before comparing.
        await BackgroundLocationPermissions.refreshPermissionStateFromOs();
        final payload = await buildPayload();
        final fingerprint = _fingerprint(payload);
        if (!force && fingerprint == _lastPayloadFingerprint) {
          if (kDebugMode) {
            debugPrint(
              '[NativePermissionStatus] skip upload (unchanged permissions)',
            );
          }
          continue;
        }

        if (kDebugMode) {
          debugPrint(
            '[NativePermissionStatus] uploading permissions '
            '(force=$force changed=${fingerprint != _lastPayloadFingerprint}) '
            'permissions=${payload['permissions']}',
          );
        }
        final uploaded = await _upload(payload);
        if (uploaded) {
          _lastPayloadFingerprint = fingerprint;
          didUpload = true;
        }
      } while (_syncCoalescePending);
    });
    return didUpload;
  }

  /// Posts in-app push toggle state to the permission-status API.
  Future<bool> uploadPushToggle({required bool enabled}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    final accessToken = await _accessTokenForLoggedInOfficer();
    if (accessToken == null || accessToken.isEmpty) return false;

    if (kDebugMode) {
      debugPrint(
        '[NativePermissionStatus] push state upload push=${enabled ? 'enabled' : 'disabled'}',
      );
    }
    return syncIfChanged(force: true);
  }

  /// Posts app lifecycle state with the same snapshot used by permission sync.
  Future<bool> uploadAppCycle({required String appCycle}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    if (!await AuthRepository.instance.isOfficerLoggedIn()) return false;

    _pendingAppCycle = appCycle;
    final inFlight = _appCycleUploadInFlight;
    if (inFlight != null) {
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] queued app_cycle upload $appCycle',
        );
      }
      return inFlight;
    }

    final task = _drainAppCycleUploads();
    _appCycleUploadInFlight = task;
    try {
      return await task;
    } finally {
      if (identical(_appCycleUploadInFlight, task)) {
        _appCycleUploadInFlight = null;
      }
    }
  }

  Future<bool> _drainAppCycleUploads() async {
    var ok = true;

    while (_pendingAppCycle != null) {
      await Future<void>.delayed(_appCycleDebounce);

      final appCycle = _pendingAppCycle;
      _pendingAppCycle = null;
      if (appCycle == null) continue;

      final uploaded = await _uploadAppCycleNow(appCycle);
      ok = ok && uploaded;
    }

    if (_deferredSyncAfterAppCycle) {
      _deferredSyncAfterAppCycle = false;
      // Flags / OS may have changed after the app_cycle snapshot. Upload only
      // if the permission map still differs (no duplicate when already sent).
      // bypass: we are still inside _appCycleUploadInFlight.
      await syncIfChanged(bypassAppCycleCoalesce: true);
    }

    return ok;
  }

  Future<bool> _uploadAppCycleNow(String appCycle) async {
    final accessToken = await _accessTokenForLoggedInOfficer();
    if (accessToken == null || accessToken.isEmpty) return false;

    var uploaded = false;
    await _serialized(() async {
      // After a real background, lasting While Using stays whenInUse; Allow Once
      // usually reverts to notDetermined. Confirm only on paused/hidden → resumed
      // (permission-dialog inactive → resumed must not confirm Allow Once).
      if (Platform.isIOS &&
          appCycle == 'resumed' &&
          (_lastAppCycle == 'paused' || _lastAppCycle == 'hidden')) {
        await _confirmIosForegroundLastingAfterRealBackground();
      }

      // Fresh OS sample so Settings toggles land in this single resume POST.
      await BackgroundLocationPermissions.refreshPermissionStateFromOs();
      final payload = await buildPayload();
      payload['app_cycle'] = appCycle;

      final fingerprint = _fingerprint(payload);
      final cycleChanged = appCycle != _lastAppCycle;
      final permissionsChanged = fingerprint != _lastPayloadFingerprint;

      if (!cycleChanged && !permissionsChanged) {
        if (kDebugMode) {
          debugPrint(
            '[NativePermissionStatus] skip app_cycle upload '
            '(unchanged cycle=$appCycle and permissions)',
          );
        }
        return;
      }

      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] app_cycle upload $appCycle '
          '(cycleChanged=$cycleChanged permissionsChanged=$permissionsChanged) '
          'permissions=${payload['permissions']}',
        );
      }
      uploaded = await _upload(payload);
      if (uploaded) {
        _lastAppCycle = appCycle;
        _lastPayloadFingerprint = fingerprint;
      }
    });
    return uploaded;
  }

  Future<void> _uploadBatteryIfChanged() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_batteryUploadInFlight) return;

    _batteryUploadInFlight = true;
    try {
      final accessToken = await _accessTokenForLoggedInOfficer();
      if (accessToken == null || accessToken.isEmpty) {
        stopBatteryMonitoring();
        return;
      }
      if (!_batteryMonitoringActive) return;

      final batteryPercentage = await _batteryPercentage();
      if (batteryPercentage == null ||
          batteryPercentage == _lastUploadedBatteryPercentage) {
        return;
      }
      if (!_batteryMonitoringActive) return;

      await _serialized(() async {
        if (!_batteryMonitoringActive) return;

        final payload = await buildPayload();
        payload['battery_percentage'] = batteryPercentage;

        if (kDebugMode) {
          debugPrint(
            '[NativePermissionStatus] battery upload $batteryPercentage%',
          );
        }
        final uploaded = await _upload(payload);
        if (uploaded) {
          _lastPayloadFingerprint = _fingerprint(payload);
        }
      });
    } finally {
      _batteryUploadInFlight = false;
    }
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _uploadSerial = _uploadSerial.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });
    return completer.future;
  }

  Future<String?> _accessTokenForLoggedInOfficer() async {
    if (!await AuthRepository.instance.isOfficerLoggedIn()) return null;
    return AuthRepository.instance.ensureValidAccessToken();
  }

  String _fingerprint(Map<String, dynamic> payload) {
    final copy = Map<String, dynamic>.from(payload)
      ..remove('app_cycle')
      ..remove('battery_percentage')
      ..remove('checkedAt');
    return jsonEncode(copy);
  }

  Future<Map<String, String>> _readPermissions() async {
    if (Platform.isAndroid) {
      await BackgroundLocationPermissions.refreshPermissionStateFromOs();
    } else if (Platform.isIOS) {
      await BackgroundLocationPermissions.refreshPermissionStateFromOs();
    }

    return {
      'foregroundLocation': await _foregroundLocationStatus(),
      'backgroundLocation': await _backgroundLocationStatus(),
      'preciseLocation': await _preciseLocationStatus(),
      'notifications': await _notificationStatus(),
      'batteryOptimization': await _batteryOptimizationStatus(),
      'backgroundAppRefresh': await _backgroundAppRefreshStatus(),
      'push': await _pushToggleStatus(),
    };
  }

  Future<String> _pushToggleStatus() async {
    if (!Platform.isAndroid && !Platform.isIOS) return 'disabled';
    final enabled = await PushNotificationPreferences.readEnabled();
    return enabled ? 'enabled' : 'disabled';
  }

  Future<String> _foregroundLocationStatus() async {
    if (!Platform.isAndroid && !Platform.isIOS) return 'unknown';

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return 'unknown';

    if (Platform.isAndroid) {
      final status = await Permission.location.status;
      // "Allow only this time" — track that location was seen, report denied.
      if (await _isAndroidOneTimeLocationPermission()) {
        await _markForegroundLocationEverGranted();
        await _clearForegroundLocationUserDenied();
        return 'denied';
      }
      if (status.isGranted || status.isLimited || status.isProvisional) {
        await _markForegroundLocationEverGranted();
        await _clearForegroundLocationUserDenied();
        return 'granted';
      }
      // Don't Allow / Settings revoke → denied (not unknown).
      return _resolveAndroidForegroundDeniedOrUnknown(status);
    }

    // iOS: While Using / Always → granted. "Ask Next Time Or When I Share"
    // resets to notDetermined (Geolocator: denied) → API denied after a prior
    // grant; first install stays unknown.
    return _resolveIosForegroundLocationApiStatus(
      await BackgroundLocationPermissions.readIosLocationPermission(),
    );
  }

  /// API-only iOS foregroundLocation mapping (does not change clock-in).
  ///
  /// While Using / Always → `granted`. Allow Once also appears as whenInUse
  /// while active, so it reports `granted` until it expires (then `denied`).
  /// `denied` only when OS access is actually denied / revoked.
  Future<String> _resolveIosForegroundLocationApiStatus(
    LocationPermission permission,
  ) async {
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      await _markForegroundLocationEverGranted();
      await _clearForegroundLocationUserDenied();
      if (permission == LocationPermission.always) {
        await _setIosForegroundLastingConfirmed(true);
      }
      return 'granted';
    }
    // Expired Allow Once / Ask Next Time → notDetermined (Geolocator: denied).
    await _setIosForegroundLastingConfirmed(false);
    if (permission == LocationPermission.deniedForever) {
      return 'denied';
    }
    if (await _hasForegroundLocationEverBeenGranted() ||
        await _hasForegroundLocationUserDenied()) {
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] iOS foregroundLocation=denied '
          '(Ask Next Time / When I Share or prior deny)',
        );
      }
      return 'denied';
    }
    return 'unknown';
  }

  Future<bool> _hasIosForegroundLastingConfirmed() {
    return _readHistoryFlag(_kIosForegroundLastingConfirmed);
  }

  Future<void> _setIosForegroundLastingConfirmed(bool value) async {
    await _clearLegacyKeychainHistoryIfNeeded();
    try {
      final prefs = await _prefs();
      if (value) {
        if (prefs.getBool(_kIosForegroundLastingConfirmed) == true) return;
        await prefs.setBool(_kIosForegroundLastingConfirmed, true);
        if (kDebugMode) {
          debugPrint(
            '[NativePermissionStatus] stored iOS foreground lasting confirmed',
          );
        }
      } else {
        await prefs.remove(_kIosForegroundLastingConfirmed);
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] iOS lasting-confirmed flag failed: $error',
        );
      }
    }
  }

  /// After paused/hidden → resumed: if whenInUse/always still holds, it is
  /// lasting While Using (Allow Once typically expired to notDetermined).
  Future<void> _confirmIosForegroundLastingAfterRealBackground() async {
    final permission =
        await BackgroundLocationPermissions.readIosLocationPermission();
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      await _setIosForegroundLastingConfirmed(true);
      await _clearForegroundLocationUserDenied();
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] iOS FG lasting confirmed after background '
          '($permission)',
        );
      }
      return;
    }
    await _setIosForegroundLastingConfirmed(false);
  }

  /// Android "Allow only this time" flag (API 30+).
  /// iOS Allow Once is indistinguishable from While Using while whenInUse is
  /// active; foregroundLocation reports granted until Allow Once expires.
  Future<bool> _isAndroidOneTimeLocationPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final oneTime = await _settingsChannel.invokeMethod<bool>(
        'hasOneTimeLocationPermission',
      );
      return oneTime == true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] one-time location check failed: $error',
        );
      }
      return false;
    }
  }

  Future<String> _backgroundLocationStatus() async {
    if (!Platform.isAndroid && !Platform.isIOS) return 'unknown';

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Services off is handled elsewhere for other fields; for background only,
      // report denied if this device previously had background location allowed.
      return _resolveBackgroundLocationApiStatus('unknown');
    }

    late final String liveStatus;
    if (Platform.isAndroid) {
      final foreground = await Permission.location.status;
      // Entire app location set to Deny in Settings → background also denied.
      if (await _androidLocationIsDeniedForApi(foreground)) {
        await _markBackgroundLocationUserDenied();
        if (kDebugMode) {
          debugPrint(
            '[NativePermissionStatus] backgroundLocation=denied '
            '(app location denied in Settings)',
          );
        }
        return 'denied';
      }

      try {
        final nativeGranted = await _settingsChannel.invokeMethod<bool>(
          'hasBackgroundLocationPermission',
        );
        if (nativeGranted == true) {
          liveStatus = 'granted';
        } else {
          liveStatus = await _mapAndroidBackgroundPermissionStatus(
            await Permission.locationAlways.status,
          );
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
            '[NativePermissionStatus] android background check failed: $error',
          );
        }
        liveStatus = await _mapAndroidBackgroundPermissionStatus(
          await Permission.locationAlways.status,
        );
      }
    } else {
      liveStatus = _mapGeolocatorPermission(
        await BackgroundLocationPermissions.readIosLocationPermission(),
        foreground: false,
      );
    }

    return _resolveBackgroundLocationApiStatus(liveStatus);
  }

  /// Android background permission → API value before history remap.
  Future<String> _mapAndroidBackgroundPermissionStatus(
    PermissionStatus status,
  ) async {
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return 'granted';
    }
    // Permanent / Settings deny of Always (or parent location) → denied.
    if (status.isPermanentlyDenied || status.isRestricted) {
      return 'denied';
    }
    // Soft denied / not asked → unknown; history remap may upgrade to denied.
    return 'unknown';
  }

  Future<String> _resolveAndroidForegroundDeniedOrUnknown(
    PermissionStatus status,
  ) async {
    if (status.isPermanentlyDenied || status.isRestricted) {
      return 'denied';
    }
    // Don't Allow on the OS dialog (stored or rationale after first deny).
    if (status.isDenied && await _hasForegroundLocationUserDenied()) {
      return 'denied';
    }
    if (status.isDenied &&
        await Permission.location.shouldShowRequestRationale) {
      return 'denied';
    }
    if (status.isDenied && await _hasForegroundLocationEverBeenGranted()) {
      return 'denied';
    }
    return 'unknown';
  }

  /// True when Android app location is fully revoked for API (Settings Deny).
  /// Does not include soft Don't Allow on the first FG OS dialog — that only
  /// remaps foregroundLocation / preciseLocation via [_hasForegroundLocationUserDenied].
  Future<bool> _androidLocationIsDeniedForApi(PermissionStatus status) async {
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return false;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return true;
    }
    if (status.isDenied && await _hasForegroundLocationEverBeenGranted()) {
      return true;
    }
    return false;
  }

  /// Call after the system foreground location dialog closes.
  /// API only: While Using / Always → granted path; Don't Allow or no access →
  /// foregroundLocation (+ precise via existing precise mapping) denied.
  Future<void> syncForegroundLocationAfterOsPrompt() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final lasting = await _hasLastingForegroundOsGrant();
    if (lasting) {
      await _markForegroundLocationEverGranted();
      await _clearForegroundLocationUserDenied();
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] OS FG prompt → whenInUse/Always; API granted',
        );
      }
      await syncIfChanged(force: true);
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[NativePermissionStatus] OS FG prompt → not While Using/Always; '
        'API foreground+precise denied',
      );
    }
    await _markForegroundLocationUserDenied();
    await _uploadPermissionMarkOrDefer();
  }

  /// True when OS has a lasting foreground grant (not one-time / Allow Once).
  ///
  /// iOS: whenInUse and always both count as a foreground grant for API sync
  /// after the OS prompt (Allow Once also appears as whenInUse while active).
  Future<bool> _hasLastingForegroundOsGrant() async {
    if (Platform.isAndroid) {
      if (await _isAndroidOneTimeLocationPermission()) return false;
      final status = await Permission.location.status;
      return status.isGranted || status.isLimited || status.isProvisional;
    }
    if (Platform.isIOS) {
      final permission =
          await BackgroundLocationPermissions.readIosLocationPermission();
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    }
    return false;
  }

  /// Call after Android/iOS foreground OS dialog → Don't Allow / non-lasting.
  /// API only: foregroundLocation + preciseLocation → denied.
  Future<void> markForegroundLocationDeniedByUser() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _markForegroundLocationUserDenied();
    await _uploadPermissionMarkOrDefer();
  }

  /// Call when the officer declines enabling background location
  /// (Cancel on Open Settings, or returns from Settings without Always).
  /// Stores deny in app prefs and uploads permission status (or defers to
  /// the pending app_cycle POST to avoid a duplicate ping).
  Future<void> markBackgroundLocationDeniedByUser() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _markBackgroundLocationUserDenied();
    await _uploadPermissionMarkOrDefer();
  }

  Future<void> _uploadPermissionMarkOrDefer() async {
    if (_pendingAppCycle != null || _appCycleUploadInFlight != null) {
      _deferredSyncAfterAppCycle = true;
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] defer mark-denied upload '
          '(app_cycle will POST; follow-up only if still changed)',
        );
      }
      return;
    }
    await syncIfChanged(force: true);
  }

  /// Persists grant/deny history for backgroundLocation only.
  /// Remaps `unknown` → `denied` after prior grant or explicit user deny.
  Future<String> _resolveBackgroundLocationApiStatus(String liveStatus) async {
    if (liveStatus == 'granted') {
      await _markBackgroundLocationEverGranted();
      await _clearBackgroundLocationUserDenied();
      return 'granted';
    }

    if (liveStatus == 'denied') {
      await _markBackgroundLocationUserDenied();
      return 'denied';
    }

    // liveStatus is typically `unknown`. Report denied when the officer
    // previously granted, or explicitly declined (including first-time Cancel).
    if (await _hasBackgroundLocationEverBeenGranted() ||
        await _hasBackgroundLocationUserDenied()) {
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] backgroundLocation remapped '
          'unknown→denied (prior grant or user deny)',
        );
      }
      return 'denied';
    }

    return liveStatus;
  }

  Future<bool> _readHistoryFlag(String key) async {
    await _clearLegacyKeychainHistoryIfNeeded();
    try {
      final prefs = await _prefs();
      return prefs.getBool(key) == true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] read history flag $key failed: $error',
        );
      }
      return false;
    }
  }

  Future<void> _writeHistoryFlag(
    String key, {
    required String debugLabel,
  }) async {
    await _clearLegacyKeychainHistoryIfNeeded();
    try {
      final prefs = await _prefs();
      if (prefs.getBool(key) == true) return;
      await prefs.setBool(key, true);
      if (kDebugMode) {
        debugPrint('[NativePermissionStatus] stored $debugLabel');
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] write history flag $key failed: $error',
        );
      }
    }
  }

  Future<void> _clearHistoryFlag(String key) async {
    await _clearLegacyKeychainHistoryIfNeeded();
    try {
      final prefs = await _prefs();
      await prefs.remove(key);
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] clear history flag $key failed: $error',
        );
      }
    }
  }

  Future<bool> _hasForegroundLocationEverBeenGranted() {
    return _readHistoryFlag(_kForegroundLocationEverGranted);
  }

  Future<void> _markForegroundLocationEverGranted() {
    return _writeHistoryFlag(
      _kForegroundLocationEverGranted,
      debugLabel: 'foregroundLocation ever_granted',
    );
  }

  Future<bool> _hasForegroundLocationUserDenied() {
    return _readHistoryFlag(_kForegroundLocationUserDenied);
  }

  Future<void> _markForegroundLocationUserDenied() {
    return _writeHistoryFlag(
      _kForegroundLocationUserDenied,
      debugLabel: 'foregroundLocation user_denied',
    );
  }

  Future<void> _clearForegroundLocationUserDenied() {
    return _clearHistoryFlag(_kForegroundLocationUserDenied);
  }

  Future<bool> _hasBackgroundLocationEverBeenGranted() {
    return _readHistoryFlag(_kBackgroundLocationEverGranted);
  }

  Future<bool> _hasBackgroundLocationUserDenied() {
    return _readHistoryFlag(_kBackgroundLocationUserDenied);
  }

  Future<void> _markBackgroundLocationEverGranted() {
    return _writeHistoryFlag(
      _kBackgroundLocationEverGranted,
      debugLabel: 'backgroundLocation ever_granted',
    );
  }

  Future<void> _markBackgroundLocationUserDenied() {
    return _writeHistoryFlag(
      _kBackgroundLocationUserDenied,
      debugLabel: 'backgroundLocation user_denied',
    );
  }

  Future<void> _clearBackgroundLocationUserDenied() {
    return _clearHistoryFlag(_kBackgroundLocationUserDenied);
  }

  Future<String> _preciseLocationStatus() async {
    if (!Platform.isAndroid && !Platform.isIOS) return 'unknown';

    if (Platform.isAndroid) {
      final foreground = await Permission.location.status;
      // "Allow only this time" — temporary; API precise = denied.
      if (await _isAndroidOneTimeLocationPermission()) {
        return 'denied';
      }
      // Lasting FG grant: report real Precise / Approximate (ignore stale deny flags).
      if (foreground.isGranted ||
          foreground.isLimited ||
          foreground.isProvisional) {
        try {
          final precise = await _settingsChannel.invokeMethod<bool>(
            'hasPreciseLocationPermission',
          );
          return precise == true ? 'granted' : 'denied';
        } catch (error) {
          if (kDebugMode) {
            debugPrint(
              '[NativePermissionStatus] android precise check failed: $error',
            );
          }
          return 'granted';
        }
      }
      // Settings revoke / Don't Allow → denied when applicable.
      if (await _androidLocationIsDeniedForApi(foreground) ||
          await _hasForegroundLocationUserDenied() ||
          (foreground.isDenied &&
              await Permission.location.shouldShowRequestRationale)) {
        return 'denied';
      }
      // Not granted yet and never previously granted → unknown.
      return _mapPermissionStatus(foreground);
    }

    final locationPermission =
        await BackgroundLocationPermissions.readIosLocationPermission();
    if (locationPermission == LocationPermission.deniedForever) {
      return 'denied';
    }
    // Ask Next Time Or When I Share (or never authorized) — match FG API:
    // after a prior grant → denied; first install → unknown.
    if (locationPermission == LocationPermission.denied ||
        locationPermission == LocationPermission.unableToDetermine) {
      await _setIosForegroundLastingConfirmed(false);
      if (await _hasForegroundLocationEverBeenGranted() ||
          await _hasForegroundLocationUserDenied()) {
        if (kDebugMode) {
          debugPrint(
            '[NativePermissionStatus] iOS preciseLocation=denied '
            '(Ask Next Time / When I Share or prior deny)',
          );
        }
        return 'denied';
      }
      return 'unknown';
    }

    // whileInUse / always: report real Precise Location (same as FG — do not
    // force denied for unconfirmed whenInUse / Allow Once while active).
    if (locationPermission == LocationPermission.whileInUse ||
        locationPermission == LocationPermission.always) {
      try {
        final precise = await _settingsChannel.invokeMethod<bool>(
          'hasPreciseLocationPermission',
        );
        if (precise != null) {
          return precise ? 'granted' : 'denied';
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
            '[NativePermissionStatus] ios native precise check failed: $error',
          );
        }
      }
      try {
        final accuracy = await Geolocator.getLocationAccuracy();
        return switch (accuracy) {
          LocationAccuracyStatus.precise => 'granted',
          LocationAccuracyStatus.reduced => 'denied',
          LocationAccuracyStatus.unknown => 'unknown',
        };
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
            '[NativePermissionStatus] ios precise check failed: $error',
          );
        }
        return 'unknown';
      }
    }

    return 'unknown';
  }

  Future<String> _notificationStatus() async {
    return OsNotificationPermission.permissionApiStatus();
  }

  Future<String> _batteryOptimizationStatus() async {
    if (!Platform.isAndroid) return 'unknown';

    try {
      final status = await _settingsChannel.invokeMethod<String>(
        'batteryOptimizationStatus',
      );
      if (status == 'granted') return 'granted';
      if (status == 'unknown') return 'unknown';
      // Legacy native builds reported "denied" for the default optimized state.
      if (status == 'denied') return 'unknown';
      if (status != null) return 'unknown';
    } on MissingPluginException {
      // Fall through for older native builds that only expose the boolean API.
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] battery optimization status check failed: $error',
        );
      }
    }

    try {
      final ignoring = await _settingsChannel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      if (ignoring == null) return 'unknown';
      // Default OS state is not exempt; that is not an explicit officer denial.
      return ignoring ? 'granted' : 'unknown';
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] battery optimization check failed: $error',
        );
      }
      return 'unknown';
    }
  }

  Future<String> _lowPowerModeStatus() async {
    if (!Platform.isAndroid && !Platform.isIOS) return 'unknown';

    try {
      final status = await _settingsChannel.invokeMethod<String>(
        'lowPowerModeStatus',
      );
      if (status == 'enabled' || status == 'disabled') return status!;
      return 'unknown';
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] low power mode check failed: $error',
        );
      }
      return 'unknown';
    }
  }

  /// iOS: Settings → Background App Refresh (`UIBackgroundRefreshStatus`).
  /// Android: closest equivalent — app background restriction
  /// (`ActivityManager.isBackgroundRestricted`, API 28+).
  Future<String> _backgroundAppRefreshStatus() async {
    if (!Platform.isAndroid && !Platform.isIOS) return 'unknown';

    try {
      final status = await _settingsChannel.invokeMethod<String>(
        'backgroundAppRefreshStatus',
      );
      if (status == 'enabled' ||
          status == 'disabled' ||
          status == 'restricted') {
        return status!;
      }
      return 'unknown';
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] backgroundAppRefresh check failed: $error',
        );
      }
      return 'unknown';
    }
  }

  Future<int?> _batteryPercentage() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      final level = await Battery().batteryLevel;
      if (level < 0 || level > 100) return null;
      return level;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[NativePermissionStatus] battery level failed: $error');
      }
      return null;
    }
  }

  String _mapPermissionStatus(PermissionStatus status) {
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return 'granted';
    }
    // permanentlyDenied/restricted = officer explicitly blocked access.
    // denied alone often means "not granted yet" before the first OS prompt.
    if (status.isPermanentlyDenied || status.isRestricted) {
      return 'denied';
    }
    return 'unknown';
  }

  String _mapGeolocatorPermission(
    LocationPermission permission, {
    required bool foreground,
  }) {
    return switch (permission) {
      LocationPermission.always => 'granted',
      LocationPermission.whileInUse => foreground ? 'granted' : 'unknown',
      LocationPermission.deniedForever => 'denied',
      LocationPermission.denied ||
      LocationPermission.unableToDetermine => 'unknown',
    };
  }

  Future<bool> _upload(Map<String, dynamic> payload) async {
    ApiClient.instance.ensureAuthInterceptorInstalled();
    final uri = Uri.parse(AppConfig.permissionStatusUrl);

    try {
      if (kDebugMode) {
        debugPrint('[NativePermissionStatus] POST ${uri.path} body=$payload');
      }
      final response = await ApiClient.instance.dio.postUri(
        uri,
        data: payload,
        options: Options(
          headers: const {'Accept': 'application/json'},
          contentType: Headers.jsonContentType,
          sendTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
        ),
      );
      final ok =
          response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
      if (ok) _rememberUploadedBattery(payload);
      return ok;
    } catch (_) {
      return false;
    }
  }

  void _rememberUploadedBattery(Map<String, dynamic> payload) {
    final batteryPercentage = payload['battery_percentage'];
    if (batteryPercentage is int &&
        batteryPercentage >= 0 &&
        batteryPercentage <= 100) {
      _lastUploadedBatteryPercentage = batteryPercentage;
    }
  }
}
