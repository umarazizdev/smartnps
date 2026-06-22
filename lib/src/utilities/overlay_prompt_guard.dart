import 'package:flutter/material.dart';

import '../app/app_navigator.dart';

/// Coordinates native overlays (bottom bar, banners, dialogs) so they do not
/// appear while the system keyboard is open.
class OverlayPromptGuard {
  OverlayPromptGuard._();

  static const Duration _pollInterval = Duration(milliseconds: 100);
  static const Duration _maxWait = Duration(seconds: 30);

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
