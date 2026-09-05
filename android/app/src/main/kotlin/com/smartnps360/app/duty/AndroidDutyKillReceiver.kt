package com.smartnps360.app.duty

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager

class AndroidDutyKillReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent?) {
    if (intent?.action != AndroidDutyKillWatch.ACTION) return
    val appContext = context.applicationContext
    val pending = goAsync()
    val powerManager = appContext.getSystemService(Context.POWER_SERVICE) as PowerManager
    val wakeLock = powerManager.newWakeLock(
      PowerManager.PARTIAL_WAKE_LOCK,
      "smartnps360:duty_kill_watch",
    )
    wakeLock.setReferenceCounted(false)
    wakeLock.acquire(45_000L)
    Thread {
      try {
        AndroidDutyKillWatch.tick(appContext)
      } finally {
        if (wakeLock.isHeld) {
          wakeLock.release()
        }
        pending.finish()
      }
    }.start()
  }
}
