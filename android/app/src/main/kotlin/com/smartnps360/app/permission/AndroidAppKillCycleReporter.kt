package com.smartnps360.app.permission

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.smartnps360.app.R
import com.smartnps360.app.duty.AndroidDutyKillStore
import com.smartnps360.app.duty.AndroidDutyUiState
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Android mirror of iOS kill-cycle reporting:
 * queue first → best-effort upload → reopen with opened_at → optional native wake.
 */
internal object AndroidAppKillCycleReporter {
  private const val TAG = "AndroidKillCycle"
  private const val NOTIF_CHANNEL = "smartnps360_kill_cycle"
  private const val NOTIF_ID = 3609
  private val uploadExecutor = Executors.newSingleThreadExecutor()
  private val killOpenFlushInFlight = AtomicBoolean(false)
  private val slcFlushInFlight = AtomicBoolean(false)

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
    if (!AndroidDutyKillStore.isArmed(context)) return false
    if (AndroidDutyKillStore.isForceOff(context)) return false
    if (AndroidDutyKillStore.isUnpaidBreak(context)) return false
    return true
  }

  /** Swipe-up / task removed while on duty and not unpaid break. */
  fun handleTerminateWhileOnDuty(context: Context) {
    if (!canReportKill(context)) {
      Log.i(
        TAG,
        "skip terminate report; armed=${AndroidDutyKillStore.isArmed(context)} " +
          "unpaid=${AndroidDutyKillStore.isUnpaidBreak(context)} " +
          "forceOff=${AndroidDutyKillStore.isForceOff(context)}",
      )
      return
    }

    val appContext = context.applicationContext
    val killedAt = utcNow()
    AndroidAppKillCycleStore.queueKilledAt(appContext, killedAt)
    Log.i(TAG, "queued killed_at=$killedAt")

    showLocalSecurityAlert(appContext)

    uploadExecutor.execute {
      val ok = AndroidPermissionStatusUploader.uploadAppCycleEvent(
        context = appContext,
        appCycle = "killed",
        killedAt = killedAt,
        openedAt = null,
        slcAwakenedAt = null,
        connectTimeoutMs = 5_000,
        readTimeoutMs = 5_000,
      )
      Log.i(
        TAG,
        "terminate upload ${if (ok) "ok" else "missed"}; queue kept for killed_at+opened_at",
      )
    }
  }

  /**
   * Native FGS / kill-watch relaunch after a queued kill — not a user open.
   * Uploads app_cycle=slc_awakened (same dashboard value as iOS SLC wake).
   */
  fun handleNativeAwakenedAfterKillIfNeeded(context: Context) {
    val appContext = context.applicationContext
    val killedAt = AndroidAppKillCycleStore.killedAt(appContext) ?: run {
      Log.i(TAG, "native wake ignored; not after killed state")
      return
    }
    if (AndroidAppKillCycleStore.isSlcAwakenedUploaded(appContext)) {
      Log.i(TAG, "slc_awakened already uploaded for this kill")
      return
    }

    val awakenedAt = AndroidAppKillCycleStore.slcAwakenedAt(appContext) ?: utcNow().also {
      AndroidAppKillCycleStore.setSlcAwakenedAt(appContext, it)
      Log.i(TAG, "queued slc_awakened_at=$it")
    }

    flushSlcAwakened(appContext, killedAt, awakenedAt, reason = "native_wake")
  }

  /** Only when UI becomes resumed after a queued kill — not normal background resume. */
  fun markOpenedAfterKillIfNeeded(context: Context) {
    val appContext = context.applicationContext
    if (AndroidAppKillCycleStore.killedAt(appContext) == null) return
    if (AndroidAppKillCycleStore.openedAt(appContext) != null) return
    if (!AndroidDutyUiState.isUiResumed) {
      Log.i(TAG, "skip opened_at; UI not resumed")
      return
    }

    val openedAt = utcNow()
    AndroidAppKillCycleStore.setOpenedAt(appContext, openedAt)
    Log.i(TAG, "queued opened_at=$openedAt (from killed state)")
  }

  fun flushPendingIfNeeded(context: Context, reason: String) {
    val appContext = context.applicationContext
    val killedAt = AndroidAppKillCycleStore.killedAt(appContext)
    val awakenedAt = AndroidAppKillCycleStore.slcAwakenedAt(appContext)
    if (killedAt != null &&
      awakenedAt != null &&
      !AndroidAppKillCycleStore.isSlcAwakenedUploaded(appContext)
    ) {
      flushSlcAwakened(appContext, killedAt, awakenedAt, reason)
    }

    val openedAt = AndroidAppKillCycleStore.openedAt(appContext)
    if (killedAt == null) return
    if (openedAt == null) {
      Log.i(TAG, "flush skip ($reason); waiting for foreground open after kill")
      return
    }
    if (!killOpenFlushInFlight.compareAndSet(false, true)) return

    Log.i(TAG, "flush attempt ($reason) killed_at=$killedAt opened_at=$openedAt")
    uploadExecutor.execute {
      try {
        val ok = AndroidPermissionStatusUploader.uploadAppCycleEvent(
          context = appContext,
          appCycle = "killed",
          killedAt = killedAt,
          openedAt = openedAt,
          slcAwakenedAt = AndroidAppKillCycleStore.slcAwakenedAt(appContext),
          connectTimeoutMs = 5_000,
          readTimeoutMs = 5_000,
        )
        if (ok) {
          AndroidAppKillCycleStore.clear(appContext)
          Log.i(TAG, "timeline uploaded; queue cleared")
        } else {
          Log.i(TAG, "upload failed/offline; queue kept for retry")
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
    Log.i(TAG, "pending cleared by Flutter upload")
  }

  private fun flushSlcAwakened(
    context: Context,
    killedAt: String,
    awakenedAt: String,
    reason: String,
  ) {
    if (!slcFlushInFlight.compareAndSet(false, true)) return
    Log.i(
      TAG,
      "SLC awakened upload ($reason) killed_at=$killedAt slc_awakened_at=$awakenedAt",
    )
    uploadExecutor.execute {
      try {
        val ok = AndroidPermissionStatusUploader.uploadAppCycleEvent(
          context = context,
          appCycle = "slc_awakened",
          killedAt = killedAt,
          openedAt = null,
          slcAwakenedAt = awakenedAt,
          connectTimeoutMs = 5_000,
          readTimeoutMs = 5_000,
        )
        if (ok) {
          AndroidAppKillCycleStore.markSlcAwakenedUploaded(context)
          Log.i(TAG, "slc_awakened uploaded")
        } else {
          Log.i(TAG, "slc_awakened upload failed; queued for retry")
        }
      } finally {
        slcFlushInFlight.set(false)
      }
    }
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
        manager.createNotificationChannel(channel)
      }
      val notification = NotificationCompat.Builder(context, NOTIF_CHANNEL)
        .setSmallIcon(R.mipmap.ic_launcher)
        .setContentTitle("Test Security Alert")
        .setContentText("The app was manually swiped up and killed!")
        .setPriority(NotificationCompat.PRIORITY_HIGH)
        .setAutoCancel(true)
        .build()
      manager.notify(NOTIF_ID, notification)
      Log.i(TAG, "scheduled local security notification")
    } catch (e: Exception) {
      Log.w(TAG, "local notification failed: ${e.message}")
    }
  }

  private fun utcNow(): String {
    val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
    fmt.timeZone = TimeZone.getTimeZone("UTC")
    return fmt.format(Date())
  }
}
