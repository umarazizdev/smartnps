import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

import 'cam_perf.dart';
import 'visit_gps_session.dart';
import 'visit_media_draft_store.dart';
import 'visit_media_geo.dart';
import 'visit_video_flow_controller.dart';

/// Result of [CaptureWorkCoordinator.waitForAcceptRequirements].
class CaptureAcceptWaitResult {
  const CaptureAcceptWaitResult({
    required this.durable,
    required this.geo,
    required this.durableWasReady,
    required this.gpsWasReady,
  });

  final VisitMediaItem? durable;
  final VisitMediaGeo geo;
  final bool durableWasReady;
  final bool gpsWasReady;
}

/// Owns async preparation for one native camera session / capture.
///
/// Session-scoped: GPS prefetch + draft context prewarm while preview is open.
/// Capture-scoped: warm durable import + GPS continuation for the current
/// [captureId]. Retake bumps generation and drops capture-scoped futures.
class CaptureWorkCoordinator {
  CaptureWorkCoordinator._({
    required this.sessionId,
    required this.expectedType,
  });

  static CaptureWorkCoordinator? _active;

  /// The coordinator for the current camera-open session, if any.
  static CaptureWorkCoordinator? get active => _active;

  final String sessionId;
  final VisitMediaType expectedType;

  int _generation = 0;
  bool _sessionDisposed = false;
  bool _captureCancelled = false;
  bool _firstFrameSeen = false;

  String? captureId;
  DateTime? captureTimestamp;
  VisitMediaType? captureMediaType;

  Future<void>? draftContextPrewarmFuture;
  Future<void>? gpsPrefetchFuture;
  Future<VisitMediaGeo?>? gpsContinueFuture;
  Future<VisitMediaItem?>? warmPersistFuture;
  bool _warmPersistCompleted = false;

  VisitMediaGeo? _latestGeo;
  String? _durablePath;
  Object? _warmError;

  Completer<VisitMediaGeo?>? _gpsReadyCompleter;

  int get generation => _generation;
  bool get isDisposed => _sessionDisposed;
  bool get isCaptureCancelled => _captureCancelled;
  String? get durablePath => _durablePath;
  VisitMediaGeo? get latestGeo => _latestGeo;

  bool get isWarmPersistCompleted => _warmPersistCompleted;

  /// Test / manual attachment of an in-flight warm import future.
  void attachWarmPersist(Future<VisitMediaItem?> future) {
    warmPersistFuture = future.then(
      (item) {
        _durablePath = item?.path;
        _warmPersistCompleted = true;
        return item;
      },
      onError: (Object error, StackTrace stackTrace) {
        _warmError = error;
        _warmPersistCompleted = true;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  /// Starts a new camera-open session. Disposes any previous active session.
  static CaptureWorkCoordinator beginSession({
    required VisitMediaType expectedType,
  }) {
    _active?.disposeSession(reason: 'superseded');
    final sessionId =
        'cam_${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final coordinator = CaptureWorkCoordinator._(
      sessionId: sessionId,
      expectedType: expectedType,
    );
    _active = coordinator;
    coordinator._startParallelPrewarm();
    return coordinator;
  }

  void _startParallelPrewarm() {
    if (_sessionDisposed) return;
    CamPerf.stage(null, 'CAMERA_PARALLEL_PREWARM_START');
    CamPerf.markGpsFlow();

    gpsPrefetchFuture = _prefetchGps();
    draftContextPrewarmFuture = _prewarmDraftContext();

    unawaited(
      Future.wait<void>([
        gpsPrefetchFuture!.catchError((_) {}),
        draftContextPrewarmFuture!.catchError((_) {}),
      ]).then((_) {
        if (_sessionDisposed) return;
        CamPerf.stage(null, 'CAMERA_PARALLEL_PREWARM_END');
      }),
    );
  }

  Future<void> _prefetchGps() async {
    CamPerf.stage(null, 'GPS_PREFETCH_START', useGpsClock: true);
    try {
      final granted = await VisitGpsSession.hasGrantedPermission();
      if (!granted) {
        CamPerf.stage(
          null,
          'GPS_PREFETCH_SKIPPED',
          detail: 'permissionNotGranted',
          useGpsClock: true,
        );
        return;
      }
      final services = await Geolocator.isLocationServiceEnabled();
      if (!services) {
        CamPerf.stage(
          null,
          'GPS_PREFETCH_SKIPPED',
          detail: 'servicesOff',
          useGpsClock: true,
        );
        return;
      }

      // Do not block camera — ensure warm stream / seed only.
      unawaited(VisitGpsSession.instance.start());

      final existing = VisitGpsSession.instance.latestUsableFresh;
      if (existing != null) {
        _logFixReceived(existing, acceptable: true);
        return;
      }

      // Best-effort one-shot while user aims; ignore failures.
      final position = await VisitGpsSession.instance.acquireForCapture();
      if (position != null) {
        final ok = VisitGpsSession.isUsableAcceptable(position);
        _logFixReceived(position, acceptable: ok);
      } else {
        CamPerf.stage(
          null,
          'GPS_PREFETCH_END',
          detail: 'noFixYet',
          useGpsClock: true,
        );
      }
    } catch (error) {
      CamPerf.stage(
        null,
        'GPS_PREFETCH_END',
        detail: 'error',
        useGpsClock: true,
      );
      if (kDebugMode) {
        debugPrint('[CaptureWork] GPS prefetch error: $error');
      }
    }
  }

  void _logFixReceived(Position position, {required bool acceptable}) {
    final ageMs = DateTime.now().difference(position.timestamp).inMilliseconds;
    CamPerf.stage(
      captureId,
      'GPS_FIX_RECEIVED',
      detail: 'accuracyM=${position.accuracy.round()}',
      useGpsClock: true,
    );
    CamPerf.stage(
      captureId,
      'GPS_FIX_AGE',
      detail: 'ageMs=$ageMs',
      useGpsClock: true,
    );
    if (acceptable) {
      CamPerf.stage(
        captureId,
        'GPS_FIX_ACCEPTABLE',
        detail: 'ageMs=$ageMs accuracyM=${position.accuracy.round()}',
        useGpsClock: true,
      );
    }
  }

  Future<void> _prewarmDraftContext() async {
    CamPerf.stage(null, 'DRAFT_CONTEXT_PREWARM_START');
    try {
      final flow = _flowOrNull();
      final key =
          flow?.activeDraftKey.value ??
          VisitDraftKey.fromContext(flow?.patrolContext.value);
      if (flow != null && flow.activeDraftKey.value != key) {
        flow.activeDraftKey.value = key;
      }
      await VisitMediaDraftStore.instance.prewarmCaptureContext(
        key: key,
        type: expectedType,
      );
      CamPerf.stage(
        null,
        'DRAFT_CONTEXT_PREWARM_END',
        detail: 'key=${key.folderName} type=${expectedType.name}',
      );
    } catch (error) {
      CamPerf.stage(
        null,
        'DRAFT_CONTEXT_PREWARM_END',
        detail: 'fallbackLater error=${error.runtimeType}',
      );
    }
  }

  VisitVideoFlowController? _flowOrNull() {
    if (!Get.isRegistered<VisitVideoFlowController>()) return null;
    return Get.find<VisitVideoFlowController>();
  }

  /// Bind native capture result. Does not await GPS / IO.
  VisitMediaGeo bindNativeResult({
    required String captureId,
    required DateTime capturedAt,
    required VisitMediaType mediaType,
  }) {
    _generation += 1;
    _captureCancelled = false;
    _firstFrameSeen = false;
    warmPersistFuture = null;
    _warmPersistCompleted = false;
    gpsContinueFuture = null;
    _warmError = null;
    _durablePath = null;
    _gpsReadyCompleter = Completer<VisitMediaGeo?>();

    this.captureId = captureId;
    captureTimestamp = capturedAt;
    captureMediaType = mediaType;

    final fix = VisitGpsSession.instance.selectFixForCapture(capturedAt);
    final ageMs = fix == null
        ? null
        : capturedAt.difference(fix.timestamp).abs().inMilliseconds;
    CamPerf.stage(
      captureId,
      'GPS_SNAPSHOT_AT_SHUTTER',
      detail: fix == null
          ? 'hasFix=false'
          : 'hasFix=true ageMs=$ageMs accuracyM=${fix.accuracy.round()}',
      useGpsClock: true,
    );

    if (fix != null) {
      _latestGeo = VisitMediaGeo(
        capturedAt: capturedAt,
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracyMeters: fix.accuracy,
      );
      _completeGpsReady(_latestGeo);
      CamPerf.stage(
        captureId,
        'GPS_READY_FOR_ACCEPT',
        detail: 'fromShutterSnapshot',
        useGpsClock: true,
      );
      return _latestGeo!;
    }

    _latestGeo = VisitMediaGeo(capturedAt: capturedAt);
    CamPerf.stage(captureId, 'GPS_CONTINUE_AFTER_SHUTTER', useGpsClock: true);
    gpsContinueFuture = _continueGps(capturedAt, _generation);
    return _latestGeo!;
  }

  Future<VisitMediaGeo?> _continueGps(DateTime capturedAt, int gen) async {
    try {
      final position = await VisitGpsSession.instance.acquireForCapture();
      if (_sessionDisposed || _captureCancelled || gen != _generation) {
        return null;
      }
      if (position == null ||
          !VisitGpsSession.isAcceptableForCapture(position, capturedAt)) {
        _completeGpsReady(null);
        return null;
      }
      _logFixReceived(position, acceptable: true);
      final geo = VisitMediaGeo(
        capturedAt: capturedAt,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );
      _latestGeo = geo;
      _completeGpsReady(geo);
      CamPerf.stage(
        captureId,
        'GPS_READY_FOR_ACCEPT',
        detail: 'fromContinue',
        useGpsClock: true,
      );
      return geo;
    } catch (_) {
      if (gen == _generation) _completeGpsReady(null);
      return null;
    }
  }

  void _completeGpsReady(VisitMediaGeo? geo) {
    final c = _gpsReadyCompleter;
    if (c != null && !c.isCompleted) {
      c.complete(geo);
    }
  }

  /// Called when Review has painted a useful first frame (photo or video).
  Future<void> onReviewFirstFrame({
    required String captureId,
    required String displayPath,
    required VisitMediaType mediaType,
    required VisitMediaGeo geo,
    required void Function(VisitMediaItem? item) onWarmItem,
    required void Function(Object error) onWarmError,
    required void Function(VisitMediaGeo geo) onGeoUpdated,
  }) async {
    if (_sessionDisposed || _captureCancelled) return;
    if (this.captureId != captureId) return;
    if (_firstFrameSeen) return;
    _firstFrameSeen = true;

    CamPerf.stage(captureId, 'REVIEW_FIRST_FRAME', useReviewClock: true);
    await WidgetsBinding.instance.endOfFrame;
    if (_sessionDisposed || _captureCancelled || this.captureId != captureId) {
      return;
    }

    CamPerf.stage(
      captureId,
      'WARM_WORK_START_AFTER_FIRST_FRAME',
      useReviewClock: true,
    );

    final gen = _generation;
    final flow = _flowOrNull();
    if (flow == null) return;

    // Parallel: durable import + GPS continuation (if still needed).
    CamPerf.stage(captureId, 'PARALLEL_DURABLE_START', useReviewClock: true);
    CamPerf.stage(captureId, 'PARALLEL_METADATA_START', useReviewClock: true);

    warmPersistFuture = () async {
      try {
        final item = await flow.finalizeCaptureDraft(
          previewPath: displayPath,
          type: mediaType,
          captureId: captureId,
          geo: _latestGeo ?? geo,
          markAccepted: false,
        );
        if (_sessionDisposed || _captureCancelled || gen != _generation) {
          return item;
        }
        _durablePath = item?.path;
        _warmPersistCompleted = true;
        onWarmItem(item);
        CamPerf.stage(
          captureId,
          'PARALLEL_DURABLE_END',
          detail: 'pathReady=${item != null}',
          useReviewClock: true,
        );
        return item;
      } catch (error) {
        _warmError = error;
        _warmPersistCompleted = true;
        if (!_sessionDisposed && !_captureCancelled && gen == _generation) {
          onWarmError(error);
        }
        CamPerf.stage(
          captureId,
          'PARALLEL_DURABLE_END',
          detail: 'error=${error.runtimeType}',
          useReviewClock: true,
        );
        rethrow;
      }
    }();

    unawaited(warmPersistFuture!.catchError((_) => null));

    // Metadata after draft context prewarm (already started) — mark complete.
    unawaited(
      (draftContextPrewarmFuture ?? Future<void>.value()).whenComplete(() {
        CamPerf.stage(captureId, 'PARALLEL_METADATA_END', useReviewClock: true);
      }),
    );

    final gpsFut = gpsContinueFuture;
    if (gpsFut != null) {
      unawaited(
        gpsFut.then((resolved) {
          if (resolved == null ||
              _sessionDisposed ||
              _captureCancelled ||
              gen != _generation) {
            return;
          }
          onGeoUpdated(resolved);
        }),
      );
    }
  }

  /// Use Photo: await only unfinished required work.
  Future<CaptureAcceptWaitResult> waitForAcceptRequirements({
    required bool gpsRequired,
    required VisitMediaGeo currentGeo,
  }) async {
    final id = captureId;
    final durableReady = isWarmPersistCompleted && _warmError == null;
    final gpsReady =
        currentGeo.hasCoordinates || (_latestGeo?.hasCoordinates ?? false);

    CamPerf.stage(id, 'USE_PHOTO_REQUIRED_WAIT_START', usePhotoClock: true);
    CamPerf.stage(
      id,
      'USE_PHOTO_WAIT_COMPONENTS',
      detail:
          'durableReady=$durableReady gpsReady=$gpsReady '
          'gpsRequired=$gpsRequired metadataReady=true',
      usePhotoClock: true,
    );

    VisitMediaItem? durable;
    final warm = warmPersistFuture;
    if (warm != null) {
      durable = await warm;
    }
    if (_warmError != null && durable == null) {
      CamPerf.stage(id, 'USE_PHOTO_REQUIRED_WAIT_END', usePhotoClock: true);
      throw _warmError!;
    }

    var geo = currentGeo.hasCoordinates
        ? currentGeo
        : (_latestGeo ?? currentGeo);

    if (gpsRequired && !geo.hasCoordinates) {
      final cont = gpsContinueFuture;
      if (cont != null) {
        final resolved = await cont;
        if (resolved != null && resolved.hasCoordinates) {
          geo = resolved;
        }
      }
      if (!geo.hasCoordinates) {
        final c = _gpsReadyCompleter;
        if (c != null && !c.isCompleted) {
          final resolved = await c.future.timeout(
            VisitGpsSession.oneShotTimeout,
            onTimeout: () => null,
          );
          if (resolved != null && resolved.hasCoordinates) {
            geo = resolved;
          }
        }
      }
    }

    CamPerf.stage(id, 'USE_PHOTO_REQUIRED_WAIT_END', usePhotoClock: true);
    return CaptureAcceptWaitResult(
      durable: durable,
      geo: geo,
      durableWasReady: durableReady,
      gpsWasReady: gpsReady,
    );
  }

  /// Close / discard current capture work (keep or dispose session separately).
  void cancelCapture({String reason = 'close'}) {
    _captureCancelled = true;
    _generation += 1;
    warmPersistFuture = null;
    gpsContinueFuture = null;
    _warmError = null;
    captureId = null;
    _firstFrameSeen = false;
    if (kDebugMode) {
      debugPrint(
        '[CaptureWork] cancelCapture reason=$reason session=$sessionId',
      );
    }
  }

  /// Retake: drop capture-scoped work; keep session GPS / draft prewarm.
  void prepareRetake() {
    cancelCapture(reason: 'retake');
  }

  void disposeSession({String reason = 'done'}) {
    if (_sessionDisposed) return;
    _sessionDisposed = true;
    cancelCapture(reason: reason);
    if (identical(_active, this)) {
      _active = null;
    }
    if (kDebugMode) {
      debugPrint('[CaptureWork] disposeSession reason=$reason id=$sessionId');
    }
  }

  /// Ensures a post-frame / end-of-frame barrier without fake delays.
  static Future<void> waitForNextFrame() async {
    final completer = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.endOfFrame.then((_) {
        if (!completer.isCompleted) completer.complete();
      });
    });
    // If no frame is scheduled, complete on microtask after endOfFrame.
    unawaited(
      WidgetsBinding.instance.endOfFrame.then((_) {
        if (!completer.isCompleted) {
          scheduleMicrotask(() {
            if (!completer.isCompleted) completer.complete();
          });
        }
      }),
    );
    await completer.future;
  }
}
