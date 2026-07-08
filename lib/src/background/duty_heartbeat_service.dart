import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import '../api/api_client.dart';
import '../app/app_navigator.dart';
import '../auth/auth_repository.dart';
import '../push/push_notification_service.dart';
import '../auth/location_disclosure_account_sync.dart';
import '../utilities/app_config.dart';
import '../utilities/overlay_prompt_guard.dart';
import '../utilities/permission_settings_helper.dart';
import '../widgets/location_tracking_disclosure_dialog.dart';
import 'background_location_controller.dart';
import 'background_location_permissions.dart';
import 'duty_tracking_preferences.dart';
import 'ios_duty_location_pinger.dart';
import 'location_disclosure_consent.dart';

class DutyHeartbeatService {
  DutyHeartbeatService._();

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

  /// After the first automatic on-duty permission flow, rely on the banner until
  /// the user taps Enable Location (matches iOS store-safe nag pattern).
  bool _onDutyAutoPromptComplete = false;
  Future<void>? _applyOnDutyFuture;
  Future<bool>? _disclosurePromptFuture;
  LocationPermission? _lastKnownIosPermission;

  final ValueNotifier<bool> backgroundLocationPermissionMissing = ValueNotifier(
    false,
  );

  final ValueNotifier<bool> disclosurePromptVisible = ValueNotifier(false);

  bool get isBackgroundLocationBannerActive =>
      backgroundLocationPermissionMissing.value;

  /// Banner shows only when permission is missing and no modal is on screen.
  bool get shouldShowBackgroundLocationBanner =>
      backgroundLocationPermissionMissing.value &&
      !PermissionSettingsHelper.settingsPromptVisible.value &&
      !disclosurePromptVisible.value;

  bool get isOnDutyTrackingActive =>
      _heartbeatActive && _lastAppliedStatus == onDuty;

  Future<void> refreshBackgroundLocationPermissionBannerState() async {
    if (_lastAppliedStatus != onDuty) {
      if (backgroundLocationPermissionMissing.value) {
        backgroundLocationPermissionMissing.value = false;
      }
      return;
    }

    final missing =
        !await BackgroundLocationPermissions.hasSufficientBackgroundAccess();
    if (backgroundLocationPermissionMissing.value != missing) {
      backgroundLocationPermissionMissing.value = missing;
    }
  }

  void _setDisclosurePromptVisible(bool visible) {
    if (disclosurePromptVisible.value != visible) {
      disclosurePromptVisible.value = visible;
    }
  }

  /// Clears modal routes left behind when returning from Settings.
  void reconcileDialogsAfterAppResume() {
    PermissionSettingsHelper.reconcilePromptsAfterAppResume();
    _backgroundLocationSettingsDialogVisible = false;
    if (!_disclosurePromptInFlight) {
      _setDisclosurePromptVisible(false);
    }
  }

  @Deprecated('Use reconcileDialogsAfterAppResume')
  void reconcileDialogsAfterAndroidResume() => reconcileDialogsAfterAppResume();

  void start() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_pollTimer != null) return;

    _heartbeatActive = true;
    ApiClient.instance.ensureAuthInterceptorInstalled();
    debugPrint('[DutyHeartbeatService] starting heartbeat polling');

    unawaited(_hydrateConsentFromStorage());
    unawaited(_pollOnce());
    _scheduleNextPoll();
  }

  Future<void> _hydrateConsentFromStorage() async {
    await LocationDisclosureAccountSync.onLoginResolved();

    if (await LocationDisclosureConsent.hasAccepted()) {
      _disclosureAccepted = true;
      _disclosureDeferred = false;
    }
  }

  /// Re-checks prompts after page refresh or app resume.
  ///
  /// [pageReload] is true for pull-to-refresh / same-URL reloads. In that case
  /// native session teardown is skipped elsewhere and we only refresh banner
  /// state without re-prompting settings the user already dismissed.
  Future<void> recheckOnDutyPrompts({bool pageReload = false}) async {
    if (!_heartbeatActive) return;

    final token = await AuthRepository.instance.ensureValidAccessToken();
    if (token == null || token.isEmpty) return;

    if (!pageReload) {
      await PushNotificationService.instance.waitForPermissionPromptCompleted(
        promptIfNeeded: true,
      );

      await OverlayPromptGuard.waitUntilReady();
    }

    await _hydrateConsentFromStorage();
    await _reconcileBgLocationReadyFlag();
    await _syncPermissionReadyState();

    final status = await _fetchDutyStatus();
    if (status != onDuty) {
      await refreshBackgroundLocationPermissionBannerState();
      return;
    }

    await _ensureIosTrackingHealthy();

    final running = await _isLocationTrackingRunning();
    if (_lastAppliedStatus == onDuty && running) {
      await refreshBackgroundLocationPermissionBannerState();
      return;
    }

    if (!pageReload) {
      if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
        await retryOnDutyTrackingIfReady();
      } else if (await _shouldAutoApplyOnDutyFromPoll()) {
        await _applyOnDuty();
      }
    }
    await refreshBackgroundLocationPermissionBannerState();
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
    if (Platform.isIOS) {
      return IosDutyLocationPinger.isRunning;
    }
    return FlutterBackgroundService().isRunning();
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
    _lastAppliedStatus = null;
    _resetDisclosureState();
    backgroundLocationPermissionMissing.value = false;
    debugPrint('[DutyHeartbeatService] stopped heartbeat polling');

    if (stopBackgroundLocation) {
      await _applyOffDuty();
    }
  }

  /// Instant logout: stop polling/tracking immediately; no batch flush here.
  Future<void> finalizeLogoutInstant() async {
    _heartbeatActive = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInFlight = false;
    _lastAppliedStatus = offDuty;
    _resetDisclosureState();
    backgroundLocationPermissionMissing.value = false;
    PermissionSettingsHelper.clearCooldown('background_location');
    debugPrint(
      '[DutyHeartbeatService] instant logout (heartbeat + tracking stopped)',
    );
    unawaited(BackgroundLocationController.stopCollectingOnly());
    unawaited(DutyTrackingPreferences.clearOnOffDuty());
    unawaited(refreshBackgroundLocationPermissionBannerState());
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
        if (kDebugMode) {
          debugPrint(
            '[DutyHeartbeatService] no auth token; stopping heartbeat and location',
          );
        }
        await stop();
        return;
      }

      final status = await _fetchDutyStatus();
      if (status == null) return;

      if (status == _lastAppliedStatus) {
        if (status == onDuty) {
          await _ensureIosTrackingHealthy();
          final running = await _isLocationTrackingRunning();
          if (!running && await _shouldAutoApplyOnDutyFromPoll()) {
            debugPrint(
              '[DutyHeartbeatService] on_duty but tracking not running; restarting',
            );
            await _applyOnDuty();
          } else if (kDebugMode) {
            debugPrint('[DutyHeartbeatService] unchanged status=$status');
          }
          await refreshBackgroundLocationPermissionBannerState();
        } else if (kDebugMode) {
          debugPrint('[DutyHeartbeatService] unchanged status=$status');
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
    } finally {
      _pollInFlight = false;
    }
  }

  Future<String?> _fetchDutyStatus() async {
    final response = await _dio.getUri(
      Uri.parse(AppConfig.heartbeatUrl),
      options: Options(
        headers: const {'Accept': 'application/json'},
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    final statusCode = response.statusCode ?? 0;
    if (statusCode == 401 || statusCode == 403) {
      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] heartbeat unauthorized status=$statusCode',
        );
      }
      return null;
    }

    if (statusCode < 200 || statusCode >= 300) {
      if (kDebugMode) {
        debugPrint('[DutyHeartbeatService] heartbeat failed status=$statusCode');
      }
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
    if (!_heartbeatActive || !await _hasActiveAuthToken()) {
      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] skip on_duty apply (heartbeat inactive or no token)',
        );
      }
      return;
    }

    final isFreshClockIn = _lastAppliedStatus == offDuty;

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
      _lastAppliedStatus = onDuty;
      if (!await _isLocationTrackingRunning()) {
        await _runPostDisclosurePermissionStep();
        final result = await BackgroundLocationController.ensureStarted();
        debugPrint(
          '[DutyHeartbeatService] ensureStarted (disclosure accepted) ok=${result['ok'] == true}',
        );
        if (result['ok'] == true) {
          await _syncPermissionReadyState();
        }
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

    _lastAppliedStatus = onDuty;

    final bool settingsPrompted;
    if (!await _isLocationTrackingRunning()) {
      settingsPrompted = await _runPostDisclosurePermissionStep();
    } else {
      _requestPermissionAfterDisclosure = false;
      settingsPrompted = false;
    }

    final backgroundReady =
        await BackgroundLocationPermissions.hasSufficientBackgroundAccess();
    final skipSettingsPrompt = backgroundReady;

    final result = await BackgroundLocationController.ensureStarted();
    debugPrint('[DutyHeartbeatService] ensureStarted ok=${result['ok'] == true}');

    if (result['ok'] == true) {
      await _syncPermissionReadyState();
      await refreshBackgroundLocationPermissionBannerState();
      return;
    }

    if (result['openSettings'] == true &&
        !skipSettingsPrompt &&
        !settingsPrompted) {
      await _showBackgroundLocationSettingsDialogIfNeeded(
        deniedReason: result['deniedReason']?.toString(),
      );
    }
    await refreshBackgroundLocationPermissionBannerState();
    _onDutyAutoPromptComplete = true;
  }

  /// Store-safe gate for web geolocation: disclosure before any OS prompt.
  /// Re-shows disclosure on user-initiated retry (forceRetry).
  Future<bool> ensureDisclosureBeforeWebLocationAccess() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

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

  /// Handles the top banner primary action with the correct next step per state.
  Future<void> handleBannerEnableLocationAction(BuildContext context) async {
    if (await BackgroundLocationPermissions.isBackgroundLocationFullyEnabled() &&
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

    if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
      final result = await BackgroundLocationController.ensureStarted();
      if (result['ok'] == true) {
        await _syncPermissionReadyState();
      }
    }
    await refreshBackgroundLocationPermissionBannerState();
  }

  /// Banner tap: OS prompt when possible, otherwise the in-app Open Settings flow.
  Future<void> _advanceBannerLocationPermissionStep(
    BuildContext context,
  ) async {
    if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
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
        if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
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
          if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
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

  /// Shows duty disclosure from the banner when it has not been accepted yet.
  Future<bool> prepareBannerLocationPermissionRequest(
    BuildContext context,
  ) async {
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

  /// Runs the next store-safe step after duty disclosure is accepted.
  /// Returns true when the Open Settings dialog was shown.
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
    if (_lastAppliedStatus != onDuty) return;
    if (!await _hasActiveAuthToken()) return;
    if (!await LocationDisclosureConsent.hasAccepted()) return;
    if (!await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
      await promptBackgroundLocationSettingsIfNeeded();
      await refreshBackgroundLocationPermissionBannerState();
      return;
    }

    final result = await BackgroundLocationController.ensureStarted();
    debugPrint(
      '[DutyHeartbeatService] retry ensureStarted ok=${result['ok'] == true}',
    );
    if (result['ok'] == true) {
      await _syncPermissionReadyState();
    } else if (result['openSettings'] == true) {
      await _showBackgroundLocationSettingsDialogIfNeeded(
        deniedReason: result['deniedReason']?.toString(),
      );
    }
    await refreshBackgroundLocationPermissionBannerState();
  }

  /// Shows the explanatory Open Settings dialog when background access is still
  /// missing after foreground was granted (Android/iOS duty flows).
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

  Future<void> _applyOffDuty() async {
    debugPrint(
      '[DutyHeartbeatService] stopping location after flushing pending batches',
    );
    final result = await BackgroundLocationController.stop();
    debugPrint('[DutyHeartbeatService] stop ok=${result['ok'] == true}');
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
    final result = await BackgroundLocationController.restart();
    if (kDebugMode) {
      debugPrint(
        '[DutyHeartbeatService] tracking restarted after permission change ok=${result['ok'] == true}',
      );
    }
    if (result['ok'] == true) {
      _lastAppliedStatus = onDuty;
      await _syncPermissionReadyState();
      await refreshBackgroundLocationPermissionBannerState();
    }
  }

  /// Marks permission-ready state after background access is sufficient.
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

    if (await BackgroundLocationPermissions.isBackgroundLocationFullyEnabled()) {
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
      if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
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
    if (_backgroundLocationSettingsDialogVisible) return false;

    if (!userInitiated && _onDutyAutoPromptComplete) {
      await refreshBackgroundLocationPermissionBannerState();
      return false;
    }

    if (await BackgroundLocationPermissions.isBackgroundLocationFullyEnabled()) {
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
