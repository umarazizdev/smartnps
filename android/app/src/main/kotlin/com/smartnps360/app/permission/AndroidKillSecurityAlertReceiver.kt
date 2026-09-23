package com.smartnps360.app.permission

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Fires the deferred kill security notification after background delay. */
class AndroidKillSecurityAlertReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent?) {
    if (intent?.action != AndroidAppKillCycleReporter.ACTION_KILL_SECURITY_ALERT) return
    AndroidAppKillCycleReporter.deliverScheduledKillSecurityAlert(context)
  }
}
