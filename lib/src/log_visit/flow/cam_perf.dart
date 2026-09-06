import 'package:flutter/foundation.dart';

/// DEBUG-only camera / draft performance milestones. Prefix: `[CAM_PERF]`.
///
/// Timer origins are independent:
/// - [resetCameraOpenFlow] — camera MethodChannel open → result (includes preview wait)
/// - [markReviewOpen] — Review route open → first display frame
/// - [markUsePhoto] — Use Photo / Done tap → complete
/// - [markDraftVisible] — Draft becomes interactive after Review pop → thumbnail frame
/// - [markGpsFlow] — GPS prefetch / continue for the current camera session
///
/// Native shutter latency uses Android/iOS SHUTTER_SUMMARY, not Flutter open timers.
class CamPerf {
  CamPerf._();

  static int? _cameraOpenMs;
  static int? _usePhotoMs;
  static int? _lastStageMs;
  static int? _reviewOpenMs;
  static int? _draftVisibleMs;
  static int? _gpsFlowMs;
  static final Set<String> _loggedImageFrames = <String>{};

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  static void resetCameraOpenFlow() {
    if (!kDebugMode) return;
    _cameraOpenMs = _now();
    _lastStageMs = _cameraOpenMs;
    log(null, 'CAMERA_OPEN_FLOW_START', 't=$_cameraOpenMs');
  }

  static void markGpsFlow() {
    if (!kDebugMode) return;
    _gpsFlowMs = _now();
    log(null, 'GPS_FLOW_START', 't=$_gpsFlowMs');
  }

  static void markUsePhoto(String? captureId) {
    if (!kDebugMode) return;
    _usePhotoMs = _now();
    _lastStageMs = _usePhotoMs;
    log(captureId, 'USE_PHOTO_TAP', 't=$_usePhotoMs');
  }

  static void markReviewOpen(String? captureId) {
    if (!kDebugMode) return;
    _reviewOpenMs = _now();
    _lastStageMs = _reviewOpenMs;
    log(captureId, 'REVIEW_SCREEN_OPEN_START', 't=$_reviewOpenMs');
  }

  static void markDraftVisible(String? captureId) {
    if (!kDebugMode) return;
    _draftVisibleMs = _now();
    log(captureId, 'DRAFT_VISIBLE_AFTER_REVIEW', 't=$_draftVisibleMs');
  }

  static void stage(
    String? captureId,
    String name, {
    String? detail,
    bool usePhotoClock = false,
    bool useReviewClock = false,
    bool useGpsClock = false,
  }) {
    if (!kDebugMode) return;
    final now = _now();
    final last = _lastStageMs ?? now;
    final sinceLast = now - last;
    _lastStageMs = now;
    final int? origin;
    final String originLabel;
    if (usePhotoClock) {
      origin = _usePhotoMs;
      originLabel = 'usePhoto';
    } else if (useReviewClock) {
      origin = _reviewOpenMs;
      originLabel = 'review';
    } else if (useGpsClock) {
      origin = _gpsFlowMs;
      originLabel = 'gps';
    } else {
      origin = _cameraOpenMs;
      originLabel = 'cameraOpen';
    }
    final total = origin == null ? 0 : now - origin;
    final extra = detail == null || detail.isEmpty ? '' : ' $detail';
    log(
      captureId,
      name,
      '+${sinceLast}ms total=${total}ms origin=$originLabel$extra',
    );
  }

  static void log(String? captureId, String name, [String detail = '']) {
    if (!kDebugMode) return;
    final idPart = (captureId == null || captureId.isEmpty)
        ? ''
        : ' captureId=$captureId';
    final detailPart = detail.isEmpty ? '' : ' $detail';
    debugPrint('[CAM_PERF]$idPart $name$detailPart');
  }

  static void firstFrameOnce(
    String key,
    String? captureId,
    String name, {
    bool fromDraftVisible = false,
  }) {
    if (!kDebugMode) return;
    if (!_loggedImageFrames.add(key)) return;
    final int? origin;
    final String label;
    if (fromDraftVisible) {
      origin = _draftVisibleMs ?? _reviewOpenMs;
      label = 'sinceDraftVisible';
    } else {
      origin = _reviewOpenMs;
      label = 'sinceReviewOpen';
    }
    final total = origin == null ? 0 : _now() - origin;
    log(captureId, name, 'total=${total}ms $label');
  }

  static String mb(int bytes) {
    return (bytes / (1024 * 1024)).toStringAsFixed(2);
  }

  static String throughput(int bytes, int elapsedMs) {
    if (elapsedMs <= 0) return 'n/a';
    final mbPerSec = (bytes / (1024 * 1024)) / (elapsedMs / 1000.0);
    return '${mbPerSec.toStringAsFixed(2)}MB/s';
  }
}
