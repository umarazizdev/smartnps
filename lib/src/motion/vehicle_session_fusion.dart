class VehicleSessionFusion {

  static const double enterDrivingGpsKmh = 12;

  static const double softEnterGpsKmh = 9.5;

  static const int enterDrivingConfidence = 40;

  static const double keepDrivingGpsKmh = 7;

  static const double stoppedGpsKmh = 2.2;

  static const double walkMinKmh = 1.4;
  static const double walkMaxKmh = 8.5;

  static const int walkExitConfidence = 35;
  static const Duration walkExitHold = Duration(milliseconds: 1800);
  static const int strongWalkConfidence = 65;
  static const Duration strongWalkExitHold = Duration(milliseconds: 900);

  static const Duration stoppedBeforeGpsWalkExit = Duration(milliseconds: 1800);
  static const Duration gpsWalkExitHold = Duration(milliseconds: 1600);

  static const Duration nonVehicleHold = Duration(milliseconds: 350);
  static const double speedEmaAlpha = 0.55;

  bool active = false;
  String state = 'unknown';
  String reason = 'boot';
  bool provisional = false;

  double? _smoothedSpeedKmh;
  DateTime? _softEnterSince;
  DateTime? _walkExitSince;
  DateTime? _lastWalkSignalAt;
  DateTime? _stoppedInVehicleSince;
  DateTime? _gpsWalkExitSince;
  DateTime? _pendingNonVehicleSince;
  String? _pendingNonVehicle;

  VehicleSessionSnapshot evaluate({
    required String nativeActivity,
    required int nativeConfidence,
    double? gpsSpeedKmh,
  }) {
    final native = _normalizeNative(nativeActivity);
    final now = DateTime.now();
    final speed = _smoothSpeed(gpsSpeedKmh);

    if (active) {
      _evaluateInSession(
        native: native,
        nativeConfidence: nativeConfidence,
        speed: speed,
        now: now,
      );
    } else {
      _evaluateOutOfSession(
        native: native,
        nativeConfidence: nativeConfidence,
        speed: speed,
        now: now,
      );
    }

    return VehicleSessionSnapshot(
      active: active,
      fusedState: state,
      nativeActivity: native,
      nativeConfidence: nativeConfidence,
      gpsSpeedKmh: gpsSpeedKmh,
      smoothedSpeedKmh: speed,
      reason: reason,
      provisional: provisional,
    );
  }

  void _evaluateInSession({
    required String native,
    required int nativeConfidence,
    required double? speed,
    required DateTime now,
  }) {
    _softEnterSince = null;
    _pendingNonVehicleSince = null;
    _pendingNonVehicle = null;

    if (native == 'driving' ||
        (speed != null && speed >= keepDrivingGpsKmh)) {
      state = 'driving';
      reason = native == 'driving'
          ? 'native driving (session)'
          : 'gps moving ≥ ${keepDrivingGpsKmh.toStringAsFixed(0)} km/h';
      provisional = native != 'driving';
      _clearWalkExitTimers();
      _stoppedInVehicleSince = null;
      return;
    }

    if (speed == null || speed < stoppedGpsKmh) {
      _stoppedInVehicleSince ??= now;
      _gpsWalkExitSince = null;
    } else if (speed >= walkMinKmh && speed < walkMaxKmh) {

    } else {
      _stoppedInVehicleSince = null;
      _gpsWalkExitSince = null;
    }

    if (_tryNativeWalkExit(native, nativeConfidence, speed, now)) {
      return;
    }
    if (_tryGpsAssistedWalkExit(native, speed, now)) {
      return;
    }

    if ((native == 'running' || native == 'cycling') &&
        nativeConfidence >= walkExitConfidence) {
      active = false;
      state = native;
      reason = 'strong non-vehicle native ($native)';
      provisional = false;
      _clearWalkExitTimers();
      _stoppedInVehicleSince = null;
      return;
    }

    if (speed != null &&
        speed >= stoppedGpsKmh &&
        speed < keepDrivingGpsKmh) {
      state = 'driving';
      if (_walkExitSince == null && _gpsWalkExitSince == null) {
        reason = 'traffic crawl (session sticky)';
      }
    } else {
      state = 'driving_stopped';
      if (_walkExitSince == null && _gpsWalkExitSince == null) {
        reason = 'stopped in vehicle (session sticky)';
      }
    }
    provisional = false;
  }

  void _evaluateOutOfSession({
    required String native,
    required int nativeConfidence,
    required double? speed,
    required DateTime now,
  }) {
    _clearWalkExitTimers();
    _stoppedInVehicleSince = null;
    _gpsWalkExitSince = null;

    final nativeDriving =
        native == 'driving' && nativeConfidence >= enterDrivingConfidence;
    final veryFastGps = speed != null && speed >= 20;
    final fastGps = speed != null &&
        speed >= enterDrivingGpsKmh &&
        native != 'walking' &&
        native != 'running';
    final softGps = speed != null &&
        speed >= softEnterGpsKmh &&
        native != 'walking' &&
        native != 'running';

    if (nativeDriving || veryFastGps || fastGps) {
      active = true;
      state = 'driving';
      provisional = !nativeDriving;
      reason = nativeDriving
          ? 'native driving enter'
          : 'fast gps enter (≥ ${(veryFastGps ? 20 : enterDrivingGpsKmh).toStringAsFixed(0)} km/h)';
      _softEnterSince = null;
      return;
    }

    if (softGps) {
      _softEnterSince ??= now;

      active = true;
      state = 'driving';
      provisional = true;
      reason =
          'soft gps enter (provisional ≥ ${softEnterGpsKmh.toStringAsFixed(0)} km/h)';
      return;
    } else {
      _softEnterSince = null;
    }

    final candidate = _candidateOutsideSession(native, speed);
    _commitNonVehicle(candidate, now);
  }

  String _candidateOutsideSession(String native, double? speed) {
    if (native == 'walking' ||
        native == 'running' ||
        native == 'cycling' ||
        native == 'stationary') {
      provisional = false;
      reason = 'native $native';
      return native;
    }

    if (speed != null) {
      if (speed < stoppedGpsKmh) {
        provisional = true;
        reason = 'provisional stationary (gps)';
        return 'stationary';
      }

      if (speed >= walkMinKmh && speed < softEnterGpsKmh) {
        provisional = true;
        reason = 'provisional walking (gps)';
        return 'walking';
      }
      if (speed >= softEnterGpsKmh) {
        provisional = true;
        reason = 'provisional driving (gps)';
        return 'driving';
      }
    }

    provisional = state == 'unknown';
    reason = 'awaiting sensors';
    return state == 'unknown' ? 'unknown' : state;
  }

  void _commitNonVehicle(String candidate, DateTime now) {
    if (candidate == 'driving') {

      if (!active) {
        active = true;
        state = 'driving';
        provisional = true;
        reason = 'gps driving candidate → session';
        _pendingNonVehicleSince = null;
        _pendingNonVehicle = null;
      }
      return;
    }

    if (candidate == state) {
      _pendingNonVehicleSince = null;
      _pendingNonVehicle = null;
      return;
    }

    if (state == 'unknown' || state.isEmpty) {
      state = candidate;
      _pendingNonVehicleSince = null;
      _pendingNonVehicle = null;
      return;
    }

    if (!provisional &&
        (candidate == 'walking' ||
            candidate == 'running' ||
            candidate == 'cycling' ||
            candidate == 'stationary')) {
      state = candidate;
      _pendingNonVehicleSince = null;
      _pendingNonVehicle = null;
      return;
    }

    if (_pendingNonVehicle == candidate) {
      if (_pendingNonVehicleSince != null &&
          now.difference(_pendingNonVehicleSince!) >= nonVehicleHold) {
        state = candidate;
        _pendingNonVehicleSince = null;
        _pendingNonVehicle = null;
      }
      return;
    }

    _pendingNonVehicle = candidate;
    _pendingNonVehicleSince = now;
  }

  bool _tryNativeWalkExit(
    String native,
    int nativeConfidence,
    double? speed,
    DateTime now,
  ) {
    if (native == 'driving' ||
        (speed != null && speed >= keepDrivingGpsKmh)) {
      _walkExitSince = null;
      _lastWalkSignalAt = null;
      return false;
    }

    if (native == 'walking' && nativeConfidence >= walkExitConfidence) {
      _lastWalkSignalAt = now;
    } else if (_walkExitSince != null &&
        (_lastWalkSignalAt == null ||
            now.difference(_lastWalkSignalAt!) > const Duration(seconds: 5))) {
      _walkExitSince = null;
      _lastWalkSignalAt = null;
      return false;
    }

    if (native != 'walking' || nativeConfidence < walkExitConfidence) {
      return false;
    }

    final inWalkBand = speed == null ||
        (speed >= walkMinKmh && speed < walkMaxKmh) ||
        speed < stoppedGpsKmh;
    if (!inWalkBand) return false;

    _walkExitSince ??= now;
    final held = now.difference(_walkExitSince!);
    Duration need;
    if (nativeConfidence >= 80) {
      need = const Duration(milliseconds: 400);
    } else if (nativeConfidence >= strongWalkConfidence) {
      need = strongWalkExitHold;
    } else {
      need = walkExitHold;
    }

    if (held < need) {
      reason =
          'walk-exit pending ${_fmtMs(held)}/${_fmtMs(need)} (native)';
      return false;
    }

    _leaveVehicleAsWalking(
      reasonText: 'walk exit after ${_fmtMs(need)} (native)',
    );
    return true;
  }

  static String _fmtMs(Duration d) {
    final ms = d.inMilliseconds;
    if (ms < 1000) return '${ms}ms';
    final s = ms / 1000.0;
    return s == s.roundToDouble()
        ? '${s.toInt()}s'
        : '${s.toStringAsFixed(1)}s';
  }

  bool _tryGpsAssistedWalkExit(
    String native,
    double? speed,
    DateTime now,
  ) {
    if (native == 'driving') {
      _gpsWalkExitSince = null;
      return false;
    }
    if (speed == null || speed < walkMinKmh || speed >= walkMaxKmh) {
      if (speed == null || speed < stoppedGpsKmh) {

      } else {
        _gpsWalkExitSince = null;
      }
      return false;
    }

    final stoppedAt = _stoppedInVehicleSince;
    if (stoppedAt == null ||
        now.difference(stoppedAt) < stoppedBeforeGpsWalkExit) {
      _gpsWalkExitSince = null;
      return false;
    }

    _gpsWalkExitSince ??= now;
    final held = now.difference(_gpsWalkExitSince!);
    if (held < gpsWalkExitHold) {
      reason =
          'gps walk-exit pending ${_fmtMs(held)}/${_fmtMs(gpsWalkExitHold)}';
      return false;
    }

    _leaveVehicleAsWalking(
      reasonText: 'walk exit after stop+walk gps (left vehicle)',
    );
    return true;
  }

  void _leaveVehicleAsWalking({required String reasonText}) {
    active = false;
    state = 'walking';
    provisional = false;
    reason = reasonText;
    _clearWalkExitTimers();
    _stoppedInVehicleSince = null;
  }

  void _clearWalkExitTimers() {
    _walkExitSince = null;
    _lastWalkSignalAt = null;
    _gpsWalkExitSince = null;
  }

  double? _smoothSpeed(double? raw) {
    if (raw == null || raw.isNaN || raw.isInfinite || raw < 0) {
      return _smoothedSpeedKmh;
    }
    final prev = _smoothedSpeedKmh;
    if (prev == null) {
      _smoothedSpeedKmh = raw;
      return raw;
    }
    final next = (speedEmaAlpha * raw) + ((1 - speedEmaAlpha) * prev);
    _smoothedSpeedKmh = next;
    return next;
  }

  String _normalizeNative(String value) {
    final n = value.toLowerCase().trim();
    if (n == 'automotive' || n == 'in_vehicle' || n == 'invehicle') {
      return 'driving';
    }
    if (n == 'on_foot' || n == 'onfoot') return 'walking';
    if (n == 'still') return 'stationary';
    return n;
  }

  void reset() {
    active = false;
    state = 'unknown';
    reason = 'reset';
    provisional = false;
    _smoothedSpeedKmh = null;
    _softEnterSince = null;
    _clearWalkExitTimers();
    _stoppedInVehicleSince = null;
    _pendingNonVehicleSince = null;
    _pendingNonVehicle = null;
  }

  static String toApiMotionActivity(String fusedState) {
    switch (fusedState.toLowerCase().trim()) {
      case 'driving':
      case 'driving_stopped':
      case 'automotive':
      case 'in_vehicle':
        return 'automotive';
      case 'walking':
      case 'on_foot':
        return 'walking';
      case 'running':
        return 'running';
      case 'cycling':
        return 'cycling';
      case 'stationary':
      case 'still':
        return 'stationary';
      default:
        return 'stationary';
    }
  }
}

class VehicleSessionSnapshot {
  const VehicleSessionSnapshot({
    required this.active,
    required this.fusedState,
    required this.nativeActivity,
    required this.nativeConfidence,
    required this.gpsSpeedKmh,
    required this.smoothedSpeedKmh,
    required this.reason,
    required this.provisional,
  });

  final bool active;
  final String fusedState;
  final String nativeActivity;
  final int nativeConfidence;
  final double? gpsSpeedKmh;
  final double? smoothedSpeedKmh;
  final String reason;
  final bool provisional;

  String get apiMotionActivity =>
      VehicleSessionFusion.toApiMotionActivity(fusedState);
}
