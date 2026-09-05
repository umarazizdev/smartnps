import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:smartnps360/src/location/batch_displacement_gate.dart';
import 'package:smartnps360/src/location/location_coordinate_smoother.dart';
import 'package:smartnps360/src/location/location_keep_point_gate.dart';
import 'package:smartnps360/src/location/location_path_batch_policy.dart';
import 'package:smartnps360/src/location/location_path_corner_sampler.dart';
import 'package:smartnps360/src/location/location_path_motion_gate.dart';
import 'package:smartnps360/src/location/location_path_coordinate_filter.dart';
import 'package:smartnps360/src/location/location_path_origin_anchor_store.dart';
import 'package:smartnps360/src/location/location_path_stationary_guard.dart';
import 'package:smartnps360/src/location/location_path_movement_mode.dart';
import 'package:smartnps360/src/location/location_path_outlier_gate.dart';
import 'package:smartnps360/src/location/speed_adaptive_gps_policy.dart';
import 'package:smartnps360/src/motion/vehicle_session_fusion.dart';
import 'package:smartnps360/src/background/location/background_location_accuracy.dart';

Position _pos({
  required double lat,
  required double lng,
  DateTime? timestamp,
  double accuracy = 10,
  double speedMs = 0,
}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: timestamp ?? DateTime.utc(2026, 1, 1, 12),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speedMs,
    speedAccuracy: 0,
  );
}

SpeedAdaptiveGpsPolicyDecision _policy({double speedKmh = 10}) {
  return SpeedAdaptiveGpsPolicyDecision(
    band: SpeedAdaptiveGpsPolicyBand.forSpeedKmh(speedKmh),
    rawSpeedKmh: speedKmh,
    smoothedSpeedKmh: speedKmh,
    speedAccuracyMetersPerSecond: 1,
    isTrusted: true,
  );
}

VehicleSessionSnapshot _fusion({
  String fusedState = 'walking',
  String nativeActivity = 'walking',
  double? speedKmh = 10,
}) {
  return VehicleSessionSnapshot(
    active: true,
    fusedState: fusedState,
    nativeActivity: nativeActivity,
    nativeConfidence: 80,
    gpsSpeedKmh: speedKmh,
    smoothedSpeedKmh: speedKmh,
    reason: 'test',
    provisional: false,
  );
}

void main() {
  group('LocationCoordinateSmoother', () {
    test('returns latest when buffer is empty', () {
      final smoother = LocationCoordinateSmoother();
      final latest = _pos(lat: 37.77, lng: -122.42);
      expect(smoother.smooth(latest).latitude, latest.latitude);
    });

    test('weights accurate fixes more than noisy fixes', () {
      final smoother = LocationCoordinateSmoother();
      smoother.configure(
        LocationPathMovementModePolicy.settingsFor(
          LocationPathMovementMode.walking,
        ),
      );
      final now = DateTime.now().toUtc();
      smoother.observe(
        _pos(lat: 37.7700, lng: -122.4200, accuracy: 3, timestamp: now),
      );
      smoother.observe(
        _pos(
          lat: 37.7710,
          lng: -122.4210,
          accuracy: 25,
          timestamp: now.add(const Duration(seconds: 1)),
        ),
      );
      final latest = _pos(
        lat: 37.7702,
        lng: -122.4202,
        accuracy: 4,
        timestamp: now.add(const Duration(seconds: 2)),
      );
      smoother.observe(latest);

      final smoothed = smoother.smooth(latest);
      expect(
        (smoothed.latitude - 37.7702).abs(),
        lessThan((smoothed.latitude - 37.7710).abs()),
      );
    });

    test('median ignores one bad driving fix', () {
      final smoother = LocationCoordinateSmoother();
      smoother.configure(
        LocationPathMovementModePolicy.settingsFor(
          LocationPathMovementMode.driving,
        ),
      );
      final now = DateTime.now().toUtc();
      smoother.observe(
        _pos(lat: 37.7700, lng: -122.4200, accuracy: 5, timestamp: now),
      );
      smoother.observe(
        _pos(
          lat: 37.7720,
          lng: -122.4220,
          accuracy: 8,
          timestamp: now.add(const Duration(seconds: 1)),
        ),
      );
      final latest = _pos(
        lat: 37.7702,
        lng: -122.4202,
        accuracy: 6,
        timestamp: now.add(const Duration(seconds: 2)),
      );
      smoother.observe(latest);

      final smoothed = smoother.smooth(latest);
      expect(smoothed.latitude, closeTo(37.7702, 0.0003));
    });
  });

  group('LocationPathMovementModePolicy', () {
    test('detects stopped, walking, and driving modes', () {
      expect(
        LocationPathMovementModePolicy.resolve(
          policy: _policy(speedKmh: 0),
          fusion: _fusion(fusedState: 'stationary', speedKmh: 0),
        ),
        LocationPathMovementMode.stopped,
      );
      expect(
        LocationPathMovementModePolicy.resolve(
          policy: _policy(speedKmh: 5),
          fusion: _fusion(fusedState: 'walking', speedKmh: 5),
        ),
        LocationPathMovementMode.walking,
      );
      expect(
        LocationPathMovementModePolicy.resolve(
          policy: _policy(speedKmh: 20),
          fusion: _fusion(fusedState: 'driving', speedKmh: 20),
        ),
        LocationPathMovementMode.driving,
      );
    });

    test('uses stricter walking accuracy than driving', () {
      expect(
        LocationPathMovementModePolicy.isPathAccuracyAcceptable(
          mode: LocationPathMovementMode.walking,
          accuracyMeters: 22,
        ),
        isFalse,
      );
      expect(
        LocationPathMovementModePolicy.isPathAccuracyAcceptable(
          mode: LocationPathMovementMode.driving,
          accuracyMeters: 22,
        ),
        isTrue,
      );
    });
  });

  group('LocationPathStationaryGuard', () {
    test('locks path when phone reports still', () {
      final guard = LocationPathStationaryGuard();
      guard.observe(
        position: _pos(lat: 37.77, lng: -122.42),
        mode: LocationPathMovementMode.walking,
        fusion: _fusion(fusedState: 'still', nativeActivity: 'still', speedKmh: 6),
        policy: _policy(speedKmh: 6),
      );
      expect(guard.blocksPathUpload, isTrue);
    });

    test('detects desk zigzag drift pattern from ping samples', () {
      final guard = LocationPathStationaryGuard();
      final fusion = _fusion(fusedState: 'unknown', nativeActivity: 'unknown', speedKmh: 4);
      final policy = _policy(speedKmh: 4);
      final start = DateTime.utc(2026, 1, 1, 12);
      guard.observe(
        position: _pos(lat: 37.7700, lng: -122.4200, timestamp: start),
        mode: LocationPathMovementMode.walking,
        fusion: fusion,
        policy: policy,
      );
      guard.observe(
        position: _pos(
          lat: 37.7710,
          lng: -122.4210,
          timestamp: start.add(const Duration(seconds: 30)),
        ),
        mode: LocationPathMovementMode.walking,
        fusion: fusion,
        policy: policy,
      );
      guard.observe(
        position: _pos(
          lat: 37.7701,
          lng: -122.4201,
          timestamp: start.add(const Duration(seconds: 60)),
        ),
        mode: LocationPathMovementMode.walking,
        fusion: fusion,
        policy: policy,
      );
      guard.observe(
        position: _pos(
          lat: 37.7712,
          lng: -122.4212,
          timestamp: start.add(const Duration(seconds: 90)),
        ),
        mode: LocationPathMovementMode.walking,
        fusion: fusion,
        policy: policy,
      );
      expect(guard.blocksPathUpload, isTrue);
    });
  });

  group('LocationPathCornerSampler', () {
    test('keeps straight-line spacing on straight segments', () {
      final sampler = LocationPathCornerSampler();
      sampler.markAccepted(_pos(lat: 37.7700, lng: -122.4200));

      final decision = sampler.displacementRequirement(
        candidate: _pos(lat: 37.77015, lng: -122.42015),
        mode: LocationPathMovementMode.walking,
        straightMinDisplacementMeters: 25,
      );

      expect(decision.isCornerSample, isFalse);
      expect(decision.effectiveMinDisplacementMeters, 25);
    });

    test('densifies path when bearing changes on a real turn', () {
      final sampler = LocationPathCornerSampler();
      sampler.markAccepted(_pos(lat: 37.7700, lng: -122.4200));
      sampler.markAccepted(_pos(lat: 37.7710, lng: -122.4200));

      final decision = sampler.displacementRequirement(
        candidate: _pos(lat: 37.7710, lng: -122.4212),
        mode: LocationPathMovementMode.walking,
        straightMinDisplacementMeters: 25,
      );

      expect(decision.effectiveMinDisplacementMeters, 10);
      expect(decision.isCornerSample, isTrue);
    });

    test('keeps corner spacing during boost window after turn starts', () {
      final sampler = LocationPathCornerSampler();
      sampler.markAccepted(_pos(lat: 37.7700, lng: -122.4200));
      sampler.markAccepted(_pos(lat: 37.7710, lng: -122.4200));

      sampler.displacementRequirement(
        candidate: _pos(lat: 37.7710, lng: -122.4212),
        mode: LocationPathMovementMode.walking,
        straightMinDisplacementMeters: 25,
      );

      final followUp = sampler.displacementRequirement(
        candidate: _pos(lat: 37.7711, lng: -122.4213),
        mode: LocationPathMovementMode.walking,
        straightMinDisplacementMeters: 25,
      );

      expect(followUp.effectiveMinDisplacementMeters, 10);
    });

    test('uses denser driving corner spacing than walking', () {
      final sampler = LocationPathCornerSampler();
      sampler.markAccepted(_pos(lat: 37.7700, lng: -122.4200));
      sampler.markAccepted(_pos(lat: 37.7710, lng: -122.4200));

      final decision = sampler.displacementRequirement(
        candidate: _pos(lat: 37.7710, lng: -122.4210),
        mode: LocationPathMovementMode.driving,
        straightMinDisplacementMeters: 12,
      );

      expect(decision.effectiveMinDisplacementMeters, 8);
      expect(decision.isCornerSample, isTrue);
    });
  });

  group('LocationPathDriveSpacing', () {
    test('uses denser city driving spacing than walking', () {
      expect(
        LocationPathMovementModePolicy.settingsFor(
          LocationPathMovementMode.walking,
        ).minBatchDisplacementMeters,
        25,
      );
      expect(
        LocationPathMovementModePolicy.settingsFor(
          LocationPathMovementMode.driving,
          speedKmh: 20,
        ).minBatchDisplacementMeters,
        12,
      );
      expect(
        LocationPathMovementModePolicy.settingsFor(
          LocationPathMovementMode.driving,
          speedKmh: 40,
        ).minBatchDisplacementMeters,
        18,
      );
    });

    test('enables driving path heartbeat only for driving mode', () {
      expect(
        LocationPathMovementModePolicy.settingsFor(
          LocationPathMovementMode.walking,
        ).pathHeartbeat,
        isNull,
      );
      expect(
        LocationPathMovementModePolicy.settingsFor(
          LocationPathMovementMode.driving,
          speedKmh: 25,
        ).pathHeartbeat,
        const Duration(seconds: 3),
      );
      expect(
        LocationPathMovementModePolicy.settingsFor(
          LocationPathMovementMode.stopped,
        ).pathHeartbeat,
        isNull,
      );
    });
  });

  group('BatchDisplacementGateHeartbeat', () {
    test('allows driving heartbeat after interval with small real move', () async {
      final gate = BatchDisplacementGate();
      gate.markQueued(_pos(lat: 37.7700, lng: -122.4200));

      expect(
        gate.shouldQueue(
          _pos(lat: 37.77005, lng: -122.42005),
          minDisplacementMeters: 12,
          maxAccuracyBoostOverride: 12,
          pathHeartbeat: const Duration(milliseconds: 30),
          heartbeatMinDisplacementMeters: 5,
        ),
        isFalse,
      );

      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(
        gate.shouldQueue(
          _pos(lat: 37.77006, lng: -122.42006),
          minDisplacementMeters: 12,
          maxAccuracyBoostOverride: 12,
          pathHeartbeat: const Duration(milliseconds: 30),
          heartbeatMinDisplacementMeters: 5,
        ),
        isTrue,
      );
    });
  });

  group('LocationPathMotionGate', () {
    test('blocks path when motion is unknown even with fake GPS speed', () {
      expect(
        LocationPathMotionGate.hasConfirmedMotion(
          fusion: _fusion(fusedState: 'unknown', nativeActivity: 'unknown', speedKmh: 8),
          policy: _policy(speedKmh: 8),
        ),
        isFalse,
      );
    });

    test('allows path when native walking is confirmed', () {
      expect(
        LocationPathMotionGate.hasConfirmedMotion(
          fusion: _fusion(fusedState: 'walking', nativeActivity: 'walking', speedKmh: 5),
          policy: _policy(speedKmh: 5),
        ),
        isTrue,
      );
    });

    test('allows path for clear driving speed without motion sensor', () {
      expect(
        LocationPathMotionGate.hasConfirmedMotion(
          fusion: _fusion(fusedState: 'unknown', nativeActivity: 'unknown', speedKmh: 20),
          policy: _policy(speedKmh: 20),
        ),
        isTrue,
      );
    });
  });

  group('LocationPathOriginAnchorStore', () {
    test('keeps latest similar-accuracy fix while still', () {
      final store = LocationPathOriginAnchorStore();
      final fusion = _fusion(fusedState: 'still', nativeActivity: 'still', speedKmh: 0);
      final start = DateTime.now().toUtc();

      store.observe(
        position: _pos(lat: 37.7700, lng: -122.4200, accuracy: 8, timestamp: start),
        mode: LocationPathMovementMode.stopped,
        fusion: fusion,
      );
      store.observe(
        position: _pos(
          lat: 37.7701,
          lng: -122.4201,
          accuracy: 7,
          timestamp: start.add(const Duration(seconds: 20)),
        ),
        mode: LocationPathMovementMode.stopped,
        fusion: fusion,
      );

      store.observe(
        position: _pos(
          lat: 37.7710,
          lng: -122.4210,
          accuracy: 6,
          speedMs: 1.5,
          timestamp: start.add(const Duration(seconds: 40)),
        ),
        mode: LocationPathMovementMode.walking,
        fusion: _fusion(fusedState: 'walking', nativeActivity: 'walking', speedKmh: 5),
      );
      store.observe(
        position: _pos(
          lat: 37.7712,
          lng: -122.4212,
          accuracy: 6,
          speedMs: 1.5,
          timestamp: start.add(const Duration(seconds: 45)),
        ),
        mode: LocationPathMovementMode.walking,
        fusion: _fusion(fusedState: 'walking', nativeActivity: 'walking', speedKmh: 5),
      );

      expect(store.hasPendingOriginUpload, isTrue);
      final origin = store.takeOriginIfPending();
      expect(origin, isNotNull);
      expect(origin!.latitude, closeTo(37.7701, 0.00001));
      expect(origin.accuracy, 7);
    });

    test('expires origin older than one minute', () {
      final store = LocationPathOriginAnchorStore();
      final fusion = _fusion(fusedState: 'still', nativeActivity: 'still', speedKmh: 0);
      final old = DateTime.now().toUtc().subtract(const Duration(minutes: 2));

      store.observe(
        position: _pos(lat: 37.7700, lng: -122.4200, accuracy: 5, timestamp: old),
        mode: LocationPathMovementMode.stopped,
        fusion: fusion,
      );

      store.observe(
        position: _pos(
          lat: 37.7710,
          lng: -122.4210,
          accuracy: 5,
          speedMs: 1.5,
          timestamp: DateTime.now().toUtc(),
        ),
        mode: LocationPathMovementMode.walking,
        fusion: _fusion(fusedState: 'walking', nativeActivity: 'walking', speedKmh: 5),
      );

      expect(store.hasPendingOriginUpload, isFalse);
    });

    test('does not store anchor without motion still', () {
      final store = LocationPathOriginAnchorStore();
      store.observe(
        position: _pos(lat: 37.7700, lng: -122.4200, accuracy: 5),
        mode: LocationPathMovementMode.stopped,
        fusion: _fusion(fusedState: 'unknown', nativeActivity: 'unknown', speedKmh: 0),
      );

      store.observe(
        position: _pos(lat: 37.7710, lng: -122.4210, accuracy: 5, speedMs: 1.5),
        mode: LocationPathMovementMode.walking,
        fusion: _fusion(fusedState: 'walking', nativeActivity: 'walking', speedKmh: 5),
      );
      store.observe(
        position: _pos(lat: 37.7712, lng: -122.4212, accuracy: 5, speedMs: 1.5),
        mode: LocationPathMovementMode.walking,
        fusion: _fusion(fusedState: 'walking', nativeActivity: 'walking', speedKmh: 5),
      );

      expect(store.hasPendingOriginUpload, isFalse);
    });
  });

  group('LocationCoordinateSmootherFreshness', () {
    test('ignores buffer points older than one minute', () {
      final smoother = LocationCoordinateSmoother();
      smoother.configure(
        LocationPathMovementModePolicy.settingsFor(
          LocationPathMovementMode.walking,
        ),
      );
      final now = DateTime.now().toUtc();
      smoother.observe(
        _pos(
          lat: 37.7800,
          lng: -122.4300,
          accuracy: 3,
          timestamp: now.subtract(const Duration(minutes: 2)),
        ),
      );
      final latest = _pos(lat: 37.7702, lng: -122.4202, accuracy: 4, timestamp: now);
      smoother.observe(latest);

      final smoothed = smoother.smooth(latest);
      expect(smoothed.latitude, closeTo(latest.latitude, 0.00001));
      expect(smoothed.longitude, closeTo(latest.longitude, 0.00001));
    });
  });

  group('LocationPathCoordinateFilter', () {
    test('uses measured-only smoothing without changing stopped mode', () {
      final filter = LocationPathCoordinateFilter();
      final raw = _pos(lat: 37.7704, lng: -122.4204, accuracy: 5);
      final stopped = filter.filter(
        raw: raw,
        mode: LocationPathMovementMode.stopped,
      );
      expect(stopped.latitude, raw.latitude);
    });
  });

  group('LocationKeepPointGate', () {
    test('skips sub-threshold drift while moving', () async {
      final gate = LocationKeepPointGate();
      final start = DateTime.utc(2026, 1, 1, 12);

      gate.evaluate(
        _pos(lat: 37.77, lng: -122.42, timestamp: start, speedMs: 3),
        _policy(),
      );

      await Future<void>.delayed(const Duration(milliseconds: 1100));

      final tooSmall = gate.evaluate(
        _pos(
          lat: 37.77005,
          lng: -122.42005,
          timestamp: start.add(const Duration(seconds: 2)),
          speedMs: 3,
        ),
        _policy(),
      );
      expect(tooSmall.shouldKeep, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 1100));

      final enough = gate.evaluate(
        _pos(
          lat: 37.77020,
          lng: -122.42020,
          timestamp: start.add(const Duration(seconds: 4)),
          speedMs: 3,
        ),
        _policy(),
      );
      expect(enough.shouldKeep, isTrue);
      expect(enough.trigger, LocationKeepPointTrigger.stream);
    });
  });

  group('BackgroundLocationAccuracy', () {
    test('accepts ping up to 100m and rejects worse', () {
      final ok = _pos(lat: 37.77, lng: -122.42, accuracy: 100);
      final weak = _pos(lat: 37.77, lng: -122.42, accuracy: 80);
      final tooWeak = _pos(lat: 37.77, lng: -122.42, accuracy: 101);
      expect(BackgroundLocationAccuracy.isAcceptableForPing(ok), isTrue);
      expect(BackgroundLocationAccuracy.isAcceptableForPing(weak), isTrue);
      expect(BackgroundLocationAccuracy.isAcceptableForPing(tooWeak), isFalse);
      expect(BackgroundLocationAccuracy.isAcceptableForPath(weak), isFalse);
    });
  });

  group('LocationPathBatchPolicy', () {
    test('blocks path for stationary ping trigger on both platforms', () {
      final shouldQueue = LocationPathBatchPolicy.shouldQueue(
        policy: _policy(),
        fusion: _fusion(),
        keepTrigger: LocationKeepPointTrigger.stationaryPing,
      );
      expect(shouldQueue, isFalse);
    });

    test('blocks path when motion fusion says stationary', () {
      final shouldQueue = LocationPathBatchPolicy.shouldQueue(
        policy: _policy(speedKmh: 6),
        fusion: _fusion(fusedState: 'stationary', speedKmh: 6),
      );
      expect(shouldQueue, isFalse);
    });

    test('allows path when walking with trusted speed', () {
      final shouldQueue = LocationPathBatchPolicy.shouldQueue(
        policy: _policy(speedKmh: 6),
        fusion: _fusion(fusedState: 'walking', speedKmh: 6),
      );
      expect(shouldQueue, isTrue);
    });

    test('blocks path when GPS speed fakes movement but motion is unknown', () {
      final shouldQueue = LocationPathBatchPolicy.shouldQueue(
        policy: _policy(speedKmh: 8),
        fusion: _fusion(fusedState: 'unknown', nativeActivity: 'unknown', speedKmh: 8),
      );
      expect(shouldQueue, isFalse);
    });
  });

  group('LocationPathOutlierGate', () {
    test('rejects accuracy spike for path', () {
      final gate = LocationPathOutlierGate();
      gate.markAccepted(_pos(lat: 37.77, lng: -122.42, accuracy: 2));

      final decision = gate.evaluate(
        _pos(lat: 37.7701, lng: -122.4201, accuracy: 22),
      );

      expect(decision.shouldQueue, isFalse);
      expect(decision.reason, LocationPathOutlierReason.accuracySpike);
    });

    test('rejects impossible jump for walking path', () {
      final gate = LocationPathOutlierGate();
      gate.markAccepted(_pos(lat: 37.77, lng: -122.42, accuracy: 5));

      final decision = gate.evaluate(
        _pos(lat: 37.7720, lng: -122.4220, accuracy: 8),
      );

      expect(decision.shouldQueue, isFalse);
      expect(decision.reason, LocationPathOutlierReason.jumpOutlier);
    });

    test('allows normal driving travel with good accuracy', () {
      final gate = LocationPathOutlierGate();
      final start = DateTime.now().toUtc();
      gate.markAccepted(
        _pos(lat: 37.7700, lng: -122.4200, accuracy: 2, timestamp: start),
      );

      // ~55m north in 2s at ~40 km/h — previously rejected as jumpOutlier.
      final decision = gate.evaluate(
        _pos(
          lat: 37.7705,
          lng: -122.4200,
          accuracy: 2,
          timestamp: start.add(const Duration(seconds: 2)),
          speedMs: 11,
        ),
        mode: LocationPathMovementMode.driving,
        speedKmh: 40,
      );

      expect(decision.shouldQueue, isTrue);
    });

    test('recovers stuck driving jump cascade after repeated rejects', () {
      final gate = LocationPathOutlierGate();
      final start = DateTime.now().toUtc();
      gate.markAccepted(
        _pos(lat: 37.7700, lng: -122.4200, accuracy: 2, timestamp: start),
      );

      // Far jump that still exceeds even the new driving floor initially.
      for (var i = 1; i <= 2; i++) {
        final rejected = gate.evaluate(
          _pos(
            lat: 37.7800,
            lng: -122.4200,
            accuracy: 2,
            timestamp: start.add(Duration(seconds: i)),
            speedMs: 12,
          ),
          mode: LocationPathMovementMode.driving,
          speedKmh: 45,
        );
        expect(rejected.reason, LocationPathOutlierReason.jumpOutlier);
      }

      final recovered = gate.evaluate(
        _pos(
          lat: 37.7800,
          lng: -122.4200,
          accuracy: 2,
          timestamp: start.add(const Duration(seconds: 3)),
          speedMs: 12,
        ),
        mode: LocationPathMovementMode.driving,
        speedKmh: 45,
      );
      expect(recovered.shouldQueue, isTrue);
    });

    test('resumes path after accuracy recovers', () {
      final gate = LocationPathOutlierGate();
      gate.markAccepted(_pos(lat: 37.77, lng: -122.42, accuracy: 2));

      gate.evaluate(_pos(lat: 37.7701, lng: -122.4201, accuracy: 22));

      final paused = gate.evaluate(
        _pos(lat: 37.7702, lng: -122.4202, accuracy: 20),
      );
      expect(paused.reason, LocationPathOutlierReason.accuracySpikePause);

      final recovered = gate.evaluate(
        _pos(lat: 37.77001, lng: -122.42001, accuracy: 6),
      );
      expect(recovered.shouldQueue, isTrue);
    });
  });

  group('LocationPathDrivingSignalStop', () {
    test('keeps driving mode through vehicle red-light still', () {
      expect(
        LocationPathMovementModePolicy.resolve(
          policy: _policy(speedKmh: 0),
          fusion: _fusion(
            fusedState: 'driving_stopped',
            nativeActivity: 'still',
            speedKmh: 0,
          ),
        ),
        LocationPathMovementMode.driving,
      );
    });

    test('does not re-block path after driving session unlocks', () {
      final guard = LocationPathStationaryGuard();
      final driving = _fusion(
        fusedState: 'driving',
        nativeActivity: 'automotive',
        speedKmh: 30,
      );
      final policy = _policy(speedKmh: 30);

      guard.observe(
        position: _pos(lat: 37.7700, lng: -122.4200),
        mode: LocationPathMovementMode.driving,
        fusion: driving,
        policy: policy,
      );
      guard.observe(
        position: _pos(lat: 37.7702, lng: -122.4200),
        mode: LocationPathMovementMode.driving,
        fusion: driving,
        policy: policy,
      );
      expect(guard.blocksPathUpload, isFalse);

      // Red light: still / zero speed should not re-lock.
      guard.observe(
        position: _pos(lat: 37.7702, lng: -122.4200),
        mode: LocationPathMovementMode.driving,
        fusion: _fusion(
          fusedState: 'driving_stopped',
          nativeActivity: 'still',
          speedKmh: 0,
        ),
        policy: _policy(speedKmh: 0),
      );
      expect(guard.blocksPathUpload, isFalse);
    });
  });
}
