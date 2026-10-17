
import 'dart:convert';

class PermissionStatusApiContract {
  PermissionStatusApiContract._();

  static const String appCycle = 'app_cycle';
  static const String killedAt = 'killed_at';
  static const String openedAt = 'opened_at';
  static const String checkedAt = 'checkedAt';
  static const String batteryPercentage = 'battery_percentage';

  static const String cycleResumed = 'resumed';
  static const String cyclePaused = 'paused';
  static const String cycleInactive = 'inactive';
  static const String cycleHidden = 'hidden';
  static const String cycleDetached = 'detached';
  static const String cycleKilled = 'killed';

  static const Set<String> fingerprintIgnoredKeys = {
    appCycle,
    batteryPercentage,
    checkedAt,
    killedAt,
    openedAt,
  };

  /// True only when HTTP is 2xx and the body does not indicate failure.
  /// Empty/null bodies are accepted (common for 202/204). HTML or
  /// `success: false` bodies are rejected even if the status is 2xx.
  static bool isAcceptedResponse({
    required int? statusCode,
    required dynamic body,
  }) {
    if (statusCode == null || statusCode < 200 || statusCode >= 300) {
      return false;
    }
    return _isAcceptedBody(body);
  }

  static bool _isAcceptedBody(dynamic body) {
    if (body == null) return true;

    if (body is String) {
      final trimmed = body.trim();
      if (trimmed.isEmpty) return true;
      final lower = trimmed.toLowerCase();
      if (lower.startsWith('<!doctype') || lower.startsWith('<html')) {
        return false;
      }
      try {
        return _isAcceptedBody(jsonDecode(trimmed));
      } catch (_) {
        return lower == 'ok' ||
            lower == 'success' ||
            lower == 'accepted' ||
            lower == 'true';
      }
    }

    if (body is bool) return body;
    if (body is num) return body != 0;
    if (body is List) return true;

    if (body is! Map) return false;
    final map = Map<String, dynamic>.from(body);

    if (_isExplicitFalse(map['success']) || _isExplicitFalse(map['ok'])) {
      return false;
    }

    final status = map['status']?.toString().trim().toLowerCase();
    if (status == 'error' ||
        status == 'failed' ||
        status == 'failure' ||
        status == 'rejected') {
      return false;
    }

    if (_hasNonEmptyErrors(map['errors']) &&
        !_isExplicitTrue(map['success']) &&
        !_isExplicitTrue(map['ok'])) {
      return false;
    }

    if (map['error'] != null &&
        !_isExplicitTrue(map['success']) &&
        !_isExplicitTrue(map['ok'])) {
      final error = map['error'];
      if (error is String && error.trim().isEmpty) {
        return true;
      }
      return false;
    }

    return true;
  }

  static bool _isExplicitTrue(dynamic value) {
    if (value == true || value == 1) return true;
    if (value is String) {
      final lower = value.trim().toLowerCase();
      return lower == 'true' || lower == '1' || lower == 'ok' || lower == 'success';
    }
    return false;
  }

  static bool _isExplicitFalse(dynamic value) {
    if (value == false || value == 0) return true;
    if (value is String) {
      final lower = value.trim().toLowerCase();
      return lower == 'false' || lower == '0';
    }
    return false;
  }

  static bool _hasNonEmptyErrors(dynamic errors) {
    if (errors == null) return false;
    if (errors is String) return errors.trim().isNotEmpty;
    if (errors is Map) return errors.isNotEmpty;
    if (errors is List) return errors.isNotEmpty;
    return true;
  }
}

class PermissionStatusTimeline {
  const PermissionStatusTimeline({
    this.killedAt,
    this.openedAt,
  });

  final String? killedAt;
  final String? openedAt;

  bool get hasKill => killedAt != null && killedAt!.trim().isNotEmpty;

  bool get hasOpen => openedAt != null && openedAt!.trim().isNotEmpty;

  bool get isEmpty => !hasKill && !hasOpen;

  bool get isKillReopen => hasKill && hasOpen;

  factory PermissionStatusTimeline.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const PermissionStatusTimeline();
    String? read(String key) {
      final raw = map[key]?.toString().trim();
      if (raw == null || raw.isEmpty || raw == 'null') return null;
      return raw;
    }

    return PermissionStatusTimeline(
      killedAt: read(PermissionStatusApiContract.killedAt),
      openedAt: read(PermissionStatusApiContract.openedAt),
    );
  }

  Map<String, String> toPayloadFields() {
    final fields = <String, String>{};
    if (hasKill) {
      fields[PermissionStatusApiContract.killedAt] = killedAt!.trim();
    }
    if (hasOpen) {
      fields[PermissionStatusApiContract.openedAt] = openedAt!.trim();
    }
    return fields;
  }
}
