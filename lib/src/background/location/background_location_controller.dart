import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'android_duty_location_health.dart';
import 'background_location_permissions.dart';
import 'background_location_service.dart';
import 'location_sharing_status_notification.dart';
import '../ios/ios_duty_location_pinger.dart';
import '../ios/ios_significant_location_change_service.dart';

class BackgroundLocationController {
  BackgroundLocationController._();

  static Future<Map<String, dynamic>>? _ensureStartedFuture;

  static Future<bool> Function()? confirmOnDutyBeforeStart;

  static void _log(String message) {
    if (kDebugMode) {
      debugPrint('[DutyLocation] $message');
    }
  }

  static Future<bool> _confirmOnDutyOrBlock() async {
    final confirm = confirmOnDutyBeforeStart;
    if (confirm == null) {
      _log('BLOCKED: no duty confirmation hook');
      return false;
    }
    final allowed = await confirm();
    if (!allowed) {
      _log('BLOCKED: duty not confirmed (not on_duty)');
    }
    return allowed;
  }

  /// True when tracking appears up but uploads/stream look stale.
  ///
  /// Android: if the FGS process is running, the UI isolate must NOT treat
  /// missing upload events as stale. Backgrounding the app pauses the UI
  /// isolate; false "stale" recovery was canceling the live GPS stream.
  /// Stream health is owned by the FGS isolate itself.
  static Future<bool> needsRecovery() async {
    if (Platform.isIOS) {
      return IosDutyLocationPinger.needsRecovery;
    }
    if (!Platform.isAndroid) return false;
    // FGS alive ⇒ healthy from the UI/heartbeat perspective.
    return false;
  }

  static Future<bool> isTrackingHealthy() async {
    if (!await isTrackingRunning()) return false;
    if (Platform.isAndroid) return true;
    return !await needsRecovery();
  }

  /// Soft-recover Android GPS without tearing down the FGS.
  /// Prefer not calling this from heartbeat while backgrounded — FGS self-heals.
  static Future<void> softRecoverAndroidTracking() async {
    if (!Platform.isAndroid) return;
    if (!await FlutterBackgroundService().isRunning()) return;
    if (!await AndroidDutyLocationHealth.computeNeedsRecovery()) return;
    _log('Android FGS soft-recover: force poll (no stop)');
    FlutterBackgroundService().invoke('rebuild_stream');
  }

  /// Tell the Android FGS the UI moved to background so it can keep GPS alive.
  static Future<void> notifyAppBackgrounded() async {
    if (!Platform.isAndroid) return;
    if (!await FlutterBackgroundService().isRunning()) return;
    FlutterBackgroundService().invoke('app_backgrounded');
  }

  /// Tell the Android FGS the UI returned to foreground.
  static Future<void> notifyAppForegrounded() async {
    if (!Platform.isAndroid) return;
    if (!await FlutterBackgroundService().isRunning()) return;
    FlutterBackgroundService().invoke('app_foregrounded');
  }

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
          if (!await _confirmOnDutyOrBlock()) {
            return {
              'ok': false,
              'started': false,
              'running': false,
              'error': {
                'code': 'duty_not_confirmed',
                'message':
                    'Background location blocked; heartbeat is not on_duty',
              },
            };
          }
          _log('RUNNING already (iOS pinger active)');
          return {'ok': true, 'started': false, 'running': true};
        }
        if (IosDutyLocationPinger.isRunning) {
          await IosDutyLocationPinger.stop();
        }
      } else if (Platform.isAndroid) {
        AndroidDutyLocationHealth.ensureListenerInstalled();
        final service = FlutterBackgroundService();
        if (await service.isRunning()) {
          if (!await _confirmOnDutyOrBlock()) {
            _log('STOPPING Android service; duty not confirmed');
            await stop();
            return {
              'ok': false,
              'started': false,
              'running': false,
              'error': {
                'code': 'duty_not_confirmed',
                'message':
                    'Background location blocked; heartbeat is not on_duty',
              },
            };
          }
          if (await FlutterBackgroundService().isRunning()) {
            _log('RUNNING already (Android background service active)');
            return {'ok': true, 'started': false, 'running': true};
          }
        }
      }

      if (!await _confirmOnDutyOrBlock()) {
        return {
          'ok': false,
          'started': false,
          'running': false,
          'error': {
            'code': 'duty_not_confirmed',
            'message':
                'Background location start blocked until heartbeat confirms on_duty',
          },
        };
      }

      await BackgroundLocationPermissions.refreshIosLocationPermission();
      final outcome = await BackgroundLocationPermissions.readinessOutcome();
      if (!outcome.granted) {
        _log('BLOCKED start: permission not granted (${outcome.deniedReason})');
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

      await LocationSharingStatusNotification.clearStopped().catchError(
        (Object e) {
          _log('clearStopped failed: $e');
        },
      );

      if (Platform.isIOS) {
        _log('starting iOS duty location pinger…');
        final previousConfirm = IosDutyLocationPinger.confirmOnDutyBeforeStart;
        IosDutyLocationPinger.confirmOnDutyBeforeStart = () async => true;
        try {
          await IosDutyLocationPinger.start();
        } finally {
          IosDutyLocationPinger.confirmOnDutyBeforeStart = previousConfirm;
        }
        final running = IosDutyLocationPinger.isRunning;
        if (!running) {
          _log('NOT RUNNING: iOS start blocked (duty not confirmed)');
          return {
            'ok': false,
            'started': false,
            'running': false,
            'permissions':
                await BackgroundLocationPermissions.statusSnapshot(),
            'error': {
              'code': 'duty_not_confirmed',
              'message':
                  'Background location start blocked until heartbeat confirms on_duty',
            },
          };
        }
        _log('RUNNING now (iOS pinger started)');
      } else {
        if (await FlutterBackgroundService().isRunning()) {
          _log('RUNNING already (Android background service active)');
          return {'ok': true, 'started': false, 'running': true};
        }
        _log('starting Android background location service…');
        AndroidDutyLocationHealth.markStarted();
        await AndroidDutyLocationHealth.persistStarted(DateTime.now());
        await BackgroundLocationService.configureAndStart();
        final running = await FlutterBackgroundService().isRunning();
        if (!running) {
          AndroidDutyLocationHealth.markStopped();
          _log('NOT RUNNING: Android service failed to start');
          return {
            'ok': false,
            'started': false,
            'running': false,
            'error': {
              'code': 'start_failed',
              'message': 'Android background location service failed to start',
            },
          };
        }
        _log('RUNNING now (Android background service started)');
      }

      return {
        'ok': true,
        'started': true,
        'running': true,
        'permissions': await BackgroundLocationPermissions.statusSnapshot(),
      };
    } catch (e) {
      _log('START FAILED: $e');
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
          await _waitUntilAndroidServiceStopped(
            maxWait: const Duration(seconds: 15),
          );
        }
        AndroidDutyLocationHealth.markStopped();
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
        _log('STOPPING Android collecting-only…');
        service.invoke('stop');
        await _waitUntilAndroidServiceStopped(
          maxWait: const Duration(seconds: 15),
        );
      }
      AndroidDutyLocationHealth.markStopped();
    } catch (_) {
      AndroidDutyLocationHealth.markStopped();
    }
  }

  static Future<Map<String, dynamic>> stop() async {
    try {
      if (Platform.isIOS) {
        final running = IosDutyLocationPinger.isRunning;
        if (!running) {
          await IosSignificantLocationChangeService.setOnDuty(false);
          _log('STOP skipped: iOS location was not running');
          return {'ok': true, 'stopped': false, 'running': false};
        }
        _log('STOPPING iOS duty location…');
        await IosDutyLocationPinger.stop();
        _log('STOPPED (iOS location not running)');
        return {'ok': true, 'stopped': true, 'running': false};
      }

      final service = FlutterBackgroundService();
      final bool runningBeforeStop = await service.isRunning();
      if (!runningBeforeStop) {
        _log('STOP skipped: Android location was not running');
      } else {
        _log('STOPPING Android background location…');
      }

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

      AndroidDutyLocationHealth.markStopped();

      if (stillRunning) {
        _log('STOP FAILED: Android service still running');
      } else if (runningBeforeStop) {
        _log('STOPPED (Android location not running)');
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
      AndroidDutyLocationHealth.markStopped();
      _log('STOP FAILED: $e');
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
