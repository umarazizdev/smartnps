import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../utilities/secure_storage_access.dart';

/// Crashlytics helpers focused on maximizing delivery for real users.
///
/// Hard process kills still upload on the *next* launch (SDK limitation).
/// Caught Flutter errors can flush immediately while the app is still alive.
///
/// Recoverable noise (network blips, keychain locked, layout overflow) is
/// ignored or recorded as non-fatal so Crashlytics stays useful for real
/// crashes.
class CrashlyticsReporter {
  CrashlyticsReporter._();

  static bool _lifecycleInstalled = false;

  static Future<void> init() async {
    FlutterError.onError = (errorDetails) {
      unawaited(_recordFlutterError(errorDetails));
      if (kDebugMode) {
        FlutterError.presentError(errorDetails);
      }
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      if (shouldIgnoreError(error)) {
        return true;
      }
      final fatal = !isNonFatalError(error);
      unawaited(_recordAndFlush(error, stack, fatal: fatal));
      return true;
    };

    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    await flushUnsent();
    _installLifecycleFlush();
  }

  static Future<void> flushUnsent() async {
    try {
      await FirebaseCrashlytics.instance.sendUnsentReports();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[CrashlyticsReporter] sendUnsentReports failed: $e\n$st');
      }
    }
  }

  /// Recoverable conditions we should not spam into Crashlytics.
  static bool shouldIgnoreError(Object error) {
    if (SecureStorageAccess.isInteractionNotAllowed(error)) return true;
    final text = error.toString();
    return _looksLikeNetworkNoise(text);
  }

  /// True for recoverable noise that should not count as a crash.
  static bool isNonFatalError(Object error) {
    if (shouldIgnoreError(error)) return true;
    if (error is SocketException ||
        error is HttpException ||
        error is HandshakeException ||
        error is TlsException ||
        error is TimeoutException ||
        error is OSError) {
      return true;
    }

    final text = error.toString();
    if (_looksLikeLayoutOverflow(text)) {
      return true;
    }
    return false;
  }

  static bool isNonFatalFlutterError(FlutterErrorDetails details) {
    if (details.silent) return true;
    if (isNonFatalError(details.exception)) return true;
    final text = '${details.exceptionAsString()} ${details.library ?? ''}';
    return _looksLikeLayoutOverflow(text) ||
        SecureStorageAccess.isInteractionNotAllowed(text) ||
        _looksLikeNetworkNoise(text);
  }

  static bool shouldIgnoreFlutterError(FlutterErrorDetails details) {
    if (details.silent) return true;
    if (shouldIgnoreError(details.exception)) return true;
    final text = details.exceptionAsString();
    return SecureStorageAccess.isInteractionNotAllowed(text) ||
        _looksLikeNetworkNoise(text);
  }

  static bool _looksLikeNetworkNoise(String text) {
    final lower = text.toLowerCase();
    return lower.contains('httpexception') ||
        lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('handshakeexception') ||
        lower.contains('tlsexception') ||
        lower.contains('connection closed') ||
        lower.contains('connection reset') ||
        lower.contains('unsolicited response') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable');
  }

  static bool _looksLikeLayoutOverflow(String text) {
    final lower = text.toLowerCase();
    return lower.contains('renderflex overflowed') ||
        lower.contains('overflowed by') ||
        lower.contains('a renderflex overflowed') ||
        lower.contains('cannot hit test a render box with no size');
  }

  static Future<void> _recordFlutterError(FlutterErrorDetails details) async {
    try {
      if (shouldIgnoreFlutterError(details)) {
        return;
      }
      if (isNonFatalFlutterError(details)) {
        await FirebaseCrashlytics.instance.recordFlutterError(details);
      } else {
        await FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      }
      await flushUnsent();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[CrashlyticsReporter] recordFlutterError failed: $e\n$st');
      }
    }
  }

  static Future<void> _recordAndFlush(
    Object error,
    StackTrace stack, {
    required bool fatal,
  }) async {
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        fatal: fatal,
        reason: fatal ? null : 'non_fatal_classified',
      );
      await flushUnsent();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[CrashlyticsReporter] recordAndFlush failed: $e\n$st');
      }
    }
  }

  /// Flush whenever the app returns to foreground (covers "user opens again"
  /// without needing them to understand Crashlytics).
  static void _installLifecycleFlush() {
    if (_lifecycleInstalled) return;
    _lifecycleInstalled = true;
    WidgetsBinding.instance.addObserver(_CrashlyticsLifecycleObserver());
  }
}

class _CrashlyticsLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(CrashlyticsReporter.flushUnsent());
    }
  }
}
