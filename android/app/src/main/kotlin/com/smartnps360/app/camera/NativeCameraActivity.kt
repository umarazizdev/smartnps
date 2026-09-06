package com.smartnps360.app.camera

import android.Manifest
import android.animation.Keyframe
import android.animation.ObjectAnimator
import android.animation.PropertyValuesHolder
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.PathInterpolator
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.smartnps360.app.R
import kotlin.math.abs

/**
 * Landscape-locked fullscreen CameraX capture UI.
 * Chrome matches the previous Flutter VisitVideoRecorderScreen landscape layout.
 */
class NativeCameraActivity : AppCompatActivity(), NativeCameraSession.Listener {
  private lateinit var previewView: PreviewView
  private lateinit var focusReticle: View
  private lateinit var extensionLabel: TextView
  private lateinit var btnClose: ImageButton
  private lateinit var btnFlash: ImageButton
  private lateinit var btnFlip: ImageButton
  private lateinit var btnShutter: ImageButton
  private lateinit var btnStop: ImageButton
  private lateinit var btnModePhoto: TextView
  private lateinit var btnModeVideo: TextView
  private lateinit var zoomRow: LinearLayout
  private lateinit var zoomLabel: TextView
  private lateinit var extensionRow: LinearLayout
  private lateinit var exposureRow: LinearLayout
  private lateinit var btnExposureDown: TextView
  private lateinit var btnExposureUp: TextView
  private lateinit var exposureValue: TextView
  private lateinit var recordingTimer: LinearLayout
  private lateinit var recordingTimerText: TextView
  private lateinit var captureHint: TextView
  private lateinit var busyOverlay: View
  private lateinit var busyLabel: TextView
  private lateinit var statusToast: TextView
  private lateinit var portraitBlockOverlay: View
  private lateinit var portraitBlockIcon: ImageView
  private lateinit var rightChrome: View

  private var rotateHintAnimator: ObjectAnimator? = null
  private var session: NativeCameraSession? = null
  private var allowModeSwitch = true
  private var rearCameraOnly = true
  private var landscapeOnly = true
  private var quality = NativeCameraContract.QUALITY_MAXIMUM
  private var requestedExtension: String? = null
  private var exposureMin = 0
  private var exposureMax = 0
  private var exposureCurrent = 0
  private var mode = NativeCameraSession.Mode.PHOTO
  private var flashCycle = NativeCameraSession.FlashCycle.OFF
  private var torchOn = false
  private var finishingWithResult = false
  private var sessionReady = false
  private var isRecordingUi = false
  private var pendingStartRecording = false
  private var pendingMicForVideo = false
  private var shutterLongPressActive = false
  private var busyVisible = false
  private var isPortraitBlocked = false

  private val mainHandler = Handler(Looper.getMainLooper())
  private var recordStartElapsed = 0L
  private val timerRunnable = object : Runnable {
    override fun run() {
      val elapsed = SystemClock.elapsedRealtime() - recordStartElapsed
      val totalSec = (elapsed / 1000L).toInt()
      val min = totalSec / 60
      val sec = totalSec % 60
      recordingTimerText.text = String.format("%d:%02d", min, sec)
      mainHandler.postDelayed(this, 250L)
    }
  }

  private var gestureDownX = 0f
  private var gestureDownY = 0f
  private var gestureMoved = false
  private var pendingVideoResult: ((Result<NativeCameraSession.CaptureOutput>) -> Unit)? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    CamPerf.configure(
      (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0,
    )
    CamPerf.resetSession()
    super.onCreate(savedInstanceState)
    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    setContentView(R.layout.activity_native_camera)
    Log.d(NativeCameraContract.LOG_TAG, "NATIVE_SCREEN_CREATED")

    previewView = findViewById(R.id.preview_view)
    // Compatible mode respects targetRotation when the activity handles
    // orientation configChanges without recreating.
    previewView.implementationMode = PreviewView.ImplementationMode.PERFORMANCE
    previewView.scaleType = PreviewView.ScaleType.FILL_CENTER
    previewView.previewStreamState.observe(this) { state ->
      if (state == PreviewView.StreamState.STREAMING) {
        Log.d(NativeCameraContract.LOG_TAG, "FIRST_PREVIEW_FRAME / PREVIEW_SURFACE_READY")
        Log.d(NativeCameraContract.LOG_TAG, "CAMERA_READY")
        CamPerf.markFirstPreviewFrame()
      }
    }
    focusReticle = findViewById(R.id.focus_reticle)
    extensionLabel = findViewById(R.id.extension_label)
    btnClose = findViewById(R.id.btn_close)
    btnFlash = findViewById(R.id.btn_flash)
    btnFlip = findViewById(R.id.btn_flip)
    btnShutter = findViewById(R.id.btn_shutter)
    btnStop = findViewById(R.id.btn_stop)
    btnModePhoto = findViewById(R.id.btn_mode_photo)
    btnModeVideo = findViewById(R.id.btn_mode_video)
    zoomRow = findViewById(R.id.zoom_row)
    zoomLabel = findViewById(R.id.zoom_label)
    extensionRow = findViewById(R.id.extension_row)
    exposureRow = findViewById(R.id.exposure_row)
    btnExposureDown = findViewById(R.id.btn_exposure_down)
    btnExposureUp = findViewById(R.id.btn_exposure_up)
    exposureValue = findViewById(R.id.exposure_value)
    recordingTimer = findViewById(R.id.recording_timer)
    recordingTimerText = findViewById(R.id.recording_timer_text)
    captureHint = findViewById(R.id.capture_hint)
    busyOverlay = findViewById(R.id.busy_overlay)
    busyLabel = findViewById(R.id.busy_label)
    statusToast = findViewById(R.id.status_toast)
    portraitBlockOverlay = findViewById(R.id.portrait_block_overlay)
    portraitBlockIcon = findViewById(R.id.portrait_block_icon)
    rightChrome = findViewById(R.id.right_chrome)

    allowModeSwitch = intent.getBooleanExtra(
      NativeCameraContract.EXTRA_ALLOW_MODE_SWITCH,
      true,
    )
    rearCameraOnly = intent.getBooleanExtra(
      NativeCameraContract.EXTRA_REAR_CAMERA_ONLY,
      true,
    )
    landscapeOnly = intent.getBooleanExtra(
      NativeCameraContract.EXTRA_LANDSCAPE_ONLY,
      true,
    )
    quality = intent.getStringExtra(NativeCameraContract.EXTRA_QUALITY)
      ?: NativeCameraContract.QUALITY_MAXIMUM
    requestedExtension = intent
      .getStringExtra(NativeCameraContract.EXTRA_PREFERRED_EXTENSION)
      ?.trim()
      ?.lowercase()
      ?.takeIf { it.isNotEmpty() }
    val type = intent.getStringExtra(NativeCameraContract.EXTRA_TYPE)
      ?: NativeCameraContract.TYPE_PHOTO
    mode = if (type == NativeCameraContract.TYPE_VIDEO) {
      NativeCameraSession.Mode.VIDEO
    } else {
      NativeCameraSession.Mode.PHOTO
    }

    wireControls()
    syncPortraitBlock()
    updateCaptureChrome()

    onBackPressedDispatcher.addCallback(
      this,
      object : OnBackPressedCallback(true) {
        override fun handleOnBackPressed() {
          cancelAndFinish()
        }
      },
    )

    if (!hasCameraPermission()) {
      requestPermissionsForMode()
    } else if (mode == NativeCameraSession.Mode.VIDEO && !hasMicPermission()) {
      requestPermissionsForMode()
    } else {
      startSession()
    }
  }

  override fun onStop() {
    super.onStop()
    if (isChangingConfigurations) return
    val active = session
    if (active != null && active.isRecording() && !finishingWithResult) {
      active.abortRecording()
      finishWithError(
        NativeCameraContract.ErrorCode.INTERRUPTED,
        "Capture interrupted",
      )
    }
  }

  override fun onDestroy() {
    mainHandler.removeCallbacksAndMessages(null)
    stopRotateHintAnimation()
    session?.release()
    session = null
    super.onDestroy()
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray,
  ) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    if (requestCode != REQ_PERMISSIONS) return

    val cameraGranted = hasCameraPermission()
    if (!cameraGranted) {
      val permanently = permissions.indices.any { index ->
        permissions[index] == Manifest.permission.CAMERA &&
          grantResults[index] != PackageManager.PERMISSION_GRANTED &&
          !ActivityCompat.shouldShowRequestPermissionRationale(
            this,
            Manifest.permission.CAMERA,
          )
      }
      pendingMicForVideo = false
      finishWithError(
        if (permanently) {
          NativeCameraContract.ErrorCode.PERMISSION_PERMANENTLY_DENIED
        } else {
          NativeCameraContract.ErrorCode.PERMISSION_DENIED
        },
        "Camera permission denied",
      )
      return
    }

    if (pendingMicForVideo) {
      pendingMicForVideo = false
      if (!hasMicPermission()) {
        finishWithError(
          NativeCameraContract.ErrorCode.MICROPHONE_PERMISSION_DENIED,
          "Microphone permission denied",
        )
        return
      }
      // Long-press was interrupted by the permission dialog; stay ready for
      // the next hold-to-record gesture.
      if (session == null) {
        startSession()
      }
      return
    }

    if (mode == NativeCameraSession.Mode.VIDEO && !hasMicPermission()) {
      finishWithError(
        NativeCameraContract.ErrorCode.MICROPHONE_PERMISSION_DENIED,
        "Microphone permission denied",
      )
      return
    }

    startSession()
  }

  override fun onSessionReady(
    hasFlash: Boolean,
    minZoom: Float,
    maxZoom: Float,
    usefulZooms: List<Double>,
    extensionMode: String?,
    availableExtensions: List<String>,
    minExposure: Int,
    maxExposure: Int,
    exposureIndex: Int,
  ) {
    sessionReady = true
    updateFlashButtonVisibility(hasFlash)
    updateExtensionLabel(extensionMode)
    rebuildExtensionChips(availableExtensions)
    updateExposureControls(minExposure, maxExposure, exposureIndex)
    rebuildZoomChips(usefulZooms)
    updateFlipVisibility()
    updateCaptureChrome()
    syncCameraTargetRotation()

    if (pendingStartRecording && mode == NativeCameraSession.Mode.VIDEO) {
      pendingStartRecording = false
      beginRecordingNow()
    } else if (!isRecordingUi) {
      hideBusy()
    }
  }

  override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
    super.onConfigurationChanged(newConfig)
    syncPortraitBlock()
    // Activity handles configChanges — refresh rotation + ViewPort so portrait
    // and landscape both show an upright, full-screen preview like the OS camera.
    syncCameraTargetRotation(rebindViewport = true)
  }

  override fun onResume() {
    super.onResume()
    syncPortraitBlock()
    syncCameraTargetRotation(rebindViewport = false)
  }

  /** Same rule as previous Flutter capture UI: height >= width ⇒ portrait blocked. */
  private fun syncPortraitBlock() {
    if (!landscapeOnly) {
      isPortraitBlocked = false
      portraitBlockOverlay.visibility = View.GONE
      rightChrome.visibility = View.VISIBLE
      updateAuxChromeVisibility()
      stopRotateHintAnimation()
      return
    }
    val metrics = resources.displayMetrics
    val portrait = metrics.heightPixels >= metrics.widthPixels
    isPortraitBlocked = portrait
    portraitBlockOverlay.visibility = if (portrait) View.VISIBLE else View.GONE
    // Keep the live camera preview visible under the dialog; only hide capture chrome.
    rightChrome.visibility = if (portrait) View.INVISIBLE else View.VISIBLE
    updateAuxChromeVisibility()
    // Top chrome close stays available; preview remains full-bleed underneath.
    if (portrait) {
      startRotateHintAnimation()
    } else {
      stopRotateHintAnimation()
    }
    if (portrait && isRecordingUi) {
      session?.abortRecording()
    }
  }

  /**
   * Align Preview / ImageCapture / VideoCapture with the current display
   * rotation in both portrait and landscape so the live preview stays upright
   * behind the landscape dialog and after rotating into landscape.
   */
  private fun syncCameraTargetRotation(rebindViewport: Boolean = false) {
    previewView.post {
      val active = session ?: return@post
      if (rebindViewport) {
        active.refreshForDisplayChange()
      } else {
        active.updateTargetRotation()
      }
    }
  }

  /** Matches Flutter [VisitAnimatedOrientationHintIcon] toward-landscape loop. */
  private fun startRotateHintAnimation() {
    if (rotateHintAnimator?.isRunning == true) return
    portraitBlockIcon.post {
      if (!isPortraitBlocked) return@post
      if (rotateHintAnimator?.isRunning == true) return@post
      val ease = PathInterpolator(0.65f, 0f, 0.35f, 1f)
      val mid = Keyframe.ofFloat(0.50f, -90f).also { it.interpolator = ease }
      val end = Keyframe.ofFloat(1f, 0f).also { it.interpolator = ease }
      val holder = PropertyValuesHolder.ofKeyframe(
        View.ROTATION,
        Keyframe.ofFloat(0f, 0f),
        Keyframe.ofFloat(0.12f, 0f),
        mid,
        Keyframe.ofFloat(0.74f, -90f),
        end,
      )
      rotateHintAnimator = ObjectAnimator.ofPropertyValuesHolder(portraitBlockIcon, holder).apply {
        duration = 1800L
        repeatCount = ObjectAnimator.INFINITE
        start()
      }
    }
  }

  private fun stopRotateHintAnimation() {
    rotateHintAnimator?.cancel()
    rotateHintAnimator = null
    if (::portraitBlockIcon.isInitialized) {
      portraitBlockIcon.rotation = 0f
    }
  }

  /**
   * Capture is impossible while the preview is portrait-blocked, an overlay is
   * up, the session has not reported ready, or a serialized rebind is running
   * (the session would reject the request with a hard capture error).
   */
  private fun isCaptureBlocked(): Boolean {
    return isPortraitBlocked ||
      busyVisible ||
      !sessionReady ||
      session?.isRebinding() == true
  }

  override fun onSessionError(code: String, message: String) {
    pendingStartRecording = false
    hideBusy()
    finishWithError(code, sanitizeMessage(message, "Camera error"))
  }

  override fun onZoomChanged(zoomRatio: Float) {
    zoomLabel.text = formatZoom(zoomRatio)
    highlightZoomChip(zoomRatio)
  }

  override fun onRecordingStatus(isRecording: Boolean, errorCode: String?) {
    isRecordingUi = isRecording
    if (isRecording) {
      hideBusy()
      recordStartElapsed = SystemClock.elapsedRealtime()
      recordingTimerText.text = "0:00"
      mainHandler.removeCallbacks(timerRunnable)
      mainHandler.post(timerRunnable)
      updateCaptureChrome()
    } else {
      mainHandler.removeCallbacks(timerRunnable)
      updateCaptureChrome()
      if (!finishingWithResult) {
        returnToPhotoMode()
      }
    }
  }

  private fun wireControls() {
    btnClose.setOnClickListener { cancelAndFinish() }
    btnExposureDown.setOnClickListener { nudgeExposure(-1) }
    btnExposureUp.setOnClickListener { nudgeExposure(1) }
    btnFlash.setOnClickListener { onFlashClicked() }
    btnFlip.setOnClickListener {
      session?.toggleFacing()
      updateFlipVisibility()
    }
    btnStop.setOnClickListener { session?.stopRecording() }

    // Mode chips are hidden in the landscape chrome; keep listeners harmless.
    btnModePhoto.setOnClickListener { /* no-op */ }
    btnModeVideo.setOnClickListener { /* no-op */ }
    btnModePhoto.visibility = View.GONE
    btnModeVideo.visibility = View.GONE

    btnShutter.setOnClickListener {
      if (isCaptureBlocked() || isRecordingUi || shutterLongPressActive) {
        return@setOnClickListener
      }
      onTakePhoto()
    }
    btnShutter.setOnLongClickListener {
      if (isCaptureBlocked() || isRecordingUi) return@setOnLongClickListener true
      shutterLongPressActive = true
      onLongPressStartVideo()
      true
    }
    btnShutter.setOnTouchListener { _, event ->
      when (event.actionMasked) {
        MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
          if (shutterLongPressActive) {
            shutterLongPressActive = false
            onLongPressEndVideo()
          }
        }
      }
      false
    }

    previewView.setOnTouchListener { _, event ->
      val pinch = session?.onPreviewTouch(event) == true
      when (event.actionMasked) {
        MotionEvent.ACTION_DOWN -> {
          gestureDownX = event.x
          gestureDownY = event.y
          gestureMoved = false
        }
        MotionEvent.ACTION_MOVE -> {
          if (abs(event.x - gestureDownX) > 24f ||
            abs(event.y - gestureDownY) > 24f
          ) {
            gestureMoved = true
          }
        }
        MotionEvent.ACTION_UP -> {
          if (!pinch && !gestureMoved) {
            showFocusReticle(event.x, event.y)
            session?.focusAt(event.x, event.y)
          }
        }
      }
      true
    }
  }

  private fun startSession() {
    session?.release()
    sessionReady = false
    val newSession = NativeCameraSession(
      context = this,
      lifecycleOwner = this,
      previewView = previewView,
      quality = quality,
      rearCameraOnly = rearCameraOnly,
      requestedExtension = requestedExtension,
    )
    newSession.listener = this
    session = newSession
    newSession.start(mode)
  }

  private fun onTakePhoto() {
    CamPerf.markShutterTap()
    CamPerf.stage(null, "SHUTTER_HANDLER_ENTER", "thread=${Thread.currentThread().name}")
    if (isPortraitBlocked) return
    val active = session ?: return
    if (!sessionReady) return
    if (mode != NativeCameraSession.Mode.PHOTO) return
    if (active.isCapturing() || active.isRebinding()) return
    showBusy(R.string.native_camera_busy_capturing)
    btnShutter.isEnabled = false
    CamPerf.stage(null, "SESSION_TAKE_PICTURE_REQUEST")
    active.takePicture { result ->
      btnShutter.isEnabled = true
      result.fold(
        onSuccess = { output ->
          showBusy(R.string.native_camera_busy_saving)
          finishWithCapture(output)
        },
        onFailure = { error ->
          hideBusy()
          val sessionError = error as? NativeCameraSession.SessionException
          val code = sessionError?.code
            ?: NativeCameraContract.ErrorCode.CAPTURE_FAILED
          if (code == NativeCameraContract.ErrorCode.PORTRAIT_CAPTURE_REJECTED) {
            showToast(getString(R.string.native_camera_portrait_rejected))
          } else {
            finishWithError(
              code,
              sanitizeMessage(error.message, "Capture failed"),
            )
          }
        },
      )
    }
  }

  private fun onLongPressStartVideo() {
    if (isPortraitBlocked) return
    if (!sessionReady && session != null) return
    val active = session ?: return
    if (active.isCapturing()) return
    if (!allowModeSwitch && mode == NativeCameraSession.Mode.PHOTO) {
      // Photo-only launch: hold-to-record is disabled.
      return
    }

    if (!hasMicPermission()) {
      pendingMicForVideo = true
      ActivityCompat.requestPermissions(
        this,
        arrayOf(Manifest.permission.RECORD_AUDIO),
        REQ_PERMISSIONS,
      )
      return
    }

    if (mode == NativeCameraSession.Mode.PHOTO) {
      pendingStartRecording = true
      sessionReady = false
      mode = NativeCameraSession.Mode.VIDEO
      torchOn = false
      showBusy(R.string.native_camera_busy_starting)
      updateCaptureChrome()
      active.switchMode(NativeCameraSession.Mode.VIDEO)
      return
    }

    beginRecordingNow()
  }

  private fun onLongPressEndVideo() {
    if (pendingStartRecording) {
      // Mode switch still in flight; cancel the pending start and return to photo.
      pendingStartRecording = false
      hideBusy()
      if (!isRecordingUi && !finishingWithResult) {
        returnToPhotoMode()
      }
      return
    }
    val active = session ?: return
    if (active.isRecording()) {
      showBusy(R.string.native_camera_busy_saving)
      active.stopRecording()
    }
  }

  private fun beginRecordingNow() {
    val active = session ?: return
    if (!sessionReady || mode != NativeCameraSession.Mode.VIDEO) return
    if (active.isRecording() || active.isRebinding()) return

    showBusy(R.string.native_camera_busy_starting)
    val callback: (Result<NativeCameraSession.CaptureOutput>) -> Unit = { result ->
      pendingVideoResult = null
      result.fold(
        onSuccess = { output ->
          showBusy(R.string.native_camera_busy_saving)
          finishWithCapture(output)
        },
        onFailure = { error ->
          hideBusy()
          val sessionError = error as? NativeCameraSession.SessionException
          val code = sessionError?.code
            ?: NativeCameraContract.ErrorCode.RECORDING_FAILED
          when {
            code == NativeCameraContract.ErrorCode.PORTRAIT_CAPTURE_REJECTED -> {
              showToast(getString(R.string.native_camera_portrait_rejected))
              if (!finishingWithResult) returnToPhotoMode()
            }
            code == NativeCameraContract.ErrorCode.INTERRUPTED && finishingWithResult -> {
              // Already finishing (close / activity stop).
            }
            code == NativeCameraContract.ErrorCode.INTERRUPTED && !finishingWithResult -> {
              // Recording cancelled without leaving the activity.
              if (!finishingWithResult) returnToPhotoMode()
            }
            else -> {
              finishWithError(
                code,
                sanitizeMessage(error.message, "Recording failed"),
              )
            }
          }
        },
      )
    }
    pendingVideoResult = callback
    active.startRecording(callback)
  }

  private fun returnToPhotoMode() {
    pendingStartRecording = false
    if (mode == NativeCameraSession.Mode.PHOTO) {
      updateCaptureChrome()
      return
    }
    val active = session
    if (active == null || active.isRecording()) return
    mode = NativeCameraSession.Mode.PHOTO
    torchOn = false
    sessionReady = false
    showBusy(R.string.native_camera_busy_starting)
    updateCaptureChrome()
    active.switchMode(NativeCameraSession.Mode.PHOTO)
  }

  private fun onFlashClicked() {
    val active = session ?: return
    if (busyVisible || isRecordingUi) return
    if (mode == NativeCameraSession.Mode.PHOTO) {
      flashCycle = active.cycleFlash()
      updateFlashIcon()
    } else {
      torchOn = active.toggleTorch()
      updateFlashIcon()
    }
  }

  private fun updateCaptureChrome() {
    btnModePhoto.visibility = View.GONE
    btnModeVideo.visibility = View.GONE

    if (isRecordingUi) {
      btnShutter.setBackgroundResource(R.drawable.native_camera_shutter_recording)
      btnShutter.setImageResource(R.drawable.native_camera_ic_stop)
      btnShutter.imageTintList = ColorStateList.valueOf(COLOR_WHITE)
      captureHint.setText(R.string.native_camera_hint_recording)
      captureHint.setTextColor(COLOR_ORANGE)
      recordingTimer.visibility = View.VISIBLE
    } else {
      btnShutter.setBackgroundResource(R.drawable.native_camera_shutter)
      btnShutter.setImageResource(R.drawable.native_camera_ic_shutter)
      btnShutter.imageTintList = ColorStateList.valueOf(COLOR_PRIMARY)
      captureHint.setText(R.string.native_camera_hint_idle)
      captureHint.setTextColor(COLOR_HINT_IDLE)
      recordingTimer.visibility = View.GONE
    }

    updateFlashIcon()
    updateFlipVisibility()
    updateZoomChipEnabledState()
    updateAuxChromeVisibility()
  }

  private fun updateFlashButtonVisibility(hasFlash: Boolean) {
    btnFlash.visibility = if (hasFlash) View.VISIBLE else View.GONE
    updateFlashIcon()
  }

  private fun updateFlashIcon() {
    if (btnFlash.visibility != View.VISIBLE) return
    if (mode == NativeCameraSession.Mode.PHOTO) {
      val (icon, desc, tint) = when (flashCycle) {
        NativeCameraSession.FlashCycle.OFF ->
          Triple(R.drawable.native_camera_ic_flash_off, "Flash off", COLOR_WHITE)
        NativeCameraSession.FlashCycle.AUTO ->
          Triple(R.drawable.native_camera_ic_flash_auto, "Flash auto", COLOR_FLASH_YELLOW)
        NativeCameraSession.FlashCycle.ON ->
          Triple(R.drawable.native_camera_ic_flash_on, "Flash on", COLOR_FLASH_YELLOW)
      }
      btnFlash.setImageResource(icon)
      btnFlash.contentDescription = desc
      btnFlash.imageTintList = ColorStateList.valueOf(tint)
      btnFlash.alpha = 1f
    } else {
      btnFlash.setImageResource(R.drawable.native_camera_ic_torch)
      btnFlash.contentDescription = if (torchOn) "Torch on" else "Torch off"
      btnFlash.imageTintList = ColorStateList.valueOf(
        if (torchOn) COLOR_FLASH_YELLOW else COLOR_WHITE,
      )
      btnFlash.alpha = 1f
    }
  }

  private fun updateFlipVisibility() {
    // Flip control is hidden in the landscape chrome layout.
    btnFlip.visibility = View.GONE
  }

  private fun updateExtensionLabel(extensionMode: String?) {
    val text = when (extensionMode) {
      "hdr" -> getString(R.string.native_camera_ext_hdr)
      "night" -> getString(R.string.native_camera_ext_night)
      "auto" -> getString(R.string.native_camera_ext_auto)
      else -> null
    }
    if (text == null || mode != NativeCameraSession.Mode.PHOTO) {
      extensionLabel.visibility = View.GONE
    } else {
      extensionLabel.text = text
      extensionLabel.visibility = View.VISIBLE
    }
  }

  /**
   * Build one chip per selectable capture mode: Std plus every extension the
   * device advertises (auto / hdr / night). Hidden when nothing is selectable.
   */
  private fun rebuildExtensionChips(availableExtensions: List<String>) {
    val labels = mutableListOf<String>()
    if (availableExtensions.isNotEmpty()) {
      labels.add(NativeCameraContract.ExtensionModeLabel.STANDARD)
      labels.addAll(availableExtensions)
    }
    extensionRow.removeAllViews()
    if (labels.size <= 1 || mode != NativeCameraSession.Mode.PHOTO) {
      updateAuxChromeVisibility()
      return
    }
    val density = resources.displayMetrics.density
    labels.forEachIndexed { index, label ->
      val chip = TextView(this).apply {
        text = extensionChipText(label)
        setTextColor(COLOR_WHITE)
        textSize = 10f
        gravity = android.view.Gravity.CENTER
        includeFontPadding = false
        setBackgroundResource(R.drawable.native_camera_zoom_chip)
        setPadding(
          (10 * density).toInt(),
          (7 * density).toInt(),
          (10 * density).toInt(),
          (7 * density).toInt(),
        )
        tag = label
        setOnClickListener { onExtensionChipClicked(label) }
      }
      val lp = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.WRAP_CONTENT,
        (34 * density).toInt(),
      )
      if (index < labels.lastIndex) {
        lp.rightMargin = (6 * density).toInt()
      }
      extensionRow.addView(chip, lp)
    }
    highlightExtensionChip()
    updateAuxChromeVisibility()
  }

  private fun extensionChipText(label: String): String = when (label) {
    NativeCameraContract.ExtensionModeLabel.HDR ->
      getString(R.string.native_camera_ext_hdr)
    NativeCameraContract.ExtensionModeLabel.NIGHT ->
      getString(R.string.native_camera_ext_night)
    NativeCameraContract.ExtensionModeLabel.AUTO ->
      getString(R.string.native_camera_ext_auto)
    else -> getString(R.string.native_camera_ext_standard)
  }

  private fun onExtensionChipClicked(label: String) {
    if (isCaptureBlocked() || isRecordingUi) return
    val active = session ?: return
    if (label == activeCaptureModeLabel()) return
    // Busy first: the session schedules a serialized rebind and reports the
    // bound mode back through onSessionReady, which clears the overlay.
    showBusy(R.string.native_camera_busy_switching)
    val accepted = active.setPreferredExtension(label)
    if (!accepted) {
      hideBusy()
      showToast(getString(R.string.native_camera_ext_unsupported))
      highlightExtensionChip()
      return
    }
    // The bound mode is only known once the rebind lands; onSessionReady
    // re-highlights the row. Busy + isRebinding() gate capture until then.
    highlightExtensionChip()
    // Safety net so the pill can never stay stuck if no callback arrives.
    mainHandler.postDelayed(
      {
        if (busyVisible && !isRecordingUi && !finishingWithResult) hideBusy()
      },
      2500L,
    )
  }

  /** The mode actually bound right now, which may be a ladder fallback. */
  private fun activeCaptureModeLabel(): String {
    return session?.currentExtensionLabel()
      ?: NativeCameraContract.ExtensionModeLabel.STANDARD
  }

  private fun highlightExtensionChip() {
    val selected = activeCaptureModeLabel()
    for (i in 0 until extensionRow.childCount) {
      val child = extensionRow.getChildAt(i) as? TextView ?: continue
      val label = (child.tag as? String) ?: continue
      val isSelected = label == selected
      child.setBackgroundResource(
        if (isSelected) {
          R.drawable.native_camera_zoom_chip_selected
        } else {
          R.drawable.native_camera_zoom_chip
        },
      )
      child.setTextColor(if (isSelected) COLOR_FLASH_YELLOW else COLOR_WHITE)
    }
  }

  private fun updateExposureControls(min: Int, max: Int, index: Int) {
    exposureMin = min
    exposureMax = max
    exposureCurrent = index.coerceIn(min, maxOf(min, max))
    exposureValue.text = getString(
      R.string.native_camera_exposure_value,
      exposureCurrent,
    )
    val enabled = !isRecordingUi && !busyVisible
    btnExposureDown.isEnabled = enabled && exposureCurrent > exposureMin
    btnExposureUp.isEnabled = enabled && exposureCurrent < exposureMax
    btnExposureDown.alpha = if (btnExposureDown.isEnabled) 1f else 0.4f
    btnExposureUp.alpha = if (btnExposureUp.isEnabled) 1f else 0.4f
    updateAuxChromeVisibility()
  }

  private fun nudgeExposure(delta: Int) {
    if (isPortraitBlocked || busyVisible || isRecordingUi) return
    val active = session ?: return
    if (!sessionReady || exposureMax <= exposureMin) return
    val applied = active.setExposureCompensationIndex(exposureCurrent + delta)
    updateExposureControls(exposureMin, exposureMax, applied)
  }

  /** Extension chips + EV stepper follow the portrait-block / mode rules. */
  private fun updateAuxChromeVisibility() {
    if (!::extensionRow.isInitialized || !::exposureRow.isInitialized) return
    extensionRow.visibility = when {
      isPortraitBlocked -> View.INVISIBLE
      extensionRow.childCount > 1 && mode == NativeCameraSession.Mode.PHOTO ->
        View.VISIBLE
      else -> View.GONE
    }
    exposureRow.visibility = when {
      isPortraitBlocked -> View.INVISIBLE
      exposureMax > exposureMin -> View.VISIBLE
      else -> View.GONE
    }
  }

  private fun rebuildZoomChips(levels: List<Double>) {
    zoomRow.removeAllViews()
    if (levels.size <= 1) {
      zoomRow.visibility = View.GONE
      return
    }
    zoomRow.visibility = View.VISIBLE
    val density = resources.displayMetrics.density
    val sizeUnselected = (34 * density).toInt()
    levels.forEachIndexed { index, level ->
      val chip = TextView(this).apply {
        text = formatZoomChip(level)
        setTextColor(COLOR_WHITE)
        textSize = 10f
        gravity = android.view.Gravity.CENTER
        setBackgroundResource(R.drawable.native_camera_zoom_chip)
        includeFontPadding = false
        setOnClickListener {
          if (isRecordingUi || busyVisible) return@setOnClickListener
          session?.setZoomRatio(level.toFloat())
        }
        tag = level
      }
      val lp = LinearLayout.LayoutParams(sizeUnselected, sizeUnselected)
      if (index < levels.lastIndex) {
        lp.bottomMargin = (6 * density).toInt()
      }
      zoomRow.addView(chip, lp)
    }
    highlightZoomChip(session?.currentZoomRatio() ?: 1f)
  }

  private fun highlightZoomChip(zoomRatio: Float) {
    val density = resources.displayMetrics.density
    val sizeUnselected = (34 * density).toInt()
    val sizeSelected = (40 * density).toInt()
    for (i in 0 until zoomRow.childCount) {
      val child = zoomRow.getChildAt(i) as? TextView ?: continue
      val level = (child.tag as? Double) ?: continue
      val selected = abs(level - zoomRatio) < 0.08
      val lp = child.layoutParams as LinearLayout.LayoutParams
      val size = if (selected) sizeSelected else sizeUnselected
      lp.width = size
      lp.height = size
      child.layoutParams = lp
      child.setBackgroundResource(
        if (selected) {
          R.drawable.native_camera_zoom_chip_selected
        } else {
          R.drawable.native_camera_zoom_chip
        },
      )
      child.setTextColor(if (selected) COLOR_FLASH_YELLOW else COLOR_WHITE)
      child.textSize = if (selected) 11f else 10f
    }
  }

  private fun updateZoomChipEnabledState() {
    val enabled = !isRecordingUi && !busyVisible
    for (i in 0 until zoomRow.childCount) {
      zoomRow.getChildAt(i).isEnabled = enabled
      zoomRow.getChildAt(i).alpha = if (enabled) 1f else 0.45f
    }
    if (!::extensionRow.isInitialized) return
    for (i in 0 until extensionRow.childCount) {
      extensionRow.getChildAt(i).isEnabled = enabled
    }
    extensionRow.alpha = if (enabled) 1f else 0.45f
    btnExposureDown.isEnabled = enabled && exposureCurrent > exposureMin
    btnExposureUp.isEnabled = enabled && exposureCurrent < exposureMax
    btnExposureDown.alpha = if (btnExposureDown.isEnabled) 1f else 0.4f
    btnExposureUp.alpha = if (btnExposureUp.isEnabled) 1f else 0.4f
  }

  private fun showBusy(labelRes: Int) {
    busyVisible = true
    busyLabel.setText(labelRes)
    busyOverlay.visibility = View.VISIBLE
    btnShutter.alpha = 0.45f
    updateZoomChipEnabledState()
  }

  private fun hideBusy() {
    busyVisible = false
    busyOverlay.visibility = View.GONE
    btnShutter.alpha = 1f
    updateZoomChipEnabledState()
  }

  private fun showFocusReticle(x: Float, y: Float) {
    focusReticle.visibility = View.VISIBLE
    focusReticle.x = x - focusReticle.width / 2f
    focusReticle.y = y - focusReticle.height / 2f
    // Width may be 0 before layout; use expected size.
    if (focusReticle.width == 0) {
      val size = (64 * resources.displayMetrics.density)
      focusReticle.x = x - size / 2f
      focusReticle.y = y - size / 2f
    }
    focusReticle.animate().cancel()
    focusReticle.alpha = 1f
    focusReticle.scaleX = 1.15f
    focusReticle.scaleY = 1.15f
    focusReticle.animate()
      .scaleX(1f)
      .scaleY(1f)
      .setDuration(120L)
      .start()
    mainHandler.removeCallbacks(hideReticleRunnable)
    mainHandler.postDelayed(hideReticleRunnable, 900L)
  }

  private val hideReticleRunnable = Runnable {
    focusReticle.animate()
      .alpha(0f)
      .setDuration(200L)
      .withEndAction {
        focusReticle.visibility = View.GONE
        focusReticle.alpha = 1f
      }
      .start()
  }

  private fun showToast(message: String) {
    statusToast.text = message
    statusToast.visibility = View.VISIBLE
    statusToast.alpha = 1f
    mainHandler.removeCallbacks(hideToastRunnable)
    mainHandler.postDelayed(hideToastRunnable, 1800L)
  }

  private val hideToastRunnable = Runnable {
    statusToast.animate()
      .alpha(0f)
      .setDuration(200L)
      .withEndAction {
        statusToast.visibility = View.GONE
        statusToast.alpha = 1f
      }
      .start()
  }

  private fun cancelAndFinish() {
    pendingStartRecording = false
    if (session?.isRecording() == true) {
      session?.abortRecording()
    }
    finishingWithResult = true
    val data = Intent().putExtra(NativeCameraContract.RESULT_CANCELED, true)
    setResult(RESULT_CANCELED, data)
    finish()
  }

  private fun finishWithCapture(output: NativeCameraSession.CaptureOutput) {
    if (finishingWithResult) return
    CamPerf.stage(output.captureId, "NATIVE_RESULT_PREPARE", "activity")
    // FAIL CLOSED: a rear-only photo request must never return a front capture.
    if (rearCameraOnly &&
      output.type == NativeCameraContract.TYPE_PHOTO &&
      output.cameraPosition != "back"
    ) {
      java.io.File(output.path).delete()
      hideBusy()
      finishWithError(
        NativeCameraContract.ErrorCode.REAR_CAMERA_REQUIRED,
        "Rear camera required for photo capture",
      )
      return
    }
    if (landscapeOnly) {
      // Prefer dimensions already validated by the session (avoid a second
      // full EXIF/MediaMetadata decode on the critical shutter path).
      val landscape = when {
        output.width != null && output.height != null ->
          output.width!! > output.height!!
        output.type == NativeCameraContract.TYPE_PHOTO ->
          NativeCameraOrientation.isLandscapePhoto(java.io.File(output.path))
        else ->
          NativeCameraOrientation.isLandscapeVideo(java.io.File(output.path))
      }
      if (!landscape) {
        java.io.File(output.path).delete()
        hideBusy()
        showToast(getString(R.string.native_camera_portrait_rejected))
        if (!finishingWithResult) returnToPhotoMode()
        return
      }
    }
    finishingWithResult = true
    val data = Intent()
    output.toResultMap().forEach { (key, value) ->
      when (value) {
        null -> Unit
        is String -> data.putExtra(key, value)
        is Int -> data.putExtra(key, value)
        is Long -> data.putExtra(key, value)
        is Double -> data.putExtra(key, value)
        is Float -> data.putExtra(key, value)
        is Boolean -> data.putExtra(key, value)
        else -> data.putExtra(key, value.toString())
      }
    }
    CamPerf.markNativeResultFinish(output.captureId)
    setResult(RESULT_OK, data)
    finish()
  }

  private fun finishWithError(code: String, message: String) {
    if (finishingWithResult) return
    finishingWithResult = true
    val safe = sanitizeMessage(message, "Camera error")
    Log.d(NativeCameraContract.LOG_TAG, "finish error=$code message=$safe")
    val data = Intent()
      .putExtra(NativeCameraContract.RESULT_ERROR_CODE, code)
      .putExtra(NativeCameraContract.RESULT_ERROR_MESSAGE, safe)
    setResult(RESULT_CANCELED, data)
    finish()
  }

  private fun sanitizeMessage(message: String?, fallback: String): String {
    if (message.isNullOrBlank()) return fallback
    // Never surface raw stack traces or multi-line exception dumps in UI/results.
    val firstLine = message.lineSequence().firstOrNull()?.trim().orEmpty()
    if (firstLine.isEmpty()) return fallback
    if (firstLine.contains('\t') ||
      firstLine.startsWith("at ") ||
      firstLine.contains("Exception:") && firstLine.length > 160
    ) {
      return fallback
    }
    return firstLine.take(160)
  }

  private fun hasCameraPermission(): Boolean {
    return ContextCompat.checkSelfPermission(
      this,
      Manifest.permission.CAMERA,
    ) == PackageManager.PERMISSION_GRANTED
  }

  private fun hasMicPermission(): Boolean {
    return ContextCompat.checkSelfPermission(
      this,
      Manifest.permission.RECORD_AUDIO,
    ) == PackageManager.PERMISSION_GRANTED
  }

  private fun requestPermissionsForMode() {
    val needed = mutableListOf<String>()
    if (!hasCameraPermission()) needed.add(Manifest.permission.CAMERA)
    if (mode == NativeCameraSession.Mode.VIDEO && !hasMicPermission()) {
      needed.add(Manifest.permission.RECORD_AUDIO)
    }
    if (needed.isEmpty()) {
      startSession()
      return
    }
    ActivityCompat.requestPermissions(
      this,
      needed.toTypedArray(),
      REQ_PERMISSIONS,
    )
  }

  private fun formatZoom(ratio: Float): String {
    return if (ratio < 1f) {
      String.format("%.1fx", ratio)
    } else if (abs(ratio - ratio.toInt()) < 0.05f) {
      "${ratio.toInt()}x"
    } else {
      String.format("%.1fx", ratio)
    }
  }

  private fun formatZoomChip(level: Double): String {
    return when {
      abs(level - 0.5) < 0.05 -> ".5"
      level < 1.0 -> String.format("%.1f", level).removePrefix("0")
      abs(level - level.toInt()) < 0.05 -> "${level.toInt()}x"
      else -> String.format("%.1fx", level)
    }
  }

  companion object {
    private const val REQ_PERMISSIONS = 0x4E50
    private const val COLOR_PRIMARY = 0xFF022A67.toInt()
    private const val COLOR_ORANGE = 0xFFE48E15.toInt()
    private const val COLOR_FLASH_YELLOW = 0xFFFFD60A.toInt()
    private const val COLOR_WHITE = 0xFFFFFFFF.toInt()
    private const val COLOR_HINT_IDLE = 0xEBFFFFFF.toInt()
  }
}
