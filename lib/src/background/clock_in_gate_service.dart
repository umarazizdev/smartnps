import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../auth/location_disclosure_account_sync.dart';
import '../app/app_navigator.dart';
import '../location/mock_location_guard.dart';
import '../utilities/app_lifecycle_resume_gate.dart';
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

  bool get isGeoUnlockedForClockIn => _geoUnlockedForClockIn;

  /// True while [prepareClockIn] is running — blocks parallel GPS / clock-in.
  bool get isPrepareInFlight => _prepareInFlight;

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

    await BackgroundLocationPermissions.refreshPermissionStateFromOs();

    final pending = _pendingFailureAfterSettings;
    if (pending != null && !_prepareInFlight) {
      _pendingFailureAfterSettings = null;
      if (await _isClockInFullyReady()) {
        _geoUnlockedForClockIn = true;
        return;
      }
      await ClockInBlockedDialog.showFailure(
        reason: pending.reason,
        title: pending.title,
        message: pending.message,
        bypassCooldown: true,
      );
      clearGeoUnlock();
      return;
    }

    if (!await LocationDisclosureConsent.hasAccepted()) return;
    if (!await BackgroundLocationPermissions.isClockInBackgroundReady()) {
      clearGeoUnlock();
      return;
    }
    if (!await MockLocationGuard.ensureClearForClockIn()) {
      clearGeoUnlock();
      return;
    }
    _geoUnlockedForClockIn = true;
  }

  Future<bool> _isClockInFullyReady() async {
    if (!await LocationDisclosureConsent.hasAccepted()) return false;
    if (!await BackgroundLocationPermissions.isClockInBackgroundReady()) {
      return false;
    }
    if (!await MockLocationGuard.ensureClearForClockIn()) return false;
    return true;
  }

  Future<void> _hydrateFromStorage() async {
    await LocationDisclosureAccountSync.onLoginResolved();
    if (await LocationDisclosureConsent.hasAccepted()) {
      _disclosureAccepted = true;
    }
  }

  Future<Map<String, dynamic>> prepareClockIn() async {
    if (_prepareInFlight) {
      return _blocked(
        reason: 'clock_in_in_progress',
        title: ClockInBlockedDialog.failureTitle,
        message: 'Please wait for the location permission step to finish.',
      );
    }

    _prepareInFlight = true;
    _geoUnlockedForClockIn = false;
    _pendingFailureAfterSettings = null;

    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        _geoUnlockedForClockIn = true;
        return _gateResult(canClockIn: true);
      }

      await _hydrateFromStorage();

      if (!await Geolocator.isLocationServiceEnabled()) {
        return _runLocationSettingsPromptFlow(
          deniedReason: 'location_services_disabled',
        );
      }

      if (!await _ensureClockInDisclosureForClockIn()) {
        return _cancelledBlocked();
      }

      if (!await BackgroundLocationPermissions.hasForegroundLocationAccess()) {
        await PermissionSettingsHelper.requestForegroundLocationStep();
      }

      await BackgroundLocationPermissions.refreshPermissionStateFromOs();

      if (!await BackgroundLocationPermissions.isClockInBackgroundReady()) {
        final deniedReason =
            await BackgroundLocationPermissions.settingsDeniedReasonIfAny();
        return _runLocationSettingsPromptFlow(deniedReason: deniedReason);
      }

      if (!await MockLocationGuard.ensureClearForClockIn()) {
        return _blocked(
          reason: 'mock_location',
          title: 'Mock location detected',
          message:
              'Disable mock or fake GPS location before clocking in from the mobile app.',
        );
      }

      _geoUnlockedForClockIn = true;
      return _gateResult(canClockIn: true);
    } finally {
      _prepareInFlight = false;
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
      return _cancelledBlocked(reason: blockReason);
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

    await PermissionSettingsHelper.openSettingsForUserTap(
      destination: ClockInBlockedDialog.settingsDestinationFor(blockReason),
    );
    await AppLifecycleResumeGate.waitForResume();
    await BackgroundLocationPermissions.refreshPermissionStateFromOs();

    _pendingFailureAfterSettings = null;

    if (await BackgroundLocationPermissions.isClockInBackgroundReady()) {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await ClockInBlockedDialog.showFailure(
          reason: blockReason,
          title: failureTitle,
          message: failureMessage,
          bypassCooldown: true,
        );
        return _cancelledBlocked(reason: blockReason);
      }

      if (!await MockLocationGuard.ensureClearForClockIn()) {
        return _blocked(
          reason: 'mock_location',
          title: 'Mock location detected',
          message:
              'Disable mock or fake GPS location before clocking in from the mobile app.',
        );
      }

      _geoUnlockedForClockIn = true;
      return _gateResult(canClockIn: true);
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
  }

  Future<bool> _ensureClockInDisclosureForClockIn() async {
    await BackgroundLocationPermissions.refreshPermissionStateFromOs();

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
