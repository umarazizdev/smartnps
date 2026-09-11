import Foundation

enum CamPerf {
  static func configure(isDebug: Bool) {}

  static func resetSession() {}

  static func markFirstPreviewFrame() {}

  static func markShutterTap(captureId: String? = nil) {}

  static func markCapturePhotoInvoke(captureId: String?) {}

  static func markProcessedCallback(captureId: String?) {}

  static func markFileDataEnd(captureId: String?) {}

  static func markWriteEnd(captureId: String?) {}

  static func markValidationEnd(captureId: String?) {}

  static func markNativeResultFinish(captureId: String?) {}

  static func stage(
    _ name: String,
    captureId: String? = nil,
    detail: String? = nil
  ) {}

  static func log(
    _ captureId: String?,
    _ name: String,
    _ detail: String = ""
  ) {}
}
