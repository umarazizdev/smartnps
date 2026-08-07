import 'package:flutter/foundation.dart';

import '../background/location/background_location_uploader.dart';
import '../background/duty/duty_heartbeat_service.dart';
import '../permissions/native_permission_status_service.dart';
import '../push/notifications/push_notification_service.dart';
import '../utilities/app_config.dart';
import 'auth_repository.dart';
import 'auth_state.dart';

class AuthSessionManager {
  AuthSessionManager._();

  static bool isLoginRoute(Uri? uri) => AppConfig.isLoginRoute(uri);

  static bool isOfficerApplicationUrl(Uri? uri) =>
      AppConfig.isOfficerApplicationUrl(uri);

  static Future<void> clearNativeSession({bool deletePushToken = false}) async {
    if (kDebugMode) {
      debugPrint('[AuthSessionManager] logout phase 1: instant UI flags');
    }
    await AuthRepository.instance.setOfficerLoggedIn(false);
    AuthState.instance.clear();
    await DutyHeartbeatService.instance.finalizeLogoutInstant();

    if (kDebugMode && deletePushToken) {
      debugPrint(
        '[AuthSessionManager] skip FCM/APNs delete on logout (temporarily disabled)',
      );
    }

    if (kDebugMode) {
      debugPrint(
        '[AuthSessionManager] logout phase 2: drain GPS batches (token kept)',
      );
    }
    await BackgroundLocationUploader.drainAndDiscardOnLogoutStatic();

    if (kDebugMode) {
      debugPrint(
        '[AuthSessionManager] logout phase 3: clear auth token '
        '(FCM/APNs kept)',
      );
    }
    NativePermissionStatusService.instance.resetSyncState();
    await AuthRepository.instance.clear();
    PushNotificationService.instance.setIosSessionAuth();

    if (kDebugMode) {
      debugPrint('[AuthSessionManager] logout complete (token cleared)');
    }
  }
}
