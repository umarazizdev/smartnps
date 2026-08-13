import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../duty/duty_status_snapshot.dart';
import 'android_duty_location_health.dart';
import 'background_location_permissions.dart';
import 'background_location_service.dart';
import 'location_sharing_status_notification.dart';
import '../ios/ios_duty_location_pinger.dart';
import '../ios/ios_significant_location_change_service.dart';

class BackgroundLocationController {
  BackgroundLocationController._();

  static Future<Map<String, dynamic>>? _ensureStartedFuture;
  static bool _uiBackgrounded = false;

  static Future<bool> Function()? confirmOnDutyBeforeStart;

  /// True while the Flutter UI is paused/hidden. FGS must self-heal then;
  /// never hard-restart or start a new FGS from the background.
  static bool get isUiBackgrounded => _uiBackgrounded;

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

  /// True when tracking appears up but GPS/ping activity looks stale.
  ///
  /// Android freshness comes from FGS-persisted timestamps (survives UI
  /// background suspend). Stationary may skip batch trail uploads but still
  /// updates this timestamp after each accepted fix/ping.
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
    return !await needsRecovery();
  }

  /// Soft-recover Android GPS without tearing down the FGS.
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

  /// Soft-recover first; hard-restart FGS only while the UI is foregrounded.
  /// Never starts GPS unless [confirmOnDutyBeforeStart] still says on_duty.
  /// Never tears down a live FGS while the UI is backgrounded (OEM GPS
  /// timeouts are common; hard-restart then fails to start a new FGS).
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
      if (_uiBackgrounded) {
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

    if (!await AndroidDutyLocationHealth.computeNeedsRecovery()) {
      return {'ok': true, 'recovered': false, 'running': true};
    }

    if (_uiBackgrounded) {
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

  /// Tell the Android FGS the UI moved to background so it can keep GPS alive.
  static Future<void> notifyAppBackgrounded() async {
    if (!Platform.isAndroid) return;
    _uiBackgrounded = true;
    if (!await FlutterBackgroundService().isRunning()) return;
    // Renew while UI is still awake so FGS starts BG with a fresh TTL.
    try {
      await DutyStatusSnapshot.renewIfStillOnDuty();
    } catch (_) {}
    FlutterBackgroundService().invoke('app_backgrounded');
  }

  /// Tell the Android FGS the UI returned to foreground.
  static Future<void> notifyAppForegrounded() async {
    if (!Platform.isAndroid) return;
    _uiBackgrounded = false;
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
          if (await AndroidDutyLocationHealth.computeNeedsRecovery()) {
            if (_uiBackgrounded) {
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
              // Fall through to start a fresh FGS below.
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
        if (_uiBackgrounded) {
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
      if (Platform.isAndroid && _uiBackgrounded) {
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
