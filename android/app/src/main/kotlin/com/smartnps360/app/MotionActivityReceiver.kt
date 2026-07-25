package com.smartnps360.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.ActivityRecognitionResult
import com.google.android.gms.location.DetectedActivity

/**
 * Receives Play Services activity updates and forwards the most probable
 * activity (with confidence) to the Flutter EventChannel.
 */
class MotionActivityReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context?, intent: Intent?) {
    if (intent == null) return
    if (intent.action != MotionActivityManager.ACTION_ACTIVITY_UPDATE &&
      !ActivityRecognitionResult.hasResult(intent)
    ) {
      return
    }
    if (!ActivityRecognitionResult.hasResult(intent)) return

    val result = ActivityRecognitionResult.extractResult(intent) ?: return
    val mostProbable = result.mostProbableActivity ?: return
    val payload =
      mapOf(
        "activity" to mapActivityType(mostProbable.type),
        "confidence" to mostProbable.confidence.coerceIn(0, 100),
        "timestampMs" to result.time,
        "source" to "android_activity_recognition",
        "raw" to mapOf(
          "type" to mostProbable.type,
          "typeName" to typeName(mostProbable.type),
          "confidence" to mostProbable.confidence,
          "probableActivities" to
            result.probableActivities.map { activity ->
              mapOf(
                "type" to activity.type,
                "typeName" to typeName(activity.type),
                "confidence" to activity.confidence,
                "activity" to mapActivityType(activity.type),
              )
            },
        ),
      )
    MotionActivityManager.emit(payload)
  }

  private fun mapActivityType(type: Int): String {
    return when (type) {
      DetectedActivity.STILL -> "stationary"
      DetectedActivity.WALKING -> "walking"
      DetectedActivity.RUNNING -> "running"
      DetectedActivity.IN_VEHICLE -> "driving"
      DetectedActivity.ON_BICYCLE -> "cycling"
      DetectedActivity.ON_FOOT -> "walking"
      DetectedActivity.TILTING -> "unknown"
      DetectedActivity.UNKNOWN -> "unknown"
      else -> "unknown"
    }
  }

  private fun typeName(type: Int): String {
    return when (type) {
      DetectedActivity.IN_VEHICLE -> "IN_VEHICLE"
      DetectedActivity.ON_BICYCLE -> "ON_BICYCLE"
      DetectedActivity.ON_FOOT -> "ON_FOOT"
      DetectedActivity.RUNNING -> "RUNNING"
      DetectedActivity.STILL -> "STILL"
      DetectedActivity.TILTING -> "TILTING"
      DetectedActivity.WALKING -> "WALKING"
      DetectedActivity.UNKNOWN -> "UNKNOWN"
      else -> "UNKNOWN_$type"
    }
  }
}
