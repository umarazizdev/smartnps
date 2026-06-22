import 'dart:io';

import 'package:flutter_background_service/flutter_background_service.dart';

import 'background_location_permissions.dart';
import 'background_location_service.dart';
import 'ios_duty_location_pinger.dart';

class BackgroundLocationController {
  BackgroundLocationController._();

  static Future<Map<String, dynamic>> ensureStarted() async {
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

      if (Platform.isIOS) {
        await IosDutyLocationPinger.start();
      } else {
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
      final bool running = await service.isRunning();
      if (!running) {
        return {'ok': true, 'stopped': false, 'running': false};
      }
      service.invoke('stop');
      await _waitUntilAndroidServiceStopped();
      final stillRunning = await service.isRunning();
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

  static Future<void> _waitUntilAndroidServiceStopped() async {
    final service = FlutterBackgroundService();
    // Allow time for queued batch uploads to finish during logout teardown.
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      if (!await service.isRunning()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
