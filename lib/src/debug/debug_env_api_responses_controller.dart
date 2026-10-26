import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'api_response_debug_logger.dart';
import 'session_debug_logger.dart';

class DebugEnvApiResponsesController extends GetxController {
  final sessionBusy = false.obs;
  final selectedTargets = <SessionDebugApiSuccessTarget>{
    SessionDebugApiSuccessTarget.heartbeat,
    SessionDebugApiSuccessTarget.permissionStatus,
  }.obs;
  final selectedDuration = SessionDebugDuration.fiveMinutes.obs;
  final sessionRevision = 0.obs;
  final detailExpanded = true.obs;

  Timer? _sessionTicker;

  ApiResponseDebugLogger get logger => ApiResponseDebugLogger.instance;

  @override
  void onInit() {
    super.onInit();
    logger.addListener(_onLoggerChanged);
    unawaited(loadSession());
  }

  @override
  void onClose() {
    logger.removeListener(_onLoggerChanged);
    _sessionTicker?.cancel();
    _sessionTicker = null;
    super.onClose();
  }

  Future<void> loadSession() async {
    await logger.ensureReady();
    if (logger.targets.isNotEmpty) {
      selectedTargets
        ..clear()
        ..addAll(logger.targets);
    }
    if (selectedTargets.isEmpty) {
      selectedTargets.add(SessionDebugApiSuccessTarget.all);
    }
    sessionRevision.value++;
    _syncSessionTicker();
  }

  void _onLoggerChanged() {
    if (isClosed) return;
    try {
      sessionRevision.value++;
      _syncSessionTicker();
    } catch (_) {}
  }

  void _syncSessionTicker() {
    if (isClosed) {
      _sessionTicker?.cancel();
      _sessionTicker = null;
      return;
    }
    if (logger.isRunning) {
      _sessionTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (isClosed) {
          _sessionTicker?.cancel();
          _sessionTicker = null;
          return;
        }
        sessionRevision.value++;
        if (!logger.isRunning) {
          _sessionTicker?.cancel();
          _sessionTicker = null;
        }
      });
    } else {
      _sessionTicker?.cancel();
      _sessionTicker = null;
    }
  }

  Future<void> runSession() async {
    if (sessionBusy.value || selectedTargets.isEmpty) return;
    sessionBusy.value = true;
    try {
      await logger.start(
        targets: Set<SessionDebugApiSuccessTarget>.from(selectedTargets),
        duration: selectedDuration.value.duration,
      );
      _snack(
        'Capture started for ${selectedDuration.value.label}. '
        'Stops automatically when the timer ends.',
      );
    } finally {
      sessionBusy.value = false;
    }
  }

  Future<void> stopSession() async {
    if (sessionBusy.value) return;
    sessionBusy.value = true;
    try {
      await logger.stop();
      _snack('Capture stopped');
    } finally {
      sessionBusy.value = false;
    }
  }

  Future<void> clearEntries() async {
    sessionBusy.value = true;
    try {
      await logger.clearEntries();
      _snack('API response logs cleared');
    } finally {
      sessionBusy.value = false;
    }
  }

  Future<void> copyEntries() async {
    final text = logger.toCopyText();
    await Clipboard.setData(ClipboardData(text: text));
    _snack('API response logs copied');
  }

  Future<void> copyEntry(String entry) async {
    final trimmed = entry.trim();
    if (trimmed.isEmpty) {
      _snack('Nothing to copy');
      return;
    }
    await Clipboard.setData(ClipboardData(text: trimmed));
    _snack('Response copied');
  }

  void toggleDetailExpanded() {
    detailExpanded.toggle();
  }

  void toggleTarget(SessionDebugApiSuccessTarget target) {
    if (logger.isRunning) return;
    if (target == SessionDebugApiSuccessTarget.all) {
      selectedTargets
        ..clear()
        ..add(SessionDebugApiSuccessTarget.all);
      return;
    }

    selectedTargets.remove(SessionDebugApiSuccessTarget.all);
    if (selectedTargets.contains(target)) {
      selectedTargets.remove(target);
      if (selectedTargets.isEmpty) {
        selectedTargets.add(SessionDebugApiSuccessTarget.all);
      }
    } else {
      selectedTargets.add(target);
    }
  }

  void selectDuration(SessionDebugDuration duration) {
    if (logger.isRunning) return;
    selectedDuration.value = duration;
  }

  String formatRemaining(Duration remaining) {
    final total = remaining.inSeconds;
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _snack(String message) {
    Get.snackbar(
      'API response logging',
      message,
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    );
  }
}
