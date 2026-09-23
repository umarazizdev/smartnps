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
import '../debug/kill_cycle_debug_service.dart';
import '../motion/motion_activity_service.dart';
import '../push/notifications/push_notification_preferences.dart';
import 'android_permission_status_watch.dart';
import 'os_notification_permission.dart';
import 'permission_status_api_contract.dart';
import '../utilities/app_config.dart';
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
      _debugLog('cleared legacy Keychain location-history');
    } catch (error) {
      _legacyKeychainCleanupStarted = false;
      _debugLog('legacy Keychain cleanup failed: $error');
    }
  }

  String? _lastPayloadFingerprint;
  String? _lastAppCycle;
  String? _pendingAppCycle;
  PermissionStatusTimeline? _pendingTimeline;
  /// Last successful kill→open pair. Kept on later sync/resume POSTs so a bare
  /// upload cannot wipe `opened_at` from the dashboard after we clear the queue.
  PermissionStatusTimeline? _stickyKillReopenTimeline;
  Future<bool>? _appCycleUploadInFlight;
  Future<bool>? _killReopenUploadInFlight;
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
    _pendingTimeline = null;
    _stickyKillReopenTimeline = null;
    _appCycleUploadInFlight = null;
    _killReopenUploadInFlight = null;
    _lastUploadedBatteryPercentage = null;
    _syncCoalescePending = false;
    _syncForceNext = false;
    _syncInFlight = null;
    _deferredSyncAfterAppCycle = false;
    unawaited(AndroidPermissionStatusWatch.disarm());
  }

  Future<Map<String, dynamic>> buildPayload() async {
    final deviceName = await DeviceIdentity.getDeviceName();
    final permissions = await _readPermissions();
    // Persist full snapshot for native kill/wake lightweight POSTs.
    unawaited(_persistFullPermissionsCache(permissions));
    return {
      'platform': DeviceIdentity.platformName(),
      'deviceId': await DeviceIdentity.getDeviceId(),
      if (deviceName != null) 'deviceName': deviceName,
      'appVersion': AppVersionInfo.version,
      'build': AppVersionInfo.buildNumber,
      'battery_percentage': await _batteryPercentage(),
      'low_power_mode': await _lowPowerModeStatus(),
      'permissions': permissions,
      'checkedAt': isoUtcMicros(DateTime.now()),
    };
  }

  /// Write last-known full permissions to native storage for kill uploads.
  Future<void> _persistFullPermissionsCache(
    Map<String, dynamic> permissions,
  ) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      final asStrings = <String, String>{};
      for (final entry in permissions.entries) {
        final value = entry.value?.toString().trim();
        if (value == null || value.isEmpty) continue;
        asStrings[entry.key] = value;
      }
      if (asStrings.isEmpty) return;
      await _settingsChannel.invokeMethod<void>(
        'cacheFullPermissionSnapshot',
        asStrings,
      );
    } catch (error) {
      _debugLog('cacheFullPermissionSnapshot failed: $error');
    }
  }

  /// 6-digit microsecond UTC ISO-8601 (e.g. `2026-09-20T02:06:00.000000Z`).
  ///
  /// Matches the server `updated_at` format so `checkedAt`, `killed_at`,
  /// and `opened_at` all upload with an identical shape across Flutter and
  /// the native (Android/iOS) uploaders.
  static String isoUtcMicros(DateTime dt) {
    final u = dt.toUtc();
    String pad(int value, int width) => value.toString().padLeft(width, '0');
    return '${pad(u.year, 4)}-${pad(u.month, 2)}-${pad(u.day, 2)}'
        'T${pad(u.hour, 2)}:${pad(u.minute, 2)}:${pad(u.second, 2)}'
        '.${pad(u.millisecond, 3)}${pad(u.microsecond, 3)}Z';
  }

  Future<dynamic> _handleSettingsMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'lowPowerModeChanged':
        _debugLog('low_power_mode changed ${call.arguments}');
        unawaited(syncIfChanged());
        return null;
      case 'backgroundAppRefreshChanged':
        _debugLog('backgroundAppRefresh changed ${call.arguments}');
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
      _debugLog(
        'ensureLatest refresh '
        'oneTime=$oneTime foreground will map '
        '${oneTime ? 'denied' : 'from OS'}',
      );
    }

    if (_pendingAppCycle != null || _appCycleUploadInFlight != null) {
      _deferredSyncAfterAppCycle = true;
      _debugLog(
        'ensureLatest coalesced into app_cycle '
        '(follow-up sync scheduled if still changed)',
      );
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
      _debugLog(
        'skip syncIfChanged '
        '(coalesced into app_cycle; follow-up if still changed)',
      );
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
          _debugLog('skip upload (unchanged permissions)');
          unawaited(AndroidPermissionStatusWatch.arm(markSynced: true));
          continue;
        }

        _debugLog(
          'uploading permissions '
          '(force=$force changed=${fingerprint != _lastPayloadFingerprint}) '
          'permissions=${payload['permissions']}',
        );
        final uploaded = await _upload(payload);
        if (uploaded) {
          _lastPayloadFingerprint = fingerprint;
          didUpload = true;
          unawaited(AndroidPermissionStatusWatch.arm(markSynced: true));
        }
      } while (_syncCoalescePending);
    });
    return didUpload;
  }

  Future<bool> uploadPushToggle({required bool enabled}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    final accessToken = await _accessTokenForLoggedInOfficer();
    if (accessToken == null || accessToken.isEmpty) return false;

    _debugLog('push state upload push=${enabled ? 'enabled' : 'disabled'}');
    return syncIfChanged(force: true);
  }

  Future<bool> uploadAppCycle({
    required String appCycle,
    PermissionStatusTimeline? timeline,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    if (!await AuthRepository.instance.isOfficerLoggedIn()) return false;

    _pendingAppCycle = appCycle;
    if (timeline != null && !timeline.isEmpty) {
      _pendingTimeline = timeline;
    }
    final inFlight = _appCycleUploadInFlight;
    if (inFlight != null) {
      _debugLog('queued app_cycle upload $appCycle');
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

  /// Attach queued kill → open timeline on Flutter [AppLifecycleState.resumed].
  ///
  /// Always asks native to stamp `opened_at` (via prepare) even when auth is not
  /// ready yet. Upload runs when both timestamps exist and a token is available;
  /// otherwise the queue is left for auth-ready / native backup.
  Future<bool> uploadAppCycleWithKillTimelineIfNeeded({
    required String appCycle,
  }) async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return uploadAppCycle(appCycle: appCycle);
    }

    var timeline = await _prepareAppKillTimelineForReopen();

    // New kill cycle — drop sticky reopen from a previous kill.
    if (timeline.hasKill &&
        _stickyKillReopenTimeline != null &&
        _stickyKillReopenTimeline!.killedAt != timeline.killedAt) {
      _stickyKillReopenTimeline = null;
    }

    // Prepare should stamp opened_at; one retry if native was briefly late.
    if (timeline.hasKill && !timeline.hasOpen) {
      unawaited(
        KillCycleDebugService.append(
          'flutter resume: killed_at present, opened_at missing — retry prepare',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      timeline = await _prepareAppKillTimelineForReopen();
    }

    if (timeline.isKillReopen) {
      final inFlight = _killReopenUploadInFlight;
      if (inFlight != null) {
        unawaited(
          KillCycleDebugService.append(
            'flutter kill-reopen coalesce; upload already in flight',
          ),
        );
        return inFlight;
      }

      final reopenTimeline = timeline;
      final task = () async {
        unawaited(
          KillCycleDebugService.append(
            'flutter kill-reopen upload '
            'killed_at=${reopenTimeline.killedAt} opened_at=${reopenTimeline.openedAt}',
          ),
        );
        final uploaded = await _uploadKillReopenNow(reopenTimeline);
        unawaited(
          KillCycleDebugService.append(
            'flutter kill-reopen result uploaded=$uploaded',
          ),
        );
        if (uploaded) {
          // Keep attaching this pair on later POSTs after native queue is cleared.
          _stickyKillReopenTimeline = reopenTimeline;
          await _clearAppKillTimeline();
          unawaited(
            KillCycleDebugService.append(
              'flutter kill-reopen sticky kept for follow-up syncs',
            ),
          );
        }
        return uploaded;
      }();

      _killReopenUploadInFlight = task;
      try {
        return await task;
      } finally {
        if (identical(_killReopenUploadInFlight, task)) {
          _killReopenUploadInFlight = null;
        }
      }
    }

    if (timeline.hasKill && !timeline.hasOpen) {
      // Never POST resumed with only killed_at — wait for open stamp / backup.
      unawaited(
        KillCycleDebugService.append(
          'flutter resume skip reopen; opened_at still missing '
          'killed_at=${timeline.killedAt}',
        ),
      );
      return false;
    }

    return uploadAppCycle(appCycle: appCycle);
  }

  /// Single authoritative POST for kill → user-open (must include opened_at).
  Future<bool> _uploadKillReopenNow(PermissionStatusTimeline timeline) async {
    if (!timeline.isKillReopen) return false;
    if (!await AuthRepository.instance.isOfficerLoggedIn()) {
      unawaited(
        KillCycleDebugService.append(
          'flutter kill-reopen skip; officer not logged in',
        ),
      );
      return false;
    }

    final accessToken = await _accessTokenForLoggedInOfficer();
    if (accessToken == null || accessToken.isEmpty) {
      unawaited(
        KillCycleDebugService.append(
          'flutter kill-reopen skip; no access token',
        ),
      );
      return false;
    }

    var uploaded = false;
    await _serialized(() async {
      await BackgroundLocationPermissions.refreshPermissionStateFromOs();
      final payload = await buildPayload();
      // Keep cycle as resumed (user opened app) but always attach kill timeline.
      payload[PermissionStatusApiContract.appCycle] =
          PermissionStatusApiContract.cycleResumed;
      payload.addAll(timeline.toPayloadFields());

      _debugLog(
        'kill-reopen upload app_cycle=resumed '
        'killed_at=${timeline.killedAt} opened_at=${timeline.openedAt}',
      );
      unawaited(
        KillCycleDebugService.append(
          'flutter kill-reopen POST app_cycle=resumed '
          'killed_at=${timeline.killedAt} opened_at=${timeline.openedAt}',
        ),
      );
      uploaded = await _upload(payload);
      if (uploaded) {
        _lastAppCycle = PermissionStatusApiContract.cycleResumed;
        _lastPayloadFingerprint = _fingerprint(payload);
        unawaited(AndroidPermissionStatusWatch.arm(markSynced: true));
      }
    });
    return uploaded;
  }

  @Deprecated('Use uploadAppCycleWithKillTimelineIfNeeded')
  Future<bool> uploadAppCycleWithIosKillTimelineIfNeeded({
    required String appCycle,
  }) {
    return uploadAppCycleWithKillTimelineIfNeeded(appCycle: appCycle);
  }

  Future<bool> _drainAppCycleUploads() async {
    var ok = true;

    while (_pendingAppCycle != null) {
      await Future<void>.delayed(_appCycleDebounce);

      final appCycle = _pendingAppCycle;
      final timeline = _pendingTimeline;
      _pendingAppCycle = null;
      _pendingTimeline = null;
      if (appCycle == null) continue;

      final uploaded = await _uploadAppCycleNow(appCycle, timeline: timeline);
      ok = ok && uploaded;
    }

    if (_deferredSyncAfterAppCycle) {
      _deferredSyncAfterAppCycle = false;

      await syncIfChanged(bypassAppCycleCoalesce: true);
    }

    return ok;
  }

  Future<bool> _uploadAppCycleNow(
    String appCycle, {
    PermissionStatusTimeline? timeline,
  }) async {
    final accessToken = await _accessTokenForLoggedInOfficer();
    if (accessToken == null || accessToken.isEmpty) return false;

    var uploaded = false;
    await _serialized(() async {
      if (Platform.isIOS &&
          appCycle == PermissionStatusApiContract.cycleResumed &&
          (_lastAppCycle == PermissionStatusApiContract.cyclePaused ||
              _lastAppCycle == PermissionStatusApiContract.cycleHidden)) {
        await _confirmIosForegroundLastingAfterRealBackground();
      }

      await BackgroundLocationPermissions.refreshPermissionStateFromOs();
      final payload = await buildPayload();
      payload[PermissionStatusApiContract.appCycle] = appCycle;
      if (timeline != null && !timeline.isEmpty) {
        payload.addAll(timeline.toPayloadFields());
      }

      final fingerprint = _fingerprint(payload);
      final cycleChanged = appCycle != _lastAppCycle;
      final permissionsChanged = fingerprint != _lastPayloadFingerprint;
      final hasTimeline = timeline != null && !timeline.isEmpty;

      // Timeline events must always POST even when permissions are unchanged.
      if (!cycleChanged && !permissionsChanged && !hasTimeline) {
        _debugLog(
          'skip app_cycle upload '
          '(unchanged cycle=$appCycle and permissions)',
        );
        unawaited(AndroidPermissionStatusWatch.arm(markSynced: true));
        return;
      }

      _debugLog(
        'app_cycle upload $appCycle '
        '(cycleChanged=$cycleChanged permissionsChanged=$permissionsChanged '
        'timeline=$hasTimeline) '
        'permissions=${payload['permissions']}',
      );
      uploaded = await _upload(payload);
      if (uploaded) {
        _lastAppCycle = appCycle;
        _lastPayloadFingerprint = fingerprint;
        unawaited(AndroidPermissionStatusWatch.arm(markSynced: true));
      }
    });
    return uploaded;
  }

  Future<PermissionStatusTimeline> _prepareAppKillTimelineForReopen() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return const PermissionStatusTimeline();
    }
    try {
      // Native stamps opened_at if killed_at exists, then returns full map.
      final raw = await _settingsChannel.invokeMethod<dynamic>(
        'prepareAppKillTimelineForReopen',
      );
      if (raw is Map) {
        return PermissionStatusTimeline.fromMap(raw);
      }
    } catch (error) {
      _debugLog('prepareAppKillTimelineForReopen failed: $error');
      unawaited(
        KillCycleDebugService.append(
          'flutter: prepareAppKillTimelineForReopen failed: $error',
        ),
      );
    }
    return _peekAppKillTimeline();
  }

  Future<PermissionStatusTimeline> _peekAppKillTimeline() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return const PermissionStatusTimeline();
    }
    try {
      final raw = await _settingsChannel.invokeMethod<dynamic>(
        'peekAppKillTimeline',
      );
      if (raw is Map) {
        return PermissionStatusTimeline.fromMap(raw);
      }
    } catch (error) {
      _debugLog('peekAppKillTimeline failed: $error');
    }
    return const PermissionStatusTimeline();
  }

  Future<void> _clearAppKillTimeline() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      await _settingsChannel.invokeMethod<dynamic>('clearAppKillTimeline');
    } catch (error) {
      _debugLog('clearAppKillTimeline failed: $error');
    }
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

        _debugLog('battery upload $batteryPercentage%');
        final uploaded = await _upload(payload);
        if (uploaded) {
          _lastPayloadFingerprint = _fingerprint(payload);
          unawaited(AndroidPermissionStatusWatch.arm(markSynced: true));
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
    final copy = Map<String, dynamic>.from(payload);
    for (final key in PermissionStatusApiContract.fingerprintIgnoredKeys) {
      copy.remove(key);
    }
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
      _debugLog(
        'iOS foregroundLocation=denied '
        '(Ask Next Time / When I Share or prior deny)',
      );
      return 'denied';
    }
    return 'unknown';
  }

  Future<void> _setIosForegroundLastingConfirmed(bool value) async {
    await _clearLegacyKeychainHistoryIfNeeded();
    try {
      final prefs = await _prefs();
      if (value) {
        if (prefs.getBool(_kIosForegroundLastingConfirmed) == true) return;
        await prefs.setBool(_kIosForegroundLastingConfirmed, true);
        _debugLog('stored iOS foreground lasting confirmed');
      } else {
        await prefs.remove(_kIosForegroundLastingConfirmed);
      }
    } catch (error) {
      _debugLog('iOS lasting-confirmed flag failed: $error');
    }
  }

  Future<void> _confirmIosForegroundLastingAfterRealBackground() async {
    final permission =
        await BackgroundLocationPermissions.readIosLocationPermission();
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      await _setIosForegroundLastingConfirmed(true);
      await _clearForegroundLocationUserDenied();
      _debugLog(
        'iOS FG lasting confirmed after background '
        '($permission)',
      );
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
      _debugLog('one-time location check failed: $error');
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
        _debugLog(
          'backgroundLocation=denied '
          '(app location denied in Settings)',
        );
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
        _debugLog('android background check failed: $error');
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
      _debugLog('OS FG prompt → whenInUse/Always; API granted');
      await syncIfChanged(force: true);
      return;
    }

    _debugLog(
      'OS FG prompt → not While Using/Always; '
      'API foreground+precise denied',
    );
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
      _debugLog(
        'defer mark-denied upload '
        '(app_cycle will POST; follow-up only if still changed)',
      );
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
      _debugLog(
        'backgroundLocation remapped '
        'unknown→denied (prior grant or user deny)',
      );
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
      _debugLog('read history flag $key failed: $error');
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
      _debugLog('stored $debugLabel');
    } catch (error) {
      _debugLog('write history flag $key failed: $error');
    }
  }

  Future<void> _clearHistoryFlag(String key) async {
    await _clearLegacyKeychainHistoryIfNeeded();
    try {
      final prefs = await _prefs();
      await prefs.remove(key);
    } catch (error) {
      _debugLog('clear history flag $key failed: $error');
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
          _debugLog('android precise check failed: $error');
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
        _debugLog(
          'iOS preciseLocation=denied '
          '(Ask Next Time / When I Share or prior deny)',
        );
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
        _debugLog('ios native precise check failed: $error');
      }
      try {
        final accuracy = await Geolocator.getLocationAccuracy();
        return switch (accuracy) {
          LocationAccuracyStatus.precise => 'granted',
          LocationAccuracyStatus.reduced => 'denied',
          LocationAccuracyStatus.unknown => 'unknown',
        };
      } catch (error) {
        _debugLog('ios precise check failed: $error');
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
      _debugLog('motion activity status check failed: $error');
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
      _debugLog('battery optimization status check failed: $error');
    }

    try {
      final ignoring = await _settingsChannel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      if (ignoring == null) return 'unknown';

      return ignoring ? 'granted' : 'unknown';
    } catch (error) {
      _debugLog('battery optimization check failed: $error');
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
      _debugLog('low power mode check failed: $error');
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
      _debugLog('backgroundAppRefresh check failed: $error');
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
      _debugLog('battery level failed: $error');
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

  void _debugLog(String message) {
    if (!AppConfig.enablePermissionStatusDebugLog) return;
    if (!kDebugMode) return;
    debugPrint('[NativePermissionStatus] $message');
  }

  Future<bool> _upload(Map<String, dynamic> payload) async {
    // Keep kill→open timeline on every POST so a bare resumed/sync cannot wipe
    // opened_at / app_cycle from the dashboard after the native queue is cleared.
    final pending = await _peekAppKillTimeline();
    if (pending.isKillReopen) {
      payload.addAll(pending.toPayloadFields());
    } else if (_stickyKillReopenTimeline != null &&
        payload[PermissionStatusApiContract.appCycle] !=
            PermissionStatusApiContract.cycleKilled) {
      payload.addAll(_stickyKillReopenTimeline!.toPayloadFields());
    }

    // Whenever both timeline stamps are present, app_cycle must be resumed.
    // Sticky follow-up syncs otherwise omit app_cycle and wipe it server-side.
    _ensureResumedAppCycleForKillReopen(payload);

    ApiClient.instance.ensureAuthInterceptorInstalled();
    final uri = Uri.parse(ApiUrls.permissionStatusUrl);

    try {
      _debugLog(
        'POST ${uri.path} keys=${payload.keys.toList()} '
        'app_cycle=${payload[PermissionStatusApiContract.appCycle]} '
        'opened_at=${payload[PermissionStatusApiContract.openedAt]} '
        'killed_at=${payload[PermissionStatusApiContract.killedAt]}',
      );
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

  /// Kill→open pair on the wire always implies user reopen (`app_cycle=resumed`).
  void _ensureResumedAppCycleForKillReopen(Map<String, dynamic> payload) {
    final killed = payload[PermissionStatusApiContract.killedAt]?.toString().trim();
    final opened = payload[PermissionStatusApiContract.openedAt]?.toString().trim();
    if (killed == null || killed.isEmpty || opened == null || opened.isEmpty) {
      return;
    }
    payload[PermissionStatusApiContract.appCycle] =
        PermissionStatusApiContract.cycleResumed;
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
