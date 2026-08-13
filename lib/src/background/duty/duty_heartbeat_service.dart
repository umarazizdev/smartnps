import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../api/api_client.dart';
import '../../api/api_urls.dart';
import '../../app/app_navigator.dart';
import '../../auth/auth_repository.dart';
import '../../push/notifications/push_notification_service.dart';
import '../../auth/location_disclosure_account_sync.dart';
import '../../permissions/required_permissions_gate.dart';
import '../../utilities/overlay_prompt_guard.dart';
import '../../utilities/permission_settings_helper.dart';
import '../../widgets/dialogs/location_tracking_disclosure_dialog.dart';
import '../location/android_duty_location_health.dart';
import '../location/background_location_controller.dart';
import '../location/background_location_permissions.dart';
import '../location/location_sharing_status_notification.dart';
import 'clock_in_gate_service.dart';
import 'duty_tracking_preferences.dart';
import '../ios/ios_duty_location_pinger.dart';
import '../ios/ios_significant_location_change_service.dart';
import 'duty_status_snapshot.dart';
import 'location_disclosure_consent.dart';

class DutyHeartbeatService {
  DutyHeartbeatService._() {
    BackgroundLocationController.confirmOnDutyBeforeStart = () {
      return confirmOnDutyFromApiForTracking(stopIfNotOnDuty: true);
    };
    if (Platform.isIOS) {
      IosDutyLocationPinger.confirmOnDutyBeforeStart = () {
        return confirmOnDutyFromApiForTracking(stopIfNotOnDuty: true);
      };
    }
  }

  static final DutyHeartbeatService instance = DutyHeartbeatService._();

  static const Duration _minPollInterval = Duration(seconds: 10);
  static const Duration _maxPollInterval = Duration(seconds: 15);

  static const String onDuty = 'on_duty';
  static const String offDuty = 'off_duty';

  final Dio _dio = ApiClient.instance.dio;
  final Random _random = Random();

  Timer? _pollTimer;
  bool _pollInFlight = false;
  bool _heartbeatActive = false;
  String? _lastAppliedStatus;
  bool _disclosureAccepted = false;
  bool _disclosureDeferred = false;
  bool _requestPermissionAfterDisclosure = false;
  bool _disclosurePromptInFlight = false;
  bool _backgroundLocationSettingsDialogVisible = false;

  bool _onDutyAutoPromptComplete = false;
  bool _locationSharingArmedThisDuty = false;
  Future<void>? _applyOnDutyFuture;
  Future<void>? _ensureTrackingFuture;
  Future<bool>? _disclosurePromptFuture;
  LocationPermission? _lastKnownIosPermission;
  bool _deferTrackingStart = false;

  final ValueNotifier<bool> backgroundLocationPermissionMissing = ValueNotifier(
    false,
  );

  final ValueNotifier<bool> disclosurePromptVisible = ValueNotifier(false);

  bool get isBackgroundLocationBannerActive =>
      backgroundLocationPermissionMissing.value;

  bool get shouldShowBackgroundLocationBanner =>
      backgroundLocationPermissionMissing.value &&
      !PermissionSettingsHelper.settingsPromptVisible.value &&
      !disclosurePromptVisible.value &&
      !_backgroundLocationSettingsDialogVisible &&
      !_disclosurePromptInFlight &&
      !ClockInGateService.instance.isPrepareInFlight &&
      !OverlayPromptGuard.blocksTopBanner;

  bool get isOnDutyTrackingActive =>
      _heartbeatActive && _lastAppliedStatus == onDuty;

  Future<bool> isOnDutyAccordingToHeartbeat() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    if (!await _hasActiveAuthToken()) return false;

    try {
      final status = await _fetchDutyStatus();
      if (status == onDuty) {
        await DutyStatusSnapshot.markOnDuty();
        return true;
      }
      if (status == offDuty) {
        await DutyStatusSnapshot.clear();
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DutyService] on-duty logout check failed: $e');
      }
    }

    if (await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) {
      return true;
    }
    return _lastAppliedStatus == onDuty;
  }

  Future<bool> confirmOnDutyFromApiForTracking({
    bool stopIfNotOnDuty = true,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    final onlineAuth = await _hasActiveAuthToken();
    if (!onlineAuth) {
      final cached = await AuthRepository.instance.getAccessToken();
      if (cached != null &&
          cached.isNotEmpty &&
          await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) {
        if (kDebugMode) {
          debugPrint(
            '[DutyHeartbeatService] offline snapshot allows on_duty '
            '(cached token, refresh unavailable)',
          );
        }
        return true;
      }
      if (kDebugMode) {
        debugPrint('[DutyHeartbeatService] tracking denied; no auth token');
      }
      await DutyStatusSnapshot.clear();
      if (stopIfNotOnDuty) {
        await _stopTrackingForFailedDutyConfirm();
      }
      return false;
    }

    try {
      final status = await _fetchDutyStatus();
      if (status == onDuty) {
        await DutyStatusSnapshot.markOnDuty();
        if (kDebugMode) {
          debugPrint(
            '[DutyHeartbeatService] heartbeat confirmed on_duty for tracking',
          );
        }
        return true;
      }

      if (status == offDuty) {
        if (kDebugMode) {
          debugPrint(
            '[DutyHeartbeatService] tracking denied; heartbeat status=off_duty',
          );
        }
        await DutyStatusSnapshot.clear();
        if (stopIfNotOnDuty) {
          await _applyOffDuty();
        }
        return false;
      }

      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] heartbeat status=$status; trying offline snapshot',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] heartbeat fetch failed; trying offline snapshot: $e',
        );
      }
    }

    if (await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) {
      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] offline snapshot allows on_duty tracking',
        );
      }
      return true;
    }

    if (kDebugMode) {
      debugPrint(
        '[DutyHeartbeatService] tracking denied; no on_duty API or snapshot',
      );
    }
    if (stopIfNotOnDuty) {
      await _stopTrackingForFailedDutyConfirm();
    }
    return false;
  }

  Future<void> _stopTrackingForFailedDutyConfirm() async {
    await DutyStatusSnapshot.clear();
    if (Platform.isIOS) {
      await IosSignificantLocationChangeService.setOnDuty(false);
    }
    await BackgroundLocationController.stop();
  }

  Future<void> refreshBackgroundLocationPermissionBannerState() async {
    if (_lastAppliedStatus != onDuty) {
      if (backgroundLocationPermissionMissing.value) {
        backgroundLocationPermissionMissing.value = false;
      }
      return;
    }

    await BackgroundLocationPermissions.refreshPermissionStateFromOs();
    final backgroundMissing =
        !await BackgroundLocationPermissions.hasSufficientBackgroundAccess();
    final preciseMissing =
        !await BackgroundLocationPermissions.hasPreciseLocationAccess();
    final missing = backgroundMissing || preciseMissing;
    if (kDebugMode) {}
    if (backgroundLocationPermissionMissing.value != missing) {
      backgroundLocationPermissionMissing.value = missing;
    }
  }

  void _setDisclosurePromptVisible(bool visible) {
    if (disclosurePromptVisible.value != visible) {
      disclosurePromptVisible.value = visible;
    }
  }

  void reconcileDialogsAfterAppResume() {
    if (Platform.isAndroid &&
        (ClockInGateService.instance.isPrepareInFlight ||
            PermissionSettingsHelper.isAwaitingSettingsReturn)) {
      return;
    }
    PermissionSettingsHelper.reconcilePromptsAfterAppResume();
    _backgroundLocationSettingsDialogVisible = false;
    if (!_disclosurePromptInFlight) {
      _setDisclosurePromptVisible(false);
    }
  }

  @Deprecated('Use reconcileDialogsAfterAppResume')
  void reconcileDialogsAfterAndroidResume() => reconcileDialogsAfterAppResume();

  /// Block GPS start until resume has fetched duty status (avoids a brief
  /// on_duty start when the officer is actually off_duty).
  void beginResumeDutyReconcile() {
    _deferTrackingStart = true;
  }

  void endResumeDutyReconcile() {
    _deferTrackingStart = false;
  }

  void start() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_pollTimer != null) return;

    _heartbeatActive = true;
    LocationSharingStatusNotification.resetSignedOutGate();
    ApiClient.instance.ensureAuthInterceptorInstalled();
    debugPrint('[DutyHeartbeatService] starting heartbeat polling');

    unawaited(_hydrateConsentFromStorage());
    unawaited(_pollOnce());
    _scheduleNextPoll();
  }

  Future<void> _hydrateConsentFromStorage() async {
    await LocationDisclosureAccountSync.reconcileDisclosureFromOs();

    if (await LocationDisclosureConsent.hasAccepted()) {
      _disclosureAccepted = true;
      _disclosureDeferred = false;
    }
  }

  Future<void> recheckOnDutyPrompts({
    bool pageReload = false,
    bool fromResume = false,
  }) async {
    if (!_heartbeatActive) return;

    if (RequiredPermissionsGate.shouldSuppressCompetingDialogs) return;

    final token = await AuthRepository.instance.ensureValidAccessToken();
    if (token == null || token.isEmpty) {
      final cached = await AuthRepository.instance.getAccessToken();
      if (cached == null ||
          cached.isEmpty ||
          !await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) {
        return;
      }
    } else if (!pageReload) {
      await PushNotificationService.instance.waitForPermissionPromptCompleted(
        promptIfNeeded: true,
      );
      await OverlayPromptGuard.waitUntilReady();
    }

    await _hydrateConsentFromStorage();
    await _reconcileBgLocationReadyFlag();
    await _syncPermissionReadyState();

    String? status;
    try {
      status = await _fetchDutyStatus();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] recheck heartbeat failed (offline?): $e',
        );
      }
      status = null;
    }

    if (status == offDuty) {
      await _applyOffDuty();
      await refreshBackgroundLocationPermissionBannerState();
      return;
    }

    if (status != onDuty) {
      if (!await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) {
        if (fromResume) {
          await _ensureOffDutyTrackingStopped();
        }
        await refreshBackgroundLocationPermissionBannerState();
        return;
      }
      // Resume without a fresh on_duty API result: keep a live FGS, but do
      // not start a new GPS session from snapshot alone.
      if (fromResume) {
        final running = await _isLocationTrackingRunning();
        if (!running) {
          if (kDebugMode) {
            debugPrint(
              '[DutyHeartbeatService] resume: no API on_duty and GPS '
              'not running — not starting',
            );
          }
          await refreshBackgroundLocationPermissionBannerState();
          return;
        }
        _lastAppliedStatus = onDuty;
        _locationSharingArmedThisDuty = true;
        await refreshBackgroundLocationPermissionBannerState();
        return;
      }
      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] recheck using offline on_duty snapshot',
        );
      }
    } else {
      await DutyStatusSnapshot.markOnDuty();
    }

    _lastAppliedStatus = onDuty;
    await _handleIosPermissionChangeIfNeeded();

    final healthy = await BackgroundLocationController.isTrackingHealthy();
    if (healthy) {
      _locationSharingArmedThisDuty = true;
      await refreshBackgroundLocationPermissionBannerState();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await refreshBackgroundLocationPermissionBannerState();
      return;
    }

    // Always start/recover when on_duty — including same-page reloads.
    // pageReload only skips permission dialogs, not GPS start.
    await _ensureTrackingRunningForOnDuty(
      allowPrompts: !pageReload,
      ignoreDefer: fromResume,
    );
    await refreshBackgroundLocationPermissionBannerState();
  }

  /// Starts or recovers duty GPS when heartbeat says on_duty.
  /// [allowPrompts] false skips disclosure/settings dialogs (e.g. page reload).
  Future<void> _ensureTrackingRunningForOnDuty({
    required bool allowPrompts,
    bool ignoreDefer = false,
  }) async {
    if (_lastAppliedStatus != onDuty) return;
    if (_deferTrackingStart && !ignoreDefer) {
      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] defer GPS start until duty status is known',
        );
      }
      return;
    }

    final inFlight = _ensureTrackingFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final future = _ensureTrackingRunningForOnDutyImpl(
      allowPrompts: allowPrompts,
    );
    _ensureTrackingFuture = future;
    try {
      await future;
    } finally {
      if (identical(_ensureTrackingFuture, future)) {
        _ensureTrackingFuture = null;
      }
    }
  }

  Future<void> _ensureTrackingRunningForOnDutyImpl({
    required bool allowPrompts,
  }) async {
    if (_lastAppliedStatus != onDuty) return;

    final healthy = await BackgroundLocationController.isTrackingHealthy();
    if (healthy) {
      _locationSharingArmedThisDuty = true;
      return;
    }

    final running = await _isLocationTrackingRunning();
    // Android FGS self-heals while the UI is backgrounded. Never stop/rebuild
    // from this isolate then — OEM GPS timeouts led to hard-restart which
    // killed the live service and could not start a new FGS from background.
    if (running && Platform.isAndroid) {
      if (BackgroundLocationController.isUiBackgrounded) {
        _locationSharingArmedThisDuty = true;
        return;
      }
      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] on_duty Android tracking stale; recovering',
        );
      }
      final result =
          await BackgroundLocationController.recoverAndroidTrackingIfNeeded();
      if (result['ok'] == true) {
        _locationSharingArmedThisDuty = true;
      }
      return;
    }

    if (!running &&
        Platform.isAndroid &&
        BackgroundLocationController.isUiBackgrounded) {
      if (kDebugMode) {
        debugPrint('[DutyHeartbeatService] skip GPS start; UI is backgrounded');
      }
      return;
    }

    if (running && Platform.isIOS) {
      if (kDebugMode) {
        debugPrint('[DutyHeartbeatService] on_duty tracking stale; recovering');
      }
      await _restartTrackingWithCurrentPermission();
      return;
    }

    final disclosureAccepted = await LocationDisclosureConsent.hasAccepted();
    final backgroundReady =
        await BackgroundLocationPermissions.hasSufficientBackgroundAccess();

    if (disclosureAccepted && backgroundReady) {
      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] on_duty but tracking not running; starting',
        );
      }
      await retryOnDutyTrackingIfReady();
      return;
    }

    if (allowPrompts && await _shouldAutoApplyOnDutyFromPoll()) {
      await _applyOnDuty();
    }
  }

  Future<bool> _shouldAutoApplyOnDutyFromPoll() async {
    if (_onDutyAutoPromptComplete) return false;
    if (_disclosureDeferred || _disclosurePromptInFlight) return false;
    if (await DutyTrackingPreferences.isSettingsPromptDeferred()) return false;
    return true;
  }

  void _resetOnDutyAutoPromptState() {
    _onDutyAutoPromptComplete = false;
  }

  Future<bool> _isLocationTrackingRunning() async {
    return BackgroundLocationController.isTrackingRunning();
  }

  Future<void> _ensureOffDutyTrackingStopped() async {
    // Always clear any leftover on_duty snapshot while heartbeat says off_duty.
    await DutyStatusSnapshot.clear();

    final running = await _isLocationTrackingRunning();
    if (!running) {
      AndroidDutyLocationHealth.markStopped();
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[DutyHeartbeatService] off_duty but tracking still running; stopping',
      );
    }
    final result = await BackgroundLocationController.stop();
    debugPrint(
      '[DutyHeartbeatService] off_duty stop retry ok=${result['ok'] == true}',
    );
  }

  Future<void> _ensureIosTrackingHealthy() async {
    if (!Platform.isIOS) return;
    if (_lastAppliedStatus != onDuty) {
      return;
    }

    final backgroundReady =
        await BackgroundLocationPermissions.hasSufficientBackgroundAccess();
    if (!backgroundReady &&
        (_disclosureDeferred || _disclosurePromptInFlight)) {
      return;
    }

    await _handleIosPermissionChangeIfNeeded();

    if (!IosDutyLocationPinger.isRunning) {
      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] on_duty but location stream not running; recovering',
        );
      }
      await _restartTrackingWithCurrentPermission();
      return;
    }

    if (IosDutyLocationPinger.needsRecovery) {
      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] on_duty location stream stale; recovering',
        );
      }
      await IosDutyLocationPinger.recoverIfNeeded();
    }
  }

  Future<void> stop({bool stopBackgroundLocation = true}) async {
    _heartbeatActive = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInFlight = false;
    _resetDisclosureState();
    backgroundLocationPermissionMissing.value = false;
    debugPrint('[DutyHeartbeatService] stopped heartbeat polling');

    if (stopBackgroundLocation) {
      await _applyOffDuty(allowAnnounce: false);
    }
    _lastAppliedStatus = null;
    _locationSharingArmedThisDuty = false;
  }

  Future<void> finalizeLogoutInstant() async {
    final wasSharing = await _shouldAnnounceLocationStop();
    _heartbeatActive = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInFlight = false;
    _lastAppliedStatus = offDuty;
    _locationSharingArmedThisDuty = false;
    _resetDisclosureState();
    backgroundLocationPermissionMissing.value = false;
    PermissionSettingsHelper.clearCooldown('background_location');
    debugPrint(
      '[DutyHeartbeatService] instant logout (heartbeat + tracking stopped)',
    );
    // Clear snapshot first so any in-flight FGS fix cannot upload while off duty.
    unawaited(DutyStatusSnapshot.clear());
    if (Platform.isIOS) {
      unawaited(IosSignificantLocationChangeService.setOnDuty(false));
    }
    unawaited(BackgroundLocationController.stopCollectingOnly());
    if (wasSharing) {
      unawaited(
        LocationSharingStatusNotification.tryAnnounceStopped(
          reason: LocationSharingStopReason.signedOut,
        ),
      );
    } else {
      unawaited(LocationSharingStatusNotification.dismissSharing());
    }
    unawaited(DutyTrackingPreferences.clearOnOffDuty());
    unawaited(refreshBackgroundLocationPermissionBannerState());
  }

  Future<bool> _shouldAnnounceLocationStop() async {
    if (_locationSharingArmedThisDuty) return true;
    if (await _isLocationTrackingRunning()) return true;
    if (LocationSharingStatusNotification.isSharingShown) return true;
    return false;
  }

  void _scheduleNextPoll() {
    _pollTimer?.cancel();
    final jitterMs =
        _minPollInterval.inMilliseconds +
        _random.nextInt(
          _maxPollInterval.inMilliseconds - _minPollInterval.inMilliseconds + 1,
        );
    _pollTimer = Timer(Duration(milliseconds: jitterMs), () async {
      if (!_heartbeatActive) return;
      await _pollOnce();
      if (_heartbeatActive && _pollTimer != null) {
        _scheduleNextPoll();
      }
    });
  }

  Future<void> _pollOnce() async {
    if (_pollInFlight || !_heartbeatActive) return;
    _pollInFlight = true;

    try {
      if (!_heartbeatActive) return;

      final token = await AuthRepository.instance.ensureValidAccessToken();
      if (token == null || token.isEmpty) {
        final cached = await AuthRepository.instance.getAccessToken();
        if (cached != null &&
            cached.isNotEmpty &&
            await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) {
          if (kDebugMode) {
            debugPrint(
              '[DutyHeartbeatService] poll auth refresh failed; '
              'keeping offline on_duty from snapshot',
            );
          }
          _lastAppliedStatus = onDuty;
          await _ensureTrackingRunningForOnDuty(allowPrompts: true);
          return;
        }
        if (kDebugMode) {
          debugPrint(
            '[DutyHeartbeatService] no auth token; stopping heartbeat and location',
          );
        }
        await stop();
        return;
      }

      final status = await _fetchDutyStatus();
      if (status == null) {
        if (await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) {
          if (kDebugMode) {
            debugPrint(
              '[DutyHeartbeatService] poll offline; snapshot on_duty — ensuring tracking',
            );
          }
          _lastAppliedStatus = onDuty;
          await _ensureTrackingRunningForOnDuty(allowPrompts: true);
        }
        return;
      }

      if (status == _lastAppliedStatus) {
        if (status == onDuty) {
          await DutyStatusSnapshot.markOnDuty();
          if (Platform.isIOS) {
            await _ensureIosTrackingHealthy();
          }
          await _ensureTrackingRunningForOnDuty(allowPrompts: true);
          await refreshBackgroundLocationPermissionBannerState();
        } else if (status == offDuty) {
          await DutyStatusSnapshot.clear();
          await _ensureOffDutyTrackingStopped();
        }
        return;
      }

      if (!_heartbeatActive || !await _hasActiveAuthToken()) return;

      debugPrint('[DutyHeartbeatService] duty status=$status');
      if (status == onDuty) {
        if (_lastAppliedStatus == offDuty) {
          _resetOnDutyAutoPromptState();
          await _hydrateConsentFromStorage();
        }
        await _applyOnDuty();
      } else if (status == offDuty) {
        await _applyOffDuty();
      } else if (kDebugMode) {
        debugPrint('[DutyHeartbeatService] ignored unknown status=$status');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DutyHeartbeatService] poll failed: $e');
      }
      if (await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) {
        _lastAppliedStatus = onDuty;
        await _ensureTrackingRunningForOnDuty(allowPrompts: true);
      }
    } finally {
      _pollInFlight = false;
    }
  }

  Future<String?> _fetchDutyStatus() async {
    final response = await _dio.getUri(
      Uri.parse(ApiUrls.heartbeatUrl),
      options: Options(
        headers: const {'Accept': 'application/json'},
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    final statusCode = response.statusCode ?? 0;
    if (statusCode == 401 || statusCode == 403) {
      return null;
    }

    if (statusCode < 200 || statusCode >= 300) {
      return null;
    }

    return _parseDutyStatus(response.data);
  }

  String? _parseDutyStatus(dynamic body) {
    if (body == null) return null;

    if (body is String) {
      final normalized = body.trim().toLowerCase();
      if (normalized == onDuty || normalized == offDuty) return normalized;
      return null;
    }

    if (body is! Map) return null;
    final map = Map<String, dynamic>.from(body);

    for (final key in const [
      'status',
      'duty_status',
      'dutyStatus',
      'duty',
      'state',
    ]) {
      final parsed = _normalizeDutyValue(map[key]);
      if (parsed != null) return parsed;
    }

    for (final nestedKey in const ['data', 'payload', 'result']) {
      final nested = map[nestedKey];
      if (nested is Map) {
        final parsed = _parseDutyStatus(nested);
        if (parsed != null) return parsed;
      }
    }

    return null;
  }

  String? _normalizeDutyValue(dynamic value) {
    if (value == null) return null;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == onDuty || normalized == offDuty) return normalized;
    if (normalized == 'onduty' || normalized == 'on-duty') return onDuty;
    if (normalized == 'offduty' || normalized == 'off-duty') return offDuty;
    return null;
  }

  Future<void> _applyOnDuty() async {
    if (_applyOnDutyFuture != null) {
      return _applyOnDutyFuture!;
    }

    final future = _applyOnDutyImpl();
    _applyOnDutyFuture = future;
    try {
      await future;
    } finally {
      if (identical(_applyOnDutyFuture, future)) {
        _applyOnDutyFuture = null;
      }
    }
  }

  Future<bool> _hasActiveAuthToken() async {
    final token = await AuthRepository.instance.ensureValidAccessToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> _applyOnDutyImpl() async {
    if (_deferTrackingStart) {
      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] defer on_duty apply until duty resume reconcile',
        );
      }
      return;
    }
    if (!_heartbeatActive || !await _hasActiveAuthToken()) {
      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] skip on_duty apply (heartbeat inactive or no token)',
        );
      }
      return;
    }

    final isFreshClockIn = _lastAppliedStatus == offDuty;

    if (isFreshClockIn || _lastAppliedStatus != onDuty) {
      LocationSharingStatusNotification.resetShiftEndedGate();
      _locationSharingArmedThisDuty = false;
    }

    await _hydrateConsentFromStorage();

    await PushNotificationService.instance.waitForPermissionPromptCompleted(
      promptIfNeeded: true,
    );
    if (!_heartbeatActive || !await _hasActiveAuthToken()) return;

    await _reconcileBgLocationReadyFlag();
    await _handleIosPermissionChangeIfNeeded();
    await _syncPermissionReadyState();

    if (!_heartbeatActive || !await _hasActiveAuthToken()) return;

    if (await LocationDisclosureConsent.hasAccepted()) {
      _disclosureAccepted = true;
      if (!await confirmOnDutyFromApiForTracking()) return;
      _lastAppliedStatus = onDuty;
      final healthy = await BackgroundLocationController.isTrackingHealthy();
      if (!healthy) {
        await _runPostDisclosurePermissionStep();
        final result = await BackgroundLocationController.ensureStarted();
        debugPrint(
          '[DutyHeartbeatService] ensureStarted (disclosure accepted) ok=${result['ok'] == true}',
        );
        if (result['ok'] == true) {
          debugPrint('[DutyLocation] on_duty → location ensureStarted OK');
          _locationSharingArmedThisDuty = true;
          await _syncPermissionReadyState();
        } else {
          debugPrint(
            '[DutyLocation] on_duty → location ensureStarted FAILED '
            '(disclosure-accepted path)',
          );
          if (result['openSettings'] == true) {
            await _showBackgroundLocationSettingsDialogIfNeeded(
              deniedReason: result['deniedReason']?.toString(),
            );
          }
          await _reconcileAfterFailedStart();
          return;
        }
      } else {
        _locationSharingArmedThisDuty = true;
      }
      await refreshBackgroundLocationPermissionBannerState();
      _onDutyAutoPromptComplete = true;
      return;
    }

    if (isFreshClockIn) {
      await Future.delayed(const Duration(seconds: 1));
      await OverlayPromptGuard.waitUntilReady();
    }

    if (!await _confirmBackgroundLocationDisclosure()) {
      _lastAppliedStatus = onDuty;
      debugPrint('[DutyHeartbeatService] on_duty start canceled by user');
      await refreshBackgroundLocationPermissionBannerState();
      return;
    }

    if (!_heartbeatActive || !await _hasActiveAuthToken()) return;

    if (!await confirmOnDutyFromApiForTracking()) return;
    _lastAppliedStatus = onDuty;

    final bool settingsPrompted;
    final alreadyHealthy =
        await BackgroundLocationController.isTrackingHealthy();
    if (!alreadyHealthy) {
      settingsPrompted = await _runPostDisclosurePermissionStep();
    } else {
      _requestPermissionAfterDisclosure = false;
      settingsPrompted = false;
      _locationSharingArmedThisDuty = true;
    }

    final backgroundReady =
        await BackgroundLocationPermissions.hasSufficientBackgroundAccess();
    final skipSettingsPrompt = backgroundReady;

    final result = alreadyHealthy
        ? <String, dynamic>{'ok': true, 'started': false, 'running': true}
        : await BackgroundLocationController.ensureStarted();
    debugPrint(
      '[DutyHeartbeatService] ensureStarted ok=${result['ok'] == true}',
    );

    if (result['ok'] == true) {
      debugPrint('[DutyLocation] on_duty → location ensureStarted OK');
      _locationSharingArmedThisDuty = true;
      await _syncPermissionReadyState();
      await refreshBackgroundLocationPermissionBannerState();
      return;
    }

    debugPrint('[DutyLocation] on_duty → location ensureStarted FAILED');
    if (result['openSettings'] == true &&
        !skipSettingsPrompt &&
        !settingsPrompted) {
      await _showBackgroundLocationSettingsDialogIfNeeded(
        deniedReason: result['deniedReason']?.toString(),
      );
    }
    await _reconcileAfterFailedStart();
  }

  Future<void> _reconcileAfterFailedStart() async {
    String? status;
    try {
      status = await _fetchDutyStatus();
    } catch (_) {
      status = null;
    }

    if (status == offDuty) {
      await _applyOffDuty();
      return;
    }
    if (status == onDuty) {
      await DutyStatusSnapshot.markOnDuty();
      await refreshBackgroundLocationPermissionBannerState();
      // Block auto permission/disclosure dialogs, but keep start retries when
      // disclosure + background access are already ready.
      _onDutyAutoPromptComplete = true;
      if (await LocationDisclosureConsent.hasAccepted() &&
          await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
        unawaited(retryOnDutyTrackingIfReady());
      }
      return;
    }
    if (await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) {
      await refreshBackgroundLocationPermissionBannerState();
      _onDutyAutoPromptComplete = true;
      if (await LocationDisclosureConsent.hasAccepted() &&
          await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
        unawaited(retryOnDutyTrackingIfReady());
      }
      return;
    }
    await _stopTrackingForFailedDutyConfirm();
    await refreshBackgroundLocationPermissionBannerState();
    _onDutyAutoPromptComplete = true;
  }

  Future<bool> ensureDisclosureBeforeWebLocationAccess() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    if (RequiredPermissionsGate.shouldSuppressCompetingDialogs) return false;

    if (!await LocationDisclosureConsent.shouldShowLocationDisclosure()) {
      _disclosureAccepted = true;
      return true;
    }

    if (_disclosurePromptFuture != null) {
      if (!await _disclosurePromptFuture!) return false;
    }

    if (_disclosureAccepted) {
      return true;
    }

    final accepted = await _confirmBackgroundLocationDisclosure(
      forceRetry: false,
    );
    if (!accepted) return false;

    if (_requestPermissionAfterDisclosure) {
      await PermissionSettingsHelper.requestForegroundLocationStep();
      _requestPermissionAfterDisclosure = false;
    }

    return await BackgroundLocationPermissions.hasForegroundLocationAccess();
  }

  Future<void> handleBannerEnableLocationAction(BuildContext context) async {
    if (!await confirmOnDutyFromApiForTracking()) {
      await refreshBackgroundLocationPermissionBannerState();
      return;
    }
    _lastAppliedStatus = onDuty;

    if (await BackgroundLocationPermissions.isBackgroundLocationFullyEnabled() &&
        await BackgroundLocationPermissions.hasPreciseLocationAccess() &&
        await LocationDisclosureConsent.hasAccepted()) {
      final result = await BackgroundLocationController.ensureStarted();
      if (result['ok'] == true) {
        await _syncPermissionReadyState();
      }
      await refreshBackgroundLocationPermissionBannerState();
      return;
    }

    _resetOnDutyAutoPromptState();
    await DutyTrackingPreferences.clearSettingsPromptDeferred();
    PermissionSettingsHelper.clearCooldown('background_location');
    final proceed = await prepareBannerLocationPermissionRequest(context);
    if (!proceed) return;

    await BackgroundLocationPermissions.refreshPermissionStateFromOs();
    await _advanceBannerLocationPermissionStep(context);

    if (!await confirmOnDutyFromApiForTracking()) {
      await refreshBackgroundLocationPermissionBannerState();
      return;
    }

    if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess() &&
        await BackgroundLocationPermissions.hasPreciseLocationAccess()) {
      final result = await BackgroundLocationController.ensureStarted();
      if (result['ok'] == true) {
        await _syncPermissionReadyState();
      }
    }
    await refreshBackgroundLocationPermissionBannerState();
  }

  Future<void> _advanceBannerLocationPermissionStep(
    BuildContext context,
  ) async {
    if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess() &&
        await BackgroundLocationPermissions.hasPreciseLocationAccess()) {
      return;
    }

    var deniedReason =
        await BackgroundLocationPermissions.settingsDeniedReasonIfAny();

    Future<void> showSettingsDialog() {
      return _showBackgroundLocationSettingsDialogIfNeeded(
        deniedReason: deniedReason,
        respectCooldown: false,
        userInitiated: true,
        context: context,
      );
    }

    switch (deniedReason) {
      case 'location_services_disabled':
      case 'location_always':
      case 'location_background':
      case 'location_precise':
        await showSettingsDialog();
        return;
      case 'location_foreground':
      case 'location_when_in_use':
        if (await PermissionSettingsHelper.foregroundRequiresSettingsPrompt()) {
          await showSettingsDialog();
          return;
        }
        await PermissionSettingsHelper.requestForegroundLocationStep();
        await BackgroundLocationPermissions.refreshPermissionStateFromOs();
        if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess() &&
            await BackgroundLocationPermissions.hasPreciseLocationAccess()) {
          return;
        }
        deniedReason =
            await BackgroundLocationPermissions.settingsDeniedReasonIfAny();
        await _showBackgroundLocationSettingsDialogIfNeeded(
          deniedReason: deniedReason,
          respectCooldown: false,
          userInitiated: true,
          context: context,
        );
        return;
      default:
        final phase =
            await BackgroundLocationPermissions.currentPermissionPhase();
        if (phase == LocationPermissionPhase.none &&
            !await PermissionSettingsHelper.foregroundRequiresSettingsPrompt()) {
          await PermissionSettingsHelper.requestForegroundLocationStep();
          await BackgroundLocationPermissions.refreshPermissionStateFromOs();
          if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess() &&
              await BackgroundLocationPermissions.hasPreciseLocationAccess()) {
            return;
          }
        }
        deniedReason =
            await BackgroundLocationPermissions.settingsDeniedReasonIfAny();
        await _showBackgroundLocationSettingsDialogIfNeeded(
          deniedReason: deniedReason,
          respectCooldown: false,
          userInitiated: true,
          context: context,
        );
    }
  }

  Future<bool> prepareBannerLocationPermissionRequest(
    BuildContext context,
  ) async {
    if (RequiredPermissionsGate.shouldSuppressCompetingDialogs) return false;

    if (!await LocationDisclosureConsent.shouldShowLocationDisclosure()) {
      _disclosureAccepted = true;
      return true;
    }

    _disclosureDeferred = false;

    await OverlayPromptGuard.waitUntilReady();
    final dialogContext = PermissionSettingsHelper.resolveDialogContext(
      context,
    );
    if (dialogContext == null) return false;

    final phase = await BackgroundLocationPermissions.currentPermissionPhase();
    final accepted = await LocationTrackingDisclosureDialog.show(
      dialogContext,
      phase: phase,
    );
    if (accepted) {
      _disclosureAccepted = true;
      _disclosureDeferred = false;
      _requestPermissionAfterDisclosure = true;
      await LocationDisclosureConsent.markAcceptedForAll();
    } else {
      _disclosureDeferred = true;
      _requestPermissionAfterDisclosure = false;
    }
    return accepted;
  }

  Future<bool> _runPostDisclosurePermissionStep({
    bool userInitiated = false,
  }) async {
    if (await BackgroundLocationPermissions.isBackgroundLocationFullyEnabled()) {
      return false;
    }

    final permissionReady =
        await BackgroundLocationPermissions.hasSufficientBackgroundAccess();
    final disclosureAccepted = await LocationDisclosureConsent.hasAccepted();
    final shouldRunPermissionFlow =
        userInitiated ||
        _requestPermissionAfterDisclosure ||
        (!permissionReady && disclosureAccepted);

    if (!shouldRunPermissionFlow) return false;
    _requestPermissionAfterDisclosure = false;

    final phase = await BackgroundLocationPermissions.currentPermissionPhase();
    switch (phase) {
      case LocationPermissionPhase.none:
        await PermissionSettingsHelper.requestForegroundLocationStep();
        break;
      case LocationPermissionPhase.foregroundOnly:
      case LocationPermissionPhase.backgroundReady:
        break;
    }

    if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
      return false;
    }

    return _showBackgroundLocationSettingsDialogIfNeeded(
      deniedReason:
          await BackgroundLocationPermissions.settingsDeniedReasonIfAny(),
      respectCooldown: false,
      userInitiated: userInitiated,
    );
  }

  Future<void> retryOnDutyTrackingIfReady() async {
    if (!await confirmOnDutyFromApiForTracking()) return;
    _lastAppliedStatus = onDuty;
    if (!await LocationDisclosureConsent.hasAccepted()) return;
    if (!await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
      await promptBackgroundLocationSettingsIfNeeded();
      await refreshBackgroundLocationPermissionBannerState();
      return;
    }

    final healthy = await BackgroundLocationController.isTrackingHealthy();
    if (healthy) {
      _locationSharingArmedThisDuty = true;
      await refreshBackgroundLocationPermissionBannerState();
      return;
    }

    final result = await BackgroundLocationController.ensureStarted();
    debugPrint(
      '[DutyHeartbeatService] retry ensureStarted ok=${result['ok'] == true}',
    );
    if (result['ok'] == true) {
      _locationSharingArmedThisDuty = true;
      await _syncPermissionReadyState();
    } else if (result['openSettings'] == true) {
      await _showBackgroundLocationSettingsDialogIfNeeded(
        deniedReason: result['deniedReason']?.toString(),
      );
    }
    await refreshBackgroundLocationPermissionBannerState();
  }

  Future<void> promptBackgroundLocationSettingsIfNeeded() async {
    if (_lastAppliedStatus != onDuty) return;
    if (!await LocationDisclosureConsent.hasAccepted()) return;
    if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
      return;
    }
    await _showBackgroundLocationSettingsDialogIfNeeded(
      deniedReason:
          await BackgroundLocationPermissions.settingsDeniedReasonIfAny(),
    );
  }

  Future<void> _applyOffDuty({bool allowAnnounce = true}) async {
    debugPrint('[DutyLocation] off_duty → stopping location tracking');
    debugPrint(
      '[DutyHeartbeatService] stopping location after flushing pending batches',
    );

    final wasOnDuty = _lastAppliedStatus == onDuty;
    final wasSharing = await _shouldAnnounceLocationStop();

    // Clear on_duty snapshot first so any in-flight FGS fix stops uploading.
    await DutyStatusSnapshot.clear();

    if (Platform.isIOS) {
      await IosSignificantLocationChangeService.setOnDuty(false);
    }
    final result = await BackgroundLocationController.stop();
    debugPrint('[DutyHeartbeatService] stop ok=${result['ok'] == true}');

    if (allowAnnounce && wasOnDuty && wasSharing) {
      await LocationSharingStatusNotification.tryAnnounceStopped(
        reason: LocationSharingStopReason.shiftEnded,
      );
    } else {
      await LocationSharingStatusNotification.dismissSharing();
    }

    _locationSharingArmedThisDuty = false;
    _lastAppliedStatus = offDuty;
    _resetDisclosureState();
    PermissionSettingsHelper.clearCooldown('background_location');
    await DutyTrackingPreferences.clearOnOffDuty();
    await refreshBackgroundLocationPermissionBannerState();
  }

  void resetLocationDisclosureMemory() {
    _disclosureAccepted = false;
    _disclosureDeferred = false;
    _requestPermissionAfterDisclosure = false;
    _disclosurePromptInFlight = false;
    _disclosurePromptFuture = null;
    _setDisclosurePromptVisible(false);
  }

  void _resetDisclosureState() {
    resetLocationDisclosureMemory();
    _resetOnDutyAutoPromptState();
  }

  Future<void> _reconcileBgLocationReadyFlag() async {
    if (!await DutyTrackingPreferences.isBgLocationReady()) return;
    if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
      return;
    }
    await DutyTrackingPreferences.clearBgLocationReady();
  }

  Future<bool> _shouldSkipSettingsPrompt() async {
    if (await DutyTrackingPreferences.isSettingsPromptDeferred()) {
      return true;
    }
    if (!await DutyTrackingPreferences.isBgLocationReady()) {
      return false;
    }
    return BackgroundLocationPermissions.hasSufficientBackgroundAccess();
  }

  Future<void> _handleIosPermissionChangeIfNeeded() async {
    if (!Platform.isIOS) return;

    final permission =
        await BackgroundLocationPermissions.refreshIosLocationPermission();
    final previous = _lastKnownIosPermission;
    _lastKnownIosPermission = permission;

    if (previous == null) return;

    final upgradedToAlways =
        permission == LocationPermission.always &&
        previous != LocationPermission.always;

    if (upgradedToAlways) {
      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] ios permission upgraded to always; restarting tracking',
        );
      }
      await _restartTrackingWithCurrentPermission();
    }
  }

  Future<void> _restartTrackingWithCurrentPermission() async {
    if (!await confirmOnDutyFromApiForTracking()) return;
    _lastAppliedStatus = onDuty;
    final result = await BackgroundLocationController.restart();
    if (kDebugMode) {
      debugPrint(
        '[DutyHeartbeatService] tracking restarted after permission change ok=${result['ok'] == true}',
      );
    }
    if (result['ok'] == true) {
      await _syncPermissionReadyState();
      await refreshBackgroundLocationPermissionBannerState();
    }
  }

  Future<void> _syncPermissionReadyState() async {
    if (!await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
      await refreshBackgroundLocationPermissionBannerState();
      return;
    }
    await DutyTrackingPreferences.setBgLocationReady();
    await LocationDisclosureConsent.markAcceptedForAll();
    _disclosureAccepted = true;
    _disclosureDeferred = false;
    _requestPermissionAfterDisclosure = false;
    await refreshBackgroundLocationPermissionBannerState();
  }

  Future<bool> _confirmBackgroundLocationDisclosure({
    bool forceRetry = false,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    if (!await LocationDisclosureConsent.shouldShowLocationDisclosure()) {
      _disclosureAccepted = true;
      return true;
    }

    if (_disclosureAccepted || await LocationDisclosureConsent.hasAccepted()) {
      _disclosureAccepted = true;
      if (!await DutyTrackingPreferences.isDisclosureAccepted()) {
        await DutyTrackingPreferences.setDisclosureAccepted();
      }
      return true;
    }

    if (!forceRetry && _disclosureDeferred) {
      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] disclosure skipped (deferred this session)',
        );
      }
      return false;
    }

    if (_disclosurePromptFuture != null) {
      return _disclosurePromptFuture!;
    }

    final completer = Completer<bool>();
    _disclosurePromptFuture = completer.future;
    _disclosurePromptInFlight = true;
    unawaited(_completeDisclosurePrompt(completer, forceRetry: forceRetry));
    return completer.future;
  }

  Future<void> _completeDisclosurePrompt(
    Completer<bool> completer, {
    bool forceRetry = false,
  }) async {
    _setDisclosurePromptVisible(true);
    try {
      if (!_heartbeatActive || !await _hasActiveAuthToken()) {
        completer.complete(false);
        return;
      }

      if (!forceRetry && _disclosureDeferred) {
        completer.complete(false);
        return;
      }

      if (!await LocationDisclosureConsent.shouldShowLocationDisclosure()) {
        _disclosureAccepted = true;
        completer.complete(true);
        return;
      }

      final context = AppNavigator.key.currentContext;
      if (context == null || !context.mounted) {
        debugPrint(
          '[DutyHeartbeatService] disclosure skipped: navigator context unavailable',
        );
        completer.complete(false);
        return;
      }

      await OverlayPromptGuard.waitUntilReady();
      if (!_heartbeatActive || !await _hasActiveAuthToken()) {
        completer.complete(false);
        return;
      }

      if (!forceRetry && _disclosureDeferred) {
        completer.complete(false);
        return;
      }

      final promptContext = AppNavigator.key.currentContext;
      if (promptContext == null || !promptContext.mounted) {
        completer.complete(false);
        return;
      }

      completer.complete(
        await _promptBackgroundLocationDisclosure(forceRetry: forceRetry),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[DutyHeartbeatService] disclosure prompt failed: $e\n$st');
      }
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    } finally {
      _disclosurePromptInFlight = false;
      _setDisclosurePromptVisible(false);
      if (identical(_disclosurePromptFuture, completer.future)) {
        _disclosurePromptFuture = null;
      }
    }
  }

  Future<bool> _promptBackgroundLocationDisclosure({
    bool forceRetry = false,
  }) async {
    if (RequiredPermissionsGate.shouldSuppressCompetingDialogs) return false;
    if (!forceRetry && _disclosureDeferred) {
      return false;
    }

    final context = AppNavigator.key.currentContext;
    if (context == null || !context.mounted) return false;

    if (!await LocationDisclosureConsent.shouldShowLocationDisclosure()) {
      _disclosureAccepted = true;
      return true;
    }

    final phase = await BackgroundLocationPermissions.currentPermissionPhase();

    final allowed = await LocationTrackingDisclosureDialog.show(
      context,
      phase: phase,
    );
    if (allowed) {
      _disclosureAccepted = true;
      _disclosureDeferred = false;
      _requestPermissionAfterDisclosure = true;
      await LocationDisclosureConsent.markAcceptedForAll();
      return true;
    }

    _disclosureDeferred = true;
    _requestPermissionAfterDisclosure = false;
    return false;
  }

  Future<bool> _showPermissionDeniedSettingsDialog({
    String? deniedReason,
    bool respectCooldown = true,
    bool ignoreDeferred = false,
    bool userInitiated = false,
    BuildContext? context,
  }) async {
    if (_backgroundLocationSettingsDialogVisible) return false;

    if (!userInitiated && _onDutyAutoPromptComplete) {
      await refreshBackgroundLocationPermissionBannerState();
      return false;
    }

    if (await BackgroundLocationPermissions.isBackgroundLocationFullyEnabled() &&
        await BackgroundLocationPermissions.hasPreciseLocationAccess()) {
      await _syncPermissionReadyState();
      await refreshBackgroundLocationPermissionBannerState();
      return false;
    }

    if (!ignoreDeferred && await _shouldSkipSettingsPrompt()) {
      await refreshBackgroundLocationPermissionBannerState();
      return false;
    }

    await OverlayPromptGuard.waitUntilReady();
    if (_backgroundLocationSettingsDialogVisible) return false;

    _backgroundLocationSettingsDialogVisible = true;
    try {
      final result = await PermissionSettingsHelper.promptOpenSettings(
        title: BackgroundLocationPermissions.settingsTitleFor(deniedReason),
        message: BackgroundLocationPermissions.settingsDialogMessageFor(
          deniedReason,
        ),
        dialogKey: BackgroundLocationPermissions.settingsDialogKeyFor(
          deniedReason,
        ),
        respectCooldown: respectCooldown,
        secondaryLabel: LocationTrackingDisclosureDialog.cancelDutyLabel,
        destructiveSecondary: true,
        skipOverlayWait: userInitiated,
        context: context,
      );

      if (result == PermissionSettingsPromptResult.skipped) {
        return false;
      }

      await _reconcileBgLocationReadyFlag();
      await _handleIosPermissionChangeIfNeeded();
      if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess() &&
          await BackgroundLocationPermissions.hasPreciseLocationAccess()) {
        await _syncPermissionReadyState();
        if (await _isLocationTrackingRunning()) {
          await _restartTrackingWithCurrentPermission();
        } else {
          await _applyOnDuty();
        }
        await refreshBackgroundLocationPermissionBannerState();
        return true;
      }

      if (result == PermissionSettingsPromptResult.dismissed &&
          !ignoreDeferred) {
        await DutyTrackingPreferences.setSettingsPromptDeferred();
      }
      return result != PermissionSettingsPromptResult.skipped;
    } finally {
      _backgroundLocationSettingsDialogVisible = false;
      await refreshBackgroundLocationPermissionBannerState();
    }
  }

  Future<bool> _showBackgroundLocationSettingsDialogIfNeeded({
    String? deniedReason,
    bool respectCooldown = true,
    bool userInitiated = false,
    BuildContext? context,
  }) async {
    if (RequiredPermissionsGate.shouldSuppressCompetingDialogs) return false;
    if (_backgroundLocationSettingsDialogVisible) return false;

    if (!userInitiated && _onDutyAutoPromptComplete) {
      await refreshBackgroundLocationPermissionBannerState();
      return false;
    }

    if (await BackgroundLocationPermissions.isBackgroundLocationFullyEnabled() &&
        await BackgroundLocationPermissions.hasPreciseLocationAccess()) {
      await _syncPermissionReadyState();
      await refreshBackgroundLocationPermissionBannerState();
      return false;
    }

    if (respectCooldown && await _shouldSkipSettingsPrompt()) {
      await refreshBackgroundLocationPermissionBannerState();
      return false;
    }

    final reason =
        deniedReason ??
        await BackgroundLocationPermissions.settingsDeniedReasonIfAny();

    if ((reason == 'location_foreground' || reason == 'location_when_in_use') &&
        !userInitiated) {
      await refreshBackgroundLocationPermissionBannerState();
      return false;
    }

    final shown = await _showPermissionDeniedSettingsDialog(
      deniedReason: reason,
      respectCooldown: respectCooldown,
      ignoreDeferred: !respectCooldown,
      userInitiated: userInitiated,
      context: context,
    );
    await refreshBackgroundLocationPermissionBannerState();
    return shown;
  }
}
