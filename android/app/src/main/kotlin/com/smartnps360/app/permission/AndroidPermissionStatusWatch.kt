package com.smartnps360.app.permission

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import com.smartnps360.app.duty.AndroidDutyUiState

/**
 * Periodic permission-status sync while the Flutter UI is gone / process killed.
 * Never starts location FGS or any other duty service.
 */
internal object AndroidPermissionStatusWatch {
  private const val TAG = "AndroidPermStatus"
  private const val REQUEST_CODE = 3602
  private const val INTERVAL_WHILE_AWAY_MS = 10 * 60_000L
  private const val INTERVAL_WHILE_UI_MS = 30 * 60_000L
  private const val FIRST_CHECK_AFTER_KILL_MS = 60_000L

  const val ACTION = "com.smartnps360.app.ANDROID_PERMISSION_STATUS_TICK"

  fun arm(
    context: Context,
    accessToken: String,
    refreshToken: String?,
    apiBaseUrl: String,
    deviceId: String,
    deviceName: String?,
    appVersion: String,
    build: String,
    pushStatus: String,
    fingerprint: String?,
  ) {
    AndroidPermissionStatusStore.arm(
      context = context,
      accessToken = accessToken,
      refreshToken = refreshToken,
      apiBaseUrl = apiBaseUrl,
      deviceId = deviceId,
      deviceName = deviceName,
      appVersion = appVersion,
      build = build,
      pushStatus = pushStatus,
      fingerprint = fingerprint,
    )
    schedule(context, FIRST_CHECK_AFTER_KILL_MS)
    Log.i(TAG, "armed permission-status watch")
  }

  fun syncSession(
    context: Context,
    accessToken: String,
    refreshToken: String?,
    apiBaseUrl: String?,
    pushStatus: String?,
  ) {
    AndroidPermissionStatusStore.syncSession(
      context = context,
      accessToken = accessToken,
      refreshToken = refreshToken,
      apiBaseUrl = apiBaseUrl,
      pushStatus = pushStatus,
      fingerprint = null,
    )
  }

  /**
   * After Flutter successfully POSTs permission-status, mark the current OS
   * snapshot as already uploaded so a killed-app tick won't re-POST the same
   * state (fingerprint formats differ between Dart and native).
   */
  fun noteCurrentSynced(context: Context) {
    if (!AndroidPermissionStatusStore.isArmed(context)) return
    try {
      val snapshot = AndroidPermissionStatusUploader.buildSnapshot(context)
      AndroidPermissionStatusStore.writeFingerprint(context, snapshot.fingerprint)
      Log.i(TAG, "noted current permissions as synced")
    } catch (e: Exception) {
      Log.w(TAG, "noteCurrentSynced failed: ${e.message}")
    }
  }

  fun disarm(context: Context) {
    AndroidPermissionStatusStore.disarm(context)
    cancel(context)
    Log.i(TAG, "disarmed permission-status watch")
  }

  fun schedule(context: Context, delayMs: Long) {
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    val pending = pendingIntent(context)
    val triggerAt = SystemClock.elapsedRealtime() + delayMs
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && alarmManager.canScheduleExactAlarms()) {
        alarmManager.setExactAndAllowWhileIdle(
          AlarmManager.ELAPSED_REALTIME_WAKEUP,
          triggerAt,
          pending,
        )
      } else {
        alarmManager.setAndAllowWhileIdle(
          AlarmManager.ELAPSED_REALTIME_WAKEUP,
          triggerAt,
          pending,
        )
      }
    } catch (e: Exception) {
      Log.w(TAG, "schedule exact failed; using inexact: ${e.message}")
      alarmManager.setAndAllowWhileIdle(
        AlarmManager.ELAPSED_REALTIME_WAKEUP,
        triggerAt,
        pending,
      )
    }
  }

  fun cancel(context: Context) {
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    alarmManager.cancel(pendingIntent(context))
  }

  fun tick(context: Context) {
    if (!AndroidPermissionStatusStore.isArmed(context)) {
      cancel(context)
      Log.i(TAG, "tick: not armed")
      return
    }
    if (AndroidPermissionStatusStore.accessToken(context).isNullOrEmpty()) {
      disarm(context)
      Log.i(TAG, "tick: no token; disarmed")
      return
    }

    // Flutter UI owns uploads while visible / briefly in Settings.
    if (AndroidDutyUiState.isUiResumed ||
      !AndroidDutyUiState.isAwayLongEnoughForNativeFgs()
    ) {
      schedule(context, INTERVAL_WHILE_UI_MS)
      Log.i(TAG, "tick skipped; Flutter UI owns permission uploads")
      return
    }

    try {
      AndroidPermissionStatusUploader.uploadIfChanged(context)
    } catch (e: Exception) {
      Log.w(TAG, "tick upload failed: ${e.message}")
    }
    schedule(context, INTERVAL_WHILE_AWAY_MS)
  }

  private fun pendingIntent(context: Context): PendingIntent {
    val intent = Intent(context, AndroidPermissionStatusReceiver::class.java).setAction(ACTION)
    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
  }
}
