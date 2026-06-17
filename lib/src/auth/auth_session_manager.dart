import 'package:flutter/foundation.dart';

import '../background/duty_heartbeat_service.dart';
import '../push/push_notification_service.dart';
import '../utilities/app_config.dart';
import 'auth_repository.dart';
import 'auth_state.dart';

class AuthSessionManager {
  AuthSessionManager._();

  static bool isLoginRoute(Uri? uri) {
    if (uri == null) return false;
    if (!AppConfig.isAllowedHost(uri.host)) return false;

    final path = uri.path.toLowerCase();
    if (path.isEmpty || path == '/' || uri.toString() == AppConfig.initialUrl) {
      return true;
    }

    return path.contains('officer/login') ||
        path.contains('officer/sign-in') ||
        path.contains('officer/signin') ||
        path.contains('officer/sign_up') ||
        path.contains('officer/sign-up') ||
        path.contains('officer/signup') ||
        path.contains('officer/register');
  }

  /// Clears native bearer auth when the WebView shows a login/signup screen.
  static Future<void> clearNativeSessionIfLoginScreen(Uri? uri) async {
    if (!isLoginRoute(uri)) return;

    final token = await AuthRepository.instance.getAccessToken();
    if (token == null || token.isEmpty) return;

    await clearNativeSession(deletePushToken: true);
    if (kDebugMode) {
      debugPrint(
        '[AuthSessionManager] cleared bearer token (login screen: ${uri?.path})',
      );
    }
  }

  static Future<void> clearNativeSession({bool deletePushToken = true}) async {
    if (deletePushToken) {
      await PushNotificationService.instance.deletePushToken();
    }

    AuthState.instance.clear();
    await DutyHeartbeatService.instance.stop();
    await AuthRepository.instance.clear();
    PushNotificationService.instance.setIosSessionAuth();
  }
}
