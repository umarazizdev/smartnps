import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PushNotificationPreferences {
  PushNotificationPreferences._();

  static const storageKey = 'push.notifications_enabled';

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static Future<bool> readEnabled() async {
    final stored = await _storage.read(key: storageKey);
    if (stored == null) return true;
    return stored != '0';
  }

  static Future<void> writeEnabled(bool enabled) async {
    await _storage.write(key: storageKey, value: enabled ? '1' : '0');
  }
}
