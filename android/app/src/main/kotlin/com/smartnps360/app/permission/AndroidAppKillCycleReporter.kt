package com.smartnps360.app.permission

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import com.smartnps360.app.duty.AndroidDutyKillStore
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * Android mirror of iOS kill-cycle reporting:
 * queue first → best-effort upload → reopen with opened_at.
 */
internal object AndroidAppKillCycleReporter {
  private const val TAG = "AndroidKillCycle"
  private const val NOTIF_CHANNEL = "smartnps360_kill_cycle"
  private const val NOTIF_ID = 3609
  private const val ALERT_REQUEST_CODE = 3610
  private const val KILL_SECURITY_ALERT_DELAY_MS = 4_000L
  const val ACTION_KILL_SECURITY_ALERT = "com.smartnps360.app.KILL_SECURITY_ALERT"
  private val uploadExecutor = Executors.newSingleThreadExecutor()
  private val killOpenFlushInFlight = AtomicBoolean(false)
  private val killedFlushInFlight = AtomicBoolean(false)
  private val lastTerminateElapsedMs = AtomicLong(0L)

  /** First Activity create in this process — used to recover kill after process death. */
  @Volatile
  private var processSessionStarted = false

  fun ensureTrackingService(context: Context) {
    if (!shouldTrack(context)) {
      stopTrackingService(context)
      return
    }
    try {
      context.startService(Intent(context, AndroidAppKillCycleService::class.java))
    } catch (e: Exception) {
      Log.w(TAG, "start kill-cycle service failed: ${e.message}")
    }
  }

  fun stopTrackingService(context: Context) {
    try {
      context.stopService(Intent(context, AndroidAppKillCycleService::class.java))
    } catch (e: Exception) {
      Log.w(TAG, "stop kill-cycle service failed: ${e.message}")
    }
  }

  fun shouldTrack(context: Context): Boolean {
    if (AndroidDutyKillStore.isForceOff(context)) return false
    if (!AndroidDutyKillStore.isArmed(context) &&
      !AndroidPermissionStatusStore.isArmed(context)
    ) {
      return false
    }
    return true
  }

  fun canReportKill(context: Context): Boolean {
    // Native arm flag, with Flutter SharedPreferences fallback if native prefs lagged.
    val armed = AndroidDutyKillStore.isArmed(context) ||
      context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        .getBoolean(AndroidDutyKillStore.FLUTTER_ARMED, false)
    if (!armed) return false
    if (AndroidDutyKillStore.isForceOff(context)) return false
    if (AndroidDutyKillStore.isUnpaidBreak(context)) return false
    return true
  }

  /**
   * Cold start: if we backgrounded while on duty and the process died before
   * onTaskRemoved queued a kill, promote background_at → killed_at.
   */
  fun onActivityCreated(context: Context) {
    if (processSessionStarted) return
    processSessionStarted = true

    val appContext = context.applicationContext
    ensureTrackingService(appContext)

    if (AndroidAppKillCycleStore.killedAt(appContext) == null) {
      val backgroundAt = AndroidAppKillCycleStore.backgroundAt(appContext)
      if (!backgroundAt.isNullOrEmpty() && canReportKill(appContext)) {
        AndroidAppKillCycleStore.queueKilledAt(appContext, backgroundAt)
        debugLog(appContext, "recovered killed_at from background_at=$backgroundAt (process died)")
        uploadKilledEventIfNeeded(appContext, "process_recover")
      } else if (!backgroundAt.isNullOrEmpty()) {
        debugLog(appContext, "recover skip background_at; canReportKill=false")
      }
    } else {
      uploadKilledEventIfNeeded(appContext, "process_start")
    }
    AndroidAppKillCycleStore.clearBackgroundAt(appContext)
  }

  /** Same-process background — candidate only; cleared on resume unless process dies. */
  fun onActivityStopped(context: Context) {
    if (!canReportKill(context)) {
      AndroidAppKillCycleStore.clearBackgroundAt(context.applicationContext)
      cancelKillSecurityAlert(context, reason = "not_armed")
      debugLog(
        context,
        "skip background_at; armed=${AndroidDutyKillStore.isArmed(context)} " +
          "unpaid=${AndroidDutyKillStore.isUnpaidBreak(context)}",
      )
      return
    }
    val at = utcNow()
    AndroidAppKillCycleStore.setBackgroundAt(context.applicationContext, at)
    debugLog(context, "noted background_at=$at (kill candidate)")
    // Do NOT schedule kill notification on background — only on real terminate.
  }

  /** Swipe-up / task removed while on duty and not unpaid break. */
  fun handleTerminateWhileOnDuty(context: Context) {
    if (!canReportKill(context)) {
      debugLog(
        context,
        "skip terminate report; armed=${AndroidDutyKillStore.isArmed(context)} " +
          "unpaid=${AndroidDutyKillStore.isUnpaidBreak(context)} " +
          "forceOff=${AndroidDutyKillStore.isForceOff(context)}",
      )
      return
    }

    // onTaskRemoved + onDestroy can both fire; only handle once per swipe.
    val nowElapsed = SystemClock.elapsedRealtime()
    val previous = lastTerminateElapsedMs.get()
    if (nowElapsed - previous < 2_500L) {
      debugLog(context, "skip duplicate terminate within 2.5s")
      return
    }
    lastTerminateElapsedMs.set(nowElapsed)

    val appContext = context.applicationContext
    // Always refresh kill stamp for this swipe (don't skip if a stale queue exists).
    val killedAt = AndroidAppKillCycleStore.backgroundAt(appContext) ?: utcNow()
    AndroidAppKillCycleStore.queueKilledAt(appContext, killedAt)
    debugLog(appContext, "queued killed_at=$killedAt")

    // Notify on real task-remove / destroy only (not deferred from background).
    showLocalSecurityAlert(appContext)
    val latch = CountDownLatch(1)
    val uploadOk = AtomicBoolean(false)
    uploadExecutor.execute {
      try {
        uploadOk.set(
          AndroidPermissionStatusUploader.uploadAppCycleEvent(
            context = appContext,
            appCycle = "killed",
            killedAt = killedAt,
            openedAt = null,
            connectTimeoutMs = 5_000,
            readTimeoutMs = 5_000,
            lightweight = true,
          ),
        )
      } finally {
        latch.countDown()
      }
    }
    val finished = latch.await(5, TimeUnit.SECONDS)
    if (uploadOk.get()) {
      AndroidAppKillCycleStore.markKilledUploaded(appContext)
    }
    debugLog(
      appContext,
      "terminate upload finished=$finished ok=${uploadOk.get()}; " +
        "queue kept for killed_at+opened_at",
    )
  }

  /**
   * Near-realtime killed POST when terminate was missed (FGS / alarm wake after kill).
   * Does not stamp opened_at and does not clear the kill queue.
   */
  fun uploadKilledEventIfNeeded(context: Context, reason: String) {
    val appContext = context.applicationContext
    val killedAt = AndroidAppKillCycleStore.killedAt(appContext) ?: return
    if (AndroidAppKillCycleStore.isKilledUploaded(appContext)) {
      debugLog(appContext, "killed upload skip ($reason); already uploaded")
      return
    }
    if (!killedFlushInFlight.compareAndSet(false, true)) {
      debugLog(appContext, "killed upload skip ($reason); already in flight")
      return
    }
    debugLog(appContext, "killed upload attempt ($reason) killed_at=$killedAt")
    uploadExecutor.execute {
      try {
        val ok = AndroidPermissionStatusUploader.uploadAppCycleEvent(
          context = appContext,
          appCycle = "killed",
          killedAt = killedAt,
          openedAt = null,
          connectTimeoutMs = 8_000,
          readTimeoutMs = 8_000,
          lightweight = true,
        )
        if (ok) {
          AndroidAppKillCycleStore.markKilledUploaded(appContext)
          debugLog(appContext, "killed upload ok ($reason); waiting for opened_at")
        } else {
          debugLog(appContext, "killed upload failed ($reason); will retry")
        }
      } finally {
        killedFlushInFlight.set(false)
      }
    }
  }

  /** Only when UI becomes resumed after a queued kill — not normal background resume. */
  fun markOpenedAfterKillIfNeeded(context: Context) {
    val appContext = context.applicationContext
    // Same-process resume: drop background candidate so it is not treated as kill.
    AndroidAppKillCycleStore.clearBackgroundAt(appContext)
    cancelKillSecurityAlert(appContext, reason = "user_foreground")

    if (AndroidAppKillCycleStore.killedAt(appContext) == null) return
    if (AndroidAppKillCycleStore.openedAt(appContext) != null) return

    if (AndroidAppKillCycleStore.wakeService(appContext).isNullOrEmpty()) {
      recordWakeService(
        appContext,
        "user_open",
        detail = "UI resumed after kill (no prior native wake)",
      )
    }

    val openedAt = utcNow()
    AndroidAppKillCycleStore.setOpenedAt(appContext, openedAt)
    val wake = AndroidAppKillCycleStore.wakeService(appContext) ?: "unknown"
    debugLog(appContext, "queued opened_at=$openedAt (from killed state) wake_service=$wake")
  }

  /**
   * Stamp opened_at if needed and return full timeline for Flutter reopen upload.
   * Does not upload — Flutter owns the reopen POST so a bare resumed/sync
   * cannot race-clear the queue without opened_at.
   */
  fun prepareTimelineForReopen(context: Context): Map<String, String>? {
    onActivityCreated(context)
    markOpenedAfterKillIfNeeded(context)
    val timeline = peekTimeline(context)
    debugLog(context, "prepareTimelineForReopen=$timeline")
    return timeline
  }

  /**
   * Backup only: if Flutter did not clear the kill-reopen queue, upload after a
   * short delay. Immediate flush on resume was racing Flutter and clearing the
   * queue (or posting resumed without opened_at surviving on the dashboard).
   */
  fun scheduleReopenFlushBackup(context: Context) {
    val appContext = context.applicationContext
    if (AndroidAppKillCycleStore.killedAt(appContext) == null) return
    markOpenedAfterKillIfNeeded(appContext)
    uploadExecutor.execute {
      try {
        Thread.sleep(4_000L)
      } catch (_: InterruptedException) {
        return@execute
      }
      if (AndroidAppKillCycleStore.killedAt(appContext) == null) {
        debugLog(appContext, "reopen backup skip; Flutter already cleared queue")
        return@execute
      }
      if (AndroidAppKillCycleStore.openedAt(appContext) == null) {
        markOpenedAfterKillIfNeeded(appContext)
      }
      flushPendingIfNeeded(appContext, "reopen_backup")
    }
  }

  fun flushPendingIfNeeded(context: Context, reason: String) {
    val appContext = context.applicationContext
    val killedAt = AndroidAppKillCycleStore.killedAt(appContext)
    val openedAt = AndroidAppKillCycleStore.openedAt(appContext)
    if (killedAt == null) return
    if (openedAt == null) {
      debugLog(appContext, "flush skip ($reason); waiting for foreground open after kill")
      return
    }
    if (!killOpenFlushInFlight.compareAndSet(false, true)) return

    debugLog(appContext, "flush attempt ($reason) killed_at=$killedAt opened_at=$openedAt")
    uploadExecutor.execute {
      try {
        val ok = AndroidPermissionStatusUploader.uploadAppCycleEvent(
          context = appContext,
          appCycle = "resumed",
          killedAt = killedAt,
          openedAt = openedAt,
          connectTimeoutMs = 12_000,
          readTimeoutMs = 12_000,
        )
        if (ok) {
          AndroidAppKillCycleStore.clear(appContext)
          debugLog(appContext, "timeline uploaded; queue cleared")
        } else {
          debugLog(appContext, "upload failed/offline; queue kept for retry")
        }
      } finally {
        killOpenFlushInFlight.set(false)
      }
    }
  }

  fun peekTimeline(context: Context): Map<String, String>? {
    return AndroidAppKillCycleStore.peekTimeline(context.applicationContext)
  }

  fun clearPendingAfterFlutterUpload(context: Context) {
    AndroidAppKillCycleStore.clear(context.applicationContext)
    debugLog(context, "pending cleared by Flutter upload")
  }

  fun debugSnapshot(context: Context): Map<String, Any?> {
    val appContext = context.applicationContext
    val timeline = peekTimeline(appContext)
    return mapOf(
      "platform" to "android",
      "onDuty" to AndroidDutyKillStore.isArmed(appContext),
      "unpaidBreak" to AndroidDutyKillStore.isUnpaidBreak(appContext),
      "slcArmed" to AndroidDutyKillStore.isArmed(appContext),
      "hasAccessToken" to (
        !AndroidPermissionStatusStore.accessToken(appContext).isNullOrEmpty() ||
          !AndroidDutyKillStore.accessToken(appContext).isNullOrEmpty()
        ),
      "notificationAuth" to "n/a",
      "killed_at" to (timeline?.get("killed_at") ?: ""),
      "opened_at" to (timeline?.get("opened_at") ?: ""),
      "background_at" to (AndroidAppKillCycleStore.backgroundAt(appContext) ?: ""),
      "wake_service" to (AndroidAppKillCycleStore.wakeService(appContext) ?: ""),
      "wake_at" to (AndroidAppKillCycleStore.wakeAt(appContext) ?: ""),
      "wake_detail" to (AndroidAppKillCycleStore.wakeDetail(appContext) ?: ""),
      "killed_uploaded" to AndroidAppKillCycleStore.isKilledUploaded(appContext),
      "logs" to AndroidAppKillCycleStore.debugLogs(appContext),
    )
  }

  fun clearDebugLogs(context: Context) {
    AndroidAppKillCycleStore.clearDebugLogs(context.applicationContext)
  }

  fun appendFlutterDebugLog(context: Context, message: String) {
    debugLog(context, "flutter: $message")
  }

  fun recordWakeService(context: Context, service: String, detail: String? = null) {
    val appContext = context.applicationContext
    val at = utcNow()
    AndroidAppKillCycleStore.setWakeService(appContext, service, at, detail)
    val suffix = if (detail.isNullOrBlank()) "" else " detail=$detail"
    debugLog(appContext, "app awoken by service=$service$suffix")
  }

  private fun debugLog(context: Context, message: String) {
    Log.i(TAG, message)
    AndroidAppKillCycleStore.appendDebugLog(
      context.applicationContext,
      "${utcNow()} $message",
    )
  }

  fun deliverScheduledKillSecurityAlert(context: Context) {
    debugLog(context, "kill alert alarm fired")
    showLocalSecurityAlert(context.applicationContext)
  }

  private fun scheduleKillSecurityAlert(context: Context) {
    val appContext = context.applicationContext
    try {
      val alarmManager = appContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager
      val pending = killSecurityPendingIntent(appContext)
      val triggerAt = SystemClock.elapsedRealtime() + KILL_SECURITY_ALERT_DELAY_MS
      val canExact = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        alarmManager.canScheduleExactAlarms()
      } else {
        true
      }
      if (canExact && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        alarmManager.setExactAndAllowWhileIdle(
          AlarmManager.ELAPSED_REALTIME_WAKEUP,
          triggerAt,
          pending,
        )
      } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        alarmManager.setAndAllowWhileIdle(
          AlarmManager.ELAPSED_REALTIME_WAKEUP,
          triggerAt,
          pending,
        )
      } else {
        @Suppress("DEPRECATION")
        alarmManager.set(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pending)
      }
      debugLog(appContext, "kill alert scheduled in ${KILL_SECURITY_ALERT_DELAY_MS / 1000}s exact=$canExact")
    } catch (e: Exception) {
      debugLog(appContext, "kill alert schedule failed: ${e.message}")
    }
  }

  private fun cancelKillSecurityAlert(context: Context, reason: String) {
    val appContext = context.applicationContext
    try {
      val alarmManager = appContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager
      alarmManager.cancel(killSecurityPendingIntent(appContext))
      val manager = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      manager.cancel(NOTIF_ID)
      debugLog(appContext, "kill alert cancelled ($reason)")
    } catch (e: Exception) {
      debugLog(appContext, "kill alert cancel failed: ${e.message}")
    }
  }

  private fun killSecurityPendingIntent(context: Context): PendingIntent {
    val intent = Intent(context, AndroidKillSecurityAlertReceiver::class.java)
      .setAction(ACTION_KILL_SECURITY_ALERT)
    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
    return PendingIntent.getBroadcast(context, ALERT_REQUEST_CODE, intent, flags)
  }

  private fun showLocalSecurityAlert(context: Context) {
    try {
      val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val channel = NotificationChannel(
          NOTIF_CHANNEL,
          "Security alerts",
          NotificationManager.IMPORTANCE_HIGH,
        )
        channel.description = "Alerts when the app is force-closed while on duty"
        channel.enableVibration(true)
        manager.createNotificationChannel(channel)
      }
      // Prefer app icon; adaptive mipmap can fail as smallIcon on some OEMs.
      val smallIcon = context.applicationInfo.icon.takeIf { it != 0 }
        ?: android.R.drawable.ic_dialog_alert
      val notification = NotificationCompat.Builder(context, NOTIF_CHANNEL)
        .setSmallIcon(smallIcon)
        .setContentTitle("SMARTNPS360 APP CLOSED ⚠️")
        .setContentText("NPS360 was force-closed. Reopen the app immediately, keep it running in the background while on duty.")
        .setPriority(NotificationCompat.PRIORITY_HIGH)
        .setCategory(NotificationCompat.CATEGORY_ALARM)
        .setAutoCancel(true)
        .build()
      manager.notify(NOTIF_ID, notification)
      debugLog(context, "scheduled local security notification")
    } catch (e: Exception) {
      debugLog(context, "local notification failed: ${e.message}")
    }
  }

  private fun utcNow(): String {
    val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)
    fmt.timeZone = TimeZone.getTimeZone("UTC")
    // Native clock is millisecond-resolution; pad the microsecond part with 000
    // to match the 6-digit ISO-8601 used by updated_at (e.g. ...:00.123000Z).
    return "${fmt.format(Date())}000Z"
  }
}
