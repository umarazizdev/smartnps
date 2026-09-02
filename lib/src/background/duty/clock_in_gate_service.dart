import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../location/mock_location_guard.dart';
import '../../permissions/required_permissions_gate.dart';
import '../../utilities/app_config.dart';
import '../../widgets/dialogs/clock_in_blocked_dialog.dart';
import '../../widgets/dialogs/clock_in_permissions_dialog.dart';
import '../location/background_location_permissions.dart';
import '../location/background_location_service.dart';
import 'location_disclosure_consent.dart';

class ClockInGateService {
  ClockInGateService._();

  static final ClockInGateService instance = ClockInGateService._();

  bool _geoUnlockedForClockIn = false;
  bool _prepareInFlight = false;
  bool _clockInAttemptActive = false;
  Future<Map<String, dynamic>>? _ongoingPrepare;
  DateTime? _lastCancelledAt;
  Timer? _clockInAbandonTimer;
  int _clockInAbandonGeneration = 0;

  static const Duration _reentryCooldownAfterCancel = Duration(seconds: 2);
  static const Duration _abandonAfterGpsDelivered = Duration(seconds: 45);
  static const Duration _abandonIfGpsNeverRequested = Duration(minutes: 4);

  final ValueNotifier<bool> prepareInFlightVisible = ValueNotifier(false);

  bool get isGeoUnlockedForClockIn => _geoUnlockedForClockIn;

  bool get isPrepareInFlight => _prepareInFlight || _ongoingPrepare != null;

  bool get isClockInAttemptActive => _clockInAttemptActive;

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

  void _cancelAbandonWatchdog() {
    _clockInAbandonGeneration++;
    _clockInAbandonTimer?.cancel();
    _clockInAbandonTimer = null;
  }

  void _scheduleAbandonWatchdog(
    Duration delay, {
    required String reason,
  }) {
    final generation = ++_clockInAbandonGeneration;
    _clockInAbandonTimer?.cancel();
    _clockInAbandonTimer = Timer(delay, () {
      if (generation != _clockInAbandonGeneration) return;
      if (!_clockInAttemptActive) return;
      unawaited(abandonClockInAttempt(reason: reason));
    });
  }

  void markClockInAttemptStarted() {
    _clockInAttemptActive = true;
    _scheduleAbandonWatchdog(
      _abandonIfGpsNeverRequested,
      reason: 'gps_never_requested',
    );
  }

  void onClockInGpsDeliveredToWeb() {
    if (!_clockInAttemptActive) return;
    _scheduleAbandonWatchdog(
      _abandonAfterGpsDelivered,
      reason: 'no_success_after_gps',
    );
  }

  void onClockInSucceeded() {
    _clockInAttemptActive = false;
    _cancelAbandonWatchdog();
  }

  Future<void> abandonClockInAttempt({required String reason}) async {
    final wasActive = _clockInAttemptActive;
    _clockInAttemptActive = false;
    _cancelAbandonWatchdog();
    clearGeoUnlock();

    if (Platform.isAndroid) {
      await BackgroundLocationService.cancelClockInWarm();
    }

    if (kDebugMode && (wasActive || Platform.isAndroid)) {
      debugPrint(
        '[ClockInGateService] clock-in attempt abandoned ($reason)',
      );
    }
  }

  void resetLocationDisclosureMemory() {
    clearGeoUnlock();
  }

  Future<void> recheckAfterAppResume() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    if (_prepareInFlight || _ongoingPrepare != null) return;

    if (!_clockInAttemptActive) {
      await BackgroundLocationService.reconcileStaleClockInWarm();
    }

    await BackgroundLocationPermissions.refreshPermissionStateFromOs();

    if (await _isClockInFullyReady(includeMockGpsCheck: false)) {
      if (kDebugMode) {
        debugPrint(
          '[ClockInGateService] resume: permissions ready; '
          'mock GPS deferred to clock-in gate',
        );
      }
      return;
    }
    clearGeoUnlock();
  }

  Future<bool> _isClockInFullyReady({required bool includeMockGpsCheck}) async {
    await BackgroundLocationPermissions.refreshPermissionStateFromOs();
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    final backgroundReady =
        await BackgroundLocationPermissions.isClockInBackgroundReady();
    if (!backgroundReady) {
      if (!await LocationDisclosureConsent.hasAccepted()) return false;
      return false;
    }

    await LocationDisclosureConsent.reconcileFromOsIfBackgroundReady();

    if (!await BackgroundLocationPermissions.hasPreciseLocationAccess()) {
      return false;
    }

    if (!includeMockGpsCheck || !AppConfig.enableMockLocationDetection) {
      return true;
    }

    final mockCheck = await MockLocationGuard.ensureClearForClockIn();
    return mockCheck == MockLocationClockInCheck.clear;
  }

  Future<void> _hydrateFromStorage() async {
    await LocationDisclosureConsent.ensureMigrated();
    await LocationDisclosureConsent.reconcileFromOsIfBackgroundReady();
  }

  Future<Map<String, dynamic>> prepareClockIn() async {
    final ongoing = _ongoingPrepare;
    if (ongoing != null) {
      if (kDebugMode) {
        debugPrint(
          '[ClockInGateService] prepareClockIn joining in-flight request',
        );
      }
      return ongoing;
    }

    final future = _runPrepareClockIn();
    _ongoingPrepare = future;
    try {
      return await future;
    } finally {
      if (identical(_ongoingPrepare, future)) {
        _ongoingPrepare = null;
      }
    }
  }

  Future<Map<String, dynamic>> _runPrepareClockIn() async {
    _setPrepareInFlight(true);
    _geoUnlockedForClockIn = false;
    if (kDebugMode) {
      debugPrint('[ClockInGateService] prepareClockIn started');
    }

    try {
      final lastCancel = _lastCancelledAt;
      if (lastCancel != null &&
          DateTime.now().difference(lastCancel) < _reentryCooldownAfterCancel) {
        if (kDebugMode) {
          debugPrint(
            '[ClockInGateService] prepareClockIn blocked: cancel cooldown',
          );
        }
        return _cancelledBlocked();
      }

      if (!Platform.isAndroid && !Platform.isIOS) {
        _geoUnlockedForClockIn = true;
        if (kDebugMode) {
          debugPrint(
            '[ClockInGateService] prepareClockIn allowed (non-mobile)',
          );
        }
        return _gateResult(canClockIn: true);
      }

      await _hydrateFromStorage();
      await BackgroundLocationPermissions.refreshPermissionStateFromOs();

      if (!await RequiredPermissionsGate.instance
          .areClockInPermissionsReady()) {
        if (kDebugMode) {
          debugPrint(
            '[ClockInGateService] prepareClockIn: showing permissions dialog',
          );
        }
        final allowed =
            await ClockInPermissionsDialog.showUntilReadyOrCancelled();
        if (!allowed) {
          _lastCancelledAt = DateTime.now();
          if (kDebugMode) {
            debugPrint(
              '[ClockInGateService] prepareClockIn blocked: permissions cancelled',
            );
          }
          return _cancelledBlocked();
        }
        await BackgroundLocationPermissions.refreshPermissionStateFromOs();
        await LocationDisclosureConsent.reconcileFromOsIfBackgroundReady();
      } else {
        await LocationDisclosureConsent.reconcileFromOsIfBackgroundReady();
      }

      if (!await RequiredPermissionsGate.instance
          .areClockInPermissionsReady()) {
        _lastCancelledAt = DateTime.now();
        if (kDebugMode) {
          debugPrint(
            '[ClockInGateService] prepareClockIn blocked: permissions still missing',
          );
        }
        return _cancelledBlocked(reason: 'background_location_required');
      }

      if (AppConfig.enableMockLocationDetection) {
        final mockCheck = await MockLocationGuard.ensureClearForClockIn();
        final mockBlocked = await _blockedIfMockCheckFailed(mockCheck);
        if (mockBlocked != null) return mockBlocked;
      }

      _lastCancelledAt = null;
      _geoUnlockedForClockIn = true;
      markClockInAttemptStarted();
      if (Platform.isAndroid) {
        unawaited(BackgroundLocationService.preWarmForClockIn());
      }
      if (kDebugMode) {
        debugPrint(
          '[ClockInGateService] prepareClockIn allowed canClockIn=true',
        );
      }
      return _gateResult(canClockIn: true);
    } finally {
      _setPrepareInFlight(false);
    }
  }

  Map<String, dynamic> _cancelledBlocked({
    String reason = ClockInBlockedDialog.cancelReason,
  }) {
    return _blocked(
      reason: reason,
      title: ClockInBlockedDialog.failureTitle,
      message: ClockInBlockedDialog.cancelMessage,
    );
  }

  Future<Map<String, dynamic>?> _blockedIfMockCheckFailed(
    MockLocationClockInCheck check,
  ) async {
    switch (check) {
      case MockLocationClockInCheck.clear:
        return null;
      case MockLocationClockInCheck.mockDetected:
        if (kDebugMode) {
          debugPrint(
            '[ClockInGateService] prepareClockIn blocked: mock_location',
          );
        }

        return _blocked(
          reason: 'mock_location',
          title: 'Mock location detected',
          message:
              'Disable mock or fake GPS location before verifying shift attendance from the mobile app.',
        );
      case MockLocationClockInCheck.gpsUnavailable:
        if (kDebugMode) {
          debugPrint(
            '[ClockInGateService] prepareClockIn blocked: gps_unavailable',
          );
        }
        const reason = 'gps_unavailable';
        const title = 'Location unavailable';
        const message =
            'Could not get your current location. Move outdoors or wait for GPS, then try again.';
        await ClockInBlockedDialog.showFailure(
          reason: reason,
          title: title,
          message: message,
          bypassCooldown: true,
        );
        return _blocked(reason: reason, title: title, message: message);
    }
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
