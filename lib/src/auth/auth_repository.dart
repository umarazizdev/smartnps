import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class AuthRepository {
  AuthRepository._();

  static final AuthRepository instance = AuthRepository._();

  static const _storage = FlutterSecureStorage();

  static const _kAccessToken = 'auth.access_token';
  static const _kRefreshToken = 'auth.refresh_token';
  static const _kUserJson = 'auth.user_json';

  Future<void> saveLogin({
    required Map<String, dynamic> user,
    String? accessToken,
    String? refreshToken,
  }) async {
    await _storage.write(key: _kUserJson, value: _safeEncode(user));
    if (accessToken != null && accessToken.isNotEmpty) {
      await _storage.write(key: _kAccessToken, value: accessToken);
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: _kRefreshToken, value: refreshToken);
    }
    debugPrint('[SmartNPS360][AuthRepo] saved login (secure storage)');
  }

  Future<void> clear() async {
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);
    await _storage.delete(key: _kUserJson);
    debugPrint('[SmartNPS360][AuthRepo] cleared auth (secure storage)');
  }

  Future<void> saveAccessToken(String token) async {
    if (token.isEmpty) return;
    await _storage.write(key: _kAccessToken, value: token);
    debugPrint('[SmartNPS360][AuthRepo] saved access token (secure storage)');
  }

  Future<String?> getAccessToken() => _storage.read(key: _kAccessToken);

  Future<String?> getRefreshToken() => _storage.read(key: _kRefreshToken);

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
