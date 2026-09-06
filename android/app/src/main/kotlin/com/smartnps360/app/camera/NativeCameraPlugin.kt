package com.smartnps360.app.camera

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * MethodChannel bridge that launches [NativeCameraActivity] for a single
 * capture result, matching the Flutter [NativeCamera] contract.
 */
class NativeCameraPlugin :
  FlutterPlugin,
  MethodChannel.MethodCallHandler,
  ActivityAware,
  PluginRegistry.ActivityResultListener {

  private var channel: MethodChannel? = null
  private var activity: Activity? = null
  private var activityBinding: ActivityPluginBinding? = null
  private var pendingResult: MethodChannel.Result? = null
  private val mainHandler = Handler(Looper.getMainLooper())

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val methodChannel = MethodChannel(
      binding.binaryMessenger,
      NativeCameraContract.CHANNEL,
    )
    methodChannel.setMethodCallHandler(this)
    channel = methodChannel
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel?.setMethodCallHandler(null)
    channel = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    activityBinding = binding
    binding.addActivityResultListener(this)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activityBinding?.removeActivityResultListener(this)
    activityBinding = null
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    onAttachedToActivity(binding)
  }

  override fun onDetachedFromActivity() {
    activityBinding?.removeActivityResultListener(this)
    activityBinding = null
    activity = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "open" -> openCamera(call, result)
      "getCapabilities" -> {
        val type = call.argument<String>("type")
          ?: NativeCameraContract.TYPE_PHOTO
        val host = activity?.applicationContext
        if (host == null) {
          result.success(emptyMap<String, Any?>())
          return
        }
        // Probe off the platform thread; reply on main.
        Thread {
          val caps = NativeCameraCapabilitiesProbe.probe(host, type)
          mainHandler.post { result.success(caps) }
        }.start()
      }
      else -> result.notImplemented()
    }
  }

  private fun openCamera(call: MethodCall, result: MethodChannel.Result) {
    val host = activity
    if (host == null) {
      result.error(
        NativeCameraContract.ErrorCode.INIT_FAILED,
        "No Android activity available",
        null,
      )
      return
    }
    if (pendingResult != null) {
      result.error(
        NativeCameraContract.ErrorCode.CAMERA_IN_USE,
        "Native camera already open",
        null,
      )
      return
    }

    val type = call.argument<String>("type") ?: NativeCameraContract.TYPE_PHOTO
    val allowModeSwitch = call.argument<Boolean>("allowModeSwitch") ?: true
    val landscapeOnly = call.argument<Boolean>("landscapeOnly") ?: true
    val rearCameraOnly = call.argument<Boolean>("rearCameraOnly") ?: true
    val quality = call.argument<String>("quality")
      ?: NativeCameraContract.QUALITY_MAXIMUM
    // Android always outputs JPEG; preferHeic is ignored.
    @Suppress("UNUSED_VARIABLE")
    val preferHeic = call.argument<Boolean>("preferHeic") ?: false
    // Optional initial extension mode: auto | hdr | night | standard.
    val preferredExtension = call.argument<String>("preferredExtension")

    Log.d(
      NativeCameraContract.LOG_TAG,
      "CAMERA_OPEN_REQUEST type=$type modeSwitch=$allowModeSwitch " +
        "landscape=$landscapeOnly rear=$rearCameraOnly quality=$quality",
    )

    pendingResult = result
    val intent = Intent(host, NativeCameraActivity::class.java).apply {
      putExtra(NativeCameraContract.EXTRA_TYPE, type)
      putExtra(NativeCameraContract.EXTRA_ALLOW_MODE_SWITCH, allowModeSwitch)
      putExtra(NativeCameraContract.EXTRA_LANDSCAPE_ONLY, landscapeOnly)
      putExtra(NativeCameraContract.EXTRA_REAR_CAMERA_ONLY, rearCameraOnly)
      putExtra(NativeCameraContract.EXTRA_QUALITY, quality)
      putExtra(NativeCameraContract.EXTRA_PREFER_HEIC, false)
      if (!preferredExtension.isNullOrBlank()) {
        putExtra(
          NativeCameraContract.EXTRA_PREFERRED_EXTENSION,
          preferredExtension,
        )
      }
    }
    try {
      host.startActivityForResult(intent, NativeCameraContract.REQUEST_CAPTURE)
    } catch (error: Exception) {
      pendingResult = null
      Log.d(
        NativeCameraContract.LOG_TAG,
        "failed to start camera activity: ${error.message}",
      )
      result.error(
        NativeCameraContract.ErrorCode.INIT_FAILED,
        error.message ?: "Failed to open camera",
        null,
      )
    }
  }

  override fun onActivityResult(
    requestCode: Int,
    resultCode: Int,
    data: Intent?,
  ): Boolean {
    if (requestCode != NativeCameraContract.REQUEST_CAPTURE) return false
    val reply = pendingResult ?: return true
    pendingResult = null

    if (data == null) {
      if (resultCode == Activity.RESULT_CANCELED) {
        reply.success(mapOf(NativeCameraContract.RESULT_CANCELED to true))
      } else {
        reply.error(
          NativeCameraContract.ErrorCode.UNKNOWN,
          "No camera result data",
          null,
        )
      }
      return true
    }

    val errorCode = data.getStringExtra(NativeCameraContract.RESULT_ERROR_CODE)
    if (!errorCode.isNullOrEmpty()) {
      val message = data.getStringExtra(NativeCameraContract.RESULT_ERROR_MESSAGE)
        ?: "Native camera error"
      if (errorCode == NativeCameraContract.ErrorCode.CANCELED) {
        reply.success(mapOf(NativeCameraContract.RESULT_CANCELED to true))
      } else {
        reply.error(errorCode, message, null)
      }
      return true
    }

    if (data.getBooleanExtra(NativeCameraContract.RESULT_CANCELED, false) ||
      resultCode == Activity.RESULT_CANCELED
    ) {
      reply.success(mapOf(NativeCameraContract.RESULT_CANCELED to true))
      return true
    }

    val path = data.getStringExtra(NativeCameraContract.RESULT_PATH)
    if (path.isNullOrEmpty()) {
      reply.error(
        NativeCameraContract.ErrorCode.FILE_CREATE_FAILED,
        "Camera returned an empty file path",
        null,
      )
      return true
    }

    val payload = HashMap<String, Any?>()
    payload[NativeCameraContract.RESULT_PATH] = path
    payload[NativeCameraContract.RESULT_TYPE] =
      data.getStringExtra(NativeCameraContract.RESULT_TYPE)
        ?: NativeCameraContract.TYPE_PHOTO
    payload[NativeCameraContract.RESULT_CAPTURED_AT_MS] =
      data.getLongExtra(
        NativeCameraContract.RESULT_CAPTURED_AT_MS,
        System.currentTimeMillis(),
      )
    putIfPresent(data, payload, NativeCameraContract.RESULT_WIDTH)
    putIfPresent(data, payload, NativeCameraContract.RESULT_HEIGHT)
    if (data.hasExtra(NativeCameraContract.RESULT_DURATION_MS)) {
      payload[NativeCameraContract.RESULT_DURATION_MS] =
        data.getLongExtra(NativeCameraContract.RESULT_DURATION_MS, 0L)
    }
    payload[NativeCameraContract.RESULT_CAMERA_POSITION] =
      data.getStringExtra(NativeCameraContract.RESULT_CAMERA_POSITION) ?: "back"
    payload[NativeCameraContract.RESULT_LENS] =
      data.getStringExtra(NativeCameraContract.RESULT_LENS)
    if (data.hasExtra(NativeCameraContract.RESULT_ZOOM_FACTOR)) {
      payload[NativeCameraContract.RESULT_ZOOM_FACTOR] =
        data.getDoubleExtra(NativeCameraContract.RESULT_ZOOM_FACTOR, 1.0)
    }
    if (data.hasExtra(NativeCameraContract.RESULT_FILE_SIZE_BYTES)) {
      payload[NativeCameraContract.RESULT_FILE_SIZE_BYTES] =
        data.getLongExtra(NativeCameraContract.RESULT_FILE_SIZE_BYTES, 0L)
    }
    payload[NativeCameraContract.RESULT_MIME_TYPE] =
      data.getStringExtra(NativeCameraContract.RESULT_MIME_TYPE)
    putIfPresent(data, payload, NativeCameraContract.RESULT_ORIENTATION_DEGREES)
    payload[NativeCameraContract.RESULT_EXTENSION_MODE] =
      data.getStringExtra(NativeCameraContract.RESULT_EXTENSION_MODE)
    payload[NativeCameraContract.RESULT_CAPTURE_MODE] =
      data.getStringExtra(NativeCameraContract.RESULT_CAPTURE_MODE)
    payload[NativeCameraContract.RESULT_FALLBACK_LEVEL] =
      data.getStringExtra(NativeCameraContract.RESULT_FALLBACK_LEVEL)
    payload[NativeCameraContract.RESULT_PHOTO_DIMENSIONS] =
      data.getStringExtra(NativeCameraContract.RESULT_PHOTO_DIMENSIONS)
    payload[NativeCameraContract.RESULT_CAPTURE_ID] =
      data.getStringExtra(NativeCameraContract.RESULT_CAPTURE_ID)

    Log.d(
      NativeCameraContract.LOG_TAG,
      "open result type=${payload[NativeCameraContract.RESULT_TYPE]} " +
        "id=${payload[NativeCameraContract.RESULT_CAPTURE_ID]} " +
        "path=$path size=${payload[NativeCameraContract.RESULT_FILE_SIZE_BYTES]} " +
        "captureMode=${payload[NativeCameraContract.RESULT_CAPTURE_MODE]} " +
        "fallback=${payload[NativeCameraContract.RESULT_FALLBACK_LEVEL]}",
    )
    reply.success(payload)
    return true
  }

  private fun putIfPresent(
    data: Intent,
    payload: HashMap<String, Any?>,
    key: String,
  ) {
    if (!data.hasExtra(key)) return
    // Width/height/orientation are ints.
    payload[key] = data.getIntExtra(key, 0)
  }
}
