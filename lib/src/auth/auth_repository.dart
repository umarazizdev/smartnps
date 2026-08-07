import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../utilities/app_config.dart';
import '../utilities/app_upgrade_reconciler.dart';
import 'auth_state.dart';
import 'location_disclosure_account_sync.dart';

class AuthRepository {
  AuthRepository._();

  static final AuthRepository instance = AuthRepository._();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static String? _cachedAccessToken;
  static String? _cachedRefreshToken;
  static DateTime? _cachedAccessTokenExpiresAt;
  static bool? _cachedOfficerLoggedIn;
  static bool _accessTokenAccessibilityMigrated = false;

  static const _kAccessToken = 'auth.access_token';
  static const _kRefreshToken = 'auth.refresh_token';
  static const _kAccessTokenExpiresAt = 'auth.access_token_expires_at';
  static const _kUserJson = 'auth.user_json';
  static const _kOfficerLoggedIn = 'auth.officer_logged_in';

  static const _refreshRetryKey = '_auth_refresh_retried';

  static final Dio _refreshDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  Future<void> Function()? onRefreshSessionExpired;

  Completer<String?>? _refreshInFlight;

  Future<void> saveLogin({
    required Map<String, dynamic> user,
    String? accessToken,
    String? refreshToken,
  }) async {
    _cacheLoginState(
      accessToken: accessToken,
      refreshToken: refreshToken,
      officerLoggedIn: true,
    );

    final userSaved = await _secureWrite(_kUserJson, _safeEncode(user));
    var accessSaved = true;
    var refreshSaved = true;
    if (accessToken != null && accessToken.isNotEmpty) {
      accessSaved = await _secureWrite(_kAccessToken, accessToken);
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      refreshSaved = await _secureWrite(_kRefreshToken, refreshToken);
    }
    final flagSaved = await setOfficerLoggedIn(true);

    await LocationDisclosureAccountSync.onLoginResolved();

    if (userSaved && accessSaved && refreshSaved && flagSaved) {
      debugPrint('[SmartNPS360][AuthRepo] saved login (secure storage)');
    } else if (kDebugMode) {
      debugPrint(
        '[SmartNPS360][AuthRepo] saved login (memory cache; keychain partial '
        'user=$userSaved access=$accessSaved refresh=$refreshSaved flag=$flagSaved)',
      );
    }
  }

  void _cacheLoginState({
    String? accessToken,
    String? refreshToken,
    bool? officerLoggedIn,
  }) {
    if (accessToken != null && accessToken.isNotEmpty) {
      _cachedAccessToken = accessToken;
      _accessTokenAccessibilityMigrated = true;
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      _cachedRefreshToken = refreshToken;
    }
    if (officerLoggedIn != null) {
      _cachedOfficerLoggedIn = officerLoggedIn;
    }
  }

  Future<bool> setOfficerLoggedIn(bool value) async {
    _cachedOfficerLoggedIn = value;
    if (value) {
      return _secureWrite(_kOfficerLoggedIn, 'true');
    }
    return _secureDelete(_kOfficerLoggedIn);
  }

  Future<bool> isOfficerLoggedIn() async {
    if (_cachedOfficerLoggedIn == true) return true;
    try {
      final value = await _storage.read(key: _kOfficerLoggedIn);
      final loggedIn = value == 'true';
      if (loggedIn) _cachedOfficerLoggedIn = true;
      return loggedIn;
    } on PlatformException catch (e) {
      if (_isKeychainInteractionNotAllowed(e)) {
        return _cachedOfficerLoggedIn ?? false;
      }
      rethrow;
    }
  }

  Future<void> clear() async {
    await _secureDelete(_kAccessToken);
    await _secureDelete(_kRefreshToken);
    await _secureDelete(_kAccessTokenExpiresAt);
    await _secureDelete(_kUserJson);
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _cachedAccessTokenExpiresAt = null;
    _cachedOfficerLoggedIn = false;
    _accessTokenAccessibilityMigrated = false;
    await setOfficerLoggedIn(false);
    LocationDisclosureAccountSync.onLoggedOut();
    debugPrint('[SmartNPS360][AuthRepo] cleared auth (secure storage)');
  }

  Future<void> saveAccessToken(String token) async {
    if (token.isEmpty) return;
    _cachedAccessToken = token;
    _accessTokenAccessibilityMigrated = true;
    final saved = await _secureWrite(_kAccessToken, token);
    debugPrint(
      saved
          ? '[SmartNPS360][AuthRepo] saved access token (secure storage)'
          : '[SmartNPS360][AuthRepo] saved access token (memory cache only)',
    );
  }

  Future<void> saveRefreshToken(String token) async {
    if (token.isEmpty) return;
    _cachedRefreshToken = token;
    final saved = await _secureWrite(_kRefreshToken, token);
    debugPrint(
      saved
          ? '[SmartNPS360][AuthRepo] saved refresh token (secure storage)'
          : '[SmartNPS360][AuthRepo] saved refresh token (memory cache only)',
    );
  }

  Future<bool> _secureWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      return true;
    } on PlatformException catch (e) {
      if (!_isKeychainDuplicateItem(e)) {
        if (kDebugMode) {
          debugPrint(
            '[SmartNPS360][AuthRepo] keychain write failed key=$key code=${e.code} ${e.message}',
          );
        }
        return false;
      }

      try {
        await _storage.delete(key: key);
        await _storage.write(key: key, value: value);
        if (kDebugMode) {
          debugPrint(
            '[SmartNPS360][AuthRepo] keychain write recovered after delete key=$key',
          );
        }
        return true;
      } on PlatformException catch (retry) {
        if (kDebugMode) {
          debugPrint(
            '[SmartNPS360][AuthRepo] keychain write failed after delete '
            'key=$key code=${retry.code} ${retry.message}',
          );
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SmartNPS360][AuthRepo] keychain write failed key=$key: $e');
      }
      return false;
    }
  }

  Future<bool> _secureDelete(String key) async {
    try {
      await _storage.delete(key: key);
      return true;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[SmartNPS360][AuthRepo] keychain delete failed key=$key code=${e.code}',
        );
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SmartNPS360][AuthRepo] keychain delete failed key=$key: $e');
      }
      return false;
    }
  }

  static bool _isKeychainDuplicateItem(PlatformException e) {
    final code = e.code.trim();
    if (code == '-25299') return true;

    final message = e.message?.toLowerCase() ?? '';
    return message.contains('already exists') ||
        (e.details?.toString().contains('-25299') ?? false);
  }

  Future<void> saveTokensFromAuthResponse(Map<String, dynamic> body) async {
    final map = _unwrapAuthPayload(body);
    final access = extractAccessToken(map);
    final refresh = extractRefreshToken(map);
    if (access != null && access.isNotEmpty) {
      await saveAccessToken(access);
    }
    if (refresh != null && refresh.isNotEmpty) {
      await saveRefreshToken(refresh);
    }
    await _persistAccessTokenExpiry(map);
    if (access != null && access.isNotEmpty) {
      AuthState.instance.setSession(sessionFromAuthMap(map));
    }
  }

  Future<void> saveLoginFromAuthResponse({
    required Map<String, dynamic> map,
    Map<String, dynamic>? user,
  }) async {
    final accessToken = extractAccessToken(map);
    final refreshToken = extractRefreshToken(map);
    _cacheLoginState(
      accessToken: accessToken,
      refreshToken: refreshToken,
      officerLoggedIn: true,
    );
    AuthState.instance.setSession(sessionFromAuthMap(map));

    final resolvedUser = user ?? extractUser(map);
    if (resolvedUser != null && resolvedUser.isNotEmpty) {
      AuthState.instance.setLoggedInUser(resolvedUser);
      await saveLogin(
        user: resolvedUser,
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    } else {
      await saveTokensFromAuthResponse(map);
    }
    await _persistAccessTokenExpiry(map);
    AppUpgradeReconciler.endPostUpgradeAuthGrace();
  }

  bool get hasCachedAccessToken =>
      _cachedAccessToken != null && _cachedAccessToken!.isNotEmpty;

  static Map<String, dynamic>? extractUser(Map<String, dynamic>? map) {
    if (map == null) return null;
    final rawUser = map['user'] ?? map['profile'];
    if (rawUser is Map) {
      return Map<String, dynamic>.from(rawUser);
    }
    return null;
  }

  static Map<String, dynamic> mergeAuthPayload(
    Map<String, dynamic> payload, {
    Map<String, dynamic>? session,
  }) {
    final merged = Map<String, dynamic>.from(session ?? const {});
    merged.addAll(payload);
    return _unwrapAuthPayload(merged);
  }

  static Map<String, dynamic> sessionFromAuthMap(Map<String, dynamic> map) {
    final session = <String, dynamic>{};
    final access = extractAccessToken(map);
    final refresh = extractRefreshToken(map);
    if (access != null && access.isNotEmpty) {
      session['accessToken'] = access;
      session['access_token'] = access;
      session['token'] = access;
    }
    if (refresh != null && refresh.isNotEmpty) {
      session['refreshToken'] = refresh;
      session['refresh_token'] = refresh;
    }
    for (final key in const [
      'token_type',
      'expires_in',
      'expires_at',
      'refresh_expires_in',
      'refresh_expires_at',
    ]) {
      if (map.containsKey(key)) session[key] = map[key];
    }
    return session;
  }

  static DateTime? parseAccessTokenExpiry(Map<String, dynamic> map) {
    final expiresAt = map['expires_at']?.toString();
    if (expiresAt != null && expiresAt.isNotEmpty) {
      return DateTime.tryParse(expiresAt);
    }
    final expiresIn = map['expires_in'];
    if (expiresIn is num && expiresIn > 0) {
      return DateTime.now().add(Duration(seconds: expiresIn.round()));
    }
    return null;
  }

  Future<void> _persistAccessTokenExpiry(Map<String, dynamic> map) async {
    final expiresAt = parseAccessTokenExpiry(map);
    if (expiresAt == null) return;
    _cachedAccessTokenExpiresAt = expiresAt;
    await _secureWrite(
      _kAccessTokenExpiresAt,
      expiresAt.toUtc().toIso8601String(),
    );
  }

  Future<DateTime?> _getAccessTokenExpiresAt() async {
    final cached = _cachedAccessTokenExpiresAt;
    if (cached != null) return cached;

    final raw = await _storage.read(key: _kAccessTokenExpiresAt);
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    _cachedAccessTokenExpiresAt = parsed;
    return parsed;
  }

  Future<bool> _isAccessTokenExpired() async {
    final expiresAt = await _getAccessTokenExpiresAt();
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(
      expiresAt.subtract(const Duration(seconds: 60)),
    );
  }

  static String? extractAccessToken(Map<String, dynamic>? map) {
    if (map == null) return null;
    return (map['access_token'] ??
            map['accessToken'] ??
            map['token'] ??
            map['jwt'])
        ?.toString();
  }

  static String? extractRefreshToken(Map<String, dynamic>? map) {
    if (map == null) return null;
    return (map['refresh_token'] ?? map['refreshToken'])?.toString();
  }

  static Map<String, dynamic> _unwrapAuthPayload(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return body;
  }

  Future<void> warmAccessTokenCache() async {
    await getAccessToken();
    await getRefreshToken();
    await isOfficerLoggedIn();
  }

  Future<String?> ensureValidAccessToken() async {
    final access = await getAccessToken();
    if (access != null && access.isNotEmpty) {
      if (!await _isAccessTokenExpired()) return access;
      return refreshAccessToken();
    }
    return refreshAccessToken();
  }

  Future<String?> refreshAccessToken() async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight.future;

    final completer = Completer<String?>();
    _refreshInFlight = completer;

    try {
      final refreshToken = await getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        if (kDebugMode) {
          debugPrint('[SmartNPS360][AuthRepo] refresh skipped (no refresh token)');
        }
        completer.complete(null);
        return null;
      }

      final response = await _refreshDio.postUri(
        Uri.parse(AppConfig.refreshTokenUrl),
        data: {'refresh_token': refreshToken},
      );

      final statusCode = response.statusCode ?? 0;
      ApiClient.logHttpResult('POST', Uri.parse(AppConfig.refreshTokenUrl), statusCode);
      if (statusCode < 200 || statusCode >= 300) {
        if (statusCode == 401 || statusCode == 403) {
          await _notifyRefreshSessionExpired();
        }
        completer.complete(null);
        return null;
      }

      final body = response.data;
      if (body is! Map) {
        completer.complete(null);
        return null;
      }

      await saveTokensFromAuthResponse(Map<String, dynamic>.from(body));
      AppUpgradeReconciler.endPostUpgradeAuthGrace();
      final access = await getAccessToken();
      completer.complete(access);
      return access;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode ?? 0;
      ApiClient.logHttpError(
        'POST',
        Uri.parse(AppConfig.refreshTokenUrl),
        statusCode,
        e.response?.data?.toString() ?? e.message ?? e.type.name,
      );
      if (statusCode == 401 || statusCode == 403) {
        await _notifyRefreshSessionExpired();
      }
      completer.complete(null);
      return null;
    } catch (e) {
      ApiClient.logHttpError(
        'POST',
        Uri.parse(AppConfig.refreshTokenUrl),
        0,
        e.toString(),
      );
      completer.complete(null);
      return null;
    } finally {
      if (identical(_refreshInFlight, completer)) {
        _refreshInFlight = null;
      }
    }
  }

  bool _logoutAfterRefreshFailureInFlight = false;

  Future<void> _notifyRefreshSessionExpired() async {
    if (_logoutAfterRefreshFailureInFlight) return;
    if (AppUpgradeReconciler.shouldSuppressRefreshSessionLogout) {
      if (kDebugMode) {
        debugPrint(
          '[SmartNPS360][AuthRepo] refresh 401/403 soft-failed '
          '(post-upgrade grace; storage kept)',
        );
      }
      return;
    }
    _logoutAfterRefreshFailureInFlight = true;
    try {
      final handler = onRefreshSessionExpired;
      if (handler != null) {
        await handler();
        return;
      }
      if (kDebugMode) {
        debugPrint(
          '[SmartNPS360][AuthRepo] refresh session expired (no logout handler)',
        );
      }
    } finally {
      _logoutAfterRefreshFailureInFlight = false;
    }
  }

  static bool isRefreshRequest(RequestOptions options) {
    return options.uri.toString().contains('/api/auth/refresh');
  }

  static bool hasRefreshRetry(RequestOptions options) {
    return options.extra[_refreshRetryKey] == true;
  }

  static void markRefreshRetry(RequestOptions options) {
    options.extra[_refreshRetryKey] = true;
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

    final migrated = await _secureWrite(_kAccessToken, token);
    if (migrated) {
      _accessTokenAccessibilityMigrated = true;
    } else if (kDebugMode) {
      debugPrint(
        '[SmartNPS360][AuthRepo] access token accessibility migration skipped',
      );
    }
  }

  static bool _isKeychainInteractionNotAllowed(PlatformException e) {
    final code = e.code.trim();
    if (code == '-25308') return true;

    final details = e.details?.toString() ?? '';
    return details.contains('-25308') ||
        (e.message?.contains('User interaction is not allowed') ?? false);
  }

  Future<String?> getRefreshToken() async {
    final cached = _cachedRefreshToken;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    try {
      final token = await _storage.read(key: _kRefreshToken);
      if (token == null || token.isEmpty) {
        _cachedRefreshToken = null;
        return null;
      }
      _cachedRefreshToken = token;
      return token;
    } on PlatformException catch (e) {
      if (_isKeychainInteractionNotAllowed(e)) {
        return _cachedRefreshToken;
      }
      rethrow;
    }
  }

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

    try {
      return jsonEncode(user);
    } catch (_) {
      return jsonEncode({'raw': user.toString()});
    }
  }
}
