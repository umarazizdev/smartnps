import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Shared Keychain / secure-storage defaults for background-safe reads.
///
/// iOS `errSecInteractionNotAllowed` (-25308) happens when the device is
/// locked or the app is backgrounded before first unlock. Prefer
/// [first_unlock_this_device] and treat -25308 as a soft failure.
class SecureStorageAccess {
  SecureStorageAccess._();

  static const FlutterSecureStorage storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static bool isInteractionNotAllowed(Object error) {
    if (error is! PlatformException) {
      final text = error.toString();
      return text.contains('-25308') ||
          text.contains('User interaction is not allowed');
    }
    final code = error.code.trim();
    if (code == '-25308') return true;
    final details = error.details?.toString() ?? '';
    return details.contains('-25308') ||
        (error.message?.contains('User interaction is not allowed') ?? false);
  }

  static Future<String?> read(String key) async {
    try {
      return await storage.read(key: key);
    } on PlatformException catch (e) {
      if (isInteractionNotAllowed(e)) return null;
      rethrow;
    }
  }

  static Future<bool> write(String key, String value) async {
    try {
      await storage.write(key: key, value: value);
      return true;
    } on PlatformException catch (e) {
      if (isInteractionNotAllowed(e)) return false;
      rethrow;
    }
  }

  static Future<bool> delete(String key) async {
    try {
      await storage.delete(key: key);
      return true;
    } on PlatformException catch (e) {
      if (isInteractionNotAllowed(e)) return false;
      rethrow;
    }
  }
}
