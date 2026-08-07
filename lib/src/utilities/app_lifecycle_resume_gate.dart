import 'dart:async';

import 'package:flutter/foundation.dart';

class AppLifecycleResumeGate {
  AppLifecycleResumeGate._();

  static Completer<void>? _waiting;

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

  static void notifyResumed() {
    final waiting = _waiting;
    if (waiting != null && !waiting.isCompleted) {
      waiting.complete();
    }
  }
}
