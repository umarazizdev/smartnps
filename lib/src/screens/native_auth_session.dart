import 'package:smartnps360/src/auth/auth_repository.dart';
import 'package:smartnps360/src/auth/auth_state.dart';
import 'package:smartnps360/src/screens/app_storage.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

class NativeAuthSession {
  NativeAuthSession._();

  static final NativeAuthSession instance = NativeAuthSession._();

  String? _accessToken;

  String? get accessTokenSync {
    final token = _accessToken?.trim();
    if (token == null || token.isEmpty) return null;
    return token;
  }

  bool get hasValidSessionSync {
    final loggedIn = box.read(isLogin) == true;
    final token = accessTokenSync;
    return loggedIn && token != null && token.isNotEmpty;
  }

  Future<void> hydrate() async {
    await _migrateLegacyGetStorageTokenIfNeeded();

    final loggedIn = await AuthRepository.instance.isOfficerLoggedIn();
    final token = await AuthRepository.instance.getAccessToken();
    final user = await AuthRepository.instance.getStoredUser();

    _accessToken = (token != null && token.trim().isNotEmpty)
        ? token.trim()
        : null;

    if (!loggedIn || _accessToken == null) {
      _clearGetStorageAuthMirror();
      box.remove(appToken);
      return;
    }

    box.write(isLogin, true);
    box.remove(appToken);

    if (user != null) {
      _mirrorUserToGetStorage(user);
      AuthState.instance.setLoggedInUser(user);
      AuthState.instance.setSession({
        'accessToken': _accessToken,
        'token': _accessToken,
      });
    }
  }

  Future<void> saveSession({
    required Map<String, dynamic> user,
    required String accessToken,
    String? refreshToken,
    String? employeeNo,
    String? password,
    bool rememberCredentials = false,
  }) async {
    final token = accessToken.trim();
    if (token.isEmpty) {
      throw StateError('Access token is required');
    }

    await AuthRepository.instance.saveLogin(
      user: user,
      accessToken: token,
      refreshToken: refreshToken,
    );

    _accessToken = token;
    box.write(isLogin, true);
    box.remove(appToken);
    _mirrorUserToGetStorage(user);

    AuthState.instance.setLoggedInUser(user);
    AuthState.instance.setSession({
      'accessToken': token,
      'token': token,
      if (refreshToken != null && refreshToken.isNotEmpty)
        'refreshToken': refreshToken,
    });

    final employee = (employeeNo ?? '').trim();
    final pass = (password ?? '');
    if (rememberCredentials && employee.isNotEmpty && pass.isNotEmpty) {
      await AuthRepository.instance.saveCredentials(
        employeeNo: employee,
        password: pass,
      );
    } else {
      await AuthRepository.instance.clearStoredCredentials();
    }
  }

  Future<void> clearSession({bool keepNotificationPrefs = true}) async {
    final notif = keepNotificationPrefs
        ? box.read('notificationsEnabled')
        : null;
    final remembered = await AuthRepository.instance.getStoredCredentials();

    await AuthRepository.instance.clear();
    if (remembered != null) {
      await AuthRepository.instance.saveCredentials(
        employeeNo: remembered.employeeNo,
        password: remembered.password,
      );
    }

    AuthState.instance.clear();
    _accessToken = null;

    await box.erase();
    if (notif != null) {
      box.write('notificationsEnabled', notif);
    }
  }

  Future<bool> isLoggedIn() async {
    if (hasValidSessionSync) return true;
    await hydrate();
    return hasValidSessionSync;
  }

  Future<void> _migrateLegacyGetStorageTokenIfNeeded() async {
    final legacyToken = (box.read(appToken) ?? '').toString().trim();
    if (legacyToken.isEmpty) return;

    final existing = await AuthRepository.instance.getAccessToken();
    if (existing != null && existing.trim().isNotEmpty) {
      box.remove(appToken);
      return;
    }

    final storedUser = box.read('userInfo');
    final user = storedUser is Map
        ? Map<String, dynamic>.from(storedUser)
        : <String, dynamic>{
            'id': box.read('userId'),
            'role': box.read(role),
          };

    await AuthRepository.instance.saveLogin(
      user: user,
      accessToken: legacyToken,
    );
    box.remove(appToken);
  }

  void _mirrorUserToGetStorage(Map<String, dynamic> user) {
    final userId = user['id'];
    final userRole = user['role']?.toString() ?? '';
    if (userId != null) {
      box.write('userId', userId);
    }
    box.write('userInfo', user);
    if (userRole.isNotEmpty) {
      box.write(role, userRole);
    }
  }

  void _clearGetStorageAuthMirror() {
    box.write(isLogin, false);
    box.remove('userId');
    box.remove('userInfo');
    box.remove('profileData');
    box.remove(role);
  }
}
