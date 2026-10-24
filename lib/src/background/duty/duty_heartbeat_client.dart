import 'package:dio/dio.dart';

import '../../api/api_client.dart';
import '../../api/api_urls.dart';
import '../../auth/auth_repository.dart';
import '../../utilities/app_debug_log.dart';

class DutyHeartbeatPayload {
  const DutyHeartbeatPayload({
    required this.dutyStatus,
    this.workingStatus,
    this.breakType,
    this.allowedBreakMinutes,
    this.breakPaid,
    this.raw,
  });

  final String? dutyStatus;
  final String? workingStatus;
  final String? breakType;
  final int? allowedBreakMinutes;
  final bool? breakPaid;
  final dynamic raw;

  static const String working = 'working';
  static const String onBreak = 'on_break';
  static const String paid = 'paid';
  static const String unpaid = 'unpaid';

  bool get isOnDuty => dutyStatus == DutyHeartbeatClient.onDuty;
  bool get isOffDuty => dutyStatus == DutyHeartbeatClient.offDuty;

  bool get isOnBreak {
    final value = workingStatus?.trim().toLowerCase();
    if (value == null || value.isEmpty) return false;
    return value == onBreak ||
        value == 'on-break' ||
        value == 'onbreak' ||
        value == 'break';
  }

  bool get isPaidBreak {
    if (breakPaid == true) return true;
    if (breakPaid == false) return false;
    final value = breakType?.trim().toLowerCase();
    if (value == null || value.isEmpty) return false;
    return value == paid || value == 'break_paid';
  }

  bool get isUnpaidBreak {
    if (!isOnBreak) return false;
    if (breakPaid == false) return true;
    if (breakPaid == true) return false;
    final value = breakType?.trim().toLowerCase();
    if (value == null || value.isEmpty) return false;
    return value == unpaid || value == 'break_unpaid';
  }

  bool get allowsLocationTracking => isOnDuty && !isUnpaidBreak;

  int get breakMinutesOrDefault =>
      (allowedBreakMinutes != null && allowedBreakMinutes! > 0)
      ? allowedBreakMinutes!
      : 30;
}

enum DutyHeartbeatFetchOutcome {

  success,

  offline,

  unauthorized,

  httpFailure,

  unrecognizableBody,
}

class DutyHeartbeatFetchResult {
  const DutyHeartbeatFetchResult._(this.outcome, [this.payload]);

  const DutyHeartbeatFetchResult.success(DutyHeartbeatPayload payload)
    : this._(DutyHeartbeatFetchOutcome.success, payload);

  const DutyHeartbeatFetchResult.offline()
    : this._(DutyHeartbeatFetchOutcome.offline);

  const DutyHeartbeatFetchResult.unauthorized()
    : this._(DutyHeartbeatFetchOutcome.unauthorized);

  const DutyHeartbeatFetchResult.httpFailure()
    : this._(DutyHeartbeatFetchOutcome.httpFailure);

  const DutyHeartbeatFetchResult.unrecognizableBody()
    : this._(DutyHeartbeatFetchOutcome.unrecognizableBody);

  final DutyHeartbeatFetchOutcome outcome;
  final DutyHeartbeatPayload? payload;

  bool get allowsOfflineSnapshotFallback =>
      outcome == DutyHeartbeatFetchOutcome.offline ||
      outcome == DutyHeartbeatFetchOutcome.httpFailure;
}

class DutyHeartbeatClient {
  DutyHeartbeatClient._();

  static const String onDuty = 'on_duty';
  static const String offDuty = 'off_duty';

  static Future<String?> fetchDutyStatus() async {
    final payload = await fetchHeartbeat();
    return payload?.dutyStatus;
  }

  static Future<DutyHeartbeatPayload?> fetchHeartbeat() async {
    final result = await fetchHeartbeatResult();
    return result.payload;
  }

  static Future<DutyHeartbeatFetchResult> fetchHeartbeatResult() async {
    ApiClient.instance.ensureAuthInterceptorInstalled();
    final token = await AuthRepository.instance.ensureValidAccessToken();
    if (token == null || token.isEmpty) {
      return const DutyHeartbeatFetchResult.offline();
    }

    try {
      final response = await ApiClient.instance.dio.getUri(
        Uri.parse(ApiUrls.heartbeatUrl),
        options: Options(
          headers: const {'Accept': 'application/json'},
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      return interpretHeartbeatResponse(
        statusCode: response.statusCode,
        body: response.data,
      );
    } catch (e) {
      dutyHeartbeatDebugLog('[DutyHeartbeatClient] heartbeat fetch failed: $e');
      return const DutyHeartbeatFetchResult.offline();
    }
  }

  static DutyHeartbeatFetchResult interpretHeartbeatResponse({
    required int? statusCode,
    required dynamic body,
  }) {
    final code = statusCode ?? 0;
    dutyHeartbeatDebugLog(
      '[DutyHeartbeatClient] heartbeat response '
      'statusCode=$code payload=$body',
    );
    if (code == 401 || code == 403) {
      return const DutyHeartbeatFetchResult.unauthorized();
    }
    if (code < 200 || code >= 300) {
      return const DutyHeartbeatFetchResult.httpFailure();
    }
    final payload = parseHeartbeat(body);
    if (payload == null) {
      dutyHeartbeatDebugLog(
        '[DutyHeartbeatClient] heartbeat 2xx body unrecognizable',
      );
      return const DutyHeartbeatFetchResult.unrecognizableBody();
    }
    return DutyHeartbeatFetchResult.success(payload);
  }

  static String? parseDutyStatus(dynamic body) {
    return parseHeartbeat(body)?.dutyStatus;
  }

  static DutyHeartbeatPayload? parseHeartbeat(dynamic body) {
    if (body == null) return null;

    if (body is String) {
      final duty = _normalizeDutyValue(body);
      if (duty == null) return null;
      return DutyHeartbeatPayload(dutyStatus: duty, raw: body);
    }

    if (body is! Map) return null;
    final map = Map<String, dynamic>.from(body);
    return _parseHeartbeatMap(map, raw: body);
  }

  static DutyHeartbeatPayload? parseAttendanceBridgePayload(dynamic body) {
    final payload = parseHeartbeat(body);
    if (payload == null) return null;
    dutyHeartbeatDebugLog(
      '[DutyHeartbeatClient] attendance bridge parsed '
      'duty=${payload.dutyStatus} working=${payload.workingStatus} '
      'break=${payload.breakType} paid=${payload.breakPaid} '
      'minutes=${payload.allowedBreakMinutes} '
      'unpaidBreak=${payload.isUnpaidBreak} '
      'allowsTracking=${payload.allowsLocationTracking}',
    );
    return payload;
  }

  static DutyHeartbeatPayload? _parseHeartbeatMap(
    Map<String, dynamic> map, {
    required dynamic raw,
  }) {
    String? duty;
    for (final key in const [
      'status',
      'duty_status',
      'dutyStatus',
      'duty',
      'state',
    ]) {
      duty = _normalizeDutyValue(map[key]);
      if (duty != null) break;
    }

    final working = _normalizeWorkingStatus(
      map['working_status'] ?? map['workingStatus'] ?? map['work_status'],
    );
    final breakType = _normalizeBreakType(
      map['break_type'] ?? map['breakType'] ?? map['break'],
    );
    final breakPaid = _normalizeBreakPaid(
      map['break_paid'] ?? map['breakPaid'] ?? map['is_paid_break'],
    );
    final minutes = _normalizeBreakMinutes(
      map['allowed_break_minutes'] ??
          map['allowedBreakMinutes'] ??
          map['break_minutes'] ??
          map['breakMinutes'],
    );

    if (duty == null) {
      for (final nestedKey in const ['data', 'payload', 'result']) {
        final nested = map[nestedKey];
        if (nested is Map) {
          final parsed = _parseHeartbeatMap(
            Map<String, dynamic>.from(nested),
            raw: raw,
          );
          if (parsed != null) return parsed;
        }
      }
      return null;
    }

    return DutyHeartbeatPayload(
      dutyStatus: duty,
      workingStatus: working,
      breakType: breakType,
      allowedBreakMinutes: minutes,
      breakPaid: breakPaid,
      raw: raw,
    );
  }

  static String? _normalizeDutyValue(dynamic value) {
    if (value == null) return null;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == onDuty || normalized == offDuty) return normalized;
    if (normalized == 'onduty' || normalized == 'on-duty') return onDuty;
    if (normalized == 'offduty' || normalized == 'off-duty') return offDuty;
    return null;
  }

  static String? _normalizeWorkingStatus(dynamic value) {
    if (value == null) return null;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized.isEmpty) return null;
    if (normalized == DutyHeartbeatPayload.working ||
        normalized == 'on_duty_working' ||
        normalized == 'active') {
      return DutyHeartbeatPayload.working;
    }
    if (normalized == DutyHeartbeatPayload.onBreak ||
        normalized == 'on-break' ||
        normalized == 'onbreak' ||
        normalized == 'break') {
      return DutyHeartbeatPayload.onBreak;
    }
    return normalized;
  }

  static String? _normalizeBreakType(dynamic value) {
    if (value == null) return null;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized.isEmpty) return null;
    if (normalized == DutyHeartbeatPayload.paid ||
        normalized == 'break_paid') {
      return DutyHeartbeatPayload.paid;
    }
    if (normalized == DutyHeartbeatPayload.unpaid ||
        normalized == 'break_unpaid') {
      return DutyHeartbeatPayload.unpaid;
    }
    return normalized;
  }

  static bool? _normalizeBreakPaid(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == 'true' ||
        normalized == '1' ||
        normalized == 'yes' ||
        normalized == 'paid') {
      return true;
    }
    if (normalized == 'false' ||
        normalized == '0' ||
        normalized == 'no' ||
        normalized == 'unpaid') {
      return false;
    }
    return null;
  }

  static int? _normalizeBreakMinutes(dynamic value) {
    if (value == null) return null;
    if (value is int) return value > 0 ? value : null;
    if (value is num) {
      final minutes = value.round();
      return minutes > 0 ? minutes : null;
    }
    return int.tryParse(value.toString().trim());
  }
}
