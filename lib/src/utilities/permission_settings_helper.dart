import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app/app_navigator.dart';
import '../background/background_location_permissions.dart';
import '../permissions/native_permission_status_service.dart';
import '../permissions/required_permissions_gate.dart';
import '../utilities/app_lifecycle_resume_gate.dart';
import '../utilities/overlay_prompt_guard.dart';
import '../widgets/glass_action_dialog.dart';

enum PermissionSettingsPromptResult { skipped, dismissed, openedSettings }

enum LocationPermissionRequestResult {
  completed,
  promptShown,
  openedSettings,
}

enum StoreSafeSettingsDestination {

  app,

  locationPermission,

  systemLocationServices,
}

class PermissionSettingsHelper {
  PermissionSettingsHelper._();

  static const MethodChannel _settingsChannel = MethodChannel(
    'com.smartnps360.app/settings',
  );

  static bool _dialogVisible = false;
  static bool _awaitingSettingsReturn = false;
  static final Map<String, DateTime> _lastPromptAtByKey = {};

  static final ValueNotifier<bool> settingsPromptVisible = ValueNotifier(false);

  static bool get isAwaitingSettingsReturn => _awaitingSettingsReturn;

  static const Duration _promptCooldown = Duration(minutes: 2);

  static bool shouldOpenSettings(PermissionStatus status) {
    return status.isPermanentlyDenied || status.isRestricted;
  }

  static Future<void> openSettingsForUserTap({
    StoreSafeSettingsDestination destination =
        StoreSafeSettingsDestination.app,
    bool waitForReturn = false,
    @Deprecated('Use waitForReturn') bool waitForReturnOnAndroid = false,
    bool holdAwaitingLock = false,
  }) async {
    final shouldWaitForReturn = waitForReturn || waitForReturnOnAndroid;
    final keepLock =
        Platform.isAndroid && shouldWaitForReturn && holdAwaitingLock;

    _awaitingSettingsReturn = true;
    try {

      if (Platform.isAndroid) {
        clearPopupRoutesImmediately();
      }

      switch (destination) {
        case StoreSafeSettingsDestination.locationPermission:
          await launchLocationPermissionSettings();
        case StoreSafeSettingsDestination.systemLocationServices:
          if (Platform.isAndroid) {
            await Geolocator.openLocationSettings();
            break;
          }
          await launchAppSettings();
        case StoreSafeSettingsDestination.app:
          await launchAppSettings();
      }

      if (shouldWaitForReturn) {
        await AppLifecycleResumeGate.waitForResume();
        if (Platform.isAndroid) {

          clearPopupRoutesImmediately();
          await WidgetsBinding.instance.endOfFrame;

          if (!await BackgroundLocationPermissions.isClockInBackgroundReady()) {
            await Future<void>.delayed(const Duration(milliseconds: 120));
            await WidgetsBinding.instance.endOfFrame;
          }
          clearPopupRoutesImmediately();
        }
        await BackgroundLocationPermissions.refreshPermissionStateFromOs();

        await NativePermissionStatusService.instance
            .ensureLatestPermissionsSynced();
      }
    } finally {
      if (!keepLock) {
        _awaitingSettingsReturn = false;
      }
    }
  }

  static void endAwaitingSettingsReturn() {
    _awaitingSettingsReturn = false;
  }

  static Future<bool> foregroundRequiresSettingsPrompt() async {
    if (Platform.isAndroid) {
      return shouldOpenSettings(await Permission.location.status);
    }
    if (Platform.isIOS) {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.deniedForever;
    }
    return false;
  }

  static BuildContext? resolveDialogContext([BuildContext? fallback]) {
    final navigatorContext = AppNavigator.key.currentContext;
    if (navigatorContext != null && navigatorContext.mounted) {
      return navigatorContext;
    }
    if (fallback != null && fallback.mounted) return fallback;
    return null;
  }

  static void reconcilePromptsAfterAppResume() {
    if (Platform.isAndroid) {
      dismissStaleModalRouteIfPresent();
    }
    _dialogVisible = false;
    settingsPromptVisible.value = false;
  }

  static void dismissStaleModalRouteIfPresent() {
    if (!Platform.isAndroid) return;
    if (!_awaitingSettingsReturn) return;
    clearPopupRoutesImmediately();
  }

  static void clearPopupRoutesImmediately() {
    if (!Platform.isAndroid) return;
    final navigator = AppNavigator.key.currentState;
    if (navigator == null) return;

    navigator.popUntil((route) => route is! PopupRoute);
  }

  static Future<void> waitForDialogDismissSettle() async {
    if (!Platform.isAndroid) return;
    clearPopupRoutesImmediately();
    await WidgetsBinding.instance.endOfFrame;
  }

  static Future<void> _openAppSettingsWithFallback() async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final opened = await _settingsChannel.invokeMethod<bool>(
          'openAppSettings',
        );
        if (opened == true) return;
      } catch (error) {
        if (kDebugMode) {
          debugPrint('[PermissionSettings] openAppSettings native failed: $error');
        }
      }
    }

    try {
      if (await openAppSettings()) return;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[PermissionSettings] permission_handler openAppSettings failed: $error',
        );
      }
    }

    await Geolocator.openAppSettings();
  }

  static Future<void> launchAppSettings() => _openAppSettingsWithFallback();

  static Future<void> launchLocationPermissionSettings() async {
    if (Platform.isAndroid) {
      try {
        await _settingsChannel.invokeMethod<void>(
          'openLocationPermissionSettings',
        );
        return;
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
            '[PermissionSettings] openLocationPermissionSettings failed: $error',
          );
        }
      }
    }

    if (Platform.isIOS) {

      await launchAppSettings();
      return;
    }

    await Geolocator.openAppSettings();
  }

  static Future<LocationPermissionRequestResult>
  requestForegroundLocationStep() async {
    if (await BackgroundLocationPermissions.isBackgroundLocationFullyEnabled()) {
      return LocationPermissionRequestResult.completed;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationPermissionRequestResult.promptShown;
      }
    }

    if (Platform.isAndroid) {
      final foreground = await Permission.location.status;
      if (foreground.isGranted) {
        return LocationPermissionRequestResult.completed;
      }
      if (shouldOpenSettings(foreground)) {
        return LocationPermissionRequestResult.promptShown;
      }
      await OverlayPromptGuard.runDuringOsPermissionPrompt(
        Permission.location.request,
      );

      unawaited(
        NativePermissionStatusService.instance
            .syncForegroundLocationAfterOsPrompt(),
      );
      return LocationPermissionRequestResult.promptShown;
    }

    if (Platform.isIOS) {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        return LocationPermissionRequestResult.completed;
      }
      if (permission == LocationPermission.deniedForever) {
        return LocationPermissionRequestResult.promptShown;
      }
      await OverlayPromptGuard.runDuringOsPermissionPrompt(
        Geolocator.requestPermission,
      );

      unawaited(
        NativePermissionStatusService.instance
            .syncForegroundLocationAfterOsPrompt(),
      );
      return LocationPermissionRequestResult.promptShown;
    }

    return LocationPermissionRequestResult.completed;
  }

  static Future<LocationPermissionRequestResult>
  requestNextLocationPermissionStep() async {
    if (await BackgroundLocationPermissions.isBackgroundLocationFullyEnabled()) {
      return LocationPermissionRequestResult.completed;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationPermissionRequestResult.promptShown;
      }
    }

    if (Platform.isAndroid) {
      return _requestNextAndroidLocationStep();
    }

    if (Platform.isIOS) {
      return _requestNextIosLocationStep();
    }

    return LocationPermissionRequestResult.completed;
  }

  static Future<LocationPermissionRequestResult>
  _requestNextAndroidLocationStep() async {
    final foreground = await Permission.location.status;
    if (!foreground.isGranted) {
      if (shouldOpenSettings(foreground)) {
        return LocationPermissionRequestResult.promptShown;
      }
      await OverlayPromptGuard.runDuringOsPermissionPrompt(
        Permission.location.request,
      );
      unawaited(
        NativePermissionStatusService.instance
            .syncForegroundLocationAfterOsPrompt(),
      );
      return LocationPermissionRequestResult.promptShown;
    }

    if (await BackgroundLocationPermissions.hasSufficientBackgroundAccess()) {
      return LocationPermissionRequestResult.completed;
    }

    return LocationPermissionRequestResult.promptShown;
  }

  static Future<LocationPermissionRequestResult> _requestNextIosLocationStep() async {
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionRequestResult.promptShown;
    }

    if (permission == LocationPermission.denied) {
      await OverlayPromptGuard.runDuringOsPermissionPrompt(
        Geolocator.requestPermission,
      );
      unawaited(
        NativePermissionStatusService.instance
            .syncForegroundLocationAfterOsPrompt(),
      );
      return LocationPermissionRequestResult.promptShown;
    }

    if (permission == LocationPermission.always) {
      return LocationPermissionRequestResult.completed;
    }

    return LocationPermissionRequestResult.promptShown;
  }

  static Future<void> launchLocationPermissionSettingsFromStep() async {
    await requestNextLocationPermissionStep();
  }

  static Future<PermissionSettingsPromptResult> promptOpenSettings({
    required String title,
    required String message,
    String dialogKey = 'default',
    String secondaryLabel = 'Not now',
    bool destructiveSecondary = false,
    bool barrierDismissible = false,
    bool respectCooldown = true,
    bool skipOverlayWait = false,
    BuildContext? context,
  }) async {
    if (RequiredPermissionsGate.shouldSuppressCompetingDialogs) {
      if (kDebugMode) {
        debugPrint(
          '[PermissionSettings] skip dialog key=$dialogKey '
          '(required-permissions blocker active)',
        );
      }
      return PermissionSettingsPromptResult.skipped;
    }

    if (await _isLocationSettingsPromptRedundant(dialogKey)) {
      if (kDebugMode) {
        debugPrint(
          '[PermissionSettings] skip dialog key=$dialogKey (location already enabled)',
        );
      }
      return PermissionSettingsPromptResult.skipped;
    }

    if (_dialogVisible) {
      return PermissionSettingsPromptResult.skipped;
    }

    if (respectCooldown && _isInCooldown(dialogKey)) {
      if (kDebugMode) {
        debugPrint(
          '[PermissionSettings] skip dialog key=$dialogKey (cooldown)',
        );
      }
      return PermissionSettingsPromptResult.skipped;
    }

    final initialContext = resolveDialogContext(context);
    if (initialContext == null) {
      if (kDebugMode) {
        debugPrint(
          '[PermissionSettings] skip dialog key=$dialogKey (no context)',
        );
      }
      return PermissionSettingsPromptResult.skipped;
    }

    if (!skipOverlayWait) {
      await OverlayPromptGuard.waitUntilReady();
    }

    final readyContext = resolveDialogContext(initialContext);
    if (readyContext == null) {
      if (kDebugMode) {
        debugPrint(
          '[PermissionSettings] skip dialog key=$dialogKey (no context after wait)',
        );
      }
      return PermissionSettingsPromptResult.skipped;
    }

    _dialogVisible = true;
    settingsPromptVisible.value = true;
    _lastPromptAtByKey[dialogKey] = DateTime.now();
    var openedSettings = false;

    try {
      final openSettings = await GlassActionDialog.show(
        context: readyContext,
        barrierDismissible: barrierDismissible,
        icon: Icons.location_on_rounded,
        title: title,
        message: message,
        secondaryLabel: secondaryLabel,
        primaryLabel: 'Open Settings',
        destructiveSecondary: destructiveSecondary,
      );
      openedSettings = openSettings == true;

      if (openedSettings) {
        if (_shouldOpenLocationPermissionSettings(dialogKey)) {
          await openSettingsForUserTap(
            destination: StoreSafeSettingsDestination.locationPermission,
            waitForReturn: true,
          );
        } else if (dialogKey == 'location_services') {
          await openSettingsForUserTap(
            destination: BackgroundLocationPermissions.settingsDestinationFor(
              'location_services_disabled',
            ),
            waitForReturn: true,
          );
        } else {
          await openSettingsForUserTap(
            waitForReturn: true,
          );
        }
        return PermissionSettingsPromptResult.openedSettings;
      }
      return PermissionSettingsPromptResult.dismissed;
    } finally {
      _dialogVisible = false;
      settingsPromptVisible.value = false;
    }
  }

  static void clearCooldown([String? dialogKey]) {
    if (dialogKey == null) {
      _lastPromptAtByKey.clear();
      return;
    }
    _lastPromptAtByKey.remove(dialogKey);
  }

  static bool _shouldOpenLocationPermissionSettings(String dialogKey) {
    if (dialogKey != 'background_location' &&
        dialogKey != 'webview_location' &&
        dialogKey != 'clockin_background_location') {
      return false;
    }
    return Platform.isAndroid || Platform.isIOS;
  }

  static Future<bool> _isLocationSettingsPromptRedundant(String dialogKey) async {
    if (!_shouldOpenLocationPermissionSettings(dialogKey)) {
      return false;
    }
    if (!await BackgroundLocationPermissions.isBackgroundLocationFullyEnabled()) {
      return false;
    }

    return BackgroundLocationPermissions.hasPreciseLocationAccess();
  }

  static bool _isInCooldown(String dialogKey) {
    final last = _lastPromptAtByKey[dialogKey];
    if (last == null) return false;
    return DateTime.now().difference(last) < _promptCooldown;
  }
}
