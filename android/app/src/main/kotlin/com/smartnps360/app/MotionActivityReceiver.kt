package com.smartnps360.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.ActivityRecognitionResult
import com.google.android.gms.location.DetectedActivity

/**
 * Receives Play Services activity updates and forwards the best activity
 * (preferring specific motion types over ON_FOOT / UNKNOWN) to Flutter.
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
    val chosen = pickBestActivity(result) ?: return
    val payload =
      mapOf(
        "activity" to mapActivityType(chosen.type),
        "confidence" to chosen.confidence.coerceIn(0, 100),
        "timestampMs" to result.time,
        "source" to "android_activity_recognition",
        "raw" to mapOf(
          "type" to chosen.type,
          "typeName" to typeName(chosen.type),
          "confidence" to chosen.confidence,
          "mostProbableType" to (result.mostProbableActivity?.type ?: -1),
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

  /**
   * Prefer actionable motion labels over coarse ON_FOOT / UNKNOWN / TILTING
   * when confidence is within a small margin of the most-probable result.
   */
  private fun pickBestActivity(result: ActivityRecognitionResult): DetectedActivity? {
    val activities = result.probableActivities
    if (activities.isEmpty()) return result.mostProbableActivity

    val preferred =
      activities
        .filter { it.type != DetectedActivity.TILTING }
        .filter { it.confidence >= 20 }
        .sortedWith(
          compareByDescending<DetectedActivity> { specificityScore(it.type) }
            .thenByDescending { it.confidence },
        )

    val top = preferred.firstOrNull() ?: result.mostProbableActivity ?: return null
    val most = result.mostProbableActivity

    // If most-probable is TILTING/UNKNOWN but we have a specific alternative, use it.
    if (most != null &&
      (most.type == DetectedActivity.TILTING || most.type == DetectedActivity.UNKNOWN) &&
      top.type != most.type
    ) {
      return top
    }

    // Prefer WALKING/RUNNING over ON_FOOT when close in confidence.
    if (most != null && most.type == DetectedActivity.ON_FOOT) {
      val specific =
        preferred.firstOrNull {
          it.type == DetectedActivity.WALKING || it.type == DetectedActivity.RUNNING
        }
      if (specific != null && specific.confidence >= most.confidence - 15) {
        return specific
      }
    }

    // Prefer IN_VEHICLE when it's nearly as confident as STILL (red-light noise).
    if (most != null && most.type == DetectedActivity.STILL) {
      val vehicle =
        preferred.firstOrNull { it.type == DetectedActivity.IN_VEHICLE }
      if (vehicle != null && vehicle.confidence >= most.confidence - 10 && vehicle.confidence >= 40) {
        return vehicle
      }
    }

    return most ?: top
  }

  private fun specificityScore(type: Int): Int {
    return when (type) {
      DetectedActivity.RUNNING -> 6
      DetectedActivity.WALKING -> 5
      DetectedActivity.IN_VEHICLE -> 5
      DetectedActivity.ON_BICYCLE -> 5
      DetectedActivity.ON_FOOT -> 3
      DetectedActivity.STILL -> 2
      DetectedActivity.UNKNOWN -> 1
      DetectedActivity.TILTING -> 0
      else -> 0
    }
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
