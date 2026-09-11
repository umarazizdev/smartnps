import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_repository.dart';

class CrashlyticsIdentity {
  CrashlyticsIdentity._();

  static Future<void> setFromUser(Map<String, dynamic>? user) async {
    try {
      final id = user == null
          ? ''
          : (AuthRepository.extractOfficerAccountId(user) ?? '');
      await FirebaseCrashlytics.instance.setUserIdentifier(id);
      if (kDebugMode && id.isNotEmpty) {
        debugPrint('[CrashlyticsIdentity] setUserIdentifier=$id');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CrashlyticsIdentity] setUserIdentifier failed: $e');
      }
    }
  }

  static Future<void> clear() => setFromUser(null);

  static Future<void> syncFromStoredSession() async {
    try {
      if (!await AuthRepository.instance.isOfficerLoggedIn()) {
        await clear();
        return;
      }
      final user = await AuthRepository.instance.getStoredUser();
      await setFromUser(user);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CrashlyticsIdentity] syncFromStoredSession failed: $e');
      }
    }
  }
}
