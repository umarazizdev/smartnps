import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_state.dart';
import 'location_disclosure_account_sync.dart';

class AuthRepository {
  AuthRepository._();

  static final AuthRepository instance = AuthRepository._();

  /// Allows Keychain reads while the screen is locked (after first unlock).
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static String? _cachedAccessToken;
  static bool _accessTokenAccessibilityMigrated = false;

  static const _kAccessToken = 'auth.access_token';
  static const _kRefreshToken = 'auth.refresh_token';
  static const _kUserJson = 'auth.user_json';
  static const _kOfficerLoggedIn = 'auth.officer_logged_in';

  Future<void> saveLogin({
    required Map<String, dynamic> user,
    String? accessToken,
    String? refreshToken,
  }) async {
    await _storage.write(key: _kUserJson, value: _safeEncode(user));
    if (accessToken != null && accessToken.isNotEmpty) {
      await _storage.write(key: _kAccessToken, value: accessToken);
      _cachedAccessToken = accessToken;
      _accessTokenAccessibilityMigrated = true;
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: _kRefreshToken, value: refreshToken);
    }
    await setOfficerLoggedIn(true);
    await LocationDisclosureAccountSync.onLoginResolved();
    debugPrint('[SmartNPS360][AuthRepo] saved login (secure storage)');
  }

  Future<void> setOfficerLoggedIn(bool value) async {
    if (value) {
      await _storage.write(key: _kOfficerLoggedIn, value: 'true');
    } else {
      await _storage.delete(key: _kOfficerLoggedIn);
    }
  }

  Future<bool> isOfficerLoggedIn() async {
    final value = await _storage.read(key: _kOfficerLoggedIn);
    return value == 'true';
  }

  Future<void> clear() async {
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);
    await _storage.delete(key: _kUserJson);
    _cachedAccessToken = null;
    _accessTokenAccessibilityMigrated = false;
    await setOfficerLoggedIn(false);
    LocationDisclosureAccountSync.onLoggedOut();
    debugPrint('[SmartNPS360][AuthRepo] cleared auth (secure storage)');
  }

  Future<void> saveAccessToken(String token) async {
    if (token.isEmpty) return;
    await _storage.write(key: _kAccessToken, value: token);
    _cachedAccessToken = token;
    _accessTokenAccessibilityMigrated = true;
    debugPrint('[SmartNPS360][AuthRepo] saved access token (secure storage)');
  }

  /// Preloads the access token while the device is unlocked (e.g. app launch).
  Future<void> warmAccessTokenCache() async {
    await getAccessToken();
  }

  Future<String?> getAccessToken() async {
    final cached = _cachedAccessToken;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    try {
      final token = await _storage.read(key: _kAccessToken);
      if (token == null || token.isEmpty) {
        _cachedAccessToken = null;
        return null;
      }

      _cachedAccessToken = token;
      unawaited(_migrateAccessTokenAccessibility(token));
      return token;
    } on PlatformException catch (e) {
      if (_isKeychainInteractionNotAllowed(e)) {
        return _cachedAccessToken;
      }
      rethrow;
    }
  }

  Future<void> _migrateAccessTokenAccessibility(String token) async {
    if (_accessTokenAccessibilityMigrated) return;

    try {
      await _storage.write(key: _kAccessToken, value: token);
      _accessTokenAccessibilityMigrated = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[SmartNPS360][AuthRepo] access token accessibility migration failed: $e',
        );
      }
    }
  }

  static bool _isKeychainInteractionNotAllowed(PlatformException e) {
    final code = e.code.trim();
    if (code == '-25308') return true;

    final details = e.details?.toString() ?? '';
    return details.contains('-25308') ||
        (e.message?.contains('User interaction is not allowed') ?? false);
  }

  Future<String?> getRefreshToken() => _storage.read(key: _kRefreshToken);

  Future<Map<String, dynamic>?> getStoredUser() async {
    final json = await _storage.read(key: _kUserJson);
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  /// Resolves the active officer account id from memory or secure storage.
  Future<String?> getOfficerAccountId() async {
    final user = await getCurrentUser();
    if (user == null) return null;
    return extractOfficerAccountId(user);
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    final live = AuthState.instance.user.value;
    if (live != null && live.isNotEmpty) {
      return Map<String, dynamic>.from(live);
    }
    return getStoredUser();
  }

  /// Common login payload keys for the officer primary key.
  static String? extractOfficerAccountId(Map<String, dynamic> user) {
    const directKeys = [
      'id',
      'officer_id',
      'officerId',
      'employee_id',
      'employeeId',
      'employee_no',
      'employeeNo',
      'user_id',
      'userId',
    ];
    for (final key in directKeys) {
      final value = user[key];
      if (value == null) continue;
      final id = value.toString().trim();
      if (id.isNotEmpty) return id;
    }

    for (final nestedKey in ['profile', 'officer', 'user']) {
      final nested = user[nestedKey];
      if (nested is Map) {
        final id = extractOfficerAccountId(Map<String, dynamic>.from(nested));
        if (id != null) return id;
      }
    }
    return null;
  }

  String _safeEncode(Map<String, dynamic> user) {
    // Keep simple for now; we only need persistence for debugging.
    // If the payload is huge, backend "/me" should be used instead.
    try {
      return jsonEncode(user);
    } catch (_) {
      return jsonEncode({'raw': user.toString()});
    }
  }
}
