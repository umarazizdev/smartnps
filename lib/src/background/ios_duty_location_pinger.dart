import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../auth/auth_repository.dart';
import '../location/mock_location_detection.dart';
import '../location/mock_location_guard.dart';
import 'background_location_uploader.dart';
import 'ios_background_location_notification.dart';

/// iOS live location pings run on the main isolate. Background service isolates
/// cannot safely use flutter_local_notifications (objective_c crash).
class IosDutyLocationPinger {
  IosDutyLocationPinger._();

  static StreamSubscription<Position>? _subscription;
  static Timer? _pingTimer;
  static BackgroundLocationUploader? _uploader;
  static DateTime? _lastUploadAt;
  static bool _running = false;
  static bool _stopping = false;
  static bool _recoverInFlight = false;

  static const Duration _pingEvery = Duration(seconds: 1);
  static const Duration _recoverDelay = Duration(seconds: 2);
  static const Duration _staleLocationThreshold = Duration(minutes: 2);

  /// True only when the position stream subscription is active.
  static bool get isRunning => _running && _subscription != null;

  /// True when the stream is alive but has not produced a ping recently.
  static bool get needsRecovery {
    if (!Platform.isIOS || !isRunning) return false;
    final last = _lastUploadAt;
    if (last == null) return false;
    return DateTime.now().difference(last) > _staleLocationThreshold;
  }

  static Future<void> start() async {
    if (!Platform.isIOS) return;
    if (_running && _subscription != null) return;
    if (_running) {
      await stop();
    }

    try {
      _uploader = BackgroundLocationUploader();
      await _uploader!.init();
      _uploader!.start();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IosDutyLocationPinger] uploader init failed: $e');
      }
      rethrow;
    }

    unawaited(
      IosBackgroundLocationNotification.show().catchError((Object e) {
        if (kDebugMode) {
          debugPrint('[IosDutyLocationPinger] notification failed: $e');
        }
      }),
    );

    final permission = await Geolocator.checkPermission();
    final allowBackground = permission == LocationPermission.always;

    final settings = AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
      allowBackgroundLocationUpdates: allowBackground,
    );

    try {
      _subscription = Geolocator.getPositionStream(locationSettings: settings)
          .listen(
        _onPosition,
        onError: (Object error) {
          if (kDebugMode) {
            debugPrint('[IosDutyLocationPinger] stream error: $error');
          }
          unawaited(_onStreamError(error));
        },
      );
    } catch (e) {
      await stop();
      rethrow;
    }

    _running = true;
    _stopping = false;
    _startPeriodicPing();
    if (kDebugMode) {
      debugPrint(
        '[IosDutyLocationPinger] started '
        '(allowBackground=$allowBackground permission=$permission)',
      );
    }
  }

  /// iOS may not emit stream events when the device is stationary (simulator).
  /// Poll explicitly so ping/batch keep running on the 1s duty interval.
  static void _startPeriodicPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingEvery, (_) {
      unawaited(_pollCurrentPosition());
    });
    unawaited(_pollCurrentPosition());
  }

  static Future<void> _pollCurrentPosition() async {
    if (_stopping || !_running || _uploader == null) return;

    try {
      final permission = await Geolocator.checkPermission();
      final allowBackground = permission == LocationPermission.always;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: allowBackground,
        ),
      );
      await _onPosition(pos);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IosDutyLocationPinger] periodic poll failed: $e');
      }
    }
  }

  /// Restarts the stream after permission changes or CoreLocation errors.
  static Future<void> recoverIfNeeded() async {
    if (!Platform.isIOS || _recoverInFlight) return;
    if (isRunning && !needsRecovery) return;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _recoverInFlight = true;
    try {
      if (kDebugMode) {
        debugPrint('[IosDutyLocationPinger] scheduling recovery');
      }
      await Future<void>.delayed(_recoverDelay);
      if (isRunning && !needsRecovery) return;

      await stop();
      await start();
      if (kDebugMode) {
        debugPrint('[IosDutyLocationPinger] recovery complete');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IosDutyLocationPinger] recovery failed: $e');
      }
    } finally {
      _recoverInFlight = false;
    }
  }

  static Future<void> _onStreamError(Object error) async {
    await _subscription?.cancel();
    _subscription = null;
    _running = false;

    if (kDebugMode) {
      debugPrint('[IosDutyLocationPinger] stream stopped after error');
    }

    unawaited(recoverIfNeeded());
  }

  static Future<void> _onPosition(Position pos) async {
    if (_stopping) return;

    final token = await AuthRepository.instance.getAccessToken();
    if (token == null || token.isEmpty) {
      await stop();
      return;
    }

    final now = DateTime.now();
    final last = _lastUploadAt;
    if (last != null && now.difference(last) < const Duration(seconds: 1)) {
      return;
    }
    _lastUploadAt = now;

    final mockFlags = MockLocationDetection.flagsFor(pos);
    if (mockFlags.isDetected) {
      MockLocationGuard.maybeShowDialog(
        isMocked: mockFlags.isMocked,
        isSimulatedBySoftware: mockFlags.isSimulatedBySoftware,
      );
    }

    if (kDebugMode) {
      debugPrint(
        '[IosDutyLocationPinger] location '
        'lat=${pos.latitude} lng=${pos.longitude} acc=${pos.accuracy} '
        'mocked=${mockFlags.isMocked} simulated=${mockFlags.isSimulatedBySoftware} '
        'ts=${pos.timestamp.toIso8601String()}',
      );
    }

    final uploader = _uploader;
    if (uploader == null) return;

    try {
      await uploader.pingNow(pos);
      await uploader.add(pos);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IosDutyLocationPinger] upload failed: $e');
      }
    }
  }

  static Future<void> stop() async {
    if (!Platform.isIOS) return;
    if (_stopping) return;

    _stopping = true;
    _running = false;
    _pingTimer?.cancel();
    _pingTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _uploader?.stop();
    _uploader = null;
    _lastUploadAt = null;

    try {
      await IosBackgroundLocationNotification.dismiss();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IosDutyLocationPinger] dismiss notification failed: $e');
      }
    }

    if (kDebugMode) {
      debugPrint('[IosDutyLocationPinger] stopped');
    }

    _stopping = false;
  }

  /// Stops GPS collection immediately without waiting for batch flush.
  static Future<void> stopCollectingOnly() async {
    if (!Platform.isIOS) return;
    if (!_running && _subscription == null && _uploader == null) return;

    _running = false;
    _pingTimer?.cancel();
    _pingTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _uploader?.stopCollectingOnly();
    _uploader = null;
    _lastUploadAt = null;

    try {
      await IosBackgroundLocationNotification.dismiss();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[IosDutyLocationPinger] dismiss notification failed: $e',
        );
      }
    }

    if (kDebugMode) {
      debugPrint('[IosDutyLocationPinger] stopped collecting (instant logout)');
    }
  }
}
