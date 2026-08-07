import 'package:flutter/material.dart';

import '../app/app_navigator.dart';

class OverlayPromptGuard {
  OverlayPromptGuard._();

  static const Duration _pollInterval = Duration(milliseconds: 100);
  static const Duration _maxWait = Duration(seconds: 30);

  static final ValueNotifier<int> _blockingOverlayCount = ValueNotifier(0);
  static final ValueNotifier<bool> osPermissionPromptInFlight =
      ValueNotifier(false);

  static Listenable get overlayVisibilityListenable => Listenable.merge([
    _blockingOverlayCount,
    osPermissionPromptInFlight,
  ]);

  static bool get hasBlockingNativeOverlay => _blockingOverlayCount.value > 0;

  static bool get blocksTopBanner =>
      hasBlockingNativeOverlay || osPermissionPromptInFlight.value;

  static void registerBlockingOverlay() {
    _blockingOverlayCount.value++;
  }

  static void unregisterBlockingOverlay() {
    if (_blockingOverlayCount.value > 0) {
      _blockingOverlayCount.value--;
    }
  }

  static Future<T> runDuringOsPermissionPrompt<T>(
    Future<T> Function() action,
  ) async {
    osPermissionPromptInFlight.value = true;
    try {
      return await action();
    } finally {
      osPermissionPromptInFlight.value = false;
    }
  }

  static bool isKeyboardVisible([BuildContext? context]) {
    final ctx = context ?? AppNavigator.key.currentContext;
    if (ctx == null || !ctx.mounted) return false;
    return MediaQuery.viewInsetsOf(ctx).bottom > 0;
  }

  static bool canShowOverlay([BuildContext? context]) {
    return !isKeyboardVisible(context);
  }

  static Future<void> waitUntilReady({
    Duration timeout = _maxWait,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (canShowOverlay()) return;
      await Future<void>.delayed(_pollInterval);
    }
  }
}
