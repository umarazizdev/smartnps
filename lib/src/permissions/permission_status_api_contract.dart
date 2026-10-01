

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
