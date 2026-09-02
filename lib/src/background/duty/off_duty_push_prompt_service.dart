import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../app/app_navigator.dart';
import '../../auth/auth_repository.dart';
import '../../auth/auth_session_manager.dart';
import '../../background/duty/clock_in_gate_service.dart';
import '../../background/duty/duty_heartbeat_service.dart';
import '../../background/duty/duty_status_snapshot.dart';
import '../../permissions/required_permissions_gate.dart';
import '../../utilities/app_config.dart';
import '../../utilities/overlay_prompt_guard.dart';
import '../../widgets/dialogs/clock_in_permissions_dialog.dart';
import '../../widgets/dialogs/off_duty_push_permissions_dialog.dart';
import '../../widgets/dialogs/on_duty_permissions_dialog.dart';

class OffDutyPushPromptService {
  OffDutyPushPromptService._();

  static final OffDutyPushPromptService instance = OffDutyPushPromptService._();

  static const Duration remindInterval = Duration(minutes: 15);

  static Uri? Function()? currentUriChecker;

  DateTime? _lastDismissedAt;
  bool _pushWasReady = true;
  Timer? _remindTimer;
  bool _checkInFlight = false;

  void startRemindLoop() {
    if (_remindTimer != null) return;
    _remindTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(maybeShow(fromResume: false));
    });
  }

  void stopRemindLoop() {
    _remindTimer?.cancel();
    _remindTimer = null;
    _lastDismissedAt = null;
    _pushWasReady = true;
  }

  void noteDismissed() {
    _lastDismissedAt = DateTime.now();
  }

  bool get _blockedByOtherUi =>
      RequiredPermissionsGate.isPrivacyNoticeVisible ||
      ClockInPermissionsDialog.isVisible ||
      OnDutyPermissionsDialog.isVisible ||
      OffDutyPushPermissionsDialog.isVisible ||
      ClockInGateService.instance.isPrepareInFlight;

  bool get _onAuthOrPrivacySurface {
    if (RequiredPermissionsGate.isPrivacyNoticeVisible) return true;
    final uri = currentUriChecker?.call();
    if (uri != null && AppConfig.isAuthEntryRoute(uri)) return true;
    if (AuthSessionManager.isLoginRoute(uri)) return true;
    return false;
  }

  Future<void> maybeShow({required bool fromResume}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final first = await _attempt(fromResume: fromResume);
    if (fromResume && first == _PromptAttemptResult.blocked) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await _attempt(fromResume: true);
    }
  }

  Future<_PromptAttemptResult> _attempt({required bool fromResume}) async {
    if (_checkInFlight) return _PromptAttemptResult.blocked;
    if (_blockedByOtherUi || _onAuthOrPrivacySurface) {
      if (_onAuthOrPrivacySurface) stopRemindLoop();
      return _PromptAttemptResult.blocked;
    }

    final context = AppNavigator.key.currentContext;
    if (context == null || !context.mounted) {
      return _PromptAttemptResult.blocked;
    }

    _checkInFlight = true;
    try {
      if (!await AuthRepository.instance.isOfficerLoggedIn()) {
        stopRemindLoop();
        if (kDebugMode) {
          debugPrint('[OffDutyPushPrompt] skip; not logged in');
        }
        return _PromptAttemptResult.notNeeded;
      }

      final token = await AuthRepository.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        stopRemindLoop();
        return _PromptAttemptResult.notNeeded;
      }

      if (_blockedByOtherUi || _onAuthOrPrivacySurface) {
        stopRemindLoop();
        return _PromptAttemptResult.blocked;
      }

      final onDuty = await _isOnDuty();
      if (onDuty) {
        stopRemindLoop();
        if (kDebugMode) {
          debugPrint('[OffDutyPushPrompt] skip; on duty');
        }
        return _PromptAttemptResult.notNeeded;
      }

      startRemindLoop();

      final ready = await RequiredPermissionsGate.instance
          .areOffDutyPushPermissionsReady();
      if (ready) {
        _pushWasReady = true;
        _lastDismissedAt = null;
        return _PromptAttemptResult.notNeeded;
      }

      final justBecameMissing = _pushWasReady;
      _pushWasReady = false;

      if (!fromResume) {
        if (!justBecameMissing) {
          final last = _lastDismissedAt;
          if (last == null ||
              DateTime.now().difference(last) < remindInterval) {
            return _PromptAttemptResult.notNeeded;
          }
        }
      }

      await OverlayPromptGuard.waitUntilReady();
      if (_blockedByOtherUi || _onAuthOrPrivacySurface) {
        stopRemindLoop();
        return _PromptAttemptResult.blocked;
      }

      if (kDebugMode) {
        debugPrint(
          '[OffDutyPushPrompt] showing dialog (fromResume=$fromResume)',
        );
      }

      final shown = await OffDutyPushPermissionsDialog.showIfNeeded();
      if (shown) {
        noteDismissed();
        return _PromptAttemptResult.shown;
      }
      return _PromptAttemptResult.blocked;
    } finally {
      _checkInFlight = false;
    }
  }

  Future<bool> _isOnDuty() async {
    if (await DutyStatusSnapshot.isValidOnDutyForCurrentUser()) return true;
    if (DutyHeartbeatService.instance.isOnDutyTrackingActive) return true;
    return DutyHeartbeatService.instance.isOnDutyAccordingToHeartbeat();
  }
}

enum _PromptAttemptResult { notNeeded, shown, blocked }
