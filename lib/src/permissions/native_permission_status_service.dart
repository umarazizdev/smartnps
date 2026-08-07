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
import '../api/api_urls.dart';
import '../auth/auth_repository.dart';
import '../background/location/background_location_permissions.dart';
import '../motion/motion_activity_service.dart';
import '../push/notifications/push_notification_preferences.dart';
import 'os_notification_permission.dart';
import '../utilities/app_version_info.dart';
import '../utilities/device_identity.dart';

class NativePermissionStatusService {
  NativePermissionStatusService._() {
    _settingsChannel.setMethodCallHandler(_handleSettingsMethodCall);
  }

  static final NativePermissionStatusService instance =
      NativePermissionStatusService._();

  static const MethodChannel _settingsChannel = MethodChannel(
    'com.smartnps360.app/settings',
  );

  static const FlutterSecureStorage _legacySecureStorage =
      FlutterSecureStorage();

  static const String _kBackgroundLocationEverGranted =
      'permission.background_location.ever_granted.v1';

  static const String _kBackgroundLocationUserDenied =
      'permission.background_location.user_denied.v1';

  static const String _kForegroundLocationEverGranted =
      'permission.foreground_location.ever_granted.v1';

  static const String _kForegroundLocationUserDenied =
      'permission.foreground_location.user_denied.v1';

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

  bool _deferredSyncAfterAppCycle = false;

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

        _onOsPermissionChanged?.call();
        return null;
      default:
        throw MissingPluginException('No handler for ${call.method}');
    }
  }

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

  Future<bool> syncLocationPermissionsOnResume() {
    return ensureLatestPermissionsSynced(settleMs: 80);
  }

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

  Future<bool> syncIfChanged({
    bool force = false,
    bool bypassAppCycleCoalesce = false,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    final accessToken = await _accessTokenForLoggedInOfficer();
    if (accessToken == null || accessToken.isEmpty) return false;

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

      await syncIfChanged(bypassAppCycleCoalesce: true);
    }

    return ok;
  }

  Future<bool> _uploadAppCycleNow(String appCycle) async {
    final accessToken = await _accessTokenForLoggedInOfficer();
    if (accessToken == null || accessToken.isEmpty) return false;

    var uploaded = false;
    await _serialized(() async {

      if (Platform.isIOS &&
          appCycle == 'resumed' &&
          (_lastAppCycle == 'paused' || _lastAppCycle == 'hidden')) {
        await _confirmIosForegroundLastingAfterRealBackground();
      }

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
      'motionActivity': await _motionActivityStatus(),
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

      return _resolveAndroidForegroundDeniedOrUnknown(status);
    }

    return _resolveIosForegroundLocationApiStatus(
      await BackgroundLocationPermissions.readIosLocationPermission(),
    );
  }

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

      return _resolveBackgroundLocationApiStatus('unknown');
    }

    late final String liveStatus;
    if (Platform.isAndroid) {
      final foreground = await Permission.location.status;

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

  Future<String> _mapAndroidBackgroundPermissionStatus(
    PermissionStatus status,
  ) async {
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return 'granted';
    }

    if (status.isPermanentlyDenied || status.isRestricted) {
      return 'denied';
    }

    return 'unknown';
  }

  Future<String> _resolveAndroidForegroundDeniedOrUnknown(
    PermissionStatus status,
  ) async {
    if (status.isPermanentlyDenied || status.isRestricted) {
      return 'denied';
    }

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

  Future<void> markForegroundLocationDeniedByUser() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _markForegroundLocationUserDenied();
    await _uploadPermissionMarkOrDefer();
  }

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

      if (await _isAndroidOneTimeLocationPermission()) {
        return 'denied';
      }

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

      if (await _androidLocationIsDeniedForApi(foreground) ||
          await _hasForegroundLocationUserDenied() ||
          (foreground.isDenied &&
              await Permission.location.shouldShowRequestRationale)) {
        return 'denied';
      }

      return _mapPermissionStatus(foreground);
    }

    final locationPermission =
        await BackgroundLocationPermissions.readIosLocationPermission();
    if (locationPermission == LocationPermission.deniedForever) {
      return 'denied';
    }

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

  Future<String> _motionActivityStatus() async {
    if (!Platform.isAndroid && !Platform.isIOS) return 'unknown';

    try {
      final available = await MotionActivityService.isAvailable();
      if (!available) return 'unknown';

      if (Platform.isAndroid) {

        final status = await Permission.activityRecognition.status;
        if (status.isGranted || status.isLimited || status.isProvisional) {
          return 'granted';
        }
        if (status.isPermanentlyDenied || status.isRestricted) {
          return 'denied';
        }

        return 'unknown';
      }

      final native = await MotionActivityService.checkPermission();
      switch (native) {
        case 'granted':
          return 'granted';
        case 'denied':
        case 'restricted':
          return 'denied';
        case 'notDetermined':
          return 'unknown';
        default:
          return 'unknown';
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[NativePermissionStatus] motion activity status check failed: $error',
        );
      }
      return 'unknown';
    }
  }

  Future<String> _batteryOptimizationStatus() async {
    if (!Platform.isAndroid) return 'unknown';

    try {
      final status = await _settingsChannel.invokeMethod<String>(
        'batteryOptimizationStatus',
      );
      if (status == 'granted') return 'granted';
      if (status == 'unknown') return 'unknown';

      if (status == 'denied') return 'unknown';
      if (status != null) return 'unknown';
    } on MissingPluginException {

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
    final uri = Uri.parse(ApiUrls.permissionStatusUrl);

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
