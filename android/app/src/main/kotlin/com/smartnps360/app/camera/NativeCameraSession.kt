package com.smartnps360.app.camera

import android.annotation.SuppressLint
import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CaptureRequest
import android.os.StatFs
import android.util.Log
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.Camera2Interop
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.core.UseCase
import androidx.camera.core.UseCaseGroup
import androidx.camera.core.ZoomState
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import android.os.SystemClock
import android.util.Size
import androidx.camera.extensions.ExtensionMode
import androidx.camera.extensions.ExtensionsManager
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.core.util.Consumer
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LiveData
import java.io.File
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

private const val EXT_AUTO = NativeCameraContract.ExtensionModeLabel.AUTO
private const val EXT_HDR = NativeCameraContract.ExtensionModeLabel.HDR
private const val EXT_NIGHT = NativeCameraContract.ExtensionModeLabel.NIGHT
private const val EXT_STANDARD = NativeCameraContract.ExtensionModeLabel.STANDARD

/**
 * CameraX bind/unbind, still capture, video recording, zoom, focus, flash,
 * exposure compensation, and selectable Extensions (AUTO / HDR / NIGHT) with
 * a graceful per-mode fallback ladder.
 */
@SuppressLint("UnsafeOptInUsageError")
class NativeCameraSession(
  private val context: Context,
  private val lifecycleOwner: LifecycleOwner,
  private val previewView: PreviewView,
  private val quality: String,
  private val rearCameraOnly: Boolean,
  private val requestedExtension: String? = null,
) {
  interface Listener {
    fun onSessionReady(
      hasFlash: Boolean,
      minZoom: Float,
      maxZoom: Float,
      usefulZooms: List<Double>,
      extensionMode: String?,
      availableExtensions: List<String>,
      minExposure: Int,
      maxExposure: Int,
      exposureIndex: Int,
    )

    fun onSessionError(code: String, message: String)
    fun onZoomChanged(zoomRatio: Float)
    fun onRecordingStatus(isRecording: Boolean, errorCode: String? = null)
  }

  enum class Mode { PHOTO, VIDEO }

  enum class FlashCycle { OFF, AUTO, ON }

  var listener: Listener? = null

  private val mainExecutor: Executor = ContextCompat.getMainExecutor(context)
  private var cameraProvider: ProcessCameraProvider? = null
  private var extensionsManager: ExtensionsManager? = null
  private var camera: Camera? = null
  private var previewUseCase: Preview? = null
  private var imageCapture: ImageCapture? = null
  private var videoCapture: VideoCapture<Recorder>? = null
  private var activeRecording: Recording? = null
  private var zoomLiveData: LiveData<ZoomState>? = null

  private var mode: Mode = Mode.PHOTO
  private var facingBack: Boolean = true
  private var flashCycle: FlashCycle = FlashCycle.OFF
  private var torchOn: Boolean = false
  private var activeExtensionMode: Int = ExtensionMode.NONE
  private var activeExtensionLabel: String? = null

  /** Camera2 id of the currently bound camera; diagnostics only. */
  private var activeCameraId: String? = null

  /** Video ladder outcome for the current bind; diagnostics only. */
  private var activeVideoQuality: Quality? = null
  private var activeVideoStabilization: Boolean = false

  /** User/host selected extension: auto | hdr | night | standard. */
  private var preferredExtension: String = EXT_STANDARD

  /** Extension labels this device actually advertises, probed independently. */
  private var availableExtensionLabels: List<String> = emptyList()

  /** Extension labels that failed to bind — disabled for this session only. */
  private val failedExtensionLabels = mutableSetOf<String>()

  private var fallbackLevel: String = NativeCameraContract.FallbackLevel.LAST_RESORT_BASIC
  private var captureMode: String = EXT_STANDARD

  private var minZoom = 1f
  private var maxZoom = 1f
  private var usefulZooms: List<Double> = listOf(1.0)
  private var hasFlashUnit = false

  private var minExposureIndex = 0
  private var maxExposureIndex = 0
  private var exposureIndex = 0

  /** Survives rebinds so EV is restored after an extension switch. */
  private var desiredExposureIndex = 0

  /** Survives rebinds so zoom is restored after an extension switch. */
  private var desiredZoomRatio: Float = 1f

  private val capturing = AtomicBoolean(false)
  private val released = AtomicBoolean(false)
  private val recordingAborted = AtomicBoolean(false)

  /** True between the start and the end of a bind pass; serializes rebinds. */
  private val isRebinding = AtomicBoolean(false)

  /** A rebind was requested while one was already running. */
  private var pendingRebind = false

  private var scaleDetector: ScaleGestureDetector? = null

  fun start(initialMode: Mode) {
    mode = initialMode
    facingBack = true
    val openStarted = SystemClock.elapsedRealtime()
    Log.d(NativeCameraContract.LOG_TAG, "CAMERA_PROVIDER_REQUEST_START")
    val providerFuture = ProcessCameraProvider.getInstance(context)
    providerFuture.addListener({
      if (released.get()) return@addListener
      try {
        cameraProvider = providerFuture.get()
        Log.d(
          NativeCameraContract.LOG_TAG,
          "CAMERA_PROVIDER_READY +${SystemClock.elapsedRealtime() - openStarted}ms",
        )
        val provider = cameraProvider ?: return@addListener
        if (!provider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA)) {
          listener?.onSessionError(
            NativeCameraContract.ErrorCode.NO_REAR_CAMERA,
            "No rear camera available",
          )
          return@addListener
        }
        Log.d(NativeCameraContract.LOG_TAG, "EXTENSIONS_MANAGER_START")
        val extFuture = ExtensionsManager.getInstanceAsync(context, provider)
        extFuture.addListener({
          if (released.get()) return@addListener
          try {
            extensionsManager = extFuture.get()
            Log.d(
              NativeCameraContract.LOG_TAG,
              "EXTENSIONS_MANAGER_READY +${SystemClock.elapsedRealtime() - openStarted}ms",
            )
          } catch (error: Exception) {
            Log.d(
              NativeCameraContract.LOG_TAG,
              "ExtensionsManager unavailable: ${error.message}",
            )
            extensionsManager = null
          }
          probeAvailableExtensions()
          Log.d(NativeCameraContract.LOG_TAG, "SESSION_BIND_START")
          requestRebind("start")
          installGestures()
        }, mainExecutor)
      } catch (error: Exception) {
        val msg = error.message ?: "Camera init failed"
        val code = if (msg.contains("in use", ignoreCase = true) ||
          msg.contains("CameraAccessException", ignoreCase = true)
        ) {
          NativeCameraContract.ErrorCode.CAMERA_IN_USE
        } else {
          NativeCameraContract.ErrorCode.INIT_FAILED
        }
        Log.d(NativeCameraContract.LOG_TAG, "start failed: $msg")
        listener?.onSessionError(code, msg)
      }
    }, mainExecutor)
  }

  fun switchMode(newMode: Mode) {
    if (mode == newMode || isRecording()) return
    mode = newMode
    if (newMode == Mode.PHOTO) {
      facingBack = true
      torchOn = false
    }
    requestRebind("switchMode=$newMode")
  }

  fun toggleFacing(): Boolean {
    if (rearCameraOnly || mode == Mode.PHOTO || isRecording()) return false
    facingBack = !facingBack
    requestRebind("toggleFacing=${if (facingBack) "back" else "front"}")
    return true
  }

  fun cycleFlash(): FlashCycle {
    if (!hasFlashUnit || mode != Mode.PHOTO) return flashCycle
    flashCycle = when (flashCycle) {
      FlashCycle.OFF -> FlashCycle.AUTO
      FlashCycle.AUTO -> FlashCycle.ON
      FlashCycle.ON -> FlashCycle.OFF
    }
    applyFlash()
    return flashCycle
  }

  fun toggleTorch(): Boolean {
    if (!hasFlashUnit || mode != Mode.VIDEO) return torchOn
    torchOn = !torchOn
    camera?.cameraControl?.enableTorch(torchOn)
    return torchOn
  }

  fun setZoomRatio(ratio: Float) {
    val clamped = ratio.coerceIn(minZoom, maxZoom)
    // Remember the intent even without a bound camera so a rebind restores it.
    desiredZoomRatio = clamped
    val cam = camera ?: return
    cam.cameraControl.setZoomRatio(clamped)
  }

  /**
   * Keep Preview / ImageCapture / VideoCapture aligned with the current
   * display rotation (portrait and landscape). Required because the activity
   * handles configChanges without recreating.
   */
  fun updateTargetRotation(rotation: Int = currentDisplayRotation()) {
    if (released.get()) return
    try {
      previewUseCase?.targetRotation = rotation
      imageCapture?.targetRotation = rotation
      videoCapture?.targetRotation = rotation
      CamPerf.log(null, "UPDATE_TARGET_ROTATION", "rotation=$rotation (no rebind)")
      Log.d(NativeCameraContract.LOG_TAG, "targetRotation=$rotation")
    } catch (error: Exception) {
      Log.d(
        NativeCameraContract.LOG_TAG,
        "updateTargetRotation failed: ${error.message}",
      )
    }
  }

  /**
   * After portrait ↔ landscape (or landscape L↔R), update use-case target
   * rotation in place. Do NOT tear down Preview/ImageCapture — a full rebind
   * after FIRST_PREVIEW_FRAME is a major shutter/ready regression.
   *
   * ViewPort was sized at bind; FILL_CENTER PreviewView + setTargetRotation is
   * sufficient for orientation while the Activity handles configChanges.
   */
  fun refreshForDisplayChange() {
    if (released.get() || cameraProvider == null) return
    CamPerf.log(null, "REFRESH_FOR_DISPLAY_CHANGE", "in-place rotation only")
    updateTargetRotation()
    Log.d(
      NativeCameraContract.LOG_TAG,
      "displayChange: targetRotation updated in place (no rebind)",
    )
  }

  fun currentDisplayRotation(): Int {
    val fromPreview = previewView.display?.rotation
    if (fromPreview != null) return fromPreview
    @Suppress("DEPRECATION")
    return try {
      (context.getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager)
        .defaultDisplay
        .rotation
    } catch (_: Exception) {
      android.view.Surface.ROTATION_0
    }
  }

  fun currentZoomRatio(): Float {
    return camera?.cameraInfo?.zoomState?.value?.zoomRatio ?: 1f
  }

  fun currentExtensionLabel(): String? = activeExtensionLabel

  /** Extension labels this device advertises, probed one mode at a time. */
  fun availableExtensionModes(): List<String> = availableExtensionLabels

  /** Currently requested extension (may differ from the bound one). */
  fun preferredExtensionMode(): String = preferredExtension

  /**
   * Switch extension mode with a safe rebind. Returns false when the request
   * cannot be honoured (busy, released, or mode not advertised); the ladder in
   * [bindUseCasesInternal] guarantees a live preview even when the mode fails
   * to bind. The rebind is scheduled through [requestRebind], so acceptance is
   * reported here and completion arrives on [Listener.onSessionReady].
   */
  fun setPreferredExtension(label: String): Boolean {
    if (released.get() || cameraProvider == null) return false
    if (isCapturing()) return false
    val normalized = label.trim().lowercase()
    val known = normalized == EXT_STANDARD ||
      normalized == EXT_AUTO ||
      normalized == EXT_HDR ||
      normalized == EXT_NIGHT
    if (!known) return false
    if (normalized != EXT_STANDARD && !availableExtensionLabels.contains(normalized)) {
      return false
    }
    preferredExtension = normalized
    // Give a previously failed mode another chance when explicitly requested.
    failedExtensionLabels.remove(normalized)
    Log.d(
      NativeCameraContract.LOG_TAG,
      "setPreferredExtension=$normalized rebinding=${isRebinding.get()}",
    )
    // Accepted either way: when a bind is in flight the request is queued and
    // runs against the preference stored above.
    requestRebind("preferredExtension=$normalized")
    return true
  }

  /** Supported EV index range; lower == upper when unsupported. */
  fun exposureRange(): Pair<Int, Int> = minExposureIndex to maxExposureIndex

  fun currentExposureIndex(): Int = exposureIndex

  /**
   * Apply an exposure compensation index, clamped to the device range.
   * Returns the applied index (0 when unsupported).
   */
  fun setExposureCompensationIndex(index: Int): Int {
    if (maxExposureIndex <= minExposureIndex) {
      desiredExposureIndex = 0
      return 0
    }
    val clamped = index.coerceIn(minExposureIndex, maxExposureIndex)
    desiredExposureIndex = clamped
    val cam = camera ?: return clamped
    return try {
      cam.cameraControl.setExposureCompensationIndex(clamped)
      exposureIndex = clamped
      clamped
    } catch (error: Exception) {
      Log.d(
        NativeCameraContract.LOG_TAG,
        "setExposureCompensationIndex failed: ${error.message}",
      )
      exposureIndex
    }
  }

  fun hasFlash(): Boolean = hasFlashUnit

  fun isRecording(): Boolean = activeRecording != null

  fun isCapturing(): Boolean = capturing.get() || isRecording()

  /** True while a bind pass is scheduled or running; capture must wait. */
  fun isRebinding(): Boolean = isRebinding.get()

  fun takePicture(onResult: (Result<CaptureOutput>) -> Unit) {
    // CaptureId assigned early so all [CAM_PERF] lines share one id.
    val captureId = java.util.UUID.randomUUID().toString()
    CamPerf.stage(captureId, "TAKE_PICTURE_ENTER", "thread=${Thread.currentThread().name}")

    if (mode != Mode.PHOTO) {
      onResult(
        Result.failure(
          SessionException(
            NativeCameraContract.ErrorCode.CAPTURE_FAILED,
            "Not in photo mode",
          ),
        ),
      )
      return
    }
    if (isRebinding.get()) {
      CamPerf.stage(captureId, "TAKE_PICTURE_BLOCKED", "reason=rebinding")
      onResult(
        Result.failure(
          SessionException(
            NativeCameraContract.ErrorCode.CAPTURE_FAILED,
            "Camera is reconfiguring",
          ),
        ),
      )
      return
    }
    CamPerf.stage(captureId, "IMAGE_CAPTURE_AVAILABLE_CHECK")
    val capture = imageCapture
    if (capture == null) {
      CamPerf.stage(captureId, "IMAGE_CAPTURE_AVAILABLE_CHECK", "result=null")
      onResult(
        Result.failure(
          SessionException(
            NativeCameraContract.ErrorCode.INIT_FAILED,
            "ImageCapture not ready",
          ),
        ),
      )
      return
    }
    if (!capturing.compareAndSet(false, true)) {
      CamPerf.stage(captureId, "SHUTTER_IGNORED", "already capturing")
      Log.d(NativeCameraContract.LOG_TAG, "SHUTTER_IGNORED already capturing")
      onResult(
        Result.failure(
          SessionException(
            NativeCameraContract.ErrorCode.CAPTURE_FAILED,
            "Capture already in progress",
          ),
        ),
      )
      return
    }
    if (!hasEnoughStorage()) {
      capturing.set(false)
      onResult(
        Result.failure(
          SessionException(
            NativeCameraContract.ErrorCode.INSUFFICIENT_STORAGE,
            "Not enough storage for photo",
          ),
        ),
      )
      return
    }

    val file = createOutputFile(isPhoto = true, captureId = captureId)
    if (file == null) {
      capturing.set(false)
      onResult(
        Result.failure(
          SessionException(
            NativeCameraContract.ErrorCode.FILE_CREATE_FAILED,
            "Could not create photo file",
          ),
        ),
      )
      return
    }

    CamPerf.log(
      captureId,
      "CAPTURE_CONFIG",
      "extRequested=$preferredExtension extBound=${activeExtensionLabel ?: "standard"} " +
        "fallback=$fallbackLevel captureMode=$captureMode " +
        "imageCaptureMode=${imageCaptureModeLabel()} jpegQuality=100 " +
        "cameraId=$activeCameraId zoom=${currentZoomRatio()} " +
        "ev=$exposureIndex flash=$flashCycle " +
        "targetRotation=${capture.targetRotation} " +
        "thread=${Thread.currentThread().name}",
    )
    CamPerf.log(
      captureId,
      "NOTE",
      "No FocusMeteringAction on shutter; tap-to-focus is user-driven only. " +
        "CameraX MAXIMIZE_QUALITY may still run AF/AE precapture (AfTask/AePreCaptureTask) " +
        "internally before OnImageSaved — that window is B_invoke_to_callback.",
    )
    CamPerf.log(
      captureId,
      "NOTE",
      "ZSL: captureMode=MAXIMIZE_QUALITY does not use CameraX ZERO_SHUTTER_LAG path; " +
        "Camera2 zslDisabled=false is capability metadata only. Keeping MAXIMIZE_QUALITY " +
        "for evidence quality (ZSL would be a future STANDARD-mode device opt-in).",
    )
    CamPerf.log(
      captureId,
      "NOTE",
      "CameraX OnImageSavedCallback has no public OEM processing stage; " +
        "B=TAKE_PICTURE_INVOKE→IMAGE_FILE_CALLBACK is the sensor/OEM/write window",
    )

    val options = ImageCapture.OutputFileOptions.Builder(file).build()
    CamPerf.markTakePictureInvoke(captureId)
    CamPerf.stage(
      captureId,
      "CAMERA_CAPTURE_STARTED",
      "path=${file.absolutePath}",
    )
    capture.takePicture(
      options,
      mainExecutor,
      object : ImageCapture.OnImageSavedCallback {
        override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
          capturing.set(false)
          CamPerf.markImageCallback(captureId)
          CamPerf.stage(
            captureId,
            "IMAGE_FILE_CALLBACK_SUCCESS",
            "thread=${Thread.currentThread().name}",
          )
          val exists = file.exists()
          val bytes = if (exists) file.length() else 0L
          CamPerf.stage(
            captureId,
            "PHOTO_FILE_EXISTS",
            "exists=$exists",
          )
          CamPerf.stage(
            captureId,
            "PHOTO_FILE_BYTES",
            "bytes=$bytes mb=${"%.2f".format(bytes / (1024.0 * 1024.0))} " +
              "path=${file.absolutePath}",
          )
          CamPerf.stage(captureId, "PHOTO_VALIDATION_START")
          CamPerf.stage(captureId, "PHOTO_METADATA_READ_START")
          val size = NativeCameraOrientation.readPhotoSize(file)
          CamPerf.stage(
            captureId,
            "PHOTO_METADATA_READ_END",
            if (size == null) "size=null" else "dim=${size.width}x${size.height} " +
              "orientation=${size.orientationDegrees}",
          )
          // FAIL CLOSED: unverifiable dimensions are rejected like portrait.
          if (size == null || size.isPortrait) {
            file.delete()
            CamPerf.stage(
              captureId,
              "PHOTO_DIMENSION_VALIDATION_END",
              "rejected portrait_or_unverifiable",
            )
            Log.d(
              NativeCameraContract.LOG_TAG,
              if (size == null) {
                "photo rejected: dimensions unverifiable"
              } else {
                "photo rejected: portrait ${size.width}x${size.height}"
              },
            )
            onResult(
              Result.failure(
                SessionException(
                  NativeCameraContract.ErrorCode.PORTRAIT_CAPTURE_REJECTED,
                  "Portrait photo rejected; capture in landscape",
                ),
              ),
            )
            return
          }
          CamPerf.stage(
            captureId,
            "PHOTO_DIMENSION_VALIDATION_END",
            "ok landscape ${size.width}x${size.height}",
          )
          val position = if (facingBack) "back" else "front"
          // FAIL CLOSED: rear-only evidence must never come from the front lens.
          if (rearCameraOnly && position != "back") {
            file.delete()
            CamPerf.stage(
              captureId,
              "PHOTO_REAR_VALIDATION_END",
              "rejected camera=$position",
            )
            Log.d(NativeCameraContract.LOG_TAG, "photo rejected: camera=$position")
            onResult(
              Result.failure(
                SessionException(
                  NativeCameraContract.ErrorCode.REAR_CAMERA_REQUIRED,
                  "Rear camera required for photo capture",
                ),
              ),
            )
            return
          }
          CamPerf.stage(captureId, "PHOTO_REAR_VALIDATION_END", "ok camera=$position")
          CamPerf.markValidationComplete(captureId)
          Log.d(
            NativeCameraContract.LOG_TAG,
            "photo saved path=${file.absolutePath} sizeBytes=$bytes " +
              "cameraId=$activeCameraId camera=$position " +
              "ext=$activeExtensionLabel preferredExt=$preferredExtension " +
              "captureMode=$captureMode fallback=$fallbackLevel " +
              "imageCaptureMode=${imageCaptureModeLabel()} " +
              "dim=${size.width}x${size.height} " +
              "orientation=${size.orientationDegrees} " +
              "zoom=${currentZoomRatio()} desiredZoom=$desiredZoomRatio " +
              "ev=$exposureIndex flash=$flashCycle flashUnit=$hasFlashUnit",
          )
          CamPerf.stage(captureId, "NATIVE_RESULT_PREPARE")
          onResult(
            Result.success(
              CaptureOutput(
                path = file.absolutePath,
                type = NativeCameraContract.TYPE_PHOTO,
                captureId = captureId,
                width = size.width,
                height = size.height,
                durationMs = null,
                cameraPosition = position,
                lens = NativeCameraZoom.lensLabel(
                  currentZoomRatio().toDouble(),
                  minZoom.toDouble(),
                ),
                zoomFactor = currentZoomRatio().toDouble(),
                fileSizeBytes = bytes,
                mimeType = "image/jpeg",
                orientationDegrees = size.orientationDegrees,
                extensionMode = activeExtensionLabel,
                captureMode = captureMode,
                fallbackLevel = fallbackLevel,
              ),
            ),
          )
        }

        override fun onError(exception: ImageCaptureException) {
          capturing.set(false)
          CamPerf.markImageCallback(captureId)
          CamPerf.stage(
            captureId,
            "IMAGE_FILE_CALLBACK_ERROR",
            "msg=${exception.message}",
          )
          file.delete()
          Log.d(
            NativeCameraContract.LOG_TAG,
            "capture error id=$captureId: ${exception.message}",
          )
          onResult(
            Result.failure(
              SessionException(
                NativeCameraContract.ErrorCode.CAPTURE_FAILED,
                exception.message ?: "Capture failed",
              ),
            ),
          )
        }
      },
    )
  }

  @SuppressLint("MissingPermission")
  fun startRecording(onFinal: (Result<CaptureOutput>) -> Unit) {
    if (mode != Mode.VIDEO) {
      onFinal(
        Result.failure(
          SessionException(
            NativeCameraContract.ErrorCode.RECORDING_FAILED,
            "Not in video mode",
          ),
        ),
      )
      return
    }
    if (isRebinding.get()) {
      onFinal(
        Result.failure(
          SessionException(
            NativeCameraContract.ErrorCode.RECORDING_FAILED,
            "Camera is reconfiguring",
          ),
        ),
      )
      return
    }
    if (activeRecording != null) return
    val capture = videoCapture
    if (capture == null) {
      onFinal(
        Result.failure(
          SessionException(
            NativeCameraContract.ErrorCode.INIT_FAILED,
            "VideoCapture not ready",
          ),
        ),
      )
      return
    }
    if (!hasEnoughStorage()) {
      onFinal(
        Result.failure(
          SessionException(
            NativeCameraContract.ErrorCode.INSUFFICIENT_STORAGE,
            "Not enough storage for video",
          ),
        ),
      )
      return
    }
    val captureId = java.util.UUID.randomUUID().toString()
    val file = createOutputFile(isPhoto = false, captureId = captureId)
    if (file == null) {
      onFinal(
        Result.failure(
          SessionException(
            NativeCameraContract.ErrorCode.FILE_CREATE_FAILED,
            "Could not create video file",
          ),
        ),
      )
      return
    }

    recordingAborted.set(false)
    val output = FileOutputOptions.Builder(file).build()
    val pending = capture.output
      .prepareRecording(context, output)
      .withAudioEnabled()

    activeRecording = pending.start(
      mainExecutor,
      Consumer { event ->
        when (event) {
          is VideoRecordEvent.Start -> {
            listener?.onRecordingStatus(true)
          }
          is VideoRecordEvent.Finalize -> {
            activeRecording = null
            listener?.onRecordingStatus(false)
            if (recordingAborted.getAndSet(false)) {
              file.delete()
              Log.d(NativeCameraContract.LOG_TAG, "recording aborted; file discarded")
              onFinal(
                Result.failure(
                  SessionException(
                    NativeCameraContract.ErrorCode.INTERRUPTED,
                    "Recording interrupted",
                  ),
                ),
              )
              return@Consumer
            }
            if (event.hasError()) {
              file.delete()
              val code = when (event.error) {
                VideoRecordEvent.Finalize.ERROR_INSUFFICIENT_STORAGE ->
                  NativeCameraContract.ErrorCode.INSUFFICIENT_STORAGE
                VideoRecordEvent.Finalize.ERROR_NO_VALID_DATA,
                VideoRecordEvent.Finalize.ERROR_ENCODING_FAILED,
                VideoRecordEvent.Finalize.ERROR_RECORDER_ERROR,
                VideoRecordEvent.Finalize.ERROR_FILE_SIZE_LIMIT_REACHED,
                -> NativeCameraContract.ErrorCode.RECORDING_FAILED
                VideoRecordEvent.Finalize.ERROR_SOURCE_INACTIVE,
                VideoRecordEvent.Finalize.ERROR_INVALID_OUTPUT_OPTIONS,
                -> NativeCameraContract.ErrorCode.INTERRUPTED
                else -> NativeCameraContract.ErrorCode.RECORDING_FAILED
              }
              Log.d(
                NativeCameraContract.LOG_TAG,
                "recording finalize error=${event.error}",
              )
              onFinal(
                Result.failure(
                  SessionException(code, "Recording failed (${event.error})"),
                ),
              )
              return@Consumer
            }
            val size = NativeCameraOrientation.readVideoSize(file)
            // FAIL CLOSED: unverifiable video track is rejected like portrait.
            if (size == null || size.isPortrait) {
              file.delete()
              Log.d(
                NativeCameraContract.LOG_TAG,
                if (size == null) {
                  "video rejected: dimensions unverifiable"
                } else {
                  "video rejected: portrait ${size.width}x${size.height}"
                },
              )
              onFinal(
                Result.failure(
                  SessionException(
                    NativeCameraContract.ErrorCode.PORTRAIT_CAPTURE_REJECTED,
                    "Portrait video rejected; record in landscape",
                  ),
                ),
              )
              return@Consumer
            }
            val duration = NativeCameraOrientation.readVideoDurationMs(file)
            val bytes = file.length()
            Log.d(
              NativeCameraContract.LOG_TAG,
              "video saved path=${file.absolutePath} sizeBytes=$bytes " +
                "cameraId=$activeCameraId durationMs=$duration " +
                "dim=${size.width}x${size.height} " +
                "requestedQuality=$activeVideoQuality " +
                "stabilization=$activeVideoStabilization " +
                "fallback=$fallbackLevel zoom=${currentZoomRatio()} " +
                "ev=$exposureIndex torch=$torchOn",
            )
            val captureId = file.nameWithoutExtension.removePrefix("VID_")
            onFinal(
              Result.success(
                CaptureOutput(
                  path = file.absolutePath,
                  type = NativeCameraContract.TYPE_VIDEO,
                  captureId = captureId.ifBlank { java.util.UUID.randomUUID().toString() },
                  width = size.width,
                  height = size.height,
                  durationMs = duration,
                  cameraPosition = if (facingBack) "back" else "front",
                  lens = NativeCameraZoom.lensLabel(
                    currentZoomRatio().toDouble(),
                    minZoom.toDouble(),
                  ),
                  zoomFactor = currentZoomRatio().toDouble(),
                  fileSizeBytes = bytes,
                  mimeType = "video/mp4",
                  orientationDegrees = size.orientationDegrees,
                  extensionMode = null,
                  captureMode = EXT_STANDARD,
                  fallbackLevel = fallbackLevel,
                ),
              ),
            )
          }
        }
      },
    )
  }

  fun stopRecording() {
    activeRecording?.stop()
  }

  /** Stop recording without delivering a success path (interrupt / cancel). */
  fun abortRecording() {
    val recording = activeRecording ?: return
    recordingAborted.set(true)
    activeRecording = null
    try {
      recording.stop()
    } catch (_: Exception) {
    }
    listener?.onRecordingStatus(false, NativeCameraContract.ErrorCode.INTERRUPTED)
  }

  fun focusAt(x: Float, y: Float) {
    val cam = camera ?: return
    val meteringPointFactory = previewView.meteringPointFactory
    val point = meteringPointFactory.createPoint(x, y)
    val action = FocusMeteringAction.Builder(
      point,
      FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE,
    )
      .setAutoCancelDuration(3, TimeUnit.SECONDS)
      .build()
    cam.cameraControl.startFocusAndMetering(action)
  }

  fun release() {
    if (!released.compareAndSet(false, true)) return
    pendingRebind = false
    abortRecording()
    try {
      zoomLiveData?.removeObservers(lifecycleOwner)
    } catch (_: Exception) {
    }
    zoomLiveData = null
    try {
      cameraProvider?.unbindAll()
    } catch (_: Exception) {
    }
    camera = null
    previewUseCase = null
    imageCapture = null
    videoCapture = null
    scaleDetector = null
  }

  private enum class BindProfile {
    /**
     * OEM extension bind: max still quality but NO forced aspect ratio, so the
     * extension vendor picks the resolution combination it actually supports.
     */
    EXTENSION_OEM_FLEX,

    /** No extension; stock-like 4:3 photo / 16:9 video + max still quality. */
    STANDARD_MAX_QUALITY,

    /** Align Preview + ImageCapture on 16:9; still max quality, JPEG 100. */
    ALIGNED_16_9,

    /** Last resort: CameraX default resolutions but still MAXIMIZE_QUALITY. */
    MINIMAL,

    /** Absolute last resort: CameraX defaults + MINIMIZE_LATENCY. */
    MINIMAL_LATENCY,
  }

  private data class BindAttempt(
    val profile: BindProfile,
    /** Extension label to bind with, or null for a plain camera selector. */
    val extensionLabel: String?,
    val fallbackLevel: String,
    /**
     * Exact video quality this attempt demands (no CameraX fallback), so the
     * ladder — not QualitySelector — decides the degradation order. Null lets
     * [videoQualitySelector] use a lenient ordered list.
     */
    val videoQuality: Quality? = null,
    val videoStabilization: Boolean = false,
  )

  /**
   * Extension ladder for the current preference, skipping modes the device
   * does not advertise and modes that already failed to bind this session:
   * AUTO → standard, HDR → AUTO → standard, NIGHT → AUTO → standard.
   */
  private fun extensionCandidates(): List<String> {
    val ladder = when (preferredExtension) {
      EXT_AUTO -> listOf(EXT_AUTO)
      EXT_HDR -> listOf(EXT_HDR, EXT_AUTO)
      EXT_NIGHT -> listOf(EXT_NIGHT, EXT_AUTO)
      else -> emptyList()
    }
    return ladder.filter {
      availableExtensionLabels.contains(it) && !failedExtensionLabels.contains(it)
    }
  }

  /**
   * Single entry point for every rebind (start, mode switch, facing toggle,
   * extension switch, rotation). Runs the bind pass on the main thread and
   * collapses concurrent requests into one trailing rebind, so an extension
   * chip tapped mid-bind can never interleave two unbind/bind passes.
   */
  private fun requestRebind(reason: String) {
    if (released.get()) return
    CamPerf.noteRebind(reason)
    if (isRebinding.compareAndSet(false, true)) {
      mainExecutor.execute {
        try {
          if (!released.get()) {
            Log.d(NativeCameraContract.LOG_TAG, "rebind reason=$reason")
            CamPerf.log(null, "BIND_CAMERA_START", "reason=$reason")
            bindUseCasesInternal()
            CamPerf.log(null, "BIND_CAMERA_END", "reason=$reason")
          }
        } finally {
          isRebinding.set(false)
          if (pendingRebind && !released.get()) {
            pendingRebind = false
            requestRebind("pending")
          }
        }
      }
    } else {
      Log.d(NativeCameraContract.LOG_TAG, "rebind queued reason=$reason")
      pendingRebind = true
    }
  }

  /**
   * Photo ladder (preferred NIGHT example): NIGHT oem-flex → AUTO oem-flex →
   * standard 4:3 max → standard 16:9 max → last-resort defaults max quality →
   * last-resort defaults minimize-latency.
   *
   * Video ladder: UHD+stab → UHD → FHD+stab → FHD → HD → CameraX defaults.
   */
  private fun bindUseCasesInternal() {
    if (released.get() || cameraProvider == null) return

    val attempts = mutableListOf<BindAttempt>()
    if (mode == Mode.PHOTO && facingBack) {
      // Every advertised extension candidate gets exactly one OEM-flex attempt:
      // forcing 4:3 on an extension bind is the most common OEM bind failure.
      extensionCandidates().forEachIndexed { index, label ->
        attempts.add(
          BindAttempt(
            profile = BindProfile.EXTENSION_OEM_FLEX,
            extensionLabel = label,
            fallbackLevel = if (index == 0) {
              NativeCameraContract.FallbackLevel.EXTENSION_PREFERRED
            } else {
              NativeCameraContract.FallbackLevel.EXTENSION_OEM_FLEX
            },
          ),
        )
      }
    }
    if (mode == Mode.VIDEO) {
      attempts.addAll(videoBindAttempts())
    } else {
      attempts.add(
        BindAttempt(
          BindProfile.STANDARD_MAX_QUALITY,
          null,
          NativeCameraContract.FallbackLevel.STANDARD_MAX,
        ),
      )
      attempts.add(
        BindAttempt(
          BindProfile.ALIGNED_16_9,
          null,
          NativeCameraContract.FallbackLevel.STANDARD_16_9,
        ),
      )
    }
    // Keep max still quality even on the last resort; only drop to
    // MINIMIZE_LATENCY when nothing else binds at all.
    attempts.add(
      BindAttempt(
        BindProfile.MINIMAL,
        null,
        NativeCameraContract.FallbackLevel.LAST_RESORT_BASIC,
      ),
    )
    attempts.add(
      BindAttempt(
        BindProfile.MINIMAL_LATENCY,
        null,
        NativeCameraContract.FallbackLevel.LAST_RESORT_BASIC,
      ),
    )

    var lastError: Exception? = null
    for (attempt in attempts) {
      try {
        bindWithAttempt(attempt)
        return
      } catch (error: Exception) {
        lastError = error
        Log.d(
          NativeCameraContract.LOG_TAG,
          "bind failed profile=${attempt.profile} " +
            "ext=${attempt.extensionLabel ?: "none"} " +
            "fallback=${attempt.fallbackLevel} " +
            "resolution=${resolutionStrategyLabel(attempt.profile)} " +
            "videoQuality=${attempt.videoQuality} " +
            "stabilization=${attempt.videoStabilization} " +
            "error=${error.javaClass.simpleName}: ${error.message}",
        )
        // OEM extension selectors often advertise support then fail the
        // Preview+ImageCapture surface combination. Disable only the mode that
        // failed so the other extension modes stay selectable this session.
        attempt.extensionLabel?.let { failedExtensionLabels.add(it) }
      }
    }

    val msg = lastError?.message ?: "Failed to bind camera"
    Log.d(NativeCameraContract.LOG_TAG, "all bind profiles failed: $msg")
    val code = if (msg.contains("in use", ignoreCase = true)) {
      NativeCameraContract.ErrorCode.CAMERA_IN_USE
    } else {
      NativeCameraContract.ErrorCode.INIT_FAILED
    }
    listener?.onSessionError(code, userFacingInitMessage(code, msg))
  }

  /**
   * Video rungs, highest quality first. Each rung pins one exact [Quality] so
   * an unsupported UHD (or an unsupported UHD+stabilization combination) walks
   * down the ladder instead of silently collapsing to whatever CameraX picks.
   */
  private fun videoBindAttempts(): List<BindAttempt> {
    val tiers = if (quality == NativeCameraContract.QUALITY_BALANCED) {
      listOf(Quality.FHD, Quality.HD)
    } else {
      listOf(Quality.UHD, Quality.FHD, Quality.HD)
    }
    val attempts = mutableListOf<BindAttempt>()
    for (tier in tiers) {
      val level = when (tier) {
        Quality.UHD -> NativeCameraContract.FallbackLevel.STANDARD_MAX
        Quality.FHD -> NativeCameraContract.FallbackLevel.STANDARD_16_9
        else -> NativeCameraContract.FallbackLevel.LAST_RESORT_BASIC
      }
      // HD is a compatibility rung; stabilization is not worth another attempt.
      if (tier != Quality.HD) {
        attempts.add(
          BindAttempt(
            profile = BindProfile.STANDARD_MAX_QUALITY,
            extensionLabel = null,
            fallbackLevel = level,
            videoQuality = tier,
            videoStabilization = true,
          ),
        )
      }
      attempts.add(
        BindAttempt(
          profile = BindProfile.STANDARD_MAX_QUALITY,
          extensionLabel = null,
          fallbackLevel = level,
          videoQuality = tier,
          videoStabilization = false,
        ),
      )
    }
    return attempts
  }

  private fun bindWithAttempt(attempt: BindAttempt) {
    val provider = cameraProvider ?: throw IllegalStateException("No provider")
    if (released.get()) throw IllegalStateException("Session released")

    val profile = attempt.profile
    // Capture the live zoom before tearing the camera down so the new bind can
    // restore it (CameraX resets zoom to 1x on every bind).
    camera?.let { desiredZoomRatio = currentZoomRatio() }
    CamPerf.noteUnbindAll("bindWithAttempt profile=${attempt.profile}")
    provider.unbindAll()
    previewUseCase = null
    imageCapture = null
    videoCapture = null
    camera = null
    activeExtensionMode = ExtensionMode.NONE
    activeExtensionLabel = null
    activeCameraId = null
    activeVideoQuality = null
    activeVideoStabilization = false

    val rotation = currentDisplayRotation()

    val baseSelector = if (facingBack) {
      preferStockLikeBackCamera(provider)
    } else {
      CameraSelector.DEFAULT_FRONT_CAMERA
    }

    var selector = baseSelector
    val requestedExtensionLabel = attempt.extensionLabel
    if (requestedExtensionLabel != null && mode == Mode.PHOTO && facingBack) {
      val chosen = chooseExtension(baseSelector, requestedExtensionLabel)
        ?: throw IllegalStateException("Extension $requestedExtensionLabel unavailable")
      selector = chosen.selector
      activeExtensionMode = chosen.mode
      activeExtensionLabel = chosen.label
    }

    val preview = buildPreview(rotation, attempt).also {
      it.surfaceProvider = previewView.surfaceProvider
    }
    previewUseCase = preview
    val useCases = mutableListOf<UseCase>(preview)

    if (mode == Mode.PHOTO) {
      imageCapture = buildImageCapture(rotation, attempt)
      useCases.add(imageCapture!!)
    } else {
      val recorder = Recorder.Builder()
        .setQualitySelector(videoQualitySelector(attempt))
        .build()
      val videoBuilder = VideoCapture.Builder(recorder)
        .setTargetRotation(rotation)
      // Stabilization is a ladder rung of its own: an UHD+stabilization bind
      // failure retries UHD without it instead of losing the resolution.
      if (attempt.videoStabilization) {
        tryEnableVideoStabilization(videoBuilder)
      }
      videoCapture = videoBuilder.build()
      useCases.add(videoCapture!!)
      activeVideoQuality = attempt.videoQuality
      activeVideoStabilization = attempt.videoStabilization
    }

    // ViewPort matches PreviewView fill so framing matches the OS camera
    // full-screen viewfinder (what you see ≈ what you capture).
    val viewPort = previewView.getViewPort(rotation)
    camera = if (viewPort != null) {
      val groupBuilder = UseCaseGroup.Builder().setViewPort(viewPort)
      for (useCase in useCases) {
        groupBuilder.addUseCase(useCase)
      }
      provider.bindToLifecycle(lifecycleOwner, selector, groupBuilder.build())
    } else {
      provider.bindToLifecycle(
        lifecycleOwner,
        selector,
        *useCases.toTypedArray(),
      )
    }
    fallbackLevel = attempt.fallbackLevel
    captureMode = activeExtensionLabel ?: EXT_STANDARD
    if (mode == Mode.PHOTO && profile == BindProfile.MINIMAL_LATENCY) {
      Log.d(
        NativeCameraContract.LOG_TAG,
        "${NativeCameraContract.Diagnostics.PHOTO_QUALITY_DEGRADED_LAST_RESORT} " +
          "profile=$profile fallback=$fallbackLevel " +
          "reason=only MINIMIZE_LATENCY defaults would bind",
      )
    }
    if (mode == Mode.VIDEO) {
      Log.d(
        NativeCameraContract.LOG_TAG,
        "video bind won quality=${attempt.videoQuality ?: "camerax_default"} " +
          "stabilization=${attempt.videoStabilization} " +
          "fallback=$fallbackLevel profile=$profile",
      )
    }
    onBoundSuccessfully(profile)
  }

  /**
   * Prefer the rear logical camera with the widest zoom span so UW / tele
   * chips match the stock Camera app when available.
   */
  private fun preferStockLikeBackCamera(provider: ProcessCameraProvider): CameraSelector {
    return try {
      data class Ranked(val info: androidx.camera.core.CameraInfo, val id: String, val score: Double)
      val ranked = provider.availableCameraInfos.mapNotNull { info ->
        try {
          val c2 = Camera2CameraInfo.from(info)
          val facing = c2.getCameraCharacteristic(CameraCharacteristics.LENS_FACING)
          if (facing != CameraCharacteristics.LENS_FACING_BACK) return@mapNotNull null
          val zoom = info.zoomState.value
          val minZ = zoom?.minZoomRatio ?: 1f
          val maxZ = zoom?.maxZoomRatio ?: 1f
          val score = (maxZ - minZ).toDouble() + if (minZ < 0.95f) 50.0 else 0.0
          Ranked(info, c2.cameraId, score)
        } catch (_: Exception) {
          null
        }
      }
      val best = ranked.maxByOrNull { it.score }
      if (best == null || ranked.size <= 1) {
        return CameraSelector.DEFAULT_BACK_CAMERA
      }
      val bestId = best.id
      CameraSelector.Builder()
        .requireLensFacing(CameraSelector.LENS_FACING_BACK)
        .addCameraFilter { infos ->
          val match = infos.filter { candidate ->
            try {
              Camera2CameraInfo.from(candidate).cameraId == bestId
            } catch (_: Exception) {
              false
            }
          }
          if (match.isEmpty()) infos else match
        }
        .build()
    } catch (error: Exception) {
      Log.d(
        NativeCameraContract.LOG_TAG,
        "preferStockLikeBackCamera fallback: ${error.message}",
      )
      CameraSelector.DEFAULT_BACK_CAMERA
    }
  }

  private fun buildPreview(rotation: Int, attempt: BindAttempt): Preview {
    val builder = Preview.Builder().setTargetRotation(rotation)
    when (attempt.profile) {
      BindProfile.EXTENSION_OEM_FLEX -> {
        // Extension binds get no forced aspect ratio: the OEM decides which
        // Preview + ImageCapture resolution pair its pipeline supports.
        // Prefer an efficient preview target when the OEM allows it — ImageCapture
        // remains MAXIMIZE_QUALITY independently.
        builder.setResolutionSelector(efficientPreviewSelector())
      }
      BindProfile.ALIGNED_16_9 -> {
        builder.setResolutionSelector(efficientPreviewSelector())
      }
      BindProfile.MINIMAL,
      BindProfile.MINIMAL_LATENCY,
      -> {
        // Leave resolution selection to CameraX defaults.
      }
      BindProfile.STANDARD_MAX_QUALITY -> {
        // Fast preview (~720p-class) while ImageCapture stays max quality.
        builder.setResolutionSelector(efficientPreviewSelector())
      }
    }
    return builder.build()
  }

  private fun buildImageCapture(rotation: Int, attempt: BindAttempt): ImageCapture {
    val builder = ImageCapture.Builder().setTargetRotation(rotation)
    when (attempt.profile) {
      BindProfile.EXTENSION_OEM_FLEX -> {
        builder
          .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
          .setJpegQuality(100)
      }
      BindProfile.STANDARD_MAX_QUALITY -> {
        builder
          .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
          .setJpegQuality(100)
          .setResolutionSelector(resolutionSelectorForMode())
      }
      BindProfile.ALIGNED_16_9 -> {
        builder
          .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
          .setJpegQuality(100)
          .setResolutionSelector(resolutionSelector16x9())
      }
      BindProfile.MINIMAL -> {
        // Still max quality; only the resolution selector is dropped.
        builder
          .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
          .setJpegQuality(100)
      }
      BindProfile.MINIMAL_LATENCY -> {
        builder.setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
      }
    }
    return builder.build()
  }

  /** Human-readable resolution strategy for bind diagnostics. */
  private fun resolutionStrategyLabel(profile: BindProfile): String = when (profile) {
    BindProfile.EXTENSION_OEM_FLEX -> "oem_flex_no_forced_aspect"
    BindProfile.STANDARD_MAX_QUALITY ->
      if (mode == Mode.VIDEO) "aspect_16_9" else "aspect_4_3"
    BindProfile.ALIGNED_16_9 -> "aspect_16_9"
    BindProfile.MINIMAL, BindProfile.MINIMAL_LATENCY -> "camerax_default"
  }

  private fun imageCaptureModeLabel(): String {
    return when (imageCapture?.captureMode) {
      ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY -> "maximize_quality"
      ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY -> "minimize_latency"
      null -> "none"
      else -> "other"
    }
  }

  /** Stock photo is typically 4:3; video is 16:9. */
  /** Preview-only: prefer ~720p for fast first frame; capture quality is separate. */
  private fun efficientPreviewSelector(): ResolutionSelector {
    return ResolutionSelector.Builder()
      .setResolutionStrategy(
        ResolutionStrategy(
          Size(1280, 720),
          ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,
        ),
      )
      .build()
  }

  private fun resolutionSelectorForMode(): ResolutionSelector {
    return if (mode == Mode.VIDEO) {
      resolutionSelector16x9()
    } else {
      ResolutionSelector.Builder()
        .setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)
        .build()
    }
  }

  private fun resolutionSelector16x9(): ResolutionSelector {
    return ResolutionSelector.Builder()
      .setAspectRatioStrategy(AspectRatioStrategy.RATIO_16_9_FALLBACK_AUTO_STRATEGY)
      .build()
  }

  private fun onBoundSuccessfully(profile: BindProfile) {
    val cam = camera ?: return
    hasFlashUnit = cam.cameraInfo.hasFlashUnit()
    applyFlash()
    if (mode == Mode.VIDEO && torchOn && hasFlashUnit) {
      cam.cameraControl.enableTorch(true)
    }

    val zoomState = cam.cameraInfo.zoomState.value
    minZoom = zoomState?.minZoomRatio ?: 1f
    val deviceMax = zoomState?.maxZoomRatio ?: 1f
    maxZoom = NativeCameraZoom.capMaxZoom(
      minZoom.toDouble(),
      deviceMax.toDouble(),
    ).toFloat()

    val cameraId = try {
      Camera2CameraInfo.from(cam.cameraInfo).cameraId
    } catch (_: Exception) {
      null
    }
    activeCameraId = cameraId
    val optical = NativeCameraZoom.opticalZoomRatios(context, cameraId)
    usefulZooms = NativeCameraZoom.usefulLevels(
      minZoom.toDouble(),
      maxZoom.toDouble(),
      optical,
    )

    Log.d(
      NativeCameraContract.LOG_TAG,
      "zoom chips cameraId=$cameraId min=$minZoom max=$maxZoom " +
        "optical=$optical chips=$usefulZooms",
    )

    readExposureState(cam)
    restoreDesiredZoom()

    try {
      zoomLiveData?.removeObservers(lifecycleOwner)
    } catch (_: Exception) {
    }
    zoomLiveData = cam.cameraInfo.zoomState
    zoomLiveData?.observe(lifecycleOwner) { state ->
      listener?.onZoomChanged(state.zoomRatio)
    }

    // Diagnostics for field debugging of extension / fallback behaviour.
    Log.d(NativeCameraContract.LOG_TAG, "SESSION_BIND_END profile=$profile")
    Log.d(
      NativeCameraContract.LOG_TAG,
      "bound cameraId=$cameraId profile=$profile mode=$mode " +
        "facing=${if (facingBack) "back" else "front"} " +
        "preferredExt=$preferredExtension ext=$activeExtensionLabel " +
        "captureMode=$captureMode fallbackLevel=$fallbackLevel " +
        "availableExt=$availableExtensionLabels failedExt=$failedExtensionLabels " +
        "resolution=${resolutionStrategyLabel(profile)} " +
        "imageCaptureMode=${imageCaptureModeLabel()} " +
        "videoQuality=$activeVideoQuality stab=$activeVideoStabilization " +
        "flash=$hasFlashUnit zoom=[$minZoom,$maxZoom] useful=$usefulZooms " +
        "ev=[$minExposureIndex,$maxExposureIndex] evIndex=$exposureIndex",
    )
    Log.d(
      NativeCameraContract.LOG_TAG,
      "restored after rebind zoom=$desiredZoomRatio " +
        "ev=$exposureIndex (desired=$desiredExposureIndex) " +
        "flashCycle=$flashCycle torch=${mode == Mode.VIDEO && torchOn}",
    )

    // Publish after the bind pass unwinds so the host observes a settled
    // session (isRebinding() == false) and capture is allowed again.
    val readyFlash = hasFlashUnit
    val readyMinZoom = minZoom
    val readyMaxZoom = maxZoom
    val readyZooms = usefulZooms
    val readyExtension = activeExtensionLabel
    val readyAvailable = availableExtensionLabels
    val readyMinEv = minExposureIndex
    val readyMaxEv = maxExposureIndex
    val readyEv = exposureIndex
    mainExecutor.execute {
      if (released.get()) return@execute
      // A queued rebind publishes its own state; drop the stale notification.
      if (isRebinding.get() || pendingRebind) return@execute
      listener?.onSessionReady(
        hasFlash = readyFlash,
        minZoom = readyMinZoom,
        maxZoom = readyMaxZoom,
        usefulZooms = readyZooms,
        extensionMode = readyExtension,
        availableExtensions = readyAvailable,
        minExposure = readyMinEv,
        maxExposure = readyMaxEv,
        exposureIndex = readyEv,
      )
    }
  }

  /**
   * CameraX resets zoom to the default ratio on every bind, so re-apply the
   * last user intent clamped to the newly bound camera's range. Flash is
   * re-applied here too because the ImageCapture use case is brand new.
   */
  private fun restoreDesiredZoom() {
    val clamped = desiredZoomRatio.coerceIn(minZoom, maxZoom)
    desiredZoomRatio = clamped
    val cam = camera ?: return
    try {
      cam.cameraControl.setZoomRatio(clamped)
    } catch (error: Exception) {
      Log.d(
        NativeCameraContract.LOG_TAG,
        "restore zoom failed: ${error.message}",
      )
    }
    applyFlash()
  }

  /** Read the bound camera's EV range and restore the desired index. */
  private fun readExposureState(cam: Camera) {
    try {
      val state = cam.cameraInfo.exposureState
      if (!state.isExposureCompensationSupported) {
        minExposureIndex = 0
        maxExposureIndex = 0
        exposureIndex = 0
        return
      }
      val range = state.exposureCompensationRange
      minExposureIndex = range.lower
      maxExposureIndex = range.upper
      exposureIndex = state.exposureCompensationIndex
      val restore = desiredExposureIndex.coerceIn(minExposureIndex, maxExposureIndex)
      if (restore != exposureIndex) {
        setExposureCompensationIndex(restore)
      }
    } catch (error: Exception) {
      Log.d(
        NativeCameraContract.LOG_TAG,
        "exposure state unavailable: ${error.message}",
      )
      minExposureIndex = 0
      maxExposureIndex = 0
      exposureIndex = 0
    }
  }

  private fun userFacingInitMessage(code: String, technical: String): String {
    return when (code) {
      NativeCameraContract.ErrorCode.CAMERA_IN_USE ->
        "Camera is in use by another app. Close it and try again."
      NativeCameraContract.ErrorCode.NO_REAR_CAMERA ->
        "No rear camera is available on this device."
      else ->
        "Unable to open the camera on this device. Please try again."
    }.also {
      Log.d(NativeCameraContract.LOG_TAG, "init error technical=$technical")
    }
  }

  private data class ChosenExtension(
    val selector: CameraSelector,
    val mode: Int,
    val label: String,
  )

  /**
   * Resolve a single extension label into a CameraX selector. The preference
   * ladder itself lives in [extensionCandidates] so every mode in the ladder
   * gets its own bind attempt.
   */
  private fun chooseExtension(base: CameraSelector, label: String): ChosenExtension? {
    val manager = extensionsManager ?: return null
    val extensionMode = extensionModeFor(label) ?: return null
    return try {
      if (!manager.isExtensionAvailable(base, extensionMode)) {
        Log.d(
          NativeCameraContract.LOG_TAG,
          "extension $label (mode=$extensionMode) not available for selector",
        )
        null
      } else {
        val selector = manager.getExtensionEnabledCameraSelector(base, extensionMode)
        Log.d(NativeCameraContract.LOG_TAG, "using extension=$label")
        ChosenExtension(selector, extensionMode, label)
      }
    } catch (error: Exception) {
      Log.d(
        NativeCameraContract.LOG_TAG,
        "extension $label selector failed: ${error.message}",
      )
      null
    }
  }

  private fun extensionModeFor(label: String): Int? = when (label) {
    EXT_AUTO -> ExtensionMode.AUTO
    EXT_HDR -> ExtensionMode.HDR
    EXT_NIGHT -> ExtensionMode.NIGHT
    else -> null
  }

  /**
   * Probe AUTO / HDR / NIGHT independently so the UI can offer real choices
   * instead of inferring HDR / NIGHT from AUTO availability.
   */
  private fun probeAvailableExtensions() {
    availableExtensionLabels = emptyList()
    val manager = extensionsManager
    val provider = cameraProvider
    if (manager == null || provider == null) {
      preferredExtension = EXT_STANDARD
      return
    }

    // Process-scoped cache: reopen camera without re-probing every ExtensionMode.
    val cached = processExtensionCache
    if (cached != null) {
      availableExtensionLabels = cached
      preferredExtension = when {
        requestedExtension?.trim()?.lowercase() == EXT_STANDARD -> EXT_STANDARD
        requestedExtension != null &&
          cached.contains(requestedExtension!!.trim().lowercase()) ->
          requestedExtension!!.trim().lowercase()
        cached.contains(EXT_AUTO) -> EXT_AUTO
        else -> EXT_STANDARD
      }
      Log.d(
        NativeCameraContract.LOG_TAG,
        "EXTENSIONS_PROBE_CACHE_HIT available=$cached preferred=$preferredExtension",
      )
      return
    }

    val probeStarted = SystemClock.elapsedRealtime()
    Log.d(NativeCameraContract.LOG_TAG, "EXTENSIONS_MANAGER_PROBE_START")
    val bases = mutableListOf<CameraSelector>()
    try {
      bases.add(preferStockLikeBackCamera(provider))
    } catch (_: Exception) {
    }
    bases.add(CameraSelector.DEFAULT_BACK_CAMERA)

    val found = mutableListOf<String>()
    for (label in listOf(EXT_AUTO, EXT_HDR, EXT_NIGHT)) {
      val extensionMode = extensionModeFor(label) ?: continue
      val available = bases.any { base ->
        try {
          manager.isExtensionAvailable(base, extensionMode)
        } catch (error: Exception) {
          Log.d(
            NativeCameraContract.LOG_TAG,
            "extension $label probe failed: ${error.message}",
          )
          false
        }
      }
      if (available) found.add(label)
    }
    availableExtensionLabels = found
    Companion.processExtensionCache = found

    val requested = requestedExtension?.trim()?.lowercase()
    preferredExtension = when {
      requested == EXT_STANDARD -> EXT_STANDARD
      requested != null && found.contains(requested) -> requested
      found.contains(EXT_AUTO) -> EXT_AUTO
      else -> EXT_STANDARD
    }
    Log.d(
      NativeCameraContract.LOG_TAG,
      "EXTENSIONS_MANAGER_PROBE_END available=$found preferred=$preferredExtension " +
        "+${SystemClock.elapsedRealtime() - probeStarted}ms",
    )
  }

  companion object {
    /** Process-scoped extension availability; not an active camera resource. */
    @Volatile
    var processExtensionCache: List<String>? = null
  }

  private fun videoQualitySelector(attempt: BindAttempt): QualitySelector {
    // A ladder rung pins one exact quality with no fallback so an unsupported
    // tier fails the bind and the next rung (lower tier / no stabilization)
    // gets its own attempt.
    attempt.videoQuality?.let { return QualitySelector.from(it) }
    // Last-resort rungs stay lenient so a preview is guaranteed.
    val ordered = if (quality == NativeCameraContract.QUALITY_BALANCED) {
      listOf(Quality.FHD, Quality.HD, Quality.SD)
    } else {
      listOf(Quality.HD, Quality.SD, Quality.FHD)
    }
    return QualitySelector.fromOrderedList(
      ordered,
      FallbackStrategy.lowerQualityOrHigherThan(Quality.HD),
    )
  }

  private fun applyFlash() {
    val capture = imageCapture ?: return
    if (mode != Mode.PHOTO) return
    capture.flashMode = when {
      !hasFlashUnit -> ImageCapture.FLASH_MODE_OFF
      flashCycle == FlashCycle.ON -> ImageCapture.FLASH_MODE_ON
      flashCycle == FlashCycle.AUTO -> ImageCapture.FLASH_MODE_AUTO
      else -> ImageCapture.FLASH_MODE_OFF
    }
  }

  private fun tryEnableVideoStabilization(builder: VideoCapture.Builder<Recorder>) {
    try {
      Camera2Interop.Extender(builder).setCaptureRequestOption(
        CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE,
        CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE_ON,
      )
    } catch (error: Exception) {
      Log.d(
        NativeCameraContract.LOG_TAG,
        "video stabilization not applied: ${error.message}",
      )
    }
  }

  private fun installGestures() {
    scaleDetector = ScaleGestureDetector(
      context,
      object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(detector: ScaleGestureDetector): Boolean {
          val current = currentZoomRatio()
          setZoomRatio(current * detector.scaleFactor)
          return true
        }
      },
    )
  }

  /** Forward touch events from Activity (so tap-to-focus reticle can coexist). */
  fun onPreviewTouch(event: MotionEvent): Boolean {
    val detector = scaleDetector ?: return false
    detector.onTouchEvent(event)
    return detector.isInProgress
  }

  private fun createOutputFile(isPhoto: Boolean, captureId: String? = null): File? {
    return try {
      val dir = File(context.cacheDir, "native_camera")
      if (!dir.exists()) dir.mkdirs()
      val id = captureId ?: java.util.UUID.randomUUID().toString()
      val name = if (isPhoto) "IMG_$id.jpg" else "VID_$id.mp4"
      File(dir, name)
    } catch (error: Exception) {
      Log.d(NativeCameraContract.LOG_TAG, "createOutputFile failed: ${error.message}")
      null
    }
  }

  data class CaptureOutput(
    val path: String,
    val type: String,
    val captureId: String,
    val width: Int?,
    val height: Int?,
    val durationMs: Long?,
    val cameraPosition: String,
    val lens: String?,
    val zoomFactor: Double?,
    val fileSizeBytes: Long?,
    val mimeType: String,
    val orientationDegrees: Int?,
    val extensionMode: String?,
    val captureMode: String = EXT_STANDARD,
    val fallbackLevel: String = NativeCameraContract.FallbackLevel.LAST_RESORT_BASIC,
  ) {
    /** "WxH" telemetry string, null when dimensions are unknown. */
    val dimensions: String?
      get() = if (width != null && height != null) "${width}x$height" else null

    fun toResultMap(): HashMap<String, Any?> = hashMapOf(
      NativeCameraContract.RESULT_PATH to path,
      NativeCameraContract.RESULT_TYPE to type,
      NativeCameraContract.RESULT_CAPTURE_ID to captureId,
      NativeCameraContract.RESULT_CAPTURED_AT_MS to System.currentTimeMillis(),
      NativeCameraContract.RESULT_WIDTH to width,
      NativeCameraContract.RESULT_HEIGHT to height,
      NativeCameraContract.RESULT_DURATION_MS to durationMs,
      NativeCameraContract.RESULT_CAMERA_POSITION to cameraPosition,
      NativeCameraContract.RESULT_LENS to lens,
      NativeCameraContract.RESULT_ZOOM_FACTOR to zoomFactor,
      NativeCameraContract.RESULT_FILE_SIZE_BYTES to fileSizeBytes,
      NativeCameraContract.RESULT_MIME_TYPE to mimeType,
      NativeCameraContract.RESULT_ORIENTATION_DEGREES to orientationDegrees,
      NativeCameraContract.RESULT_EXTENSION_MODE to extensionMode,
      NativeCameraContract.RESULT_CAPTURE_MODE to captureMode,
      NativeCameraContract.RESULT_FALLBACK_LEVEL to fallbackLevel,
      NativeCameraContract.RESULT_PHOTO_DIMENSIONS to dimensions,
    )
  }

  private fun hasEnoughStorage(): Boolean {
    return try {
      val path = context.cacheDir.absolutePath
      val stat = StatFs(path)
      val available = stat.availableBlocksLong * stat.blockSizeLong
      // Require at least 50 MB free.
      available > 50L * 1024L * 1024L
    } catch (_: Exception) {
      true
    }
  }

  class SessionException(
    val code: String,
    override val message: String,
  ) : Exception(message)
}
