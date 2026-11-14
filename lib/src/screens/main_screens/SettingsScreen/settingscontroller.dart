import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:flutter/material.dart';
import 'package:smartnps360/src/screens/controllers/auth_controller.dart';
import 'package:smartnps360/src/screens/controllers/usercontroller.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/timer_controller.dart';
import 'package:smartnps360/src/screens/main_screens/auth_screen.dart';
import 'package:smartnps360/src/screens/main_screens/main_controller.dart';
import 'package:smartnps360/src/screens/native_auth_session.dart';
import 'package:smartnps360/src/screens/new_screens/new_main_screen.dart';
import 'package:smartnps360/src/screens/services/notification_manager.dart';
import 'package:smartnps360/src/screens/utilities/appsnackbar.dart';

void _log(String msg, {String tag = 'APP', Object? error, StackTrace? stack}) {
  if (kDebugMode) {
    developer.log(msg, name: tag, error: error, stackTrace: stack);
  }
}

class SettingsController extends GetxController {
  final GetStorage _box = GetStorage();

  // persistently store/read the dark mode flag
  var isDarkMode = false.obs;
  var notificationsEnabled = false.obs;
  var is2HourReminder = false.obs;
  var is1HourReminder = false.obs;
  var is30MinReminder = false.obs;
  var is5MinReminder = false.obs;
  var isUpdatingNotificationToggle = false.obs;

  @override
  void onInit() {
    super.onInit();
    isDarkMode.value = _box.read('isDarkMode') ?? false;
    notificationsEnabled.value = _box.read('notificationsEnabled') ?? false;
  }

  @override
  void onReady() {
    super.onReady();
    _checkPermissionOnOpen();
  }

  Future<void> _checkPermissionOnOpen() async {
    final stored = _box.read('notificationsEnabled');

    // Check current permission status
    final granted = await NotificationManager.instance.isPermissionGranted();

    _log(
      'Settings onReady: stored=$stored, permission granted=$granted',
      tag: 'Settings',
    );

    if (stored == null) {
      // First time opening settings - no preference stored yet
      // On Android, permission might be granted by default
      // Set initial state based on system permission
      if (granted) {
        _log(
          'First time: Permission granted by default (Android), enabling notifications',
          tag: 'Settings',
        );
        _box.write('notificationsEnabled', true);
        notificationsEnabled.value = true;
      } else {
        _log(
          'First time: Permission not granted, keeping notifications disabled',
          tag: 'Settings',
        );
        _box.write('notificationsEnabled', false);
        notificationsEnabled.value = false;
      }
    } else if (stored == true) {
      // User previously enabled notifications
      if (!granted) {
        // Permission was revoked, update the toggle state silently
        _box.write('notificationsEnabled', false);
        notificationsEnabled.value = false;
        _log(
          'Notifications were enabled but permission is now revoked',
          tag: 'Settings',
        );
      } else {
        // Ensure the state matches
        _box.write('notificationsEnabled', true);
        notificationsEnabled.value = true;
      }
    } else {
      // User explicitly disabled notifications (stored == false)
      // Respect their choice regardless of system permission status
      _log('Respecting user choice: notifications disabled', tag: 'Settings');
      _box.write('notificationsEnabled', false);
      notificationsEnabled.value = false;
    }
  }

  /// Refresh permission state when app resumes from background
  Future<void> refreshPermissionState() async {
    _log('Refreshing permission state after app resume', tag: 'Settings');

    final stored = _box.read('notificationsEnabled');
    final granted = await NotificationManager.instance.isPermissionGranted();

    _log('After resume: stored=$stored, granted=$granted', tag: 'Settings');

    // If user previously had notifications enabled but permission is now revoked
    if (stored == true && !granted) {
      _log('Permission revoked, updating toggle to OFF', tag: 'Settings');
      _box.write('notificationsEnabled', false);
      notificationsEnabled.value = false;
    }
    // If user just granted permission (was disabled, now granted)
    else if (stored == false && granted) {
      _log('Permission granted, updating toggle to ON', tag: 'Settings');
      _box.write('notificationsEnabled', true);
      notificationsEnabled.value = true;

      // Schedule notifications if TimeController is available
      try {
        if (Get.isRegistered<TimeController>()) {
          await Get.find<TimeController>().refreshServerSession(
            showShimmer: false,
            blockUI: false,
            suppressScopeLoading: true,
          );
          _log(
            'Notifications scheduled after permission grant',
            tag: 'Settings',
          );
        }
      } catch (e) {
        _log('Error scheduling notifications', tag: 'Settings', error: e);
      }
    }
  }

  void _closeSettingsAndGoDashboard() {
    if (Get.key.currentState?.canPop() ?? false) {
      Get.back();
    }

    if (Get.isRegistered<MainController>()) {
      Future.microtask(() => Get.find<MainController>().changePage(0));
      return;
    }

    Future.microtask(() => Get.offAll(() => const NewMainScreen()));
  }

  void toggleDarkMode(bool value) {
    // Close and route first so the tap feels instant.

    // Keep local reactive state in sync immediately.
    isDarkMode.value = value;

    // Defer expensive app-wide theme rebuild until after route transition starts.
    Future.microtask(() {
      Get.changeThemeMode(value ? ThemeMode.dark : ThemeMode.light);
      _box.write('isDarkMode', value);
    });
    // _closeSettingsAndGoDashboard();
  }

  void toggle2HourReminder(bool value) {
    is2HourReminder.value = value;
  }

  void toggle1HourReminder(bool value) {
    is1HourReminder.value = value;
  }

  void toggle30MinReminder(bool value) {
    is30MinReminder.value = value;
  }

  void toggle5MinReminder(bool value) {
    is5MinReminder.value = value;
  }

  Future<void> handleLogout(BuildContext context) async {
    EasyLoading.show();

    try {
      Get.delete<TimeController>(force: true);
      Get.delete<UserController>(force: true);
      await NotificationManager.instance.cancelAll();
      await NativeAuthSession.instance.clearSession();
    } catch (e) {
      _log('Logout cleanup error', tag: 'Settings', error: e);
    } finally {
      EasyLoading.dismiss();
      if (Get.isRegistered<AuthController>()) {
        Get.delete<AuthController>(force: true);
      }
      Get.offAll(
        () => const AuthScreen(),
        arguments: {'skipAutoLogin': true},
      );
    }
  }

  Future<void> toggleNotifications(bool value) async {
    if (isUpdatingNotificationToggle.value) return;
    final previousState = notificationsEnabled.value;

    // Optimistic update so the toggle feels instant.
    notificationsEnabled.value = value;
    _box.write('notificationsEnabled', value);

    isUpdatingNotificationToggle.value = true;
    _closeSettingsAndGoDashboard();

    try {
      _log('Toggle notifications: $value', tag: 'Settings');

      // Let route transition finish before showing permission flows.
      await Future<void>.delayed(Duration.zero);

      // Let NotificationManager handle all permission logic
      // It will request permission, show dialogs, or open settings as needed
      final finalState = await NotificationManager.instance
          .handleNotificationToggle(value);

      _log('Notification toggle result: $finalState', tag: 'Settings');

      // Reconcile UI/state with permission result.
      _box.write('notificationsEnabled', finalState);
      notificationsEnabled.value = finalState;

      // If toggle is OFF, ensure all notifications are cancelled
      if (!value || !finalState) {
        _log('Cancelling all scheduled notifications', tag: 'Settings');
        await NotificationManager.instance.cancelAll();
      }

      // If toggle is ON and successful, refresh session to schedule upcoming notifications
      if (value && finalState) {
        _log(
          'Notifications enabled, refreshing session to schedule upcoming reminders',
          tag: 'Settings',
        );
        try {
          // Refresh server session to get latest shift data and schedule notifications
          if (Get.isRegistered<TimeController>()) {
            await Get.find<TimeController>().refreshServerSession(
              showShimmer: false,
              blockUI: false,
              suppressScopeLoading: true,
            );
            _log(
              'Session refreshed successfully, notifications scheduled',
              tag: 'Settings',
            );
          } else {
            _log(
              'TimeController not registered, notifications will be scheduled when session loads',
              tag: 'Settings',
            );
          }
        } catch (e) {
          _log(
            'Error refreshing session after enabling notifications',
            tag: 'Settings',
            error: e,
          );
          // Continue even if refresh fails - notifications will be scheduled on next session update
        }
      }

      // Show feedback to user if they tried to enable but permission was denied
      if (value && !finalState) {
        final ctx = Get.context;
        if (ctx != null && ctx.mounted) {
          AppSnackBar.show(
            ctx,
            'Notification permission is required to enable reminders',
            type: SnackBarType.error,
          );
        }
      }
    } catch (e) {
      _log('Error toggling notifications', tag: 'Settings', error: e);
      // Rollback optimistic update on error.
      _box.write('notificationsEnabled', previousState);
      notificationsEnabled.value = previousState;
    } finally {
      isUpdatingNotificationToggle.value = false;
    }
  }
}
