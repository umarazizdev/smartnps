import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:smartnps360/src/screens/services/notification_manager.dart';
import 'package:smartnps360/src/screens/services/local_notification_service.dart';

class SettingsController extends GetxController {
  final RxBool notificationsEnabled = false.obs;
  final box = GetStorage();

  @override
  void onInit() {
    super.onInit();
    // Initialize toggle from persisted value but ensure it matches OS permission
    final saved = box.read('notificationsEnabled') == true;
    notificationsEnabled.value = saved;

    // Sync with real OS permission (toggle must reflect OS state)
    _syncWithOsPermission();
  }

  Future<void> _syncWithOsPermission() async {
    final granted = await LocalNotificationService.instance
        .isPermissionGranted();
    if (!granted && notificationsEnabled.value) {
      // Persisted true but OS denied -> update stored value and UI
      try {
        box.write('notificationsEnabled', false);
      } catch (_) {}
      notificationsEnabled.value = false;
    } else if (granted && notificationsEnabled.value != true) {
      // OS granted but stored might be false; keep stored value unless user toggles.
      // We avoid enabling silently; UI will show real permission below.
      notificationsEnabled.value = true;
      try {
        box.write('notificationsEnabled', true);
      } catch (_) {}
    }
  }

  /// Call this when user toggles the switch in settings UI.
  Future<void> onNotificationsToggle(bool value) async {
    // Optimistically set UI; handleNotificationToggle will return real outcome
    notificationsEnabled.value = value;

    final success = await NotificationManager.instance.handleNotificationToggle(
      value,
    );

    // If denied or failed, revert the UI toggle
    if (!success) {
      notificationsEnabled.value = false;
    } else {
      notificationsEnabled.value = true;
    }
  }
}
