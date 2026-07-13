import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persisted in-app push notification toggle (distinct from OS notification permission).
///
/// Uses the same secure-storage accessibility as auth tokens so reads succeed
/// on iOS after backgrounding and on Android with encrypted preferences.
class PushNotificationPreferences {
  PushNotificationPreferences._();

  static const storageKey = 'push.notifications_enabled';

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// `true` when the officer has not turned push off in-app (default on).
  static Future<bool> readEnabled() async {
    final stored = await _storage.read(key: storageKey);
    if (stored == null) return true;
    return stored != '0';
  }

  static Future<void> writeEnabled(bool enabled) async {
    await _storage.write(key: storageKey, value: enabled ? '1' : '0');
  }
}
