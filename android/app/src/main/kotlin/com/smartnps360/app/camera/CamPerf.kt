package com.smartnps360.app.camera

object CamPerf {
  fun configure(debuggable: Boolean) {}

  fun resetSession() {}

  fun markFirstPreviewFrame() {}

  fun markShutterTap(captureId: String? = null) {}

  fun markTakePictureInvoke(captureId: String?) {}

  fun markImageCallback(captureId: String?) {}

  fun markValidationComplete(captureId: String?) {}

  fun markNativeResultFinish(captureId: String?) {}

  fun noteRebind(reason: String) {}

  fun noteUnbindAll(where: String) {}

  fun stage(captureId: String?, name: String, detail: String? = null) {}

  fun log(captureId: String?, name: String, detail: String = "") {}
}
