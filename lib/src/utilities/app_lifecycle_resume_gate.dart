import 'dart:async';

import 'package:flutter/foundation.dart';

class AppLifecycleResumeGate {
  AppLifecycleResumeGate._();

  static Completer<void>? _waiting;
  static bool _sawBackgroundAfterResume = false;

  static Future<bool> waitForResume({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    _waiting = Completer<void>();
    final completer = _waiting!;
    try {
      await completer.future.timeout(timeout);
      return true;
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('[AppLifecycleResumeGate] resume wait timed out');
      }
      return false;
    } finally {
      if (identical(_waiting, completer)) {
        _waiting = null;
      }
    }
  }

  static Future<bool> waitForStableResume({
    Duration timeout = const Duration(minutes: 5),
    Duration stableDuration = const Duration(milliseconds: 700),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        if (kDebugMode) {
          debugPrint('[AppLifecycleResumeGate] stable resume timed out');
        }
        return false;
      }

      final resumed = await waitForResume(timeout: remaining);
      if (!resumed) return false;

      _sawBackgroundAfterResume = false;
      await Future<void>.delayed(stableDuration);
      if (!_sawBackgroundAfterResume) return true;

      if (kDebugMode) {
        debugPrint(
          '[AppLifecycleResumeGate] resume not stable; waiting again',
        );
      }
    }
  }

  static void notifyResumed() {
    final waiting = _waiting;
    if (waiting != null && !waiting.isCompleted) {
      waiting.complete();
    }
  }

  static void notifyBackgrounded() {
    _sawBackgroundAfterResume = true;
  }
}
