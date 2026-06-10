import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api/api_client.dart';
import '../app/app_navigator.dart';
import '../auth/auth_repository.dart';
import '../push/push_notification_service.dart';
import '../utilities/app_config.dart';
import '../utilities/permission_settings_helper.dart';
import '../widgets/location_tracking_disclosure_dialog.dart';
import 'background_location_controller.dart';
import 'background_location_permissions.dart';
import 'duty_tracking_preferences.dart';
import 'ios_duty_location_pinger.dart';

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
  bool _backgroundLocationSettingsDialogVisible = false;
  Future<void>? _applyOnDutyFuture;
  Future<bool>? _disclosurePromptFuture;
  LocationPermission? _lastKnownIosPermission;

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
    if (await DutyTrackingPreferences.isDisclosureAccepted()) {
      _disclosureAccepted = true;
    }
  }

  /// Re-checks prompts after page refresh or app resume.
  /// "Not now" is memory-only and is cleared here so the user can be asked again.
  Future<void> recheckOnDutyPrompts() async {
    final token = await AuthRepository.instance.getAccessToken();
    if (token == null || token.isEmpty) return;

    await PushNotificationService.instance.waitForPermissionPromptCompleted(
      promptIfNeeded: true,
    );

    _disclosureDeferred = false;
    await DutyTrackingPreferences.clearSettingsPromptDeferred();

    await _hydrateConsentFromStorage();
    await _reconcileBgLocationReadyFlag();
    await _syncPermissionReadyState();

    final status = await _fetchDutyStatus();
    if (status != onDuty) return;

    await _ensureIosTrackingHealthy();

    final running = await _isLocationTrackingRunning();
    if (_lastAppliedStatus == onDuty && running) {
      await _showBackgroundLocationSettingsDialogIfNeeded(
        deniedReason:
            await BackgroundLocationPermissions.settingsDeniedReasonIfAny(),
      );
      return;
    }

    await _applyOnDuty();
  }

  Future<bool> _isLocationTrackingRunning() async {
    if (Platform.isIOS) {
      return IosDutyLocationPinger.isRunning;
    }
    return FlutterBackgroundService().isRunning();
  }

  Future<void> _ensureIosTrackingHealthy() async {
    if (!Platform.isIOS) return;
    if (_lastAppliedStatus != onDuty || _disclosureDeferred) return;

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

  void stop({bool stopBackgroundLocation = true}) {
    _heartbeatActive = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInFlight = false;
    _lastAppliedStatus = null;
    _resetDisclosureState();
    debugPrint('[DutyHeartbeatService] stopped heartbeat polling');

    if (stopBackgroundLocation) {
      unawaited(_applyOffDuty());
    }
  }

  void _scheduleNextPoll() {
    _pollTimer?.cancel();
    final jitterMs =
        _minPollInterval.inMilliseconds +
        _random.nextInt(
          _maxPollInterval.inMilliseconds - _minPollInterval.inMilliseconds + 1,
        );
    _pollTimer = Timer(Duration(milliseconds: jitterMs), () async {
      await _pollOnce();
      if (_pollTimer != null) {
        _scheduleNextPoll();
      }
    });
  }

  Future<void> _pollOnce() async {
    if (_pollInFlight) return;
    _pollInFlight = true;

    try {
      final token = await AuthRepository.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        if (kDebugMode) {
          debugPrint('[DutyHeartbeatService] skip poll: no auth token');
        }
        return;
      }

      final status = await _fetchDutyStatus();
      if (status == null) return;

      if (status == _lastAppliedStatus) {
        if (status == onDuty) {
          await _ensureIosTrackingHealthy();
          final running = await _isLocationTrackingRunning();
          if (!running && !_disclosureDeferred) {
            debugPrint(
              '[DutyHeartbeatService] on_duty but tracking not running; restarting',
            );
            await _applyOnDuty();
          } else if (kDebugMode) {
            debugPrint('[DutyHeartbeatService] unchanged status=$status');
          }
        } else if (kDebugMode) {
          debugPrint('[DutyHeartbeatService] unchanged status=$status');
        }
        return;
      }

      debugPrint('[DutyHeartbeatService] duty status=$status');
      if (status == onDuty) {
        if (_lastAppliedStatus == offDuty) {
          _disclosureDeferred = false;
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
        debugPrint(
          '[DutyHeartbeatService] heartbeat failed status=$statusCode body=${_truncate(response.data)}',
        );
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
    final token = await AuthRepository.instance.getAccessToken();
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

    await PushNotificationService.instance.waitForPermissionPromptCompleted(
      promptIfNeeded: true,
    );
    if (!_heartbeatActive || !await _hasActiveAuthToken()) return;

    await _reconcileBgLocationReadyFlag();
    await _handleIosPermissionChangeIfNeeded();
    await _syncPermissionReadyState();

    if (!_heartbeatActive || !await _hasActiveAuthToken()) return;

    if (!await _confirmBackgroundLocationDisclosure()) {
      _lastAppliedStatus = onDuty;
      debugPrint('[DutyHeartbeatService] on_duty start canceled by user');
      return;
    }

    if (!_heartbeatActive || !await _hasActiveAuthToken()) return;

    final result = await BackgroundLocationController.ensureStarted();
    debugPrint('[DutyHeartbeatService] ensureStarted result=$result');

    if (result['ok'] == true) {
      _lastAppliedStatus = onDuty;
      await _syncPermissionReadyState();
      await _showBackgroundLocationSettingsDialogIfNeeded(
        deniedReason: result['deniedReason']?.toString(),
      );
      return;
    }

    if (result['openSettings'] == true) {
      await _showBackgroundLocationSettingsDialogIfNeeded(
        deniedReason: result['deniedReason']?.toString(),
      );
    }
  }

  Future<void> _applyOffDuty() async {
    final result = await BackgroundLocationController.stop();
    debugPrint('[DutyHeartbeatService] stop result=$result');
    if (result['ok'] == true) {
      _lastAppliedStatus = offDuty;
      _resetDisclosureState();
      PermissionSettingsHelper.clearCooldown('background_location');
      await DutyTrackingPreferences.clearOnOffDuty();
    }
  }

  void _resetDisclosureState() {
    _disclosureAccepted = false;
    _disclosureDeferred = false;
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
        '[DutyHeartbeatService] tracking restarted after permission change: $result',
      );
    }
    if (result['ok'] == true) {
      _lastAppliedStatus = onDuty;
      await _syncPermissionReadyState();
    }
  }

  /// Marks permission-ready state and auto-accepts disclosure when already enabled.
  Future<void> _syncPermissionReadyState() async {
    if (!await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
      return;
    }
    await DutyTrackingPreferences.setBgLocationReady();
    if (!await DutyTrackingPreferences.isDisclosureAccepted()) {
      await DutyTrackingPreferences.setDisclosureAccepted();
      _disclosureAccepted = true;
      _disclosureDeferred = false;
    }
  }

  Future<bool> _confirmBackgroundLocationDisclosure() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    if (_disclosureAccepted ||
        await DutyTrackingPreferences.isDisclosureAccepted()) {
      _disclosureAccepted = true;
      return true;
    }

    if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
      await DutyTrackingPreferences.setDisclosureAccepted();
      _disclosureAccepted = true;
      return true;
    }

    if (_disclosureDeferred) {
      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] disclosure skipped (not now, until refresh)',
        );
      }
      return false;
    }

    if (_disclosurePromptFuture != null) {
      return _disclosurePromptFuture!;
    }

    final context = AppNavigator.key.currentContext;
    if (context == null) {
      debugPrint(
        '[DutyHeartbeatService] disclosure skipped: navigator context unavailable',
      );
      return false;
    }

    if (!context.mounted) return false;

    final future = _promptBackgroundLocationDisclosure(context);
    _disclosurePromptFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_disclosurePromptFuture, future)) {
        _disclosurePromptFuture = null;
      }
    }
  }

  Future<bool> _promptBackgroundLocationDisclosure(BuildContext context) async {
    final allowed = await LocationTrackingDisclosureDialog.show(context);
    if (allowed) {
      _disclosureAccepted = true;
      _disclosureDeferred = false;
      await DutyTrackingPreferences.setDisclosureAccepted();
      return true;
    }

    _disclosureDeferred = true;
    return false;
  }

  Future<void> _showPermissionDeniedSettingsDialog({
    String? deniedReason,
  }) async {
    if (_backgroundLocationSettingsDialogVisible) return;

    if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
      await _syncPermissionReadyState();
      return;
    }

    if (await _shouldSkipSettingsPrompt()) {
      return;
    }

    _backgroundLocationSettingsDialogVisible = true;
    try {
      final result = await PermissionSettingsHelper.promptOpenSettings(
        title: BackgroundLocationPermissions.settingsTitleFor(deniedReason),
        message: BackgroundLocationPermissions.settingsMessageFor(deniedReason),
        dialogKey: 'background_location',
        respectCooldown: true,
      );

      await _reconcileBgLocationReadyFlag();
      await _handleIosPermissionChangeIfNeeded();
      if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
        await _syncPermissionReadyState();
        if (await _isLocationTrackingRunning()) {
          await _restartTrackingWithCurrentPermission();
        } else {
          await _applyOnDuty();
        }
        return;
      }

      if (result == PermissionSettingsPromptResult.dismissed) {
        await DutyTrackingPreferences.setSettingsPromptDeferred();
      }
    } finally {
      _backgroundLocationSettingsDialogVisible = false;
    }
  }

  Future<void> _showBackgroundLocationSettingsDialogIfNeeded({
    String? deniedReason,
  }) async {
    if (_backgroundLocationSettingsDialogVisible) return;

    if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
      await _syncPermissionReadyState();
      return;
    }

    if (await _shouldSkipSettingsPrompt()) {
      return;
    }

    if (Platform.isIOS) {
      if (deniedReason == 'location_always') {
        await _showPermissionDeniedSettingsDialog(
          deniedReason: deniedReason,
        );
      }
      return;
    }

    if (deniedReason == 'location_background' ||
        deniedReason == 'location_always') {
      await _showPermissionDeniedSettingsDialog(deniedReason: deniedReason);
      return;
    }

    final foreground = await Permission.location.status;
    if (!foreground.isGranted) return;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always) {
      await _syncPermissionReadyState();
      return;
    }

    await _showPermissionDeniedSettingsDialog(
      deniedReason: 'location_background',
    );
  }

  String _truncate(Object? value, {int max = 800}) {
    final text = value?.toString() ?? '';
    if (text.length <= max) return text;
    return '${text.substring(0, max)}...';
  }
}
