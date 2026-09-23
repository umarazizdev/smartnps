package com.smartnps360.app.camera

import android.util.Log

/**
 * Lightweight shutter/bind timing breadcrumbs. Always logs to Logcat under
 * [NativeCameraContract.LOG_TAG] so Android capture regressions are visible
 * without a separate debug flag.
 */
object CamPerf {
  @Volatile
  private var debuggable: Boolean = true

  fun configure(debuggable: Boolean) {
    this.debuggable = debuggable
  }

  fun resetSession() {
    log(null, "PERF_RESET_SESSION")
  }

  fun markFirstPreviewFrame() {
    log(null, "FIRST_PREVIEW_FRAME_MARK")
  }

  fun markShutterTap(captureId: String? = null) {
    log(captureId, "SHUTTER_TAP")
  }

  fun markTakePictureInvoke(captureId: String?) {
    log(captureId, "TAKE_PICTURE_INVOKE")
  }

  fun markImageCallback(captureId: String?) {
    log(captureId, "IMAGE_CALLBACK")
  }

  fun markValidationComplete(captureId: String?) {
    log(captureId, "VALIDATION_COMPLETE")
  }

  fun markNativeResultFinish(captureId: String?) {
    log(captureId, "NATIVE_RESULT_FINISH")
  }

  fun noteRebind(reason: String) {
    log(null, "REBIND", reason)
  }

  fun noteUnbindAll(where: String) {
    log(null, "UNBIND_ALL", where)
  }

  fun stage(captureId: String?, name: String, detail: String? = null) {
    log(captureId, name, detail.orEmpty())
  }

  fun log(captureId: String?, name: String, detail: String = "") {
    if (!debuggable) return
    val idPart = if (captureId.isNullOrBlank()) "" else " id=$captureId"
    val detailPart = if (detail.isBlank()) "" else " $detail"
    Log.d(NativeCameraContract.LOG_TAG, "PERF $name$idPart$detailPart")
  }
}
