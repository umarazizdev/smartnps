import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../app/app_navigator.dart';
import '../location/mock_location_guard.dart';
import '../permissions/native_permission_status_service.dart';
import '../utilities/overlay_prompt_guard.dart';
import '../utilities/permission_settings_helper.dart';
import '../widgets/clock_in_blocked_dialog.dart';
import '../widgets/clock_in_location_disclosure_dialog.dart';
import 'background_location_permissions.dart';
import 'location_disclosure_consent.dart';

/// Store-safe clock-in gate: disclosure before OS prompts, then background check.
class ClockInGateService {
  ClockInGateService._();

  static final ClockInGateService instance = ClockInGateService._();

  bool _disclosureAccepted = false;
  bool _geoUnlockedForClockIn = false;
  bool _prepareInFlight = false;
  Future<bool>? _disclosurePromptFuture;
  _PendingClockInFailureDialog? _pendingFailureAfterSettings;

  final ValueNotifier<bool> prepareInFlightVisible = ValueNotifier(false);

  bool get isGeoUnlockedForClockIn => _geoUnlockedForClockIn;

  /// True while [prepareClockIn] is running — blocks parallel GPS / clock-in.
  bool get isPrepareInFlight => _prepareInFlight;

  void _setPrepareInFlight(bool value) {
    if (_prepareInFlight == value) return;
    _prepareInFlight = value;
    if (prepareInFlightVisible.value != value) {
      prepareInFlightVisible.value = value;
    }
  }

  void clearGeoUnlock() {
    _geoUnlockedForClockIn = false;
  }

  void resetLocationDisclosureMemory() {
    _disclosureAccepted = false;
    _disclosurePromptFuture = null;
    clearGeoUnlock();
  }

  /// Shows failure dialog on resume only when user opened Settings and still blocked.
  Future<void> recheckAfterAppResume() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    // prepareClockIn owns the settings-return flow; avoid racing it.
    if (_prepareInFlight) return;

    await BackgroundLocationPermissions.refreshPermissionStateFromOs();

    final pending = _pendingFailureAfterSettings;
    if (pending != null) {
      if (Platform.isAndroid) {
        await _waitUntilClockInBackgroundReady();
      }
      if (await _isClockInFullyReady()) {
        _pendingFailureAfterSettings = null;
        _geoUnlockedForClockIn = true;
        return;
      }
      _pendingFailureAfterSettings = null;
      await ClockInBlockedDialog.showFailure(
        reason: pending.reason,
        title: pending.title,
        message: pending.message,
        bypassCooldown: true,
      );
      clearGeoUnlock();
      return;
    }

    if (await _isClockInFullyReady()) {
      _geoUnlockedForClockIn = true;
      return;
    }
    clearGeoUnlock();
  }

  Future<bool> _isClockInFullyReady() async {
    await BackgroundLocationPermissions.refreshPermissionStateFromOs();
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    final backgroundReady =
        await BackgroundLocationPermissions.isClockInBackgroundReady();
    if (!backgroundReady) {
      if (!await LocationDisclosureConsent.hasAccepted()) return false;
      return false;
    }

    await LocationDisclosureConsent.reconcileFromOsIfBackgroundReady();
    _disclosureAccepted = true;

    if (!await BackgroundLocationPermissions.hasPreciseLocationAccess()) {
      return false;
    }

    return await MockLocationGuard.ensureClearForClockIn();
  }

  Future<void> _hydrateFromStorage() async {
    await LocationDisclosureConsent.ensureMigrated();
    await LocationDisclosureConsent.reconcileFromOsIfBackgroundReady();
    if (await LocationDisclosureConsent.hasAccepted()) {
      _disclosureAccepted = true;
    }
  }

  Future<Map<String, dynamic>> prepareClockIn() async {
    if (_prepareInFlight) {
      debugPrint(
        '[ClockInGateService] prepareClockIn blocked: already in progress',
      );
      return _blocked(
        reason: 'clock_in_in_progress',
        title: ClockInBlockedDialog.failureTitle,
        message: 'Please wait for the location permission step to finish.',
      );
    }

    _setPrepareInFlight(true);
    _geoUnlockedForClockIn = false;
    _pendingFailureAfterSettings = null;
    debugPrint('[ClockInGateService] prepareClockIn started');

    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        _geoUnlockedForClockIn = true;
        debugPrint('[ClockInGateService] prepareClockIn allowed (non-mobile)');
        return _gateResult(canClockIn: true);
      }

      await _hydrateFromStorage();

      if (!await Geolocator.isLocationServiceEnabled()) {
        debugPrint(
          '[ClockInGateService] prepareClockIn blocked: location_services_disabled',
        );
        return _runLocationSettingsPromptFlow(
          deniedReason: 'location_services_disabled',
        );
      }

      if (!await _ensureClockInDisclosureForClockIn()) {
        debugPrint(
          '[ClockInGateService] prepareClockIn blocked: disclosure cancelled',
        );
        return _cancelledBlocked();
      }

      if (!await BackgroundLocationPermissions.hasForegroundLocationAccess()) {
        debugPrint(
          '[ClockInGateService] prepareClockIn: requesting foreground location',
        );
        await PermissionSettingsHelper.requestForegroundLocationStep();
      }

      await BackgroundLocationPermissions.refreshPermissionStateFromOs();

      if (!await BackgroundLocationPermissions.isClockInBackgroundReady()) {
        final deniedReason =
            await BackgroundLocationPermissions.settingsDeniedReasonIfAny();
        debugPrint(
          '[ClockInGateService] prepareClockIn blocked: background not ready '
          'deniedReason=$deniedReason',
        );
        return _runLocationSettingsPromptFlow(deniedReason: deniedReason);
      }

      if (!await BackgroundLocationPermissions.hasPreciseLocationAccess()) {
        debugPrint(
          '[ClockInGateService] prepareClockIn blocked: location_precise',
        );
        return _runLocationSettingsPromptFlow(deniedReason: 'location_precise');
      }

      if (!await MockLocationGuard.ensureClearForClockIn()) {
        debugPrint(
          '[ClockInGateService] prepareClockIn blocked: mock_location '
          '(or GPS unavailable during mock check)',
        );
        return _blocked(
          reason: 'mock_location',
          title: 'Mock location detected',
          message:
              'Disable mock or fake GPS location before verifying shift attendance from the mobile app.',
        );
      }

      _geoUnlockedForClockIn = true;
      debugPrint('[ClockInGateService] prepareClockIn allowed canClockIn=true');
      return _gateResult(canClockIn: true);
    } finally {
      _setPrepareInFlight(false);
    }
  }

  /// Step 1: settings education prompt. Step 2: error only after Settings return.
  Future<Map<String, dynamic>> _runLocationSettingsPromptFlow({
    required String? deniedReason,
  }) async {
    final blockReason = deniedReason ?? 'background_location_required';

    final action = await ClockInBlockedDialog.showLocationSettingsPrompt(
      deniedReason,
    );

    if (action != ClockInBlockedAction.openSettings) {
      _pendingFailureAfterSettings = null;
      // First-time Cancel on Open Settings = user denied background location.
      // Do not treat Precise Location cancel as a background denial.
      if (blockReason != 'location_precise') {
        unawaited(
          NativePermissionStatusService.instance
              .markBackgroundLocationDeniedByUser(),
        );
      }
      return _cancelledBlocked(reason: blockReason);
    }

    // Android: strip the education dialog route immediately (no animation wait)
    // so Settings opens without the prior ~350ms settle delay. iOS unchanged.
    if (Platform.isAndroid) {
      PermissionSettingsHelper.clearPopupRoutesImmediately();
      await WidgetsBinding.instance.endOfFrame;
    }

    return _openSettingsRecheckOrShowFailure(blockReason: blockReason);
  }

  Future<Map<String, dynamic>> _openSettingsRecheckOrShowFailure({
    required String blockReason,
  }) async {
    final failureTitle = ClockInBlockedDialog.failureTitle;
    final failureMessage = ClockInBlockedDialog.failureMessageFor(blockReason);

    _pendingFailureAfterSettings = _PendingClockInFailureDialog(
      reason: blockReason,
      title: failureTitle,
      message: failureMessage,
    );

    try {
      await PermissionSettingsHelper.openSettingsForUserTap(
        destination: ClockInBlockedDialog.settingsDestinationFor(blockReason),
        waitForReturn: true,
        holdAwaitingLock: Platform.isAndroid,
      );
      await BackgroundLocationPermissions.refreshPermissionStateFromOs();

      if (Platform.isAndroid) {
        // Adaptive: succeed immediately if already granted; otherwise a short
        // poll for OEM lag, then fail fast (no long fixed delay).
        var ready =
            await BackgroundLocationPermissions.isClockInBackgroundReady();
        if (!ready) {
          ready = await _waitUntilClockInBackgroundReady();
        }
        if (kDebugMode) {
          debugPrint(
            '[ClockInGateService] post-settings bg ready=$ready',
          );
        }
      }

      _pendingFailureAfterSettings = null;

      if (await BackgroundLocationPermissions.isClockInBackgroundReady()) {
        await LocationDisclosureConsent.reconcileFromOsIfBackgroundReady();
        // Release Settings lock before any UI so resume handlers cannot pop it.
        if (Platform.isAndroid) {
          PermissionSettingsHelper.endAwaitingSettingsReturn();
        }
        if (!await Geolocator.isLocationServiceEnabled()) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (!await Geolocator.isLocationServiceEnabled()) {
            await ClockInBlockedDialog.showFailure(
              reason: blockReason,
              title: failureTitle,
              message: failureMessage,
              bypassCooldown: true,
            );
            return _cancelledBlocked(reason: blockReason);
          }
        }

        if (!await BackgroundLocationPermissions.hasPreciseLocationAccess()) {
          return _showPreciseLocationFailureAfterSettings();
        }

        if (!await MockLocationGuard.ensureClearForClockIn()) {
          return _blocked(
            reason: 'mock_location',
            title: 'Mock location detected',
            message:
                'Disable mock or fake GPS location before verifying shift attendance from the mobile app.',
          );
        }

        _geoUnlockedForClockIn = true;
        debugPrint(
          '[ClockInGateService] prepareClockIn allowed after Settings return',
        );
        return _gateResult(canClockIn: true);
      }

      // One short recheck — covers late OEM flips without delaying failure UI.
      if (Platform.isAndroid) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await BackgroundLocationPermissions.refreshPermissionStateFromOs();
        if (await BackgroundLocationPermissions.isClockInBackgroundReady()) {
          await LocationDisclosureConsent.reconcileFromOsIfBackgroundReady();
          PermissionSettingsHelper.endAwaitingSettingsReturn();
          if (!await BackgroundLocationPermissions.hasPreciseLocationAccess()) {
            return _showPreciseLocationFailureAfterSettings();
          }
          if (await MockLocationGuard.ensureClearForClockIn()) {
            _geoUnlockedForClockIn = true;
            debugPrint(
              '[ClockInGateService] prepareClockIn allowed after final settle',
            );
            return _gateResult(canClockIn: true);
          }
        }
      }

      // Must clear before showFailure — resume handlers pop while this is true.
      if (Platform.isAndroid) {
        PermissionSettingsHelper.endAwaitingSettingsReturn();
      }

      // Returned from Settings without Always / Allow all the time.
      // Precise-only blocks are not background denials.
      if (blockReason != 'location_precise') {
        unawaited(
          NativePermissionStatusService.instance
              .markBackgroundLocationDeniedByUser(),
        );
      }

      final failureAction = await ClockInBlockedDialog.showFailure(
        reason: blockReason,
        title: failureTitle,
        message: failureMessage,
        bypassCooldown: true,
      );

      if (failureAction == ClockInBlockedAction.openSettings) {
        return _openSettingsRecheckOrShowFailure(blockReason: blockReason);
      }

      return _cancelledBlocked(reason: blockReason);
    } finally {
      if (Platform.isAndroid) {
        PermissionSettingsHelper.endAwaitingSettingsReturn();
      }
      _pendingFailureAfterSettings = null;
    }
  }

  /// After Settings return: background is OK but Precise Location is still off.
  Future<Map<String, dynamic>> _showPreciseLocationFailureAfterSettings() async {
    const preciseReason = 'location_precise';
    final failureAction = await ClockInBlockedDialog.showFailure(
      reason: preciseReason,
      title: ClockInBlockedDialog.failureTitle,
      message: ClockInBlockedDialog.failureMessageFor(preciseReason),
      bypassCooldown: true,
    );
    if (failureAction == ClockInBlockedAction.openSettings) {
      return _openSettingsRecheckOrShowFailure(blockReason: preciseReason);
    }
    return _cancelledBlocked(reason: preciseReason);
  }

  /// Retries OS background readiness after Settings (Android OEM grant lag).
  /// Returns as soon as ready; otherwise exits after a short window (~0.5s).
  Future<bool> _waitUntilClockInBackgroundReady({
    int attempts = 4,
    Duration interval = const Duration(milliseconds: 120),
  }) async {
    for (var i = 0; i < attempts; i++) {
      await BackgroundLocationPermissions.refreshPermissionStateFromOs();
      if (await BackgroundLocationPermissions.isClockInBackgroundReady()) {
        return true;
      }
      if (i < attempts - 1) {
        await Future<void>.delayed(interval);
      }
    }
    return BackgroundLocationPermissions.isClockInBackgroundReady();
  }

  Future<bool> _ensureClockInDisclosureForClockIn() async {
    await BackgroundLocationPermissions.refreshPermissionStateFromOs();

    if (await BackgroundLocationPermissions.isClockInBackgroundReady()) {
      await LocationDisclosureConsent.reconcileFromOsIfBackgroundReady();
      _disclosureAccepted = true;
      return true;
    }

    if (!await LocationDisclosureConsent.shouldShowLocationDisclosure()) {
      _disclosureAccepted = true;
      return true;
    }

    if (_disclosureAccepted || await LocationDisclosureConsent.hasAccepted()) {
      _disclosureAccepted = true;
      return true;
    }

    if (_disclosurePromptFuture != null) {
      return _disclosurePromptFuture!;
    }

    final completer = Completer<bool>();
    _disclosurePromptFuture = completer.future;
    unawaited(_completeDisclosurePrompt(completer));
    return completer.future;
  }

  Map<String, dynamic> _cancelledBlocked({
    String reason = ClockInBlockedDialog.cancelReason,
  }) {
    _pendingFailureAfterSettings = null;
    return _blocked(
      reason: reason,
      title: ClockInBlockedDialog.failureTitle,
      message: ClockInBlockedDialog.cancelMessage,
    );
  }

  Future<void> _completeDisclosurePrompt(Completer<bool> completer) async {
    try {
      await BackgroundLocationPermissions.refreshPermissionStateFromOs();

      if (!await LocationDisclosureConsent.shouldShowLocationDisclosure()) {
        _disclosureAccepted = true;
        completer.complete(true);
        return;
      }

      await OverlayPromptGuard.waitUntilReady();

      completer.complete(await _promptClockInDisclosure());
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[ClockInGateService] disclosure prompt failed: $e\n$st');
      }
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    } finally {
      if (identical(_disclosurePromptFuture, completer.future)) {
        _disclosurePromptFuture = null;
      }
    }
  }

  Future<bool> _promptClockInDisclosure() async {
    final context = AppNavigator.key.currentContext;
    if (context == null || !context.mounted) {
      return false;
    }

    await BackgroundLocationPermissions.refreshPermissionStateFromOs();

    if (!await LocationDisclosureConsent.shouldShowLocationDisclosure()) {
      _disclosureAccepted = true;
      return true;
    }

    final phase = await BackgroundLocationPermissions.currentPermissionPhase();
    if (!context.mounted) return false;

    final allowed = await ClockInLocationDisclosureDialog.show(
      context,
      phase: phase,
    );
    if (allowed) {
      _disclosureAccepted = true;
      await LocationDisclosureConsent.markAcceptedForAll();
      return true;
    }

    return false;
  }

  Map<String, dynamic> _blocked({
    required String reason,
    required String title,
    required String message,
  }) {
    return _gateResult(
      canClockIn: false,
      reason: reason,
      title: title,
      message: message,
    );
  }

  Map<String, dynamic> _gateResult({
    required bool canClockIn,
    String? reason,
    String? title,
    String? message,
  }) {
    return {
      'ok': true,
      'canClockIn': canClockIn,
      'prepareInFlight': _prepareInFlight,
      if (!canClockIn) ...{
        'reason': reason,
        'title': title,
        'message': message,
      },
    };
  }
}

class _PendingClockInFailureDialog {
  const _PendingClockInFailureDialog({
    required this.reason,
    required this.title,
    required this.message,
  });

  final String reason;
  final String title;
  final String message;
}
