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
import '../../permissions/os_notification_permission.dart';
import '../../permissions/required_permissions_gate.dart';
import '../../utilities/overlay_prompt_guard.dart';
import '../../utilities/permission_settings_helper.dart';
import '../../utilities/device_identity.dart';
import '../../widgets/dialogs/location_tracking_disclosure_dialog.dart';
import '../location/android_duty_location_health.dart';
import '../location/background_location_controller.dart';
import '../location/background_location_permissions.dart';
import '../location/background_location_service.dart';
import '../location/location_sharing_status_notification.dart';
import 'clock_in_gate_service.dart';
import 'duty_heartbeat_client.dart';
import 'duty_tracking_preferences.dart';
import 'android_duty_kill_watch.dart';
import '../ios/ios_duty_location_pinger.dart';
import '../ios/ios_significant_location_change_service.dart';
import 'duty_status_snapshot.dart';
import 'location_disclosure_consent.dart';
import 'on_duty_permissions_prompt_service.dart';
import '../../utilities/app_debug_log.dart';

class DutyHeartbeatService {
  DutyHeartbeatService._() {
    BackgroundLocationController.confirmOnDutyBeforeStart = () {
      return confirmOnDutyFromApiForTracking(stopIfNotOnDuty: true);
    };
    AuthRepository.onSecureTokensChanged = () {
      unawaited(_mirrorNativeAuthSession());
    };
    unawaited(_mirrorNativeAuthSession());
    if (Platform.isIOS) {
      IosDutyLocationPinger.confirmOnDutyBeforeStart = () {
        return confirmOnDutyFromApiForTracking(stopIfNotOnDuty: true);
      };
      IosSignificantLocationChangeService.setOnLocationWake(() {
        return recoverAfterIosLocationWakeIfNeeded();
      });
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
  int _clockInBurstGeneration = 0;
  DateTime? _optimisticClockInTrackingUntil;
  Future<void>? _clockInImmediateStartFuture;
  DateTime? _lastHeartbeatSuccessAt;
  String? _lastAppliedStatus;
  bool _locationPausedForUnpaidBreak = false;
  String? _lastWorkingStatus;
  String? _lastBreakType;
  bool? _lastBreakPaid;
  bool _disclosureAccepted = false;
  bool _disclosureDeferred = false;
  bool _requestPermissionAfterDisclosure = false;
  bool _disclosurePromptInFlight = false;
  bool _backgroundLocationSettingsDialogVisible = false;

  bool _onDutyAutoPromptComplete = false;
  bool _locationSharingArmedThisDuty = false;
  Future<void>? _applyOnDutyFuture;
  Future<void>? _ensureTrackingFuture;
  Future<void>? _locationWakeRecoverFuture;
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
      _heartbeatActive &&
      _lastAppliedStatus == onDuty &&
      !_locationPausedForUnpaidBreak;

  bool get isLocationPausedForUnpaidBreak => _locationPausedForUnpaidBreak;

  Future<bool> isOnDutyAccordingToHeartbeat() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    if (!await _hasActiveAuthToken()) return false;

    try {
      final payload = await _fetchHeartbeat();
      if (payload?.isOnDuty == true) {
        if (payload!.allowsLocationTracking) {
          await DutyStatusSnapshot.markOnDuty();
          await _setNativeUnpaidBreak(false);
        } else {
          await DutyStatusSnapshot.clear();
          await _setNativeUnpaidBreak(true);
        }
        return true;
      }
      if (payload?.isOffDuty == true) {
        await DutyStatusSnapshot.clear();
        await _setNativeUnpaidBreak(false);
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

  Future<void> recoverAfterIosLocationWakeIfNeeded() async {
    if (!Platform.isIOS) return;

    final inFlight = _locationWakeRecoverFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final future = _recoverAfterIosLocationWakeIfNeededImpl();
    _locationWakeRecoverFuture = future;
    try {
      await future;
    } finally {
      if (identical(_locationWakeRecoverFuture, future)) {
        _locationWakeRecoverFuture = null;
      }
    }
  }

  Future<void> _recoverAfterIosLocationWakeIfNeededImpl() async {
    final ready = await IosSignificantLocationChangeService.ensureNativeReady();
    if (!ready) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] iOS location wake skipped; SLC channel not ready',
      );
      return;
    }

    final loggedIn = await AuthRepository.instance.isOfficerLoggedIn();
    final token = await AuthRepository.instance.getAccessToken();
    final hasToken = token != null && token.isNotEmpty;
    if (!loggedIn || !hasToken) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] iOS location wake stopped; '
        'not logged in or no auth token',
      );
      await DutyStatusSnapshot.clear();
      await IosSignificantLocationChangeService.setOnDuty(false);
      await BackgroundLocationController.stop();
      return;
    }

    final status = await IosSignificantLocationChangeService.status();
    final launchedForLocation = status['launchedForLocation'] == true;
    final nativeOnDuty = status['onDuty'] == true;
    final nativeRunning = status['running'] == true;

    if (!nativeOnDuty && !nativeRunning) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] iOS location wake ignored; native duty/slc not armed',
      );
      return;
    }

    if (launchedForLocation) {
      await IosSignificantLocationChangeService.claimWake();
    }

    if (!nativeOnDuty) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] iOS location wake stopped; native onDuty=false',
      );
      await IosSignificantLocationChangeService.setOnDuty(false);
      return;
    }

    dutyHeartbeatDebugLog(
      launchedForLocation
          ? '[DutyHeartbeatService] iOS location wake; confirming duty before GPS'
          : '[DutyHeartbeatService] iOS on-duty launch; confirming duty before GPS',
    );

    final allowed = await confirmOnDutyFromApiForTracking(
      stopIfNotOnDuty: true,
    );
    if (!allowed) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] iOS location wake stopped; officer is not on_duty',
      );
      return;
    }

    // Login / logout may have raced while we confirmed duty.
    if (!await AuthRepository.instance.isOfficerLoggedIn()) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] iOS location wake aborted; logged out during confirm',
      );
      await DutyStatusSnapshot.clear();
      await IosSignificantLocationChangeService.setOnDuty(false);
      await BackgroundLocationController.stop();
      return;
    }

    _lastAppliedStatus = onDuty;
    await IosDutyLocationPinger.recoverIfNeeded(
      fromLocationWake: true,
      dutyAlreadyConfirmed: true,
    );
    start();
  }

  static Future<void> _mirrorNativeAuthSession() async {
    if (Platform.isAndroid) {
      final access = await AuthRepository.instance.getAccessToken();
      if (access == null || access.isEmpty) {
        await AndroidDutyKillWatch.disarm();
        return;
      }
      if (await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) {
        if (await AndroidDutyKillWatch.isKillWatchArmed()) {
          await AndroidDutyKillWatch.syncTokens();
        } else {
          await AndroidDutyKillWatch.arm();
        }
      } else {
        await AndroidDutyKillWatch.syncTokens();
      }
      return;
    }
    if (!Platform.isIOS) return;
    final access = await AuthRepository.instance.getAccessToken();
    final refresh = await AuthRepository.instance.getRefreshToken();
    if (access == null || access.isEmpty) {
      await IosSignificantLocationChangeService.syncNativeAuth(clear: true);
      await IosSignificantLocationChangeService.setOnDuty(false);
      return;
    }
    await IosSignificantLocationChangeService.syncNativeAuth(
      accessToken: access,
      refreshToken: refresh,
      deviceId: await DeviceIdentity.getDeviceId(),
    );
  }

  Future<bool> confirmOnDutyFromApiForTracking({
    bool stopIfNotOnDuty = true,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    if (!await AuthRepository.instance.isOfficerLoggedIn()) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] tracking denied; officer not logged in',
      );
      await DutyStatusSnapshot.clear();
      if (stopIfNotOnDuty) {
        await _stopTrackingForFailedDutyConfirm();
      }
      return false;
    }

    final onlineAuth = await _hasActiveAuthToken();
    if (!onlineAuth) {
      final cached = await AuthRepository.instance.getAccessToken();
      if (cached != null &&
          cached.isNotEmpty &&
          await DutyStatusSnapshot.isValidOnDutyForCurrentUser() &&
          !await _isNativeUnpaidBreak()) {
        dutyHeartbeatDebugLog(
          '[DutyHeartbeatService] offline snapshot allows on_duty '
          '(cached token, refresh unavailable)',
        );
        return true;
      }
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] tracking denied; no auth token',
      );
      await DutyStatusSnapshot.clear();
      if (stopIfNotOnDuty) {
        await _stopTrackingForFailedDutyConfirm();
      }
      return false;
    }

    try {
      final payload = await _fetchHeartbeat();
      if (payload != null && payload.allowsLocationTracking) {
        await DutyStatusSnapshot.markOnDuty();
        await _setNativeUnpaidBreak(false);
        _locationPausedForUnpaidBreak = false;
        dutyHeartbeatDebugLog(
          '[DutyHeartbeatService] heartbeat confirmed on_duty for tracking',
        );
        _clearOptimisticClockInTracking();
        return true;
      }

      if (payload != null && payload.isUnpaidBreak) {
        dutyHeartbeatDebugLog(
          '[DutyHeartbeatService] tracking denied; unpaid break active',
        );
        await DutyStatusSnapshot.clear();
        await _setNativeUnpaidBreak(true);
        if (stopIfNotOnDuty) {
          await _pauseLocationForUnpaidBreak(
            payload: payload,
            notify: !_locationPausedForUnpaidBreak,
            source: 'confirm',
          );
        }
        return false;
      }

      if (payload?.dutyStatus == offDuty) {
        if (_isOptimisticClockInTrackingActive()) {
          dutyHeartbeatDebugLog(
            '[DutyHeartbeatService] tracking denied deferred; '
            'optimistic clock-in window active',
          );
          return true;
        }
        dutyHeartbeatDebugLog(
          '[DutyHeartbeatService] tracking denied; heartbeat status=off_duty',
        );
        await DutyStatusSnapshot.clear();
        await _setNativeUnpaidBreak(false);
        if (stopIfNotOnDuty) {
          await _applyOffDuty();
        }
        return false;
      }

      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] heartbeat status=${payload?.dutyStatus}; '
        'trying offline snapshot',
      );
    } catch (e) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] heartbeat fetch failed; trying offline snapshot: $e',
      );
    }

    if (await DutyStatusSnapshot.isValidOnDutyForCurrentUser() &&
        !await _isNativeUnpaidBreak()) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] offline snapshot allows on_duty tracking',
      );
      return true;
    }

    dutyHeartbeatDebugLog(
      '[DutyHeartbeatService] tracking denied; no on_duty API or snapshot',
    );
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
    final wasMissing = backgroundLocationPermissionMissing.value;
    if (backgroundLocationPermissionMissing.value != missing) {
      backgroundLocationPermissionMissing.value = missing;
    }

    // Permission just became sufficient while still on duty — Flutter must
    // start FGS (native kill-watch does not start FGS while UI is open).
    if (wasMissing && !missing && _heartbeatActive) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] BG permission became ready on duty; '
        'retrying ensureStarted',
      );
      unawaited(retryOnDutyTrackingIfReady());
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

  void beginResumeDutyReconcile() {
    _deferTrackingStart = true;
  }

  void endResumeDutyReconcile() {
    _deferTrackingStart = false;
    // Resume may have deferred on_duty tracking start while prompts ran.
    // Permissions may also have just become granted — start FGS from Flutter.
    unawaited(_retryTrackingAfterResumeIfNeeded());
  }

  Future<void> _retryTrackingAfterResumeIfNeeded() async {
    if (!_heartbeatActive) return;
    final onDutyLikely =
        _lastAppliedStatus == onDuty ||
        _locationSharingArmedThisDuty ||
        _optimisticClockInTrackingUntil != null ||
        await DutyStatusSnapshot.isValidOnDutyForCurrentUser();
    if (!onDutyLikely) return;
    await retryOnDutyTrackingIfReady();
  }

  void start() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_pollTimer != null) return;

    _heartbeatActive = true;
    LocationSharingStatusNotification.resetSignedOutGate();
    ApiClient.instance.ensureAuthInterceptorInstalled();
    dutyHeartbeatDebugLog('[DutyHeartbeatService] starting heartbeat polling');

    unawaited(_hydrateConsentFromStorage());
    unawaited(_pollOnce());
    _scheduleNextPoll();
  }

  void pollAfterClockInSuccess() {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    _pollTimer?.cancel();
    _pollTimer = null;

    if (!_heartbeatActive) {
      _heartbeatActive = true;
      LocationSharingStatusNotification.resetSignedOutGate();
      ApiClient.instance.ensureAuthInterceptorInstalled();
      unawaited(_hydrateConsentFromStorage());
    }

    _resetOnDutyAutoPromptState();
    if (_lastAppliedStatus == onDuty) {
      _lastAppliedStatus = offDuty;
    }

    unawaited(_burstPollAfterClockInSuccess());
  }

  void onClockInSuccessFromBridge() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    ClockInGateService.instance.onClockInSucceeded();
    dutyHeartbeatDebugLog(
      '[DutyHeartbeatService] clock_in_success from bridge; immediate start queued',
    );
    pollAfterClockInSuccess();
    unawaited(_beginTrackingImmediatelyAfterClockInSuccess());
  }

  void _clearOptimisticClockInTracking() {
    _optimisticClockInTrackingUntil = null;
  }

  bool _isOptimisticClockInTrackingActive() {
    final until = _optimisticClockInTrackingUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  Future<bool> _shouldDeferOffDutyTrackingStop() async {
    if (_isOptimisticClockInTrackingActive()) return true;
    if (_clockInImmediateStartFuture != null) return true;
    if (ClockInGateService.instance.isPrepareInFlight) return true;
    if (ClockInGateService.instance.isGeoUnlockedForClockIn) return true;
    if (ClockInGateService.instance.isClockInAttemptActive) return true;
    return false;
  }

  Future<void> _beginTrackingImmediatelyAfterClockInSuccess() async {
    final inFlight = _clockInImmediateStartFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final future = _beginTrackingImmediatelyAfterClockInSuccessImpl();
    _clockInImmediateStartFuture = future;
    try {
      await future;
    } finally {
      if (identical(_clockInImmediateStartFuture, future)) {
        _clockInImmediateStartFuture = null;
      }
    }
  }

  Future<void> _beginTrackingImmediatelyAfterClockInSuccessImpl() async {
    if (_deferTrackingStart) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] immediate clock-in start deferred (resume reconcile)',
      );
      return;
    }
    if (!await _hasActiveAuthTokenForImmediateClockInStart()) return;
    if (!await _clockInImmediateStartEligible()) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] immediate clock-in start skipped: not eligible',
      );
      return;
    }

    _optimisticClockInTrackingUntil = DateTime.now().add(
      const Duration(seconds: 90),
    );
    _heartbeatActive = true;
    LocationSharingStatusNotification.resetShiftEndedGate();
    ApiClient.instance.ensureAuthInterceptorInstalled();
    await DutyStatusSnapshot.markOnDuty();

    if (await BackgroundLocationController.isTrackingHealthy()) {
      _locationSharingArmedThisDuty = true;
      _lastAppliedStatus = onDuty;
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] immediate clock-in start: already tracking',
      );
      return;
    }

    if (Platform.isAndroid) {
      unawaited(BackgroundLocationService.preWarmForClockIn());
    }

    final clockInFastStart = await _clockInFastStartEligible();
    dutyHeartbeatDebugLog(
      '[DutyHeartbeatService] immediate clock-in start: launching tracking'
      '${clockInFastStart ? ' (fast)' : ''}',
    );

    final result = await BackgroundLocationController.ensureStarted(
      clockInFastStart: clockInFastStart,
    );
    if (result['ok'] == true) {
      _locationSharingArmedThisDuty = true;
      _lastAppliedStatus = onDuty;
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] immediate clock-in start ok=true',
      );
    } else {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] immediate clock-in start failed: '
        '${result['error']}',
      );
    }
  }

  Future<bool> _clockInImmediateStartEligible() async {
    if (ClockInGateService.instance.isPrepareInFlight) return false;
    if (OverlayPromptGuard.blocksTopBanner) return false;
    if (RequiredPermissionsGate.shouldSuppressCompetingDialogs) return false;
    if (disclosurePromptVisible.value) return false;
    if (!await LocationDisclosureConsent.hasAccepted()) return false;
    if (!await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
      return false;
    }
    return await RequiredPermissionsGate.instance.areClockInPermissionsReady();
  }

  void _cancelClockInBurst() {
    _clockInBurstGeneration++;
    _clearOptimisticClockInTracking();
  }

  Future<void> _burstPollAfterClockInSuccess() async {
    final generation = ++_clockInBurstGeneration;

    for (var attempt = 1; attempt <= 15; attempt++) {
      if (generation != _clockInBurstGeneration || !_heartbeatActive) {
        return;
      }

      final waitDeadline = DateTime.now().add(const Duration(seconds: 2));
      while (_pollInFlight && DateTime.now().isBefore(waitDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (generation != _clockInBurstGeneration || !_heartbeatActive) {
        return;
      }

      await _pollOnce();

      if (generation != _clockInBurstGeneration || !_heartbeatActive) {
        return;
      }

      if (_lastAppliedStatus == onDuty) {
        await _applyOnDuty();

        final running = await _isLocationTrackingRunning();
        if (running || _locationSharingArmedThisDuty) {
          break;
        }
      }

      if (attempt < 15) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }

    if (generation == _clockInBurstGeneration && _heartbeatActive) {
      if (_lastAppliedStatus != onDuty &&
          _isOptimisticClockInTrackingActive()) {
        _clearOptimisticClockInTracking();
        dutyHeartbeatDebugLog(
          '[DutyHeartbeatService] clock-in burst ended without on_duty; '
          'stopping optimistic tracking',
        );
        if (Platform.isAndroid) {
          unawaited(BackgroundLocationService.cancelClockInWarm());
        }
        await _applyOffDuty();
      }
      _scheduleNextPoll();
    }
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
        // On resume, OnDutyPermissionsDialog covers missing notifications.
        promptIfNeeded: !fromResume,
      );
      await OverlayPromptGuard.waitUntilReady();
    }

    await _hydrateConsentFromStorage();
    await _reconcileBgLocationReadyFlag();
    await _syncPermissionReadyState();

    DutyHeartbeatPayload? payload;
    try {
      payload = await _fetchHeartbeat();
    } catch (e) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] recheck heartbeat failed (offline?): $e',
      );
      payload = null;
    }

    if (payload != null && payload.isUnpaidBreak) {
      final shouldNotify = !_locationPausedForUnpaidBreak;
      await _pauseLocationForUnpaidBreak(
        payload: payload,
        notify: shouldNotify,
        source: 'recheck',
      );
      await refreshBackgroundLocationPermissionBannerState();
      return;
    }

    final status = payload?.dutyStatus;

    if (status == offDuty) {
      if (_isOptimisticClockInTrackingActive()) {
        dutyHeartbeatDebugLog(
          '[DutyHeartbeatService] recheck: ignore transient off_duty during clock-in',
        );
        await refreshBackgroundLocationPermissionBannerState();
        return;
      }
      await _applyOffDuty();
      await refreshBackgroundLocationPermissionBannerState();
      return;
    }

    if (status != onDuty) {
      if (!await DutyStatusSnapshot.isValidOnDutyForCurrentUser() ||
          await _isNativeUnpaidBreak()) {
        if (fromResume) {
          await _ensureOffDutyTrackingStopped();
        }
        await refreshBackgroundLocationPermissionBannerState();
        return;
      }
      if (fromResume) {
        final running = await _isLocationTrackingRunning();
        if (!running) {
          dutyHeartbeatDebugLog(
            '[DutyHeartbeatService] resume: no API on_duty and GPS '
            'not running — not starting',
          );
          await refreshBackgroundLocationPermissionBannerState();
          return;
        }
        _lastAppliedStatus = onDuty;
        _locationSharingArmedThisDuty = true;
        await refreshBackgroundLocationPermissionBannerState();
        return;
      }
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] recheck using offline on_duty snapshot',
      );
    } else {
      await _setNativeUnpaidBreak(false);
      _locationPausedForUnpaidBreak = false;
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

    if (pageReload && _isOptimisticClockInTrackingActive()) {
      final running = await _isLocationTrackingRunning();
      if (running || _clockInImmediateStartFuture != null) {
        dutyHeartbeatDebugLog(
          '[DutyHeartbeatService] recheck skipped; immediate clock-in start active',
        );
        await refreshBackgroundLocationPermissionBannerState();
        return;
      }
    }

    await _ensureTrackingRunningForOnDuty(
      // Resume: do not show Always/settings/disclosure dialogs — the
      // OnDutyPermissionsDialog already covers all missing permissions.
      allowPrompts: !pageReload && !fromResume,
      ignoreDefer: fromResume,
    );
    await refreshBackgroundLocationPermissionBannerState();
  }

  Future<void> _ensureTrackingRunningForOnDuty({
    required bool allowPrompts,
    bool ignoreDefer = false,
  }) async {
    if (_lastAppliedStatus != onDuty) return;
    if (_deferTrackingStart && !ignoreDefer) {
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
    if (_locationPausedForUnpaidBreak || await _isNativeUnpaidBreak()) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] skip tracking ensure; unpaid break active',
      );
      return;
    }

    final healthy = await BackgroundLocationController.isTrackingHealthy();
    if (healthy) {
      _locationSharingArmedThisDuty = true;
      return;
    }

    final running = await _isLocationTrackingRunning();
    if (running && Platform.isAndroid) {
      if (BackgroundLocationController.isUiBackgrounded) {
        _locationSharingArmedThisDuty = true;
        return;
      }
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] on_duty Android tracking stale; recovering',
      );
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
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] skip GPS start; UI is backgrounded',
      );
      return;
    }

    if (running && Platform.isIOS) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] on_duty iOS stream live; skipping rebuild',
      );
      _locationSharingArmedThisDuty = true;
      return;
    }

    final disclosureAccepted = await LocationDisclosureConsent.hasAccepted();
    final backgroundReady =
        await BackgroundLocationPermissions.hasSufficientBackgroundAccess();

    if (disclosureAccepted && backgroundReady) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] on_duty but tracking not running; starting',
      );
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
    if (await _shouldDeferOffDutyTrackingStop()) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] defer off_duty stop during clock-in flow',
      );
      return;
    }

    await DutyStatusSnapshot.clear();
    await AndroidDutyKillWatch.disarm(forceOff: true);

    final running = await _isLocationTrackingRunning();
    if (!running) {
      AndroidDutyLocationHealth.markStopped();
      return;
    }

    dutyHeartbeatDebugLog(
      '[DutyHeartbeatService] off_duty but tracking still running; stopping',
    );
    final result = await BackgroundLocationController.stop();
    dutyHeartbeatDebugLog(
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
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] on_duty but location stream not running; recovering',
      );
      await _restartTrackingWithCurrentPermission();
      return;
    }

    if (IosDutyLocationPinger.needsRecovery) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] on_duty location stream dead; recovering',
      );
      await IosDutyLocationPinger.recoverIfNeeded();
      return;
    }
  }

  Future<void> stop({bool stopBackgroundLocation = true}) async {
    _cancelClockInBurst();
    _heartbeatActive = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInFlight = false;
    _resetDisclosureState();
    backgroundLocationPermissionMissing.value = false;
    dutyHeartbeatDebugLog('[DutyHeartbeatService] stopped heartbeat polling');

    if (stopBackgroundLocation) {
      await _applyOffDuty(allowAnnounce: false);
    }
    _lastAppliedStatus = null;
    _locationSharingArmedThisDuty = false;
  }

  Future<void> finalizeLogoutInstant() async {
    final wasSharing = await _shouldAnnounceLocationStop();
    _cancelClockInBurst();
    _heartbeatActive = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInFlight = false;
    _lastAppliedStatus = offDuty;
    _locationSharingArmedThisDuty = false;
    _resetDisclosureState();
    backgroundLocationPermissionMissing.value = false;
    PermissionSettingsHelper.clearCooldown('background_location');
    dutyHeartbeatDebugLog(
      '[DutyHeartbeatService] instant logout (heartbeat + tracking stopped)',
    );
    unawaited(DutyStatusSnapshot.clear());
    unawaited(AndroidDutyKillWatch.disarm(forceOff: true));
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
            await DutyStatusSnapshot.isValidOnDutyForCurrentUser() &&
            !await _isNativeUnpaidBreak()) {
          dutyHeartbeatDebugLog(
            '[DutyHeartbeatService] poll auth refresh failed; '
            'keeping offline on_duty from snapshot',
          );
          _lastAppliedStatus = onDuty;
          await _ensureTrackingRunningForOnDuty(allowPrompts: true);
          return;
        }
        dutyHeartbeatDebugLog(
          '[DutyHeartbeatService] no auth token; stopping heartbeat and location',
        );
        await stop();
        return;
      }

      final payload = await _fetchHeartbeat();
      if (payload == null) {
        if (await DutyStatusSnapshot.isValidOnDutyForCurrentUser() &&
            !await _isNativeUnpaidBreak()) {
          dutyHeartbeatDebugLog(
            '[DutyHeartbeatService] poll offline; snapshot on_duty — ensuring tracking',
          );
          _lastAppliedStatus = onDuty;
          await _ensureTrackingRunningForOnDuty(allowPrompts: true);
        }
        return;
      }

      await _applyAttendancePayload(payload, source: 'heartbeat');
    } catch (e) {
      dutyHeartbeatDebugLog('[DutyHeartbeatService] poll failed: $e');
      if (await DutyStatusSnapshot.isValidOnDutyForCurrentUser() &&
          !await _isNativeUnpaidBreak()) {
        _lastAppliedStatus = onDuty;
        await _ensureTrackingRunningForOnDuty(allowPrompts: true);
      }
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> onAttendanceStatusChangedFromBridge(dynamic raw) async {
    dutyHeartbeatDebugLog(
      '[DutyHeartbeatService] attendance_status_changed raw=$raw',
    );
    final payload = DutyHeartbeatClient.parseAttendanceBridgePayload(raw);
    if (payload == null) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] attendance_status_changed ignored; invalid payload',
      );
      return;
    }

    if (!_heartbeatActive) {
      _heartbeatActive = true;
      _scheduleNextPoll();
    }

    await _applyAttendancePayload(payload, source: 'js_bridge');
  }

  Future<void> _applyAttendancePayload(
    DutyHeartbeatPayload payload, {
    required String source,
  }) async {
    dutyHeartbeatDebugLog(
      '[DutyHeartbeatService] attendance ($source) '
      'duty=${payload.dutyStatus} working=${payload.workingStatus} '
      'break=${payload.breakType} paid=${payload.breakPaid} '
      'minutes=${payload.allowedBreakMinutes} '
      'unpaid=${payload.isUnpaidBreak} track=${payload.allowsLocationTracking}',
    );

    final enteredBreak =
        payload.isOnBreak &&
        (_lastWorkingStatus != DutyHeartbeatPayload.onBreak ||
            _lastBreakType != payload.breakType ||
            _lastBreakPaid != payload.breakPaid);

    _lastWorkingStatus = payload.workingStatus;
    _lastBreakType = payload.breakType;
    _lastBreakPaid = payload.breakPaid;

    if (payload.isOffDuty) {
      if (_isOptimisticClockInTrackingActive()) {
        dutyHeartbeatDebugLog(
          '[DutyHeartbeatService] ignore transient off_duty during clock-in ($source)',
        );
        return;
      }
      if (await _shouldDeferOffDutyTrackingStop()) {
        dutyHeartbeatDebugLog(
          '[DutyHeartbeatService] defer off_duty stop during clock-in ($source)',
        );
        return;
      }
      _locationPausedForUnpaidBreak = false;
      await _setNativeUnpaidBreak(false);
      await _applyOffDuty();
      return;
    }

    if (!payload.isOnDuty) return;

    if (enteredBreak) {
      await LocationSharingStatusNotification.showBreakStarted(
        unpaid: payload.isUnpaidBreak,
        minutes: payload.breakMinutesOrDefault,
      );
    } else if (!payload.isOnBreak) {
      LocationSharingStatusNotification.resetBreakStartedGate();
    }

    if (payload.isUnpaidBreak) {
      if (_locationPausedForUnpaidBreak) {
        _lastAppliedStatus = onDuty;
        await _setNativeUnpaidBreak(true);
        return;
      }
      await _pauseLocationForUnpaidBreak(
        payload: payload,
        notify: false,
        source: source,
      );
      return;
    }

    final wasPaused = _locationPausedForUnpaidBreak;
    await _setNativeUnpaidBreak(false);
    _locationPausedForUnpaidBreak = false;

    if (_lastAppliedStatus == offDuty) {
      _resetOnDutyAutoPromptState();
      await _hydrateConsentFromStorage();
    }
    _clearOptimisticClockInTracking();

    if (wasPaused || _lastAppliedStatus != onDuty) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] resuming/applying on_duty tracking ($source)'
        '${wasPaused ? ' after unpaid break' : ''}',
      );
      await _applyOnDuty();
    } else {
      await DutyStatusSnapshot.markOnDuty();
      if (Platform.isIOS) {
        await _ensureIosTrackingHealthy();
      }
      await _ensureTrackingRunningForOnDuty(allowPrompts: true);
      await refreshBackgroundLocationPermissionBannerState();
    }
  }

  Future<void> _pauseLocationForUnpaidBreak({
    required DutyHeartbeatPayload payload,
    required bool notify,
    required String source,
  }) async {
    if (_locationPausedForUnpaidBreak) {
      await _setNativeUnpaidBreak(true);
      _lastAppliedStatus = onDuty;
      if (notify) {
        dutyHeartbeatDebugLog(
          '[DutyHeartbeatService] unpaid break already paused; '
          'ensuring break notification ($source)',
        );
        await LocationSharingStatusNotification.showBreakStarted(
          unpaid: true,
          minutes: payload.breakMinutesOrDefault,
        );
        dutyHeartbeatDebugLog(
          '[DutyHeartbeatService] unpaid break notification requested '
          'minutes=${payload.breakMinutesOrDefault} ($source)',
        );
      } else {
        dutyHeartbeatDebugLog(
          '[DutyHeartbeatService] unpaid break already paused; skip stop ($source)',
        );
      }
      return;
    }

    dutyHeartbeatDebugLog(
      '[DutyHeartbeatService] unpaid break → pause GPS/FGS/SLC ($source)',
    );

    _lastAppliedStatus = onDuty;
    _locationPausedForUnpaidBreak = true;

    await DutyStatusSnapshot.clear();
    await _setNativeUnpaidBreak(true);

    final result = await BackgroundLocationController.stop();
    dutyHeartbeatDebugLog(
      '[DutyHeartbeatService] unpaid break stop ok=${result['ok'] == true}',
    );

    if (Platform.isIOS) {
      await IosSignificantLocationChangeService.armForUnpaidBreak();
    }

    await LocationSharingStatusNotification.dismissSharing();

    if (notify) {
      await LocationSharingStatusNotification.showBreakStarted(
        unpaid: true,
        minutes: payload.breakMinutesOrDefault,
      );
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] unpaid break notification requested '
        'minutes=${payload.breakMinutesOrDefault} ($source)',
      );
    }

    await refreshBackgroundLocationPermissionBannerState();
  }

  Future<void> _setNativeUnpaidBreak(bool unpaid) async {
    if (Platform.isAndroid) {
      await AndroidDutyKillWatch.setUnpaidBreak(unpaid);
    }
    if (Platform.isIOS) {
      await IosSignificantLocationChangeService.setUnpaidBreak(unpaid);
    }
  }

  Future<bool> _isNativeUnpaidBreak() async {
    if (Platform.isAndroid) {
      return AndroidDutyKillWatch.isUnpaidBreak();
    }
    return _locationPausedForUnpaidBreak;
  }

  Future<DutyHeartbeatPayload?> _fetchHeartbeat() async {
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
    dutyHeartbeatDebugLog(
      '[DutyHeartbeat] response statusCode=$statusCode payload=${response.data}',
    );
    if (statusCode == 401 || statusCode == 403) {
      return null;
    }

    if (statusCode < 200 || statusCode >= 300) {
      return null;
    }

    final payload = DutyHeartbeatClient.parseHeartbeat(response.data);
    if (payload != null && kDebugMode) {
      final now = DateTime.now();
      final gap = _lastHeartbeatSuccessAt == null
          ? 'first'
          : '${now.difference(_lastHeartbeatSuccessAt!).inSeconds}s';
      _lastHeartbeatSuccessAt = now;
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      final ss = now.second.toString().padLeft(2, '0');
      dutyHeartbeatDebugLog(
        '[DutyHeartbeat] ok duty=${payload.dutyStatus} '
        'working=${payload.workingStatus} break=${payload.breakType} '
        'unpaid=${payload.isUnpaidBreak} after=$gap @$hh:$mm:$ss',
      );
    }
    return payload;
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

  Future<bool> _hasActiveAuthTokenForImmediateClockInStart() async {
    if (await _hasActiveAuthToken()) return true;

    final cached = await AuthRepository.instance.getAccessToken();
    if (cached != null && cached.isNotEmpty) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] immediate clock-in start using cached access token',
      );
      return true;
    }

    dutyHeartbeatDebugLog(
      '[DutyHeartbeatService] immediate clock-in start skipped: no auth token',
    );
    return false;
  }

  Future<bool> _clockInFastStartEligible() async {
    return _clockInImmediateStartEligible();
  }

  Future<void> _applyOnDutyImpl() async {
    if (_deferTrackingStart) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] defer on_duty apply until duty resume reconcile',
      );
      return;
    }
    if (!_heartbeatActive || !await _hasActiveAuthToken()) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] skip on_duty apply (heartbeat inactive or no token)',
      );
      return;
    }

    final isFreshClockIn = _lastAppliedStatus == offDuty;

    if (isFreshClockIn || _lastAppliedStatus != onDuty) {
      LocationSharingStatusNotification.resetShiftEndedGate();
      _locationSharingArmedThisDuty = false;
    }

    await _hydrateConsentFromStorage();

    if (isFreshClockIn && Platform.isAndroid) {
      unawaited(BackgroundLocationService.preWarmForClockIn());
    }

    final pushPromptIfNeeded =
        isFreshClockIn && await OsNotificationPermission.isGranted()
        ? false
        : true;
    await PushNotificationService.instance.waitForPermissionPromptCompleted(
      promptIfNeeded: pushPromptIfNeeded,
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
        final clockInFastStart =
            isFreshClockIn && await _clockInFastStartEligible();
        final result = await BackgroundLocationController.ensureStarted(
          clockInFastStart: clockInFastStart,
        );
        dutyHeartbeatDebugLog(
          '[DutyHeartbeatService] ensureStarted (disclosure accepted) '
          'ok=${result['ok'] == true}'
          '${clockInFastStart ? ' clockInFastStart=true' : ''}',
        );
        if (result['ok'] == true) {
          locationDebugLog(
            '[DutyLocation] on_duty → location ensureStarted OK',
          );
          _locationSharingArmedThisDuty = true;
          await _syncPermissionReadyState();
        } else {
          locationDebugLog(
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
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] on_duty start canceled by user',
      );
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

    final clockInFastStart =
        isFreshClockIn && await _clockInFastStartEligible();
    final result = alreadyHealthy
        ? <String, dynamic>{'ok': true, 'started': false, 'running': true}
        : await BackgroundLocationController.ensureStarted(
            clockInFastStart: clockInFastStart,
          );
    dutyHeartbeatDebugLog(
      '[DutyHeartbeatService] ensureStarted ok=${result['ok'] == true}'
      '${clockInFastStart ? ' clockInFastStart=true' : ''}',
    );

    if (result['ok'] == true) {
      locationDebugLog('[DutyLocation] on_duty → location ensureStarted OK');
      _locationSharingArmedThisDuty = true;
      await _syncPermissionReadyState();
      await refreshBackgroundLocationPermissionBannerState();
      return;
    }

    locationDebugLog('[DutyLocation] on_duty → location ensureStarted FAILED');
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
    DutyHeartbeatPayload? payload;
    try {
      payload = await _fetchHeartbeat();
    } catch (_) {
      payload = null;
    }

    if (payload != null && payload.isUnpaidBreak) {
      final shouldNotify = !_locationPausedForUnpaidBreak;
      await _pauseLocationForUnpaidBreak(
        payload: payload,
        notify: shouldNotify,
        source: 'reconcile_failed_start',
      );
      return;
    }

    final status = payload?.dutyStatus;

    if (status == offDuty) {
      await _applyOffDuty();
      return;
    }
    if (status == onDuty) {
      await _setNativeUnpaidBreak(false);
      _locationPausedForUnpaidBreak = false;
      await DutyStatusSnapshot.markOnDuty();
      await refreshBackgroundLocationPermissionBannerState();
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

    if (Platform.isAndroid) {
      if (!await LocationDisclosureConsent.shouldShowLocationDisclosure()) {
        _disclosureAccepted = true;
      }
      return true;
    }

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

    if (Platform.isAndroid) {
      _disclosureDeferred = false;
      _requestPermissionAfterDisclosure = true;
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
    dutyHeartbeatDebugLog(
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
    _clearOptimisticClockInTracking();
    _locationPausedForUnpaidBreak = false;
    _lastWorkingStatus = null;
    _lastBreakType = null;
    _lastBreakPaid = null;
    LocationSharingStatusNotification.resetBreakStartedGate();
    locationDebugLog('[DutyLocation] off_duty → stopping location tracking');
    dutyHeartbeatDebugLog(
      '[DutyHeartbeatService] stopping location after flushing pending batches',
    );

    final wasOnDuty = _lastAppliedStatus == onDuty;
    final wasSharing = await _shouldAnnounceLocationStop();

    await DutyStatusSnapshot.clear();
    await _setNativeUnpaidBreak(false);
    await AndroidDutyKillWatch.disarm(forceOff: true);

    if (Platform.isIOS) {
      await IosSignificantLocationChangeService.setOnDuty(false);
    }
    final result = await BackgroundLocationController.stop();
    dutyHeartbeatDebugLog(
      '[DutyHeartbeatService] stop ok=${result['ok'] == true}',
    );

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
    OnDutyPermissionsPromptService.instance.stopRemindLoop();
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
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] ios permission upgraded to always; '
        '${BackgroundLocationController.isUiBackgrounded ? "soft-applying (UI backgrounded)" : "restarting tracking"}',
      );
      await _restartTrackingWithCurrentPermission();
    }
  }

  Future<void> _restartTrackingWithCurrentPermission() async {
    if (!await confirmOnDutyFromApiForTracking()) return;
    _lastAppliedStatus = onDuty;
    final result = await BackgroundLocationController.restart();
    dutyHeartbeatDebugLog(
      '[DutyHeartbeatService] tracking restarted after permission change '
      'ok=${result['ok'] == true} soft=${result['softRebuilt'] == true} '
      'deferred=${result['deferredHardRestart'] == true}',
    );
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
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] disclosure skipped (deferred this session)',
      );
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
        dutyHeartbeatDebugLog(
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
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatService] disclosure prompt failed: $e\n$st',
      );
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

    if (Platform.isAndroid) {
      if (await LocationDisclosureConsent.hasAccepted()) {
        _disclosureAccepted = true;
        return true;
      }
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

    // On duty: consolidated OnDutyPermissionsDialog owns missing-permission UX.
    // Skip auto Always/settings popups (resume / poll); allow user-initiated.
    if (!userInitiated && _lastAppliedStatus == onDuty) {
      await refreshBackgroundLocationPermissionBannerState();
      return false;
    }

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
