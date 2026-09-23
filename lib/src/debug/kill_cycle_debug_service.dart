import 'dart:io';

import 'package:flutter/services.dart';

/// Reads native kill-cycle debug snapshot for the Debug Env screen (TestFlight).
class KillCycleDebugService {
  KillCycleDebugService._();

  static const MethodChannel _settingsChannel = MethodChannel(
    'com.smartnps360.app/settings',
  );

  static Future<KillCycleDebugSnapshot> loadSnapshot() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const KillCycleDebugSnapshot.empty();
    }
    try {
      final raw = await _settingsChannel.invokeMethod<dynamic>(
        'getAppKillCycleDebugSnapshot',
      );
      if (raw is Map) {
        return KillCycleDebugSnapshot.fromMap(raw);
      }
    } catch (_) {}
    return const KillCycleDebugSnapshot.empty();
  }

  static Future<void> clearLogs() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _settingsChannel.invokeMethod<dynamic>('clearAppKillCycleDebugLogs');
    } catch (_) {}
  }

  static Future<void> append(String message) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    try {
      await _settingsChannel.invokeMethod<dynamic>(
        'appendAppKillCycleDebugLog',
        {'message': trimmed},
      );
    } catch (_) {}
  }
}

class KillCycleDebugSnapshot {
  const KillCycleDebugSnapshot({
    required this.platform,
    required this.onDuty,
    required this.unpaidBreak,
    required this.slcArmed,
    required this.hasAccessToken,
    required this.notificationAuth,
    required this.killedAt,
    required this.openedAt,
    required this.backgroundAt,
    required this.wakeService,
    required this.wakeAt,
    required this.wakeDetail,
    required this.killedUploaded,
    required this.logs,
  });

  const KillCycleDebugSnapshot.empty()
      : platform = '',
        onDuty = false,
        unpaidBreak = false,
        slcArmed = false,
        hasAccessToken = false,
        notificationAuth = 'unknown',
        killedAt = '',
        openedAt = '',
        backgroundAt = '',
        wakeService = '',
        wakeAt = '',
        wakeDetail = '',
        killedUploaded = false,
        logs = const [];

  final String platform;
  final bool onDuty;
  final bool unpaidBreak;
  final bool slcArmed;
  final bool hasAccessToken;
  final String notificationAuth;
  final String killedAt;
  final String openedAt;
  final String backgroundAt;
  final String wakeService;
  final String wakeAt;
  final String wakeDetail;
  final bool killedUploaded;
  final List<String> logs;

  factory KillCycleDebugSnapshot.fromMap(Map<dynamic, dynamic> map) {
    bool asBool(dynamic v) => v == true || v == 1 || v == 'true';
    String asString(dynamic v) => v?.toString() ?? '';
    final rawLogs = map['logs'];
    final logs = <String>[];
    if (rawLogs is List) {
      for (final line in rawLogs) {
        final text = line?.toString().trim();
        if (text != null && text.isNotEmpty) logs.add(text);
      }
    }
    return KillCycleDebugSnapshot(
      platform: asString(map['platform']),
      onDuty: asBool(map['onDuty']),
      unpaidBreak: asBool(map['unpaidBreak']),
      slcArmed: asBool(map['slcArmed']),
      hasAccessToken: asBool(map['hasAccessToken']),
      notificationAuth: asString(map['notificationAuth']),
      killedAt: asString(map['killed_at']),
      openedAt: asString(map['opened_at']),
      backgroundAt: asString(map['background_at']),
      wakeService: asString(map['wake_service']),
      wakeAt: asString(map['wake_at']),
      wakeDetail: asString(map['wake_detail']),
      killedUploaded: asBool(map['killed_uploaded']),
      logs: logs,
    );
  }

  String toCopyText() {
    final buffer = StringBuffer()
      ..writeln('platform=$platform')
      ..writeln('onDuty=$onDuty unpaidBreak=$unpaidBreak slcArmed=$slcArmed')
      ..writeln('hasAccessToken=$hasAccessToken notificationAuth=$notificationAuth')
      ..writeln('killed_at=$killedAt')
      ..writeln('opened_at=$openedAt')
      ..writeln('background_at=$backgroundAt')
      ..writeln('wake_service=$wakeService')
      ..writeln('wake_at=$wakeAt')
      ..writeln('wake_detail=$wakeDetail')
      ..writeln('killed_uploaded=$killedUploaded')
      ..writeln('--- logs (${logs.length}) ---');
    for (final line in logs) {
      buffer.writeln(line);
    }
    return buffer.toString();
  }
}
