/// Shared contract for `POST /native-app/permission-status`.
///
/// Timeline fields are event metadata. They must never affect the permission
/// fingerprint used for change-detection syncs.
class PermissionStatusApiContract {
  PermissionStatusApiContract._();

  // --- Payload keys -----------------------------------------------------------
  static const String appCycle = 'app_cycle';
  static const String killedAt = 'killed_at';
  static const String openedAt = 'opened_at';
  static const String checkedAt = 'checkedAt';
  static const String batteryPercentage = 'battery_percentage';

  // --- app_cycle values -------------------------------------------------------
  static const String cycleResumed = 'resumed';
  static const String cyclePaused = 'paused';
  static const String cycleInactive = 'inactive';
  static const String cycleHidden = 'hidden';
  static const String cycleDetached = 'detached';
  static const String cycleKilled = 'killed';

  /// Keys excluded from permission change fingerprints.
  static const Set<String> fingerprintIgnoredKeys = {
    appCycle,
    batteryPercentage,
    checkedAt,
    killedAt,
    openedAt,
  };
}

/// Optional kill → reopen timeline for permission-status POSTs.
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

  /// True when this is a user reopen after a queued kill (dashboard pair).
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
