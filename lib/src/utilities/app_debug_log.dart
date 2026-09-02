import 'package:flutter/foundation.dart';

import 'app_config.dart';

void locationDebugLog(String message) {
  if (!AppConfig.enablePingDebugLog) return;
  if (!kDebugMode) return;
  debugPrint(message);
}

void batchDebugLog(String message) {
  if (!AppConfig.enableBatchDebugLog) return;
  if (!kDebugMode) return;
  debugPrint(message);
}

void dutyHeartbeatDebugLog(String message) {
  if (!AppConfig.enableDutyHeartbeatDebugLog) return;
  if (!kDebugMode) return;
  debugPrint(message);
}
