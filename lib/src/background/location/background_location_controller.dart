import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'background_location_permissions.dart';
import 'background_location_service.dart';
import '../ios/ios_duty_location_pinger.dart';

class BackgroundLocationController {
  BackgroundLocationController._();

  static Future<Map<String, dynamic>>? _ensureStartedFuture;

  static Future<Map<String, dynamic>> ensureStarted() async {
    final inFlight = _ensureStartedFuture;
    if (inFlight != null) return inFlight;

    final future = _ensureStartedImpl();
    _ensureStartedFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_ensureStartedFuture, future)) {
        _ensureStartedFuture = null;
      }
    }
  }

  static Future<Map<String, dynamic>> _ensureStartedImpl() async {
    try {
      if (Platform.isIOS) {
        if (IosDutyLocationPinger.isRunning &&
            !IosDutyLocationPinger.needsRecovery) {
          return {'ok': true, 'started': false, 'running': true};
        }
        if (IosDutyLocationPinger.isRunning) {
          await IosDutyLocationPinger.stop();
        }
      } else {
        final service = FlutterBackgroundService();
        if (await service.isRunning()) {
          return {'ok': true, 'started': false, 'running': true};
        }
      }

      await BackgroundLocationPermissions.refreshIosLocationPermission();
      final outcome = await BackgroundLocationPermissions.readinessOutcome();
      if (!outcome.granted) {
        return {
          'ok': false,
          'permissions': await BackgroundLocationPermissions.statusSnapshot(),
          'openSettings': outcome.openSettings,
          'deniedReason': outcome.deniedReason,
          'error': {
            'code': 'permission_denied',
            'message': 'Background location permission not granted',
          },
        };
      }

      await BackgroundLocationPermissions.ensureAndroidNotificationForService();

      await SchedulerBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 300));

      if (Platform.isIOS) {
        await IosDutyLocationPinger.start();
      } else {
        if (await FlutterBackgroundService().isRunning()) {
          return {'ok': true, 'started': false, 'running': true};
        }
        await BackgroundLocationService.configureAndStart();
      }

      return {
        'ok': true,
        'started': true,
        'running': true,
        'permissions': await BackgroundLocationPermissions.statusSnapshot(),
      };
    } catch (e) {
      return {
        'ok': false,
        'permissions': await BackgroundLocationPermissions.statusSnapshot(),
        'error': {'code': 'start_failed', 'message': e.toString()},
      };
    }
  }

  static Future<Map<String, dynamic>> restart() async {
    try {
      if (Platform.isIOS) {
        if (IosDutyLocationPinger.isRunning) {
          await IosDutyLocationPinger.stop();
        }
      } else {
        final service = FlutterBackgroundService();
        if (await service.isRunning()) {
          service.invoke('stop');
        }
      }
      return ensureStarted();
    } catch (e) {
      return {
        'ok': false,
        'permissions': await BackgroundLocationPermissions.statusSnapshot(),
        'error': {'code': 'restart_failed', 'message': e.toString()},
      };
    }
  }

  static Future<void> stopCollectingOnly() async {
    try {
      if (Platform.isIOS) {
        await IosDutyLocationPinger.stopCollectingOnly();
        return;
      }

      final service = FlutterBackgroundService();
      if (await service.isRunning()) {
        service.invoke('stop');
      }
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> stop() async {
    try {
      if (Platform.isIOS) {
        final running = IosDutyLocationPinger.isRunning;
        if (!running) {
          return {'ok': true, 'stopped': false, 'running': false};
        }
        await IosDutyLocationPinger.stop();
        return {'ok': true, 'stopped': true, 'running': false};
      }

      final service = FlutterBackgroundService();
      final bool runningBeforeStop = await service.isRunning();

      service.invoke('stop');
      if (runningBeforeStop) {
        await _waitUntilAndroidServiceStopped();
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }

      var stillRunning = await service.isRunning();
      if (stillRunning) {
        service.invoke('stop');
        await _waitUntilAndroidServiceStopped(
          maxWait: const Duration(seconds: 15),
        );
        stillRunning = await service.isRunning();
      }

      return {
        'ok': !stillRunning,
        'stopped': !stillRunning,
        'running': stillRunning,
        if (stillRunning)
          'error': {
            'code': 'stop_timeout',
            'message': 'Background location service did not stop in time',
          },
      };
    } catch (e) {
      return {
        'ok': false,
        'error': {'code': 'stop_failed', 'message': e.toString()},
      };
    }
  }

  static Future<void> _waitUntilAndroidServiceStopped({
    Duration maxWait = const Duration(seconds: 60),
  }) async {
    final service = FlutterBackgroundService();
    final deadline = DateTime.now().add(maxWait);
    while (DateTime.now().isBefore(deadline)) {
      if (!await service.isRunning()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  static Future<bool> isTrackingRunning() async {
    if (Platform.isIOS) {
      return IosDutyLocationPinger.isRunning;
    }
    return FlutterBackgroundService().isRunning();
  }
}
