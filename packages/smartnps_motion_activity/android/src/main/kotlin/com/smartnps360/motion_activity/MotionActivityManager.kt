package com.smartnps360.motion_activity

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
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger

/**
 * Bridges Google Play Services Activity Recognition to Flutter via
 * MethodChannel + EventChannel. Updates arrive through [MotionActivityReceiver].
 *
 * Start/stop is process-wide ref-counted so UI + FGS engines can both attach
 * without one engine tearing down recognition for the other.
 */
class MotionActivityManager(
  private val context: Context,
) : EventChannel.StreamHandler {
  companion object {
    const val METHOD_CHANNEL = "com.smartnps360.app/motion_activity"
    const val EVENT_CHANNEL = "com.smartnps360.app/motion_activity_events"
    const val ACTION_ACTIVITY_UPDATE = "com.smartnps360.app.ACTION_ACTIVITY_UPDATE"
    /**
     * Detection cadence for ActivityRecognitionClient.
     * 0 = as fast as Play Services will deliver (snappier UI).
     * OS still batches; expect ~1–3s in practice, not true 1Hz.
     */
    private const val DETECTION_INTERVAL_MS = 0L
    private const val REQUEST_CODE = 3601

    private val eventSinks = CopyOnWriteArrayList<EventChannel.EventSink>()
    private val startRefCount = AtomicInteger(0)

    @Volatile
    private var lastPayload: Map<String, Any?>? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    fun emit(payload: Map<String, Any?>) {
      lastPayload = payload
      mainHandler.post {
        for (sink in eventSinks) {
          try {
            sink.success(payload)
          } catch (_: Exception) {
          }
        }
      }
    }

    fun lastKnown(): Map<String, Any?>? = lastPayload
  }

  private val client: ActivityRecognitionClient =
    ActivityRecognition.getClient(context.applicationContext)

  private var methodChannel: MethodChannel? = null
  private var eventChannel: EventChannel? = null
  private var instanceSink: EventChannel.EventSink? = null
  private var thisEngineStarted = false

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
          result.success(mapOf("ok" to true, "running" to (startRefCount.get() > 0)))
        }
        "isRunning" ->
          result.success(mapOf("ok" to true, "running" to (startRefCount.get() > 0)))
        "queryLatest" -> {
          val known = lastPayload
          if (known != null) {
            result.success(mapOf("ok" to true, "update" to known))
          } else {
            result.success(mapOf("ok" to true, "update" to null))
          }
        }
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
    instanceSink?.let { eventSinks.remove(it) }
    instanceSink = null
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    instanceSink?.let { eventSinks.remove(it) }
    instanceSink = events
    if (events != null && !eventSinks.contains(events)) {
      eventSinks.add(events)
    }
    // Replay last known so UI paints immediately on (re)subscribe.
    lastPayload?.let { payload ->
      mainHandler.post { events?.success(payload) }
    }
  }

  override fun onCancel(arguments: Any?) {
    // Clear this engine's sink only — do NOT stop recognition. Duty GPS /
    // fusion may still need updates; Flutter calls stop() explicitly.
    instanceSink?.let { eventSinks.remove(it) }
    instanceSink = null
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

    if (thisEngineStarted) {
      result.success(
        mapOf(
          "ok" to true,
          "running" to true,
          "permission" to permissionStatus(),
        ),
      )
      return
    }

    // Another engine already holds the process-wide recognition session.
    if (startRefCount.get() > 0) {
      thisEngineStarted = true
      startRefCount.incrementAndGet()
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
          thisEngineStarted = true
          startRefCount.incrementAndGet()
          result.success(
            mapOf(
              "ok" to true,
              "running" to true,
              "permission" to permissionStatus(),
            ),
          )
        }
        .addOnFailureListener { error ->
          thisEngineStarted = false
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
      thisEngineStarted = false
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
      thisEngineStarted = false
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
    if (!thisEngineStarted) return
    thisEngineStarted = false
    val remaining = startRefCount.decrementAndGet()
    if (remaining > 0) return
    startRefCount.set(0)
    try {
      client.removeActivityUpdates(activityPendingIntent())
    } catch (_: Exception) {
    }
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
