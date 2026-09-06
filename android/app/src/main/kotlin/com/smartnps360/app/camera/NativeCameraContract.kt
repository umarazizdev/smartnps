package com.smartnps360.app.camera

/**
 * Shared Intent extras / result keys and MethodChannel error codes for the
 * native CameraX capture flow.
 */
object NativeCameraContract {
  const val CHANNEL = "com.smartnps360.app/native_camera"
  const val LOG_TAG = "SmartNPS360Camera"

  const val REQUEST_CAPTURE = 0x4E43 // 'NC'

  const val EXTRA_TYPE = "type"
  const val EXTRA_ALLOW_MODE_SWITCH = "allowModeSwitch"
  const val EXTRA_LANDSCAPE_ONLY = "landscapeOnly"
  const val EXTRA_REAR_CAMERA_ONLY = "rearCameraOnly"
  const val EXTRA_QUALITY = "quality"
  const val EXTRA_PREFER_HEIC = "preferHeic"

  const val RESULT_PATH = "path"
  const val RESULT_TYPE = "type"
  const val RESULT_CAPTURED_AT_MS = "capturedAtMs"
  const val RESULT_WIDTH = "width"
  const val RESULT_HEIGHT = "height"
  const val RESULT_DURATION_MS = "durationMs"
  const val RESULT_CAMERA_POSITION = "cameraPosition"
  const val RESULT_LENS = "lens"
  const val RESULT_ZOOM_FACTOR = "zoomFactor"
  const val RESULT_FILE_SIZE_BYTES = "fileSizeBytes"
  const val RESULT_MIME_TYPE = "mimeType"
  const val RESULT_ORIENTATION_DEGREES = "orientationDegrees"
  const val RESULT_EXTENSION_MODE = "extensionMode"
  const val RESULT_CAPTURE_MODE = "captureMode"
  const val RESULT_FALLBACK_LEVEL = "fallbackLevel"
  const val RESULT_PHOTO_DIMENSIONS = "photoDimensions"
  const val RESULT_CAPTURE_ID = "captureId"
  const val RESULT_CANCELED = "canceled"
  const val RESULT_ERROR_CODE = "errorCode"
  const val RESULT_ERROR_MESSAGE = "errorMessage"

  const val EXTRA_PREFERRED_EXTENSION = "preferredExtension"

  object ExtensionModeLabel {
    const val AUTO = "auto"
    const val HDR = "hdr"
    const val NIGHT = "night"
    const val STANDARD = "standard"
  }

  object FallbackLevel {
    const val EXTENSION_PREFERRED = "extension_preferred"
    const val EXTENSION_OEM_FLEX = "extension_oem_flex"
    const val EXTENSION_CONSERVATIVE = "extension_conservative"
    const val STANDARD_MAX = "standard_max"
    const val STANDARD_16_9 = "standard_16_9"
    const val LAST_RESORT_BASIC = "last_resort_basic"
    /** @deprecated Prefer [LAST_RESORT_BASIC]; kept for older log readers. */
    const val BASIC = LAST_RESORT_BASIC
  }

  object Diagnostics {
    const val PHOTO_QUALITY_DEGRADED_LAST_RESORT =
      "PHOTO_QUALITY_DEGRADED_LAST_RESORT"
  }

  object ErrorCode {
    const val CANCELED = "canceled"
    const val PERMISSION_DENIED = "permission_denied"
    const val PERMISSION_PERMANENTLY_DENIED = "permission_permanently_denied"
    const val MICROPHONE_PERMISSION_DENIED = "microphone_permission_denied"
    const val NO_REAR_CAMERA = "no_rear_camera"
    const val CAMERA_IN_USE = "camera_in_use"
    const val INIT_FAILED = "init_failed"
    const val CAPTURE_FAILED = "capture_failed"
    const val RECORDING_FAILED = "recording_failed"
    const val INSUFFICIENT_STORAGE = "insufficient_storage"
    const val INTERRUPTED = "interrupted"
    const val PORTRAIT_CAPTURE_REJECTED = "portrait_capture_rejected"
    const val REAR_CAMERA_REQUIRED = "rear_camera_required"
    const val FILE_CREATE_FAILED = "file_create_failed"
    const val UNSUPPORTED = "unsupported"
    const val UNKNOWN = "unknown"
  }

  const val TYPE_PHOTO = "photo"
  const val TYPE_VIDEO = "video"
  const val QUALITY_MAXIMUM = "maximum"
  const val QUALITY_BALANCED = "balanced"
}
