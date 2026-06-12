import 'package:flutter/material.dart';

import '../app/app_navigator.dart';

/// Coordinates native overlays (bottom bar, banners, dialogs) so they do not
/// appear while the WebView keyboard is open or during the post-login grace period.
class OverlayPromptGuard {
  OverlayPromptGuard._();

  static const Duration postLoginDelay = Duration(seconds: 1);
  static const Duration _pollInterval = Duration(milliseconds: 100);
  static const Duration _maxWait = Duration(seconds: 30);

  static bool webKeyboardVisible = false;
  static DateTime? _postLoginDelayUntil;

  static void setWebKeyboardVisible(bool visible) {
    webKeyboardVisible = visible;
  }

  static void markPostLoginDelay() {
    _postLoginDelayUntil = DateTime.now().add(postLoginDelay);
  }

  static void clearPostLoginDelay() {
    _postLoginDelayUntil = null;
  }

  static bool isWithinPostLoginDelay() {
    final until = _postLoginDelayUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _postLoginDelayUntil = null;
    return false;
  }

  static bool isKeyboardVisible([BuildContext? context]) {
    if (webKeyboardVisible) return true;
    final ctx = context ?? AppNavigator.key.currentContext;
    if (ctx == null || !ctx.mounted) return false;
    return MediaQuery.viewInsetsOf(ctx).bottom > 0;
  }

  static bool canShowOverlay([BuildContext? context]) {
    return !isKeyboardVisible(context) && !isWithinPostLoginDelay();
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
