package com.smartnps360.app

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityRecognitionClient
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Google Play Services Activity Recognition to Flutter via
 * MethodChannel + EventChannel. Updates arrive through [MotionActivityReceiver].
 */
class MotionActivityManager(
  private val context: Context,
) : EventChannel.StreamHandler {
  companion object {
    const val METHOD_CHANNEL = "com.smartnps360.app/motion_activity"
    const val EVENT_CHANNEL = "com.smartnps360.app/motion_activity_events"
    const val ACTION_ACTIVITY_UPDATE = "com.smartnps360.app.ACTION_ACTIVITY_UPDATE"
    /** Detection cadence for ActivityRecognitionClient (lower = snappier UI, more battery). */
    private const val DETECTION_INTERVAL_MS = 2_000L
    private const val REQUEST_CODE = 3601

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    fun emit(payload: Map<String, Any?>) {
      mainHandler.post {
        eventSink?.success(payload)
      }
    }
  }

  private val client: ActivityRecognitionClient =
    ActivityRecognition.getClient(context.applicationContext)

  private var methodChannel: MethodChannel? = null
  private var eventChannel: EventChannel? = null
  private var isRunning = false

  fun register(messenger: BinaryMessenger) {
    val methods = MethodChannel(messenger, METHOD_CHANNEL)
    methodChannel = methods
    methods.setMethodCallHandler { call, result ->
      when (call.method) {
        "isAvailable" -> result.success(true)
        "checkPermission" -> result.success(permissionStatus())
        "requestPermission" -> {
          // Runtime prompt is owned by Flutter (permission_handler).
          result.success(permissionStatus())
        }
        "start" -> start(result)
        "stop" -> {
          stop()
          result.success(mapOf("ok" to true, "running" to false))
        }
        "isRunning" -> result.success(mapOf("ok" to true, "running" to isRunning))
        else -> result.notImplemented()
      }
    }

    val events = EventChannel(messenger, EVENT_CHANNEL)
    eventChannel = events
    events.setStreamHandler(this)
  }

  fun dispose() {
    stop()
    methodChannel?.setMethodCallHandler(null)
    methodChannel = null
    eventChannel?.setStreamHandler(null)
    eventChannel = null
    eventSink = null
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
    stop()
  }

  private fun permissionStatus(): String {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
      return "granted"
    }
    val granted =
      ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.ACTIVITY_RECOGNITION,
      ) == PackageManager.PERMISSION_GRANTED
    return if (granted) "granted" else "denied"
  }

  private fun hasPermission(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
    return ContextCompat.checkSelfPermission(
      context,
      Manifest.permission.ACTIVITY_RECOGNITION,
    ) == PackageManager.PERMISSION_GRANTED
  }

  private fun start(result: MethodChannel.Result) {
    if (!hasPermission()) {
      result.success(
        mapOf(
          "ok" to false,
          "running" to false,
          "permission" to permissionStatus(),
          "error" to mapOf(
            "code" to "permission_denied",
            "message" to "ACTIVITY_RECOGNITION permission is required",
          ),
        ),
      )
      return
    }

    if (isRunning) {
      result.success(
        mapOf(
          "ok" to true,
          "running" to true,
          "permission" to permissionStatus(),
        ),
      )
      return
    }

    try {
      client
        .requestActivityUpdates(DETECTION_INTERVAL_MS, activityPendingIntent())
        .addOnSuccessListener {
          isRunning = true
          result.success(
            mapOf(
              "ok" to true,
              "running" to true,
              "permission" to permissionStatus(),
            ),
          )
        }
        .addOnFailureListener { error ->
          isRunning = false
          result.success(
            mapOf(
              "ok" to false,
              "running" to false,
              "error" to mapOf(
                "code" to "start_failed",
                "message" to (error.message ?: "Failed to start activity recognition"),
              ),
            ),
          )
        }
    } catch (error: SecurityException) {
      isRunning = false
      result.success(
        mapOf(
          "ok" to false,
          "running" to false,
          "permission" to permissionStatus(),
          "error" to mapOf(
            "code" to "security",
            "message" to (error.message ?: "SecurityException"),
          ),
        ),
      )
    } catch (error: Exception) {
      isRunning = false
      result.success(
        mapOf(
          "ok" to false,
          "running" to false,
          "error" to mapOf(
            "code" to "start_failed",
            "message" to (error.message ?: "Failed to start activity recognition"),
          ),
        ),
      )
    }
  }

  fun stop() {
    if (!isRunning) return
    try {
      client.removeActivityUpdates(activityPendingIntent())
    } catch (_: Exception) {
    }
    isRunning = false
  }

  private fun activityPendingIntent(): PendingIntent {
    val intent =
      Intent(context, MotionActivityReceiver::class.java).apply {
        action = ACTION_ACTIVITY_UPDATE
      }
    val flags =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
      } else {
        PendingIntent.FLAG_UPDATE_CURRENT
      }
    return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
  }
}
