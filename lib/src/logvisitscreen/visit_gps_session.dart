import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../background/ios_duty_location_pinger.dart';

class VisitGpsSession {
  VisitGpsSession._();

  static final VisitGpsSession instance = VisitGpsSession._();

  static const Duration maxFreshAge = Duration(seconds: 15);
  static const Duration maxAcceptAge = Duration(seconds: 30);

  static final Duration oneShotTimeout =
      Duration(seconds: Platform.isIOS ? 15 : 10);

  StreamSubscription<Position>? _subscription;
  Position? _latest;
  Future<void>? _startFuture;
  var _running = false;

  bool get isRunning => _running && _subscription != null;

  Position? get latestUsableFresh {
    final candidates = <Position?>[
      _latest,
      if (Platform.isIOS) IosDutyLocationPinger.latestAcceptedPosition,
    ];
    Position? best;
    for (final candidate in candidates) {
      if (candidate == null || !isUsableFresh(candidate)) continue;
      if (best == null || candidate.timestamp.isAfter(best.timestamp)) {
        best = candidate;
      }
    }
    return best;
  }

  static bool isUsableFresh(Position position) {
    return _isUsable(position, maxAge: maxFreshAge);
  }

  static bool isUsableAcceptable(Position position) {
    return _isUsable(position, maxAge: maxAcceptAge);
  }

  static bool _isUsable(Position position, {required Duration maxAge}) {
    if (!position.latitude.isFinite || !position.longitude.isFinite) {
      return false;
    }
    if (!position.accuracy.isFinite || position.accuracy < 0) {
      return false;
    }
    final age = DateTime.now().difference(position.timestamp);
    return age <= maxAge;
  }

  Future<void> start() async {
    if (_running && _subscription != null) {
      unawaited(_seedLatest());
      return;
    }
    final inFlight = _startFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final future = _startInternal();
    _startFuture = future;
    try {
      await future;
    } finally {
      if (identical(_startFuture, future)) {
        _startFuture = null;
      }
    }
  }

  Future<void> _startInternal() async {
    await stop();

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (kDebugMode) {
          debugPrint('[VisitGpsSession] start skipped: permission=$permission');
        }
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (kDebugMode) {
          debugPrint('[VisitGpsSession] start skipped: location services off');
        }
        return;
      }

      await _seedLatest();

      _subscription = Geolocator.getPositionStream(
        locationSettings: _streamSettings(),
      ).listen(
        (position) {
          if (!_hasValidCoords(position)) return;
          _latest = position;
        },
        onError: (Object error) {
          if (kDebugMode) {
            debugPrint('[VisitGpsSession] stream error: $error');
          }
        },
        cancelOnError: false,
      );
      _running = true;

      unawaited(_seedFromCurrentPosition());

      if (kDebugMode) {
        debugPrint('[VisitGpsSession] stream started');
      }
    } catch (e) {
      _running = false;
      _subscription = null;
      if (kDebugMode) {
        debugPrint('[VisitGpsSession] start failed: $e');
      }
    }
  }

  Future<void> _seedLatest() async {
    final duty = Platform.isIOS
        ? IosDutyLocationPinger.latestAcceptedPosition
        : null;
    if (duty != null && isUsableFresh(duty)) {
      _latest = duty;
    }

    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && isUsableFresh(lastKnown)) {
        final current = _latest;
        if (current == null ||
            lastKnown.timestamp.isAfter(current.timestamp)) {
          _latest = lastKnown;
        }
      }
    } catch (_) {}
  }

  Future<void> _seedFromCurrentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: _oneShotSettings(),
      );
      if (!isUsableAcceptable(position)) return;
      final current = _latest;
      if (current == null || position.timestamp.isAfter(current.timestamp)) {
        _latest = position;
      }
    } catch (_) {}
  }

  Future<void> stop() async {
    final sub = _subscription;
    _subscription = null;
    _running = false;
    _latest = null;
    if (sub != null) {
      await sub.cancel();
      if (kDebugMode) {
        debugPrint('[VisitGpsSession] stream stopped');
      }
    }
  }

  Future<Position?> acquireForCapture() async {
    final fromWarm = latestUsableFresh;
    if (fromWarm != null) return fromWarm;

    if (!_running) {
      unawaited(start());
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: _oneShotSettings(),
      );
      if (!isUsableAcceptable(position)) return null;
      _latest = position;
      return position;
    } catch (_) {
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null && isUsableAcceptable(lastKnown)) {
          _latest = lastKnown;
          return lastKnown;
        }
      } catch (_) {}
      return null;
    }
  }

  static bool _hasValidCoords(Position position) {
    return position.latitude.isFinite &&
        position.longitude.isFinite &&
        position.accuracy.isFinite &&
        position.accuracy >= 0;
  }

  static LocationSettings _streamSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(milliseconds: 500),
        forceLocationManager: false,
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );
  }

  static LocationSettings _oneShotSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        timeLimit: oneShotTimeout,
        forceLocationManager: false,
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        timeLimit: oneShotTimeout,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: false,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      timeLimit: oneShotTimeout,
    );
  }
}
