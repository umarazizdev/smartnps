package com.smartnps360.app.permission

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log

/**
 * Lightweight sticky service so [onTaskRemoved] fires on swipe-kill.
 * Not a location FGS — only tracks task removal while duty/permission watch is armed.
 */
class AndroidAppKillCycleService : Service() {
  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    Log.i(TAG, "kill-cycle tracker started")
    return START_STICKY
  }

  override fun onTaskRemoved(rootIntent: Intent?) {
    Log.i(TAG, "onTaskRemoved — treating as swipe kill")
    AndroidAppKillCycleReporter.handleTerminateWhileOnDuty(applicationContext)
    super.onTaskRemoved(rootIntent)
  }

  override fun onDestroy() {
    Log.i(TAG, "kill-cycle tracker stopped")
    super.onDestroy()
  }

  companion object {
    private const val TAG = "AndroidKillCycleSvc"
  }
}
