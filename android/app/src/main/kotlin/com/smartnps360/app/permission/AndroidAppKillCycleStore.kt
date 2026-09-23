package com.smartnps360.app.permission

import android.content.Context

/** Local queue for kill → native-wake → user-open timeline (mirrors iOS). */
internal object AndroidAppKillCycleStore {
  private const val PREFS = "smartnps360_android_app_kill_cycle"
  private const val KEY_KILLED_AT = "killed_at"
  private const val KEY_OPENED_AT = "opened_at"
  private const val KEY_SLC_AWAKENED_AT = "slc_awakened_at"
  private const val KEY_SLC_UPLOADED = "slc_awakened_uploaded"

  fun queueKilledAt(context: Context, killedAt: String) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .putString(KEY_KILLED_AT, killedAt)
      .remove(KEY_OPENED_AT)
      .remove(KEY_SLC_AWAKENED_AT)
      .putBoolean(KEY_SLC_UPLOADED, false)
      .commit()
  }

  fun killedAt(context: Context): String? {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(KEY_KILLED_AT, null)
      ?.takeIf { it.isNotEmpty() }
  }

  fun openedAt(context: Context): String? {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(KEY_OPENED_AT, null)
      ?.takeIf { it.isNotEmpty() }
  }

  fun setOpenedAt(context: Context, openedAt: String) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .putString(KEY_OPENED_AT, openedAt)
      .commit()
  }

  fun slcAwakenedAt(context: Context): String? {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(KEY_SLC_AWAKENED_AT, null)
      ?.takeIf { it.isNotEmpty() }
  }

  fun setSlcAwakenedAt(context: Context, awakenedAt: String) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .putString(KEY_SLC_AWAKENED_AT, awakenedAt)
      .commit()
  }

  fun isSlcAwakenedUploaded(context: Context): Boolean {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getBoolean(KEY_SLC_UPLOADED, false)
  }

  fun markSlcAwakenedUploaded(context: Context) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .putBoolean(KEY_SLC_UPLOADED, true)
      .apply()
  }

  fun clear(context: Context) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .clear()
      .commit()
  }

  fun peekTimeline(context: Context): Map<String, String>? {
    val killedAt = killedAt(context) ?: return null
    val map = linkedMapOf("killed_at" to killedAt)
    openedAt(context)?.let { map["opened_at"] = it }
    slcAwakenedAt(context)?.let { map["slc_awakened_at"] = it }
    return map
  }
}
