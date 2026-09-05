package com.smartnps360.app.duty

import android.app.ActivityManager
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import id.flutter.flutter_background_service.BackgroundService
import id.flutter.flutter_background_service.Config
import id.flutter.flutter_background_service.WatchdogReceiver

/**
 * Kill-state keep-alive only.
 *
 * While the Flutter UI is resumed, Flutter owns starting/stopping the location FGS.
 * This watch only restarts/stops that same FGS after the UI is gone.
 */
internal object AndroidDutyKillWatch {
  private const val TAG = "AndroidDutyKill"
  private const val REQUEST_CODE = 3601
  private const val KEEP_ALIVE_WHILE_DOWN_MS = 20_000L
  private const val KEEP_ALIVE_WHILE_UP_MS = 60_000L

  const val ACTION = "com.smartnps360.app.ANDROID_DUTY_KILL_TICK"

  fun arm(context: Context, accessToken: String, refreshToken: String?) {
    val alreadyArmed = AndroidDutyKillStore.isArmed(context)
    Config(context).setManuallyStopped(false)
    if (alreadyArmed) {
      // Quiet token refresh — no log spam, no FGS start.
      AndroidDutyKillStore.syncSession(context, accessToken, refreshToken)
      return
    }
    AndroidDutyKillStore.arm(context, accessToken, refreshToken)
    // Never start FGS from arm — Flutter owns start while UI is open.
    // After a real kill, tick() starts FGS once the UI has been away ≥45s.
    schedule(context, 15_000L)
    Log.i(TAG, "armed native kill-watch uiResumed=${AndroidDutyUiState.isUiResumed}")
  }

  fun syncSession(context: Context, accessToken: String, refreshToken: String?) {
    AndroidDutyKillStore.syncSession(context, accessToken, refreshToken)
  }

  fun disarm(context: Context, forceOff: Boolean) {
    AndroidDutyKillStore.disarm(context, forceOff)
    cancel(context)
    if (forceOff) {
      stopLocationService(context)
    }
    Log.i(TAG, "disarmed native kill-watch forceOff=$forceOff")
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
    if (AndroidDutyKillStore.isForceOff(context) || !AndroidDutyKillStore.isArmed(context)) {
      if (AndroidDutyKillStore.isForceOff(context)) {
        stopLocationService(context)
        AndroidDutyKillStore.disarm(context, forceOff = true)
      }
      cancel(context)
      Log.i(TAG, "tick: not armed; location FGS left stopped")
      return
    }

    // UI alive or only briefly paused (Settings): Flutter owns FGS.
    if (AndroidDutyUiState.isUiResumed ||
      !AndroidDutyUiState.isAwayLongEnoughForNativeFgs()
    ) {
      schedule(context, KEEP_ALIVE_WHILE_UP_MS)
      if (AndroidDutyUiState.isUiResumed) {
        Log.i(TAG, "tick skipped; UI resumed (Flutter owns FGS)")
      } else {
        Log.i(TAG, "tick skipped; UI briefly away (likely Settings)")
      }
      return
    }

    if (AndroidDutyKillStore.isUnpaidBreak(context)) {
      stopLocationService(context)
      Log.i(TAG, "tick: unpaid break — keeping FGS stopped until break ends")
    } else {
      val running = isLocationServiceRunning(context)
      if (!running) {
        Log.i(TAG, "tick: FGS down after kill — restarting immediately")
        AndroidDutyKillStore.markApiOnDuty(context)
        ensureLocationServiceRunning(context, reason = "keep_alive")
      } else {
        WatchdogReceiver.enqueue(context, 5_000)
      }
    }

    val status = AndroidDutyKillHeartbeat.confirmDuty(context)
    Log.i(TAG, "tick heartbeat=$status fgsRunning=${isLocationServiceRunning(context)}")
    when (status) {
      AndroidDutyKillHeartbeat.DutyStatus.OFF_DUTY -> {
        AndroidDutyKillStore.disarm(context, forceOff = true)
        stopLocationService(context)
        cancel(context)
        return
      }
      AndroidDutyKillHeartbeat.DutyStatus.UNPAID_BREAK -> {
        AndroidDutyKillStore.setUnpaidBreak(context, true)
        stopLocationService(context)
      }
      AndroidDutyKillHeartbeat.DutyStatus.ON_DUTY -> {
        AndroidDutyKillStore.setUnpaidBreak(context, false)
        AndroidDutyKillStore.markApiOnDuty(context)
        ensureLocationServiceRunning(context, reason = "heartbeat_on_duty")
      }
      AndroidDutyKillHeartbeat.DutyStatus.UNKNOWN -> {
        if (!AndroidDutyKillStore.isUnpaidBreak(context) &&
          !isLocationServiceRunning(context)
        ) {
          AndroidDutyKillStore.markApiOnDuty(context)
          ensureLocationServiceRunning(context, reason = "heartbeat_unknown")
        }
      }
    }

    val stillRunning = isLocationServiceRunning(context)
    schedule(
      context,
      if (stillRunning) KEEP_ALIVE_WHILE_UP_MS else KEEP_ALIVE_WHILE_DOWN_MS,
    )
  }

  /** True only when the location BackgroundService process is actually running. */
  private fun isLocationServiceRunning(context: Context): Boolean {
    val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    @Suppress("DEPRECATION")
    return manager.getRunningServices(Integer.MAX_VALUE).any { service ->
      BackgroundService::class.java.name == service.service.className
    }
  }

  private fun ensureLocationServiceRunning(context: Context, reason: String) {
    if (isLocationServiceRunning(context)) {
      Log.i(TAG, "FGS already running ($reason)")
      return
    }
    startLocationService(context, reason)
  }

  private fun startLocationService(context: Context, reason: String) {
    try {
      Config(context).setManuallyStopped(false)
      ContextCompat.startForegroundService(
        context,
        Intent(context, BackgroundService::class.java),
      )
      WatchdogReceiver.enqueue(context, 1_000)
      Log.i(TAG, "started location FGS ($reason)")
    } catch (e: Exception) {
      Log.w(TAG, "start FGS failed ($reason): ${e.message}")
    }
  }

  private fun stopLocationService(context: Context) {
    try {
      Config(context).setManuallyStopped(true)
      WatchdogReceiver.remove(context)
      context.stopService(Intent(context, BackgroundService::class.java))
      Log.i(TAG, "stopped location FGS")
    } catch (e: Exception) {
      Log.w(TAG, "stop FGS failed: ${e.message}")
    }
  }

  fun stopLocationServiceForUnpaidBreak(context: Context) {
    stopLocationService(context)
  }

  private fun pendingIntent(context: Context): PendingIntent {
    val intent = Intent(context, AndroidDutyKillReceiver::class.java).setAction(ACTION)
    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
  }
}
