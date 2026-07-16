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
import '../utilities/app_lifecycle_resume_gate.dart';
import '../utilities/overlay_prompt_guard.dart';
import '../widgets/glass_action_dialog.dart';

enum PermissionSettingsPromptResult { skipped, dismissed, openedSettings }

enum LocationPermissionRequestResult {
  completed,
  promptShown,
  openedSettings,
}

/// Where [openSettingsForUserTap] should navigate after an explicit user tap.
enum StoreSafeSettingsDestination {
  /// Settings > SmartNPS360 (iOS) or app details (Android).
  app,

  /// Android location permission page when available; otherwise app settings.
  locationPermission,

  /// Android system Location Services toggle screen.
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

  /// True while the store-safe Open Settings dialog is on screen.
  static final ValueNotifier<bool> settingsPromptVisible = ValueNotifier(false);

  static bool get isAwaitingSettingsReturn => _awaitingSettingsReturn;

  static const Duration _promptCooldown = Duration(minutes: 2);

  static bool shouldOpenSettings(PermissionStatus status) {
    return status.isPermanentlyDenied || status.isRestricted;
  }

  /// Opens device settings only after the user tapped an in-app control.
  /// Never call this automatically from background polling or page loads.
  ///
  /// When [holdAwaitingLock] is true (Android + waitForReturn), the caller must
  /// call [endAwaitingSettingsReturn] after post-return settle so resume
  /// handlers do not pop dialogs mid-check.
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
      // Android: drop any leftover education popup, then open Settings right away.
      // Avoid frame/delay waits here — they made Open Settings feel laggy.
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
          // Strip any Activity-restored dialog before the next frame paints.
          clearPopupRoutesImmediately();
          await WidgetsBinding.instance.endOfFrame;
          // Adaptive: only brief extra settle when permission is not ready yet.
          if (!await BackgroundLocationPermissions.isClockInBackgroundReady()) {
            await Future<void>.delayed(const Duration(milliseconds: 120));
            await WidgetsBinding.instance.endOfFrame;
          }
          clearPopupRoutesImmediately();
        }
        await BackgroundLocationPermissions.refreshPermissionStateFromOs();
        // After Settings settle: coalesce into pending app_cycle, or upload
        // a follow-up if app_cycle already posted a stale snapshot.
        await NativePermissionStatusService.instance
            .ensureLatestPermissionsSynced();
      }
    } finally {
      if (!keepLock) {
        _awaitingSettingsReturn = false;
      }
    }
  }

  /// Ends the Settings-return lock after Android permission settle completes.
  static void endAwaitingSettingsReturn() {
    _awaitingSettingsReturn = false;
  }

  /// True when the OS will not show another in-app location prompt.
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

  /// Clears stale dialog state when returning from Settings.
  static void reconcilePromptsAfterAppResume() {
    if (Platform.isAndroid) {
      dismissStaleModalRouteIfPresent();
    }
    _dialogVisible = false;
    settingsPromptVisible.value = false;
  }

  /// Clears leftover Settings/education modal only while returning from
  /// Settings. Removes every popup route in one shot so Android does not
  /// briefly paint a restored dialog ("Unable to verify…" flash).
  static void dismissStaleModalRouteIfPresent() {
    if (!Platform.isAndroid) return;
    if (!_awaitingSettingsReturn) return;
    clearPopupRoutesImmediately();
  }

  /// Drop all popup/dialog routes without waiting for reverse animation.
  /// Android-only callers use this for fast Settings handoff.
  static void clearPopupRoutesImmediately() {
    if (!Platform.isAndroid) return;
    final navigator = AppNavigator.key.currentState;
    if (navigator == null) return;
    // Keep the first non-popup route; strip restored dialogs before paint.
    navigator.popUntil((route) => route is! PopupRoute);
  }

  /// @deprecated Prefer [clearPopupRoutesImmediately] — no fixed delay needed.
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

  /// Opens this app's page in the device Settings app.
  static Future<void> launchAppSettings() => _openAppSettingsWithFallback();

  /// Opens the app's Location permission screen when possible (Android 11+),
  /// otherwise falls back to the general app settings page.
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
      // iOS has no public deep link to the Location sub-page; open this app's
      // Settings entry so the user can set Location to Always.
      await launchAppSettings();
      return;
    }

    await Geolocator.openAppSettings();
  }

  /// Foreground-only OS prompt. Does not open Settings or request background.
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
      // API only: lasting While Using → granted; Don't Allow / only this time → denied.
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
      // API only: While Using / Always → granted; Don't Allow / other → denied.
      unawaited(
        NativePermissionStatusService.instance
            .syncForegroundLocationAfterOsPrompt(),
      );
      return LocationPermissionRequestResult.promptShown;
    }

    return LocationPermissionRequestResult.completed;
  }

  /// Handles one location-permission step per call: OS prompt or Settings, never both.
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

    // Android background/all-the-time access usually requires Settings.
    // Do not call locationAlways.request() here — it jumps straight to the
    // system permission screen. The in-app Open Settings dialog comes first.
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

    // Foreground granted; background requires Settings. Do not auto-open —
    // the explanatory Open Settings dialog handles the next step store-safely.
    return LocationPermissionRequestResult.promptShown;
  }

  /// One staged step per call. Prefer [requestNextLocationPermissionStep].
  static Future<void> launchLocationPermissionSettingsFromStep() async {
    await requestNextLocationPermissionStep();
  }

  /// Shows an explanatory dialog first. Settings open only if the user taps
  /// [Open Settings]. Never auto-redirects without that tap.
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
    return BackgroundLocationPermissions.isBackgroundLocationFullyEnabled();
  }

  static bool _isInCooldown(String dialogKey) {
    final last = _lastPromptAtByKey[dialogKey];
    if (last == null) return false;
    return DateTime.now().difference(last) < _promptCooldown;
  }
}
