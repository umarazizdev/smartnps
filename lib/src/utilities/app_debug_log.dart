import 'package:flutter/foundation.dart';

import '../debug/session_debug_logger.dart';
import 'app_config.dart';

void locationDebugLog(String message) {
  SessionDebugLogger.instance.logIfErrorLike(
    SessionDebugCategory.duty,
    message,
  );
  if (!AppConfig.enablePingDebugLog) return;
  if (!kDebugMode) return;
  debugPrint(message);
}

void batchDebugLog(String message) {
  SessionDebugLogger.instance.logIfErrorLike(
    SessionDebugCategory.duty,
    message,
  );
  if (!AppConfig.enableBatchDebugLog) return;
  if (!kDebugMode) return;
  debugPrint(message);
}

void dutyHeartbeatDebugLog(String message) {
  SessionDebugLogger.instance.logIfErrorLike(
    SessionDebugCategory.duty,
    message,
  );
  if (!AppConfig.enableDutyHeartbeatDebugLog) return;
  if (!kDebugMode) return;
  debugPrint(message);
}

void patrolLogDebugLog(String message) {
  SessionDebugLogger.instance.logIfErrorLike(
    SessionDebugCategory.uploads,
    message,
  );
  if (!AppConfig.enablePatrolLogDebugLog) return;
  if (!kDebugMode) return;
  debugPrint(message);
}
