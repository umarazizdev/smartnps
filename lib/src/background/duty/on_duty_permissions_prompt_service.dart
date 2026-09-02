import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../app/app_navigator.dart';
import '../../background/duty/clock_in_gate_service.dart';
import '../../background/duty/duty_heartbeat_service.dart';
import '../../background/duty/duty_status_snapshot.dart';
import '../../permissions/required_permissions_gate.dart';
import '../../utilities/overlay_prompt_guard.dart';
import '../../widgets/dialogs/clock_in_permissions_dialog.dart';
import '../../widgets/dialogs/off_duty_push_permissions_dialog.dart';
import '../../widgets/dialogs/on_duty_permissions_dialog.dart';

class OnDutyPermissionsPromptService {
  OnDutyPermissionsPromptService._();

  static final OnDutyPermissionsPromptService instance =
      OnDutyPermissionsPromptService._();

  static const Duration remindInterval = Duration(minutes: 15);

  DateTime? _lastDismissedAt;
  bool _permissionsWereReady = true;
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
    _permissionsWereReady = true;
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
    if (_blockedByOtherUi) return _PromptAttemptResult.blocked;

    final context = AppNavigator.key.currentContext;
    if (context == null || !context.mounted) {
      return _PromptAttemptResult.blocked;
    }

    _checkInFlight = true;
    try {
      final onDuty = await _isOnDuty();
      if (!onDuty) {
        stopRemindLoop();
        if (kDebugMode) {
          debugPrint('[OnDutyPermissionsPrompt] skip; not on duty');
        }
        return _PromptAttemptResult.notNeeded;
      }

      startRemindLoop();

      final ready =
          await RequiredPermissionsGate.instance.areOnDutyPermissionsReady();
      if (ready) {
        _permissionsWereReady = true;
        _lastDismissedAt = null;
        if (kDebugMode) {
          debugPrint('[OnDutyPermissionsPrompt] skip; permissions ready');
        }
        return _PromptAttemptResult.notNeeded;
      }

      final justBecameMissing = _permissionsWereReady;
      _permissionsWereReady = false;

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
      if (_blockedByOtherUi) return _PromptAttemptResult.blocked;

      if (kDebugMode) {
        debugPrint(
          '[OnDutyPermissionsPrompt] showing dialog '
          '(fromResume=$fromResume)',
        );
      }

      final shown = await OnDutyPermissionsDialog.showIfNeeded();
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
