import Foundation

/// DEBUG-only camera performance milestones. Prefix: `[CAM_PERF]`
enum CamPerf {
  private static var shutterTapAt: CFAbsoluteTime = 0
  private static var lastStageAt: CFAbsoluteTime = 0
  private static var capturePhotoInvokeAt: CFAbsoluteTime = 0
  private static var processedCallbackAt: CFAbsoluteTime = 0
  private static var fileDataEndAt: CFAbsoluteTime = 0
  private static var writeEndAt: CFAbsoluteTime = 0
  private static var validationEndAt: CFAbsoluteTime = 0
  private static var activeCaptureId: String?

  static func markShutterTap(captureId: String? = nil) {
    #if DEBUG
    shutterTapAt = CFAbsoluteTimeGetCurrent()
    lastStageAt = shutterTapAt
    capturePhotoInvokeAt = 0
    processedCallbackAt = 0
    fileDataEndAt = 0
    writeEndAt = 0
    validationEndAt = 0
    activeCaptureId = captureId
    log(captureId, "SHUTTER_TAP", "t=\(shutterTapAt)")
    #endif
  }

  static func stage(_ name: String, captureId: String? = nil, detail: String = "") {
    #if DEBUG
    let id = captureId ?? activeCaptureId
    let now = CFAbsoluteTimeGetCurrent()
    let sinceLast = Int((now - lastStageAt) * 1000)
    let total = shutterTapAt > 0 ? Int((now - shutterTapAt) * 1000) : 0
    lastStageAt = now
    let extra = detail.isEmpty ? "" : " \(detail)"
    log(id, name, "+\(sinceLast)ms total=\(total)ms\(extra)")
    #endif
  }

  static func markCapturePhotoInvoke(captureId: String?) {
    #if DEBUG
    activeCaptureId = captureId ?? activeCaptureId
    capturePhotoInvokeAt = CFAbsoluteTimeGetCurrent()
    stage("AV_CAPTURE_PHOTO_INVOKE", captureId: captureId)
    #endif
  }

  static func markProcessedCallback(captureId: String?) {
    #if DEBUG
    processedCallbackAt = CFAbsoluteTimeGetCurrent()
    stage("DID_FINISH_PROCESSING_PHOTO_ENTER", captureId: captureId)
    #endif
  }

  static func markFileDataEnd(captureId: String?) {
    #if DEBUG
    fileDataEndAt = CFAbsoluteTimeGetCurrent()
    stage("FILE_DATA_REPRESENTATION_END", captureId: captureId)
    #endif
  }

  static func markWriteEnd(captureId: String?) {
    #if DEBUG
    writeEndAt = CFAbsoluteTimeGetCurrent()
    stage("FILE_WRITE_END", captureId: captureId)
    #endif
  }

  static func markValidationEnd(captureId: String?) {
    #if DEBUG
    validationEndAt = CFAbsoluteTimeGetCurrent()
    stage("PHOTO_VALIDATION_END", captureId: captureId)
    #endif
  }

  static func markNativeResultFinish(captureId: String?) {
    #if DEBUG
    stage("NATIVE_RESULT_FINISH", captureId: captureId)
    summary(captureId: captureId)
    #endif
  }

  static func log(_ captureId: String?, _ name: String, _ detail: String = "") {
    #if DEBUG
    let idPart = (captureId?.isEmpty == false) ? " captureId=\(captureId!)" : ""
    let detailPart = detail.isEmpty ? "" : " \(detail)"
    NSLog("[CAM_PERF]\(idPart) \(name)\(detailPart)")
    #endif
  }

  private static func summary(captureId: String?) {
    #if DEBUG
    guard shutterTapAt > 0 else { return }
    func ms(_ from: CFAbsoluteTime, _ to: CFAbsoluteTime) -> Int {
      guard from > 0, to > 0 else { return -1 }
      return Int((to - from) * 1000)
    }
    let now = CFAbsoluteTimeGetCurrent()
    let a = ms(shutterTapAt, capturePhotoInvokeAt)
    let b = ms(capturePhotoInvokeAt, processedCallbackAt)
    let c = ms(processedCallbackAt, fileDataEndAt)
    let d = ms(fileDataEndAt, writeEndAt)
    let e = ms(writeEndAt, validationEndAt)
    let total = Int((now - shutterTapAt) * 1000)
    log(
      captureId,
      "SHUTTER_SUMMARY",
      "A_tap_to_capturePhoto=\(a)ms " +
        "B_capturePhoto_to_processed=\(b)ms " +
        "C_processed_to_fileData=\(c)ms " +
        "D_fileData_to_write=\(d)ms " +
        "E_write_to_validation=\(e)ms " +
        "F_total_shutter_to_result=\(total)ms"
    )
    #endif
  }
}
