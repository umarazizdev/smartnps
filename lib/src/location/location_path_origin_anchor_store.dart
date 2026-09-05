import 'package:geolocator/geolocator.dart';

import '../motion/vehicle_session_fusion.dart';
import 'location_path_freshness.dart';
import 'location_path_movement_mode.dart';

/// Keeps a short-lived best-accuracy fix while stopped and uploads it once
/// as the path origin when confirmed movement begins (live-first TTL).
class LocationPathOriginAnchorStore {
  static const Duration maxAnchorAge = LocationPathFreshness.reuseMaxAge;
  static const double maxStoreAccuracyMeters = 25;
  static const double accuracyImprovementMeters = 1;
  static const double similarAccuracySlackMeters = 2;
  static const int movementConfirmSamples = 2;

  Position? _anchor;
  DateTime? _storedAt;
  LocationPathMovementMode _lastMode = LocationPathMovementMode.stopped;
  int _movingConfirmSamples = 0;
  bool _originUploadPending = false;
  bool _awaitingMovementConfirm = false;

  void reset() {
    _anchor = null;
    _storedAt = null;
    _lastMode = LocationPathMovementMode.stopped;
    _movingConfirmSamples = 0;
    _originUploadPending = false;
    _awaitingMovementConfirm = false;
  }

  void observe({
    required Position position,
    required LocationPathMovementMode mode,
    required VehicleSessionSnapshot fusion,
  }) {
    _expireIfStale();

    if (_shouldStoreAnchor(mode: mode, fusion: fusion, position: position)) {
      _maybeUpdateAnchor(position);
      _movingConfirmSamples = 0;
      _originUploadPending = false;
      _awaitingMovementConfirm = true;
      _lastMode = mode;
      return;
    }

    if (mode != LocationPathMovementMode.stopped &&
        !_isPhysicallyStill(fusion) &&
        _anchor != null &&
        _awaitingMovementConfirm) {
      _movingConfirmSamples++;
      if (_movingConfirmSamples >= movementConfirmSamples) {
        _originUploadPending = true;
        _awaitingMovementConfirm = false;
      }
    } else if (mode == LocationPathMovementMode.stopped ||
        _isPhysicallyStill(fusion)) {
      _movingConfirmSamples = 0;
    }

    _lastMode = mode;
  }

  bool get hasPendingOriginUpload => _originUploadPending && _anchor != null;

  Position? takeOriginIfPending() {
    if (!_originUploadPending || _anchor == null) return null;
    _expireIfStale();
    if (_anchor == null) {
      _originUploadPending = false;
      return null;
    }

    _originUploadPending = false;
    final origin = _anchor!;
    _anchor = null;
    _storedAt = null;
    _movingConfirmSamples = 0;
    _awaitingMovementConfirm = false;
    return origin;
  }

  void discardPendingOrigin() {
    _originUploadPending = false;
  }

  void _setAnchor(Position position) {
    _anchor = position;
    _storedAt = DateTime.now();
  }

  void _maybeUpdateAnchor(Position position) {
    final accuracy = position.accuracy;
    if (accuracy > maxStoreAccuracyMeters) return;

    final current = _anchor;
    if (current == null) {
      _setAnchor(position);
      return;
    }

    final betterAccuracy =
        accuracy + accuracyImprovementMeters < current.accuracy;
    final similarButNewer =
        accuracy <= current.accuracy + similarAccuracySlackMeters &&
        !position.timestamp.isBefore(current.timestamp);

    if (betterAccuracy || similarButNewer) {
      _setAnchor(position);
    }
  }

  void _expireIfStale() {
    final storedAt = _storedAt;
    final anchor = _anchor;
    if (storedAt == null || anchor == null) return;
    final now = DateTime.now();
    final storeAge = now.difference(storedAt);
    final fixAge = now.toUtc().difference(anchor.timestamp.toUtc());
    if (storeAge > maxAnchorAge || fixAge > maxAnchorAge) {
      _anchor = null;
      _storedAt = null;
      _originUploadPending = false;
      _awaitingMovementConfirm = false;
      _movingConfirmSamples = 0;
    }
  }

  bool _shouldStoreAnchor({
    required LocationPathMovementMode mode,
    required VehicleSessionSnapshot fusion,
    required Position position,
  }) {
    if (!_isPhysicallyStill(fusion)) return false;
    return position.accuracy > 0 &&
        position.accuracy <= maxStoreAccuracyMeters;
  }

  static bool _isPhysicallyStill(VehicleSessionSnapshot fusion) {
    final native = fusion.nativeActivity.toLowerCase().trim();
    final fused = fusion.fusedState.toLowerCase().trim();
    return native == 'still' ||
        native == 'stationary' ||
        fused == 'stationary' ||
        fused == 'still';
  }
}
