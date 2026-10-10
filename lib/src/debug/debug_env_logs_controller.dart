import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'kill_cycle_debug_service.dart';
import 'session_debug_logger.dart';

class DebugEnvLogsController extends GetxController {
  final killCycleBusy = false.obs;
  final sessionBusy = false.obs;
  final killCycle = const KillCycleDebugSnapshot.empty().obs;
  final selectedCategories = <SessionDebugCategory>{
    SessionDebugCategory.apiErrors,
  }.obs;
  final selectedApiSuccessTargets = <SessionDebugApiSuccessTarget>{
    SessionDebugApiSuccessTarget.all,
  }.obs;
  final selectedDuration = SessionDebugDuration.fiveMinutes.obs;
  final sessionRevision = 0.obs;

  Timer? _sessionTicker;

  SessionDebugLogger get session => SessionDebugLogger.instance;

  bool get showKillCycleTimeline =>
      selectedCategories.contains(SessionDebugCategory.kill) ||
      session.categories.contains(SessionDebugCategory.kill);

  bool get showApiSuccessTarget =>
      selectedCategories.contains(SessionDebugCategory.apiSuccess) ||
      session.categories.contains(SessionDebugCategory.apiSuccess);

  @override
  void onInit() {
    super.onInit();
    session.addListener(_onSessionChanged);
    unawaited(loadSession());
  }

  @override
  void onClose() {
    session.removeListener(_onSessionChanged);
    _sessionTicker?.cancel();
    _sessionTicker = null;
    super.onClose();
  }

  Future<void> loadSession() async {
    await session.ensureReady();
    if (session.categories.isNotEmpty) {
      selectedCategories
        ..clear()
        ..addAll(session.categories);
    }
    selectedApiSuccessTargets
      ..clear()
      ..addAll(session.apiSuccessTargets);
    if (selectedApiSuccessTargets.isEmpty) {
      selectedApiSuccessTargets.add(SessionDebugApiSuccessTarget.all);
    }
    sessionRevision.value++;
    if (showKillCycleTimeline) {
      unawaited(refreshKillCycle());
    }
    _syncSessionTicker();
  }

  void _onSessionChanged() {
    sessionRevision.value++;
    _syncSessionTicker();
  }

  void _syncSessionTicker() {
    if (session.isRunning) {
      _sessionTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        sessionRevision.value++;
        if (!session.isRunning) {
          _sessionTicker?.cancel();
          _sessionTicker = null;
        }
      });
    } else {
      _sessionTicker?.cancel();
      _sessionTicker = null;
    }
  }

  Future<void> refreshKillCycle() async {
    killCycleBusy.value = true;
    try {
      killCycle.value = await KillCycleDebugService.loadSnapshot();
    } finally {
      killCycleBusy.value = false;
    }
  }

  Future<void> clearKillCycleLogs() async {
    killCycleBusy.value = true;
    try {
      await KillCycleDebugService.clearLogs();
      killCycle.value = await KillCycleDebugService.loadSnapshot();
      _snack('Kill-cycle logs cleared');
    } finally {
      killCycleBusy.value = false;
    }
  }

  Future<void> copyKillCycle() async {
    await Clipboard.setData(ClipboardData(text: killCycle.value.toCopyText()));
    _snack('Kill-cycle snapshot copied');
  }

  Future<void> runSession() async {
    if (sessionBusy.value || selectedCategories.isEmpty) return;
    sessionBusy.value = true;
    try {
      await session.start(
        categories: Set<SessionDebugCategory>.from(selectedCategories),
        duration: selectedDuration.value.duration,
        apiSuccessTargets:
            Set<SessionDebugApiSuccessTarget>.from(selectedApiSuccessTargets),
      );
      if (selectedCategories.contains(SessionDebugCategory.kill)) {
        unawaited(refreshKillCycle());
      }
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
      await session.stop();
      _snack('Capture stopped');
    } finally {
      sessionBusy.value = false;
    }
  }

  Future<void> clearSessionLogs() async {
    sessionBusy.value = true;
    try {
      await session.clearLogs();
      _snack('Session logs cleared');
    } finally {
      sessionBusy.value = false;
    }
  }

  Future<void> copySessionLogs() async {
    await Clipboard.setData(ClipboardData(text: session.toCopyText()));
    _snack('Session logs copied');
  }

  void toggleCategory(SessionDebugCategory category) {
    if (session.isRunning) return;
    if (selectedCategories.contains(category)) {
      if (selectedCategories.length == 1) return;
      selectedCategories.remove(category);
    } else {
      selectedCategories.add(category);
    }
    if (selectedCategories.contains(SessionDebugCategory.kill)) {
      unawaited(refreshKillCycle());
    }
  }

  void toggleApiSuccessTarget(SessionDebugApiSuccessTarget target) {
    if (session.isRunning) return;
    if (target == SessionDebugApiSuccessTarget.all) {
      selectedApiSuccessTargets
        ..clear()
        ..add(SessionDebugApiSuccessTarget.all);
      return;
    }

    selectedApiSuccessTargets.remove(SessionDebugApiSuccessTarget.all);
    if (selectedApiSuccessTargets.contains(target)) {
      selectedApiSuccessTargets.remove(target);
      if (selectedApiSuccessTargets.isEmpty) {
        selectedApiSuccessTargets.add(SessionDebugApiSuccessTarget.all);
      }
    } else {
      selectedApiSuccessTargets.add(target);
    }
  }

  void selectDuration(SessionDebugDuration duration) {
    if (session.isRunning) return;
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
      'Diagnostic logging',
      message,
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    );
  }
}
