import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../background/location/background_location_permissions.dart';
import '../motion/motion_activity_service.dart';
import '../push/notifications/push_notification_preferences.dart';
import '../push/notifications/push_notification_service.dart';
import '../utilities/overlay_prompt_guard.dart';
import '../utilities/permission_settings_helper.dart';
import '../widgets/dialogs/motion_activity_settings_dialog.dart';
import 'native_permission_status_service.dart';
import 'os_notification_permission.dart';

enum RequiredPermissionAction { allow, openSettings, enable, none }

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

  bool get suppressesCompetingDialogs => isBlocking.value || isRefreshing.value;

  static bool Function()? privacyNoticeVisibleChecker;

  static bool get isPrivacyNoticeVisible =>
      privacyNoticeVisibleChecker?.call() ?? false;

  static bool get shouldSuppressCompetingDialogs =>
      instance.suppressesCompetingDialogs || isPrivacyNoticeVisible;

  bool _active = false;
  bool _refreshInFlight = false;
  bool _refreshAgain = false;
  bool _autoOsPromptInFlight = false;
  Timer? _pollTimer;
  String? _lastFingerprint;
  int _actionSerial = 0;

  static const Set<String> clockInPermissionIds = {
    'locationServices',
    'foregroundLocation',
    'backgroundLocation',
    'preciseLocation',
    'motionActivity',
  };

  static const Set<String> onDutyPermissionIds = {
    ...clockInPermissionIds,
    'backgroundAppRefresh',
    'notifications',
    'push',
  };

  static const Set<String> offDutyPushPermissionIds = {
    'notifications',
    'push',
  };

  Future<List<RequiredPermissionItem>> buildClockInPermissionItems() async {
    await BackgroundLocationPermissions.refreshPermissionStateFromOs();
    final all = await _buildItems();
    return _sortMissingFirst(
      all
          .where((item) => clockInPermissionIds.contains(item.id))
          .toList(growable: false),
    );
  }

  Future<List<RequiredPermissionItem>> missingClockInPermissionItems() async {
    final items = await buildClockInPermissionItems();
    return items.where((item) => item.needsAction).toList(growable: false);
  }

  Future<bool> areClockInPermissionsReady() async {
    final missing = await missingClockInPermissionItems();
    return missing.isEmpty;
  }

  Future<List<RequiredPermissionItem>> buildOnDutyPermissionItems() async {
    await BackgroundLocationPermissions.refreshPermissionStateFromOs();
    final all = await _buildItems();
    return _sortMissingFirst(
      all
          .where((item) => onDutyPermissionIds.contains(item.id))
          .toList(growable: false),
    );
  }

  Future<List<RequiredPermissionItem>> missingOnDutyPermissionItems() async {
    final items = await buildOnDutyPermissionItems();
    return items.where((item) => item.needsAction).toList(growable: false);
  }

  Future<bool> areOnDutyPermissionsReady() async {
    final missing = await missingOnDutyPermissionItems();
    return missing.isEmpty;
  }

  Future<List<RequiredPermissionItem>> buildOffDutyPushPermissionItems() async {
    final all = await _buildItems();
    return _sortMissingFirst(
      all
          .where((item) => offDutyPushPermissionIds.contains(item.id))
          .toList(growable: false),
    );
  }

  Future<List<RequiredPermissionItem>> missingOffDutyPushPermissionItems() async {
    final items = await buildOffDutyPushPermissionItems();
    return items.where((item) => item.needsAction).toList(growable: false);
  }

  Future<bool> areOffDutyPushPermissionsReady() async {
    final missing = await missingOffDutyPushPermissionItems();
    return missing.isEmpty;
  }

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
        final next = _sortMissingFirst(await _buildItems());
        final fingerprint = _fingerprint(next);
        if (force || fingerprint != _lastFingerprint) {
          _lastFingerprint = fingerprint;
          items.value = next;
          const blocking = false;
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

          unawaited(
            NativePermissionStatusService.instance
                .ensureLatestPermissionsSynced(),
          );
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
          break;
        case RequiredPermissionAction.openSettings:
          await _openSettingsFor(item.id);
          break;
        case RequiredPermissionAction.enable:
          await _enableInApp(item.id);
          break;
        case RequiredPermissionAction.none:
          break;
      }
    } finally {
      if (serial == _actionSerial) {
        await refresh(force: true);
        unawaited(
          NativePermissionStatusService.instance
              .ensureLatestPermissionsSynced(),
        );
      }
    }
  }

  Future<void> requestPendingAllowPermissionsAutomatically() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (!_active || _autoOsPromptInFlight || isPrivacyNoticeVisible) return;

    _autoOsPromptInFlight = true;
    try {
      await refresh(force: true);
      if (!_active || isPrivacyNoticeVisible) return;

      const promptOrder = <String>['notifications'];
      final pending =
          items.value
              .where(
                (item) =>
                    !item.enabled &&
                    item.action == RequiredPermissionAction.allow &&
                    promptOrder.contains(item.id),
              )
              .toList();

      for (final item in pending) {
        if (!_active || isPrivacyNoticeVisible) return;
        if (kDebugMode) {
          debugPrint('[RequiredPermissionsGate] auto OS prompt id=${item.id}');
        }
        await handleAction(item);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }

      final enableItems = items.value
          .where(
            (item) =>
                !item.enabled &&
                item.action == RequiredPermissionAction.enable &&
                item.id == 'push',
          )
          .toList();
      for (final item in enableItems) {
        if (!_active || isPrivacyNoticeVisible) return;
        await handleAction(item);
      }
    } finally {
      _autoOsPromptInFlight = false;
    }
  }

  Future<void> _requestOsPermission(String id) async {
    switch (id) {
      case 'foregroundLocation':
        await PermissionSettingsHelper.requestForegroundLocationStep();
        break;
      case 'backgroundLocation':
        await _requestBackgroundLocationStep();
        break;
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
        break;
      case 'motionActivity':
        await _requestMotionPermissionAndGuideIfDenied();
        break;
      default:
        break;
    }
  }

  Future<void> _requestBackgroundLocationStep() async {
    if (Platform.isIOS) {
      var permission = await Geolocator.checkPermission();
      if (kDebugMode) {
        debugPrint(
          '[RequiredPermissionsGate] backgroundLocation iOS before=$permission',
        );
      }
      if (permission == LocationPermission.denied) {
        permission = await OverlayPromptGuard.runDuringOsPermissionPrompt(
          Geolocator.requestPermission,
        );
        if (kDebugMode) {
          debugPrint(
            '[RequiredPermissionsGate] backgroundLocation iOS after whenInUse '
            'request=$permission',
          );
        }
      }
      if (permission == LocationPermission.always) return;

      if (permission == LocationPermission.whileInUse) {
        final alwaysStatus =
            await OverlayPromptGuard.runDuringOsPermissionPrompt(
              Permission.locationAlways.request,
            );
        await BackgroundLocationPermissions.refreshPermissionStateFromOs();
        permission = await Geolocator.checkPermission();
        if (kDebugMode) {
          debugPrint(
            '[RequiredPermissionsGate] backgroundLocation iOS '
            'locationAlways=$alwaysStatus geolocator=$permission',
          );
        }
        if (permission == LocationPermission.always ||
            alwaysStatus.isGranted ||
            alwaysStatus.isLimited) {
          return;
        }
      }

      if (kDebugMode) {
        debugPrint(
          '[RequiredPermissionsGate] backgroundLocation iOS opening Settings '
          '(still=$permission)',
        );
      }
      await PermissionSettingsHelper.openSettingsForUserTap(
        destination: StoreSafeSettingsDestination.locationPermission,
        waitForReturn: true,
      );
      return;
    }

    if (Platform.isAndroid) {
      final fg = await Permission.location.status;
      if (!fg.isGranted && !fg.isLimited && !fg.isProvisional) {
        await PermissionSettingsHelper.requestForegroundLocationStep();
      }
      final bgBefore = await Permission.locationAlways.status;
      if (kDebugMode) {
        debugPrint(
          '[RequiredPermissionsGate] backgroundLocation Android before=$bgBefore',
        );
      }
      if (bgBefore.isGranted || bgBefore.isLimited || bgBefore.isProvisional) {
        return;
      }
      if (!bgBefore.isPermanentlyDenied && !bgBefore.isRestricted) {
        final bg = await OverlayPromptGuard.runDuringOsPermissionPrompt(
          Permission.locationAlways.request,
        );
        if (kDebugMode) {
          debugPrint(
            '[RequiredPermissionsGate] backgroundLocation Android after=$bg',
          );
        }
        if (bg.isGranted || bg.isLimited || bg.isProvisional) return;
      }
      await PermissionSettingsHelper.openSettingsForUserTap(
        destination: StoreSafeSettingsDestination.locationPermission,
        waitForReturn: true,
      );
    }
  }

  Future<RequiredPermissionAction> _backgroundLocationAction() async {
    if (Platform.isIOS) {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        return RequiredPermissionAction.allow;
      }
      if (permission == LocationPermission.whileInUse) {
        final alwaysStatus = await Permission.locationAlways.status;
        if (alwaysStatus.isPermanentlyDenied || alwaysStatus.isRestricted) {
          return RequiredPermissionAction.openSettings;
        }
        return RequiredPermissionAction.allow;
      }
      return RequiredPermissionAction.openSettings;
    }
    if (Platform.isAndroid) {
      final bg = await Permission.locationAlways.status;
      if (bg.isPermanentlyDenied || bg.isRestricted) {
        return RequiredPermissionAction.openSettings;
      }
      return RequiredPermissionAction.allow;
    }
    return RequiredPermissionAction.openSettings;
  }

  Future<void> _requestMotionPermissionAndGuideIfDenied() async {
    var denied = false;

    if (Platform.isAndroid) {
      final status = await OverlayPromptGuard.runDuringOsPermissionPrompt(
        Permission.activityRecognition.request,
      );
      denied = !(status.isGranted || status.isLimited || status.isProvisional);
    } else if (Platform.isIOS) {
      final result = await OverlayPromptGuard.runDuringOsPermissionPrompt(
        MotionActivityService.requestPermission,
      );
      denied = result != 'granted';
    }

    if (!denied) return;
    await MotionActivitySettingsDialog.showAndMaybeOpenSettings();
  }

  Future<void> _openSettingsFor(String id) async {
    if (id == 'motionActivity') {
      await MotionActivitySettingsDialog.showAndMaybeOpenSettings();
      return;
    }

    if (id == 'backgroundLocation') {
      if (kDebugMode) {
        debugPrint(
          '[RequiredPermissionsGate] openSettings backgroundLocation → '
          'try upgrade then Settings',
        );
      }
      await _requestBackgroundLocationStep();
      return;
    }

    final destination = switch (id) {
      'foregroundLocation' ||
      'preciseLocation' => StoreSafeSettingsDestination.locationPermission,
      'locationServices' => StoreSafeSettingsDestination.systemLocationServices,
      'backgroundAppRefresh' => StoreSafeSettingsDestination.app,
      _ => StoreSafeSettingsDestination.app,
    };

    if (kDebugMode) {
      debugPrint(
        '[RequiredPermissionsGate] openSettings id=$id destination=$destination',
      );
    }

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
    final motionAvailable = await MotionActivityService.isAvailable();
    final motionGranted = motionAvailable ? await _motionGranted() : true;
    final backgroundAppRefresh = await _backgroundAppRefreshEnabled();

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
            : await _backgroundLocationAction(),
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
      if (motionAvailable)
        RequiredPermissionItem(
          id: 'motionActivity',
          name: Platform.isAndroid ? 'Physical activity' : 'Motion & Fitness',
          description: 'Detects walking, driving, and other activity.',
          enabled: motionGranted,
          action: motionGranted
              ? RequiredPermissionAction.none
              : await _motionAction(),
          icon: Icons.directions_walk_rounded,
        ),
      RequiredPermissionItem(
        id: 'backgroundAppRefresh',
        name: Platform.isAndroid
            ? 'Background activity'
            : 'Background App Refresh',
        description: Platform.isAndroid
            ? 'Allow background work so shift tracking can continue.'
            : 'Needed for reliable location updates in the background.',
        enabled: backgroundAppRefresh,
        action: backgroundAppRefresh
            ? RequiredPermissionAction.none
            : RequiredPermissionAction.openSettings,
        icon: Icons.sync_rounded,
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

    return list;
  }

  Future<bool> _backgroundAppRefreshEnabled() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    try {
      final status = await _settingsChannel.invokeMethod<String>(
        'backgroundAppRefreshStatus',
      );
      if (status == 'disabled' || status == 'restricted') return false;
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> _motionGranted() async {
    if (Platform.isAndroid) {
      final status = await Permission.activityRecognition.status;
      return status.isGranted || status.isLimited || status.isProvisional;
    }
    if (Platform.isIOS) {
      final native = await MotionActivityService.checkPermission();
      return native == 'granted';
    }
    return true;
  }

  Future<RequiredPermissionAction> _motionAction() async {
    if (Platform.isAndroid) {
      final status = await Permission.activityRecognition.status;
      if (status.isPermanentlyDenied || status.isRestricted) {
        return RequiredPermissionAction.openSettings;
      }
      return RequiredPermissionAction.allow;
    }
    if (Platform.isIOS) {
      final native = await MotionActivityService.checkPermission();
      if (native == 'denied' || native == 'restricted') {
        return RequiredPermissionAction.openSettings;
      }
      return RequiredPermissionAction.allow;
    }
    return RequiredPermissionAction.openSettings;
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

  List<RequiredPermissionItem> _sortMissingFirst(
    List<RequiredPermissionItem> items,
  ) {
    final missing = <RequiredPermissionItem>[];
    final enabled = <RequiredPermissionItem>[];
    for (final item in items) {
      if (item.needsAction) {
        missing.add(item);
      } else {
        enabled.add(item);
      }
    }
    return [...missing, ...enabled];
  }

  String _fingerprint(List<RequiredPermissionItem> next) {
    return next
        .map((e) => '${e.id}:${e.enabled ? 1 : 0}:${e.action.name}')
        .join('|');
  }
}
