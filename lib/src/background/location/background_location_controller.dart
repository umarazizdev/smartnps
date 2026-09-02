import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../duty/clock_in_engine_warm_snapshot.dart';
import '../duty/duty_status_snapshot.dart';
import 'android_duty_location_health.dart';
import 'background_location_permissions.dart';
import 'background_location_service.dart';
import 'location_sharing_status_notification.dart';
import '../ios/ios_duty_location_pinger.dart';
import '../ios/ios_significant_location_change_service.dart';
import '../../utilities/app_debug_log.dart';

class BackgroundLocationController {
  BackgroundLocationController._();

  static Future<Map<String, dynamic>>? _ensureStartedFuture;
  static bool _uiBackgrounded = false;

  static Future<bool> Function()? confirmOnDutyBeforeStart;

  static bool get isUiBackgrounded {
    if (_uiBackgrounded) return true;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == AppLifecycleState.inactive ||
        lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.hidden;
  }

  static void _log(String message) {
    locationDebugLog('[DutyLocation] $message');
  }

  static Future<Map<String, dynamic>?> _tryActivateAndroidWarmEngine() async {
    if (!Platform.isAndroid) return null;
    if (!await FlutterBackgroundService().isRunning()) return null;
    if (!await ClockInEngineWarmSnapshot.isValidPending()) return null;

    _log('Android FGS warm engine ready → activating GPS tracking');
    await BackgroundLocationService.activateFromClockInWarm();
    unawaited(
      LocationSharingStatusNotification.showBgLocationStartedTestAlert()
          .catchError((Object e) {
        _log('bg start test alert failed: $e');
      }),
    );
    return {
      'ok': true,
      'started': true,
      'running': true,
      'warmActivated': true,
    };
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

  static Future<bool> needsRecovery() async {
    if (Platform.isIOS) {
      return IosDutyLocationPinger.needsRecovery;
    }
    if (!Platform.isAndroid) return false;
    if (!await FlutterBackgroundService().isRunning()) return false;
    AndroidDutyLocationHealth.ensureListenerInstalled();
    return AndroidDutyLocationHealth.computeNeedsRecovery();
  }

  static Future<bool> isTrackingHealthy() async {
    if (!await isTrackingRunning()) return false;
    if (Platform.isAndroid && await ClockInEngineWarmSnapshot.isValidPending()) {
      return false;
    }
    return !await needsRecovery();
  }

  static Future<void> softRecoverAndroidTracking({
    bool force = false,
    bool countTowardHardRestart = true,
  }) async {
    if (!Platform.isAndroid) return;
    if (!await FlutterBackgroundService().isRunning()) return;
    if (!force && !await AndroidDutyLocationHealth.computeNeedsRecovery()) {
      return;
    }
    if (countTowardHardRestart) {
      AndroidDutyLocationHealth.noteSoftRecoverAttempted();
    }
    _log(
      'Android FGS soft-recover: force poll '
      '(attempt=${AndroidDutyLocationHealth.softRecoverAttempts})',
    );
    FlutterBackgroundService().invoke('rebuild_stream');
  }

  static Future<Map<String, dynamic>> recoverAndroidTrackingIfNeeded() async {
    if (!Platform.isAndroid) {
      return {'ok': true, 'recovered': false};
    }
    AndroidDutyLocationHealth.ensureListenerInstalled();

    if (!await _confirmOnDutyOrBlock()) {
      if (await FlutterBackgroundService().isRunning()) {
        await stop();
      }
      return {
        'ok': false,
        'recovered': false,
        'running': false,
        'error': {
          'code': 'duty_not_confirmed',
          'message': 'Background location blocked; heartbeat is not on_duty',
        },
      };
    }

    if (!await FlutterBackgroundService().isRunning()) {
      if (isUiBackgrounded) {
        _log('SKIP start; UI is backgrounded (no new FGS from background)');
        return {
          'ok': false,
          'recovered': false,
          'running': false,
          'skipped': true,
        };
      }
      return ensureStarted();
    }

    final warmActivated = await _tryActivateAndroidWarmEngine();
    if (warmActivated != null) {
      return {...warmActivated, 'recovered': true};
    }

    if (!await AndroidDutyLocationHealth.computeNeedsRecovery()) {
      return {'ok': true, 'recovered': false, 'running': true};
    }

    if (isUiBackgrounded) {
      _log('UI backgrounded — keep FGS, soft-recover only (no hard-restart)');
      await softRecoverAndroidTracking(
        force: true,
        countTowardHardRestart: false,
      );
      return {
        'ok': true,
        'recovered': true,
        'soft': true,
        'running': true,
        'deferredHardRestart': true,
      };
    }

    if (AndroidDutyLocationHealth.shouldHardRestart) {
      _log('Android FGS hard-restart after soft recover failures');
      AndroidDutyLocationHealth.resetRecoverAttempts();
      final result = await restart();
      return {
        ...result,
        'recovered': result['ok'] == true,
        'hardRestart': true,
      };
    }

    await softRecoverAndroidTracking(force: true);
    return {
      'ok': true,
      'recovered': true,
      'soft': true,
      'running': true,
      'softAttempt': AndroidDutyLocationHealth.softRecoverAttempts,
    };
  }

  static Future<void> notifyAppBackgrounded() async {
    _uiBackgrounded = true;
    if (!Platform.isAndroid) return;
    if (!await FlutterBackgroundService().isRunning()) return;
    try {
      await DutyStatusSnapshot.renewIfStillOnDuty();
    } catch (_) {}
    FlutterBackgroundService().invoke('app_backgrounded');
  }

  static Future<void> notifyAppForegrounded() async {
    _uiBackgrounded = false;
    if (!Platform.isAndroid) return;
    if (!await FlutterBackgroundService().isRunning()) return;
    FlutterBackgroundService().invoke('app_foregrounded');
  }

  static Future<void> _yieldForStartIfForeground({bool skip = false}) async {
    if (skip) {
      _log('clock-in fast start: skipping UI yield');
      return;
    }
    if (isUiBackgrounded) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return;
    }
    try {
      await SchedulerBinding.instance.endOfFrame.timeout(
        const Duration(milliseconds: 800),
      );
    } on TimeoutException {
      _log('endOfFrame timed out; continuing GPS start');
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  static Future<Map<String, dynamic>> ensureStarted({
    bool clockInFastStart = false,
  }) async {
    final inFlight = _ensureStartedFuture;
    if (inFlight != null) return inFlight;

    final future = _ensureStartedImpl(clockInFastStart: clockInFastStart);
    _ensureStartedFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_ensureStartedFuture, future)) {
        _ensureStartedFuture = null;
      }
    }
  }

  static Future<Map<String, dynamic>> _ensureStartedImpl({
    bool clockInFastStart = false,
  }) async {
    try {
      if (Platform.isIOS) {
        if (IosDutyLocationPinger.isRunning) {
          if (IosDutyLocationPinger.needsRecovery) {
            _log('iOS stream subscription missing; resubscribe in place');
            await IosDutyLocationPinger.rebuildForCurrentPermission(
              reason: 'subscription_missing',
            );
          } else {
            _log('RUNNING already (iOS pinger active)');
          }
          return {'ok': true, 'started': false, 'running': true};
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

          final warmActivated = await _tryActivateAndroidWarmEngine();
          if (warmActivated != null) {
            return warmActivated;
          }

          if (await AndroidDutyLocationHealth.computeNeedsRecovery()) {
            if (isUiBackgrounded) {
              await softRecoverAndroidTracking(
                force: true,
                countTowardHardRestart: false,
              );
              _log('Android FGS kept (UI backgrounded; no hard-restart)');
              return {
                'ok': true,
                'started': false,
                'running': true,
                'softRecovered': true,
                'deferredHardRestart': true,
              };
            }
            if (AndroidDutyLocationHealth.shouldHardRestart) {
              _log(
                'Android FGS hard-restart after soft recover failures '
                '(ensureStarted)',
              );
              AndroidDutyLocationHealth.resetRecoverAttempts();
              service.invoke('stop');
              await _waitUntilAndroidServiceStopped(
                maxWait: const Duration(seconds: 15),
              );
              AndroidDutyLocationHealth.markStopped();
            } else {
              await softRecoverAndroidTracking(force: true);
              _log('Android FGS soft-recovered (ensureStarted)');
              return {
                'ok': true,
                'started': false,
                'running': true,
                'softRecovered': true,
              };
            }
          } else if (await FlutterBackgroundService().isRunning()) {
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

      await _yieldForStartIfForeground(skip: clockInFastStart);

      await LocationSharingStatusNotification.clearStopped().catchError((
        Object e,
      ) {
        _log('clearStopped failed: $e');
      });

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
            'permissions': await BackgroundLocationPermissions.statusSnapshot(),
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
          final warmActivated = await _tryActivateAndroidWarmEngine();
          if (warmActivated != null) {
            return warmActivated;
          }
          _log('RUNNING already (Android background service active)');
          return {'ok': true, 'started': false, 'running': true};
        }
        if (isUiBackgrounded) {
          _log('SKIP start; UI is backgrounded (no new FGS from background)');
          return {
            'ok': false,
            'started': false,
            'running': false,
            'skipped': true,
            'error': {
              'code': 'backgrounded',
              'message':
                  'Android background location start deferred until foreground',
            },
          };
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
        unawaited(
          LocationSharingStatusNotification.showBgLocationStartedTestAlert()
              .catchError((Object e) {
            _log('bg start test alert failed: $e');
          }),
        );
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
      if (Platform.isAndroid && isUiBackgrounded) {
        _log('SKIP hard-restart; UI is backgrounded (keep live FGS)');
        if (await FlutterBackgroundService().isRunning()) {
          await softRecoverAndroidTracking(
            force: true,
            countTowardHardRestart: false,
          );
          return {
            'ok': true,
            'skipped': true,
            'running': true,
            'deferredHardRestart': true,
          };
        }
        return {'ok': false, 'skipped': true, 'running': false};
      }
      if (Platform.isIOS && isUiBackgrounded) {
        if (IosDutyLocationPinger.isRunning) {
          _log('SKIP hard-restart; UI is backgrounded (keep live iOS stream)');
          await IosDutyLocationPinger.rebuildForCurrentPermission(
            reason: 'permission_while_backgrounded',
          );
          return {
            'ok': true,
            'skipped': true,
            'running': true,
            'softRebuilt': true,
            'deferredHardRestart': true,
          };
        }
        _log(
          'iOS tracking stopped while UI backgrounded; starting without hard-stop',
        );
        return ensureStarted();
      }
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
      await BackgroundLocationService.cancelClockInWarm();
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
