import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../background/background_location_permissions.dart';
import '../push/push_notification_preferences.dart';
import '../push/push_notification_service.dart';
import '../utilities/overlay_prompt_guard.dart';
import '../utilities/permission_settings_helper.dart';
import 'native_permission_status_service.dart';
import 'os_notification_permission.dart';

/// Action the blocker CTA should take for a permission row.
enum RequiredPermissionAction {
  /// OS can still show a system permission dialog.
  allow,

  /// Must be changed in device Settings.
  openSettings,

  /// In-app preference (not an OS permission).
  enable,

  /// Already satisfied — no CTA.
  none,
}

/// One row on the logged-in required-permissions blocker.
class RequiredPermissionItem {
  const RequiredPermissionItem({
    required this.id,
    required this.name,
    required this.description,
    required this.enabled,
    required this.action,
    required this.icon,
  });

  final String id;
  final String name;
  final String description;
  final bool enabled;
  final RequiredPermissionAction action;
  final IconData icon;

  bool get needsAction => !enabled;
}

/// Tracks OS + in-app permissions required after officer login and drives the
/// full-screen blocker. Refreshes live on resume, after Allow taps, and via a
/// short poll while blocking so Settings toggles appear without delay.
class RequiredPermissionsGate {
  RequiredPermissionsGate._();

  static final RequiredPermissionsGate instance = RequiredPermissionsGate._();

  static const MethodChannel _settingsChannel = MethodChannel(
    'com.smartnps360.app/settings',
  );

  static const Duration _pollWhileBlocking = Duration(milliseconds: 450);

  final ValueNotifier<List<RequiredPermissionItem>> items = ValueNotifier(
    const [],
  );
  final ValueNotifier<bool> isBlocking = ValueNotifier(false);
  final ValueNotifier<bool> isRefreshing = ValueNotifier(false);

  bool _active = false;
  bool _refreshInFlight = false;
  bool _refreshAgain = false;
  Timer? _pollTimer;
  String? _lastFingerprint;
  int _actionSerial = 0;

  /// Start monitoring when the officer is logged in (mobile only).
  void start() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      stop();
      return;
    }
    NativePermissionStatusService.instance.setOnOsPermissionChanged(() {
      unawaited(refresh(force: true));
    });
    PushNotificationService.instance.setOnPushPreferenceChanged(() {
      unawaited(refresh(force: true));
    });
    if (_active) {
      unawaited(refresh(force: true));
      return;
    }
    _active = true;
    unawaited(refresh(force: true));
  }

  void stop() {
    _active = false;
    NativePermissionStatusService.instance.setOnOsPermissionChanged(null);
    PushNotificationService.instance.setOnPushPreferenceChanged(null);
    _pollTimer?.cancel();
    _pollTimer = null;
    _lastFingerprint = null;
    if (items.value.isNotEmpty) {
      items.value = const [];
    }
    if (isBlocking.value) {
      isBlocking.value = false;
    }
  }

  /// Immediate re-read (Settings return, Allow result, lifecycle resume).
  Future<void> refresh({bool force = false}) async {
    if (!_active) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    if (_refreshInFlight) {
      _refreshAgain = true;
      return;
    }

    _refreshInFlight = true;
    if (force || items.value.isEmpty) {
      isRefreshing.value = true;
    }
    try {
      do {
        _refreshAgain = false;
        await BackgroundLocationPermissions.refreshPermissionStateFromOs();
        final next = await _buildItems();
        final fingerprint = _fingerprint(next);
        if (force || fingerprint != _lastFingerprint) {
          _lastFingerprint = fingerprint;
          items.value = next;
          final blocking = next.any((item) => item.needsAction);
          if (isBlocking.value != blocking) {
            isBlocking.value = blocking;
          }
          _syncPollTimer(blocking);
          if (kDebugMode) {
            debugPrint(
              '[RequiredPermissionsGate] refresh blocking=$blocking '
              'missing=${next.where((e) => e.needsAction).map((e) => e.id).join(',')}',
            );
          }
        }
      } while (_refreshAgain);
    } finally {
      _refreshInFlight = false;
      isRefreshing.value = false;
    }
  }

  void _syncPollTimer(bool blocking) {
    if (!blocking || !_active) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(_pollWhileBlocking, (_) {
      unawaited(refresh());
    });
  }

  Future<void> handleAction(RequiredPermissionItem item) async {
    if (item.action == RequiredPermissionAction.none || item.enabled) {
      return;
    }

    final serial = ++_actionSerial;
    try {
      switch (item.action) {
        case RequiredPermissionAction.allow:
          await _requestOsPermission(item.id);
        case RequiredPermissionAction.openSettings:
          await _openSettingsFor(item.id);
        case RequiredPermissionAction.enable:
          await _enableInApp(item.id);
        case RequiredPermissionAction.none:
          break;
      }
    } finally {
      if (serial == _actionSerial) {
        await refresh(force: true);
        unawaited(
          NativePermissionStatusService.instance.ensureLatestPermissionsSynced(),
        );
      }
    }
  }

  Future<void> _requestOsPermission(String id) async {
    switch (id) {
      case 'foregroundLocation':
        await PermissionSettingsHelper.requestForegroundLocationStep();
      case 'notifications':
        if (Platform.isAndroid) {
          await OverlayPromptGuard.runDuringOsPermissionPrompt(
            Permission.notification.request,
          );
        } else if (Platform.isIOS) {
          await OverlayPromptGuard.runDuringOsPermissionPrompt(() async {
            final messaging = FirebaseMessaging.instance;
            await messaging.requestPermission(
              alert: true,
              badge: true,
              sound: true,
              provisional: false,
            );
          });
        }
      case 'batteryOptimization':
        if (Platform.isAndroid) {
          await OverlayPromptGuard.runDuringOsPermissionPrompt(
            Permission.ignoreBatteryOptimizations.request,
          );
        }
      default:
        break;
    }
  }

  Future<void> _openSettingsFor(String id) async {
    final destination = switch (id) {
      'foregroundLocation' ||
      'backgroundLocation' ||
      'preciseLocation' =>
        StoreSafeSettingsDestination.locationPermission,
      'locationServices' => StoreSafeSettingsDestination.systemLocationServices,
      _ => StoreSafeSettingsDestination.app,
    };

    await PermissionSettingsHelper.openSettingsForUserTap(
      destination: destination,
      waitForReturn: true,
    );
  }

  Future<void> _enableInApp(String id) async {
    if (id != 'push') return;
    await PushNotificationService.instance.setNotificationsEnabled(true);
  }

  Future<List<RequiredPermissionItem>> _buildItems() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    final foreground = await _foregroundGranted(serviceEnabled);
    final background = await _backgroundGranted(serviceEnabled);
    final precise = await _preciseGranted(serviceEnabled, foreground);
    final notifications = await OsNotificationPermission.isGranted();
    final pushEnabled = await PushNotificationPreferences.readEnabled();

    final list = <RequiredPermissionItem>[
      if (!serviceEnabled)
        RequiredPermissionItem(
          id: 'locationServices',
          name: 'Location Services',
          description: 'Turn on device location to continue.',
          enabled: false,
          action: RequiredPermissionAction.openSettings,
          icon: Icons.location_off_rounded,
        ),
      RequiredPermissionItem(
        id: 'foregroundLocation',
        name: 'Location',
        description: 'Needed while using the app.',
        enabled: foreground,
        action: foreground
            ? RequiredPermissionAction.none
            : await _foregroundAction(),
        icon: Icons.location_on_rounded,
      ),
      RequiredPermissionItem(
        id: 'backgroundLocation',
        name: Platform.isAndroid ? 'All-the-time location' : 'Always location',
        description: 'Continues when the app is in the background.',
        enabled: background,
        action: background
            ? RequiredPermissionAction.none
            : RequiredPermissionAction.openSettings,
        icon: Icons.share_location_rounded,
      ),
      RequiredPermissionItem(
        id: 'preciseLocation',
        name: 'Precise location',
        description: 'Exact position for check-ins.',
        enabled: precise,
        action: precise
            ? RequiredPermissionAction.none
            : RequiredPermissionAction.openSettings,
        icon: Icons.gps_fixed_rounded,
      ),
      RequiredPermissionItem(
        id: 'notifications',
        name: 'Notifications',
        description: 'Shift alerts and updates.',
        enabled: notifications,
        action: notifications
            ? RequiredPermissionAction.none
            : await _notificationAction(),
        icon: Icons.notifications_rounded,
      ),
      RequiredPermissionItem(
        id: 'push',
        name: 'Push alerts',
        description: 'In-app push messages.',
        enabled: pushEnabled,
        action: pushEnabled
            ? RequiredPermissionAction.none
            : RequiredPermissionAction.enable,
        icon: Icons.send_rounded,
      ),
    ];

    if (Platform.isAndroid) {
      final batteryOk = await _batteryOptimizationGranted();
      list.add(
        RequiredPermissionItem(
          id: 'batteryOptimization',
          name: 'Battery unrestricted',
          description: 'Stops the OS from pausing the app.',
          enabled: batteryOk,
          action: batteryOk
              ? RequiredPermissionAction.none
              : await _batteryAction(),
          icon: Icons.battery_charging_full_rounded,
        ),
      );
    }

    final barOk = await _backgroundAppRefreshEnabled();
    list.add(
      RequiredPermissionItem(
        id: 'backgroundAppRefresh',
        name: Platform.isIOS ? 'Background App Refresh' : 'Background activity',
        description: Platform.isIOS
            ? 'Allows background updates.'
            : 'Turn off battery restrictions for this app.',
        enabled: barOk,
        action: barOk
            ? RequiredPermissionAction.none
            : RequiredPermissionAction.openSettings,
        icon: Icons.sync_rounded,
      ),
    );

    return list;
  }

  Future<bool> _foregroundGranted(bool serviceEnabled) async {
    if (!serviceEnabled) return false;
    if (Platform.isAndroid && await _isAndroidOneTimeLocation()) {
      return false;
    }
    return BackgroundLocationPermissions.hasForegroundLocationAccess();
  }

  Future<bool> _backgroundGranted(bool serviceEnabled) async {
    if (!serviceEnabled) return false;
    return BackgroundLocationPermissions.isClockInBackgroundReady();
  }

  Future<bool> _preciseGranted(bool serviceEnabled, bool foreground) async {
    if (!serviceEnabled || !foreground) return false;
    if (Platform.isAndroid && await _isAndroidOneTimeLocation()) {
      return false;
    }
    return BackgroundLocationPermissions.hasPreciseLocationAccess();
  }

  Future<RequiredPermissionAction> _foregroundAction() async {
    if (await PermissionSettingsHelper.foregroundRequiresSettingsPrompt()) {
      return RequiredPermissionAction.openSettings;
    }
    return RequiredPermissionAction.allow;
  }

  Future<RequiredPermissionAction> _notificationAction() async {
    if (Platform.isAndroid) {
      if (!await OsNotificationPermission.androidRequiresRuntimePermission()) {
        return RequiredPermissionAction.none;
      }
      final status = await Permission.notification.status;
      if (PermissionSettingsHelper.shouldOpenSettings(status)) {
        return RequiredPermissionAction.openSettings;
      }
      return RequiredPermissionAction.allow;
    }
    if (Platform.isIOS) {
      final status = await OsNotificationPermission.permissionApiStatus();
      if (status == 'denied') {
        return RequiredPermissionAction.openSettings;
      }
      return RequiredPermissionAction.allow;
    }
    return RequiredPermissionAction.openSettings;
  }

  Future<RequiredPermissionAction> _batteryAction() async {
    // Status is read via the native channel (not permission_handler.status) so
    // the 450ms blocker poll does not spam "No permissions found in manifest".
    // Allow still uses Permission.ignoreBatteryOptimizations.request() on tap.
    if (await _batteryOptimizationGranted()) {
      return RequiredPermissionAction.none;
    }
    return RequiredPermissionAction.allow;
  }

  Future<bool> _batteryOptimizationGranted() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await _settingsChannel.invokeMethod<String>(
        'batteryOptimizationStatus',
      );
      if (status == 'granted') return true;
      if (status == 'unknown' || status == 'denied') return false;
    } catch (_) {}
    try {
      final ignoring = await _settingsChannel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      if (ignoring != null) return ignoring;
    } catch (_) {}
    // Unknown native result — do not block or hit permission_handler.status.
    return true;
  }

  Future<bool> _backgroundAppRefreshEnabled() async {
    try {
      final status = await _settingsChannel.invokeMethod<String>(
        'backgroundAppRefreshStatus',
      );
      if (status == 'enabled') return true;
      if (status == 'disabled' || status == 'restricted') return false;
    } catch (_) {}
    // Unknown / older builds — do not block.
    return true;
  }

  Future<bool> _isAndroidOneTimeLocation() async {
    if (!Platform.isAndroid) return false;
    try {
      final oneTime = await _settingsChannel.invokeMethod<bool>(
        'hasOneTimeLocationPermission',
      );
      return oneTime == true;
    } catch (_) {
      return false;
    }
  }

  String _fingerprint(List<RequiredPermissionItem> next) {
    return next
        .map((e) => '${e.id}:${e.enabled ? 1 : 0}:${e.action.name}')
        .join('|');
  }
}
