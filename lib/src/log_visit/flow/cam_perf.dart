class CamPerf {
  CamPerf._();

  static void resetCameraOpenFlow() {}

  static void markGpsFlow() {}

  static void markUsePhoto(String? captureId) {}

  static void markReviewOpen(String? captureId) {}

  static void markDraftVisible(String? captureId) {}

  static void stage(
    String? captureId,
    String name, {
    String? detail,
    bool usePhotoClock = false,
    bool useReviewClock = false,
    bool useGpsClock = false,
  }) {}

  static void log(String? captureId, String name, [String detail = '']) {}

  static void firstFrameOnce(
    String key,
    String? captureId,
    String name, {
    bool fromDraftVisible = false,
  }) {}

  static String mb(int bytes) {
    return (bytes / (1024 * 1024)).toStringAsFixed(2);
  }

  static String throughput(int bytes, int elapsedMs) {
    if (elapsedMs <= 0) return 'n/a';
    final mbPerSec = (bytes / (1024 * 1024)) / (elapsedMs / 1000.0);
    return '${mbPerSec.toStringAsFixed(2)}MB/s';
  }
}
