import 'package:flutter/foundation.dart';

import '../background/background_location_uploader.dart';
import '../background/duty_heartbeat_service.dart';
import '../permissions/native_permission_status_service.dart';
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

  static bool isLogoutRoute(Uri? uri) {
    if (uri == null) return false;
    if (!AppConfig.isAllowedHost(uri.host)) return false;

    final path = uri.path.toLowerCase();
    return path.contains('officer/logout') || path.endsWith('/logout');
  }

  /// Authenticated officer application surface (not login/logout/admin).
  static bool isOfficerApplicationUrl(Uri? uri) {
    if (uri == null) return false;
    if (!AppConfig.isAllowedHost(uri.host)) return false;
    if (isLoginRoute(uri) || isLogoutRoute(uri)) return false;

    final path = uri.path.toLowerCase();
    return path.contains('/officer') || path.startsWith('officer');
  }

  /// Logout phases:
  /// 1. Instant — logged-out flag + stop tracking + start FCM delete
  /// 2. Drain — flush/discard GPS batches (token still in secure storage)
  /// 3. Final — clear bearer token and credentials
  static Future<void> clearNativeSession({bool deletePushToken = true}) async {
    if (kDebugMode) {
      debugPrint('[AuthSessionManager] logout phase 1: instant UI flags');
    }
    await AuthRepository.instance.setOfficerLoggedIn(false);
    AuthState.instance.clear();
    await DutyHeartbeatService.instance.finalizeLogoutInstant();

    final fcmDelete = deletePushToken
        ? PushNotificationService.instance.deletePushToken()
        : Future<void>.value();

    if (kDebugMode) {
      debugPrint(
        '[AuthSessionManager] logout phase 2: drain GPS batches (token kept)',
      );
    }
    await BackgroundLocationUploader.drainAndDiscardOnLogoutStatic();

    if (kDebugMode) {
      debugPrint(
        '[AuthSessionManager] logout phase 3: await FCM + clear token',
      );
    }
    await fcmDelete;
    NativePermissionStatusService.instance.resetSyncState();
    await AuthRepository.instance.clear();
    PushNotificationService.instance.setIosSessionAuth();

    if (kDebugMode) {
      debugPrint('[AuthSessionManager] logout complete (token cleared)');
    }
  }
}
