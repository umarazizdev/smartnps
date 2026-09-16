import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Shared Keychain / secure-storage defaults for background-safe reads.
///
/// iOS notes:
/// - `-25308` (`errSecInteractionNotAllowed`): device locked / no UI.
/// - `-25299` (`errSecDuplicateItem`): item exists under different attrs
///   (common after changing [KeychainAccessibility]). Delete + rewrite.
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

  static bool isDuplicateItem(Object error) {
    if (error is! PlatformException) {
      final text = error.toString().toLowerCase();
      return text.contains('-25299') || text.contains('already exists');
    }
    final code = error.code.trim();
    if (code == '-25299') return true;
    final message = error.message?.toLowerCase() ?? '';
    return message.contains('already exists') ||
        (error.details?.toString().contains('-25299') ?? false);
  }

  /// Keychain conditions that should never be treated as app crashes.
  static bool isRecoverableKeychainError(Object error) {
    return isInteractionNotAllowed(error) || isDuplicateItem(error);
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
      if (!isDuplicateItem(e)) rethrow;

      // Accessibility / attribute mismatch: replace the existing item.
      try {
        await storage.delete(key: key);
        await storage.write(key: key, value: value);
        if (kDebugMode) {
          debugPrint(
            '[SecureStorageAccess] write recovered after duplicate delete key=$key',
          );
        }
        return true;
      } on PlatformException catch (retry) {
        if (isInteractionNotAllowed(retry)) return false;
        if (kDebugMode) {
          debugPrint(
            '[SecureStorageAccess] write failed after duplicate delete '
            'key=$key code=${retry.code} ${retry.message}',
          );
        }
        return false;
      }
    }
  }

  static Future<bool> delete(String key) async {
    try {
      await storage.delete(key: key);
      return true;
    } on PlatformException catch (e) {
      if (isInteractionNotAllowed(e)) return false;
      // Deleting a missing item is fine.
      if (isDuplicateItem(e)) return true;
      rethrow;
    }
  }
}
