import 'package:flutter/foundation.dart';

class AuthState {
  AuthState._();

  static final AuthState instance = AuthState._();

  /// User profile data coming from the WebView (e.g. id, name, roles).
  final ValueNotifier<Map<String, dynamic>?> user =
      ValueNotifier<Map<String, dynamic>?>(null);

  /// Auth/session data coming from the WebView (e.g. access/refresh token, expiry).
  ///
  /// Keep tokens out of logs and UI by default; use this only where needed
  /// (e.g. native API calls, background uploads).
  final ValueNotifier<Map<String, dynamic>?> session =
      ValueNotifier<Map<String, dynamic>?>(null);

  bool get isLoggedIn => user.value != null;

  void setLoggedInUser(Map<String, dynamic> payload) {
    user.value = Map<String, dynamic>.from(payload);
    debugPrint('[SmartNPS360][Auth] logged-in user=${_safeUserForLog(user.value)}');
  }

  void setSession(Map<String, dynamic> payload) {
    session.value = Map<String, dynamic>.from(payload);
    debugPrint('[SmartNPS360][Auth] session updated=${_safeSessionForLog(session.value)}');
  }

  void clear() {
    user.value = null;
    session.value = null;
    debugPrint('[SmartNPS360][Auth] logged out (cleared user)');
  }

  Map<String, dynamic>? _safeUserForLog(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    final copy = Map<String, dynamic>.from(raw);
    copy.remove('token');
    copy.remove('accessToken');
    copy.remove('refreshToken');
    copy.remove('jwt');
    copy.remove('password');
    return copy;
  }

  Map<String, dynamic>? _safeSessionForLog(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    final copy = Map<String, dynamic>.from(raw);
    copy.remove('token');
    copy.remove('accessToken');
    copy.remove('refreshToken');
    copy.remove('jwt');
    copy.remove('idToken');
    return copy;
  }
}
