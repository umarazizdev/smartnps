package com.smartnps360.app.camera

import android.os.SystemClock
import android.util.Log

/**
 * DEBUG-only camera performance milestones.
 * Prefix: [CAM_PERF]
 *
 * Enabled when [configure] is called with debuggable=true (Activity onCreate).
 * Call [resetSession] at the start of every NativeCameraActivity/Session so
 * prior opens cannot produce false post-preview rebind warnings.
 */
object CamPerf {
  private const val TAG = "CAM_PERF"

  @Volatile
  private var enabled = false

  fun configure(debuggable: Boolean) {
    enabled = debuggable
  }

  /** Clears session-scoped state for a newly opened camera UI. */
  fun resetSession() {
    firstPreviewFrameAtMs = 0L
    rebindAfterPreview = false
    shutterTapAtMs = 0L
    lastStageAtMs = 0L
    takePictureInvokeAtMs = 0L
    imageCallbackAtMs = 0L
    validationCompleteAtMs = 0L
    if (enabled) {
      log(null, "SESSION_RESET", "camPerf timers cleared for new Activity")
    }
  }

  @Volatile
  var firstPreviewFrameAtMs: Long = 0L
    private set

  @Volatile
  private var rebindAfterPreview = false

  @Volatile
  private var shutterTapAtMs: Long = 0L

  @Volatile
  private var lastStageAtMs: Long = 0L

  @Volatile
  private var takePictureInvokeAtMs: Long = 0L

  @Volatile
  private var imageCallbackAtMs: Long = 0L

  @Volatile
  private var validationCompleteAtMs: Long = 0L

  fun markFirstPreviewFrame() {
    if (!enabled) return
    // Only the first STREAMING event in this session counts.
    if (firstPreviewFrameAtMs > 0L) return
    firstPreviewFrameAtMs = SystemClock.elapsedRealtime()
    rebindAfterPreview = false
    log(null, "FIRST_PREVIEW_FRAME", "ready for capture")
  }

  fun markShutterTap(captureId: String? = null) {
    if (!enabled) return
    shutterTapAtMs = SystemClock.elapsedRealtime()
    lastStageAtMs = shutterTapAtMs
    takePictureInvokeAtMs = 0L
    imageCallbackAtMs = 0L
    validationCompleteAtMs = 0L
    if (rebindAfterPreview) {
      log(
        captureId,
        "WARNING",
        "CAMERA_REBIND_OCCURRED_BEFORE_CAPTURE " +
          "sinceFirstPreview=${shutterTapAtMs - firstPreviewFrameAtMs}ms",
      )
    }
    log(captureId, "SHUTTER_TAP", "t=$shutterTapAtMs")
  }

  fun markTakePictureInvoke(captureId: String?) {
    if (!enabled) return
    takePictureInvokeAtMs = SystemClock.elapsedRealtime()
    stage(captureId, "TAKE_PICTURE_INVOKE")
  }

  fun markImageCallback(captureId: String?) {
    if (!enabled) return
    imageCallbackAtMs = SystemClock.elapsedRealtime()
    stage(captureId, "IMAGE_FILE_CALLBACK_ENTER")
  }

  fun markValidationComplete(captureId: String?) {
    if (!enabled) return
    validationCompleteAtMs = SystemClock.elapsedRealtime()
    stage(captureId, "PHOTO_VALIDATION_COMPLETE")
  }

  fun markNativeResultFinish(captureId: String?) {
    if (!enabled) return
    stage(captureId, "NATIVE_RESULT_FINISH")
    summary(captureId)
  }

  fun noteRebind(reason: String) {
    if (!enabled) return
    // Initial "start" bind before any preview in THIS session is expected.
    val afterPreview = firstPreviewFrameAtMs > 0L
    if (afterPreview) {
      rebindAfterPreview = true
      log(
        null,
        "WARNING",
        "CAMERA_REBIND_OCCURRED_BEFORE_CAPTURE reason=$reason",
      )
    }
    log(
      null,
      "REQUEST_REBIND",
      "reason=$reason afterPreview=$afterPreview " +
        "firstPreviewAt=$firstPreviewFrameAtMs",
    )
  }

  fun noteUnbindAll(where: String) {
    if (!enabled) return
    val afterPreview = firstPreviewFrameAtMs > 0L
    if (afterPreview) {
      rebindAfterPreview = true
      log(
        null,
        "WARNING",
        "CAMERA_REBIND_OCCURRED_BEFORE_CAPTURE unbindAll where=$where",
      )
    }
    log(null, "UNBIND_ALL", "where=$where afterPreview=$afterPreview")
  }

  fun stage(captureId: String?, name: String, detail: String? = null) {
    if (!enabled) return
    val now = SystemClock.elapsedRealtime()
    val sinceLast = if (lastStageAtMs > 0L) now - lastStageAtMs else 0L
    val total = if (shutterTapAtMs > 0L) now - shutterTapAtMs else 0L
    lastStageAtMs = now
    val extra = if (detail.isNullOrBlank()) "" else " $detail"
    log(captureId, name, "+${sinceLast}ms total=${total}ms$extra")
  }

  fun log(captureId: String?, name: String, detail: String = "") {
    if (!enabled) return
    val idPart = if (captureId.isNullOrBlank()) "" else " captureId=$captureId"
    val detailPart = if (detail.isBlank()) "" else " $detail"
    Log.d(TAG, "[CAM_PERF]$idPart $name$detailPart")
  }

  private fun summary(captureId: String?) {
    if (shutterTapAtMs <= 0L) return
    val a = if (takePictureInvokeAtMs > 0L) {
      takePictureInvokeAtMs - shutterTapAtMs
    } else {
      -1L
    }
    val b = if (takePictureInvokeAtMs > 0L && imageCallbackAtMs > 0L) {
      imageCallbackAtMs - takePictureInvokeAtMs
    } else {
      -1L
    }
    val c = if (imageCallbackAtMs > 0L && validationCompleteAtMs > 0L) {
      validationCompleteAtMs - imageCallbackAtMs
    } else {
      -1L
    }
    val d = if (validationCompleteAtMs > 0L) {
      SystemClock.elapsedRealtime() - validationCompleteAtMs
    } else {
      -1L
    }
    val e = SystemClock.elapsedRealtime() - shutterTapAtMs
    log(
      captureId,
      "SHUTTER_SUMMARY",
      "A_tap_to_invoke=${a}ms " +
        "B_invoke_to_callback=${b}ms " +
        "C_callback_to_validation=${c}ms " +
        "D_validation_to_result=${d}ms " +
        "E_total_shutter_to_result=${e}ms " +
        "thread=${Thread.currentThread().name}",
    )
  }
}
