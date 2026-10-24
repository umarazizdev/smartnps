import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../debug/session_debug_logger.dart';
import 'app_config.dart';

const JsonEncoder _debugJsonEncoder = JsonEncoder.withIndent('  ');

void logDebugJson(String name, Object? value) {
  if (!kDebugMode) return;
  developer.log(_encodeDebugJson(value), name: name);
}

void logJsBridgePayload(String name, Object? value) {
  if (!AppConfig.enablePatrolLogDebugLog) return;
  logDebugJson(name, value);
}

String _encodeDebugJson(Object? value) {
  try {
    return _debugJsonEncoder.convert(_jsonSafe(value));
  } catch (_) {
    return '$value';
  }
}

Object? _jsonSafe(Object? value, [int depth = 0]) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (depth > 32) return value.toString();
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _jsonSafe(entry.value, depth + 1),
    };
  }
  if (value is Iterable) {
    return <Object?>[for (final item in value) _jsonSafe(item, depth + 1)];
  }
  try {
    final dynamic dynamicValue = value;
    return _jsonSafe(dynamicValue.toJson(), depth + 1);
  } catch (_) {
    return value.toString();
  }
}

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
