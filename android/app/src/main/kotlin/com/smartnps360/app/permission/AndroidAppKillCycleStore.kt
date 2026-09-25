package com.smartnps360.app.permission

import android.content.Context

/** Local queue for kill → user-open timeline (mirrors iOS). */
internal object AndroidAppKillCycleStore {
  private const val PREFS = "smartnps360_android_app_kill_cycle"
  private const val DEBUG_PREFS = "smartnps360_android_app_kill_cycle_debug"
  private const val KEY_KILLED_AT = "killed_at"
  private const val KEY_OPENED_AT = "opened_at"
  private const val KEY_BACKGROUND_AT = "background_at"
  private const val KEY_DEBUG_LOGS = "debug_logs"
  private const val KEY_KILL_CAPTURE = "kill_debug_capture_enabled"
  private const val KEY_WAKE_SERVICE = "wake_service"
  private const val KEY_WAKE_AT = "wake_at"
  private const val KEY_WAKE_DETAIL = "wake_detail"
  private const val KEY_KILLED_UPLOADED = "killed_uploaded"
  private const val MAX_DEBUG_LOGS = 100

  fun queueKilledAt(context: Context, killedAt: String) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .putString(KEY_KILLED_AT, killedAt)
      .remove(KEY_OPENED_AT)
      .remove(KEY_BACKGROUND_AT)
      .putBoolean(KEY_KILLED_UPLOADED, false)
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

  /** Candidate time written on onStop; promoted to killed_at after process death. */
  fun setBackgroundAt(context: Context, backgroundAt: String) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .putString(KEY_BACKGROUND_AT, backgroundAt)
      .commit()
  }

  fun backgroundAt(context: Context): String? {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(KEY_BACKGROUND_AT, null)
      ?.takeIf { it.isNotEmpty() }
  }

  fun clearBackgroundAt(context: Context) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .remove(KEY_BACKGROUND_AT)
      .commit()
  }

  fun clear(context: Context) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .clear()
      .commit()
  }

  fun isKilledUploaded(context: Context): Boolean {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getBoolean(KEY_KILLED_UPLOADED, false)
  }

  fun markKilledUploaded(context: Context) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .putBoolean(KEY_KILLED_UPLOADED, true)
      .commit()
  }

  fun peekTimeline(context: Context): Map<String, String>? {
    val killedAt = killedAt(context) ?: return null
    val map = linkedMapOf("killed_at" to killedAt)
    openedAt(context)?.let { map["opened_at"] = it }
    return map
  }

  fun appendDebugLog(context: Context, message: String) {
    if (!isKillDebugCaptureEnabled(context)) return
    val prefs = context.applicationContext.getSharedPreferences(DEBUG_PREFS, Context.MODE_PRIVATE)
    val existing = prefs.getString(KEY_DEBUG_LOGS, "") ?: ""
    val lines = if (existing.isEmpty()) {
      mutableListOf()
    } else {
      existing.split('\n').toMutableList()
    }
    lines.add(message)
    val trimmed = if (lines.size > MAX_DEBUG_LOGS) {
      lines.takeLast(MAX_DEBUG_LOGS)
    } else {
      lines
    }
    prefs.edit().putString(KEY_DEBUG_LOGS, trimmed.joinToString("\n")).commit()
  }

  fun setKillDebugCaptureEnabled(context: Context, enabled: Boolean) {
    context.applicationContext
      .getSharedPreferences(DEBUG_PREFS, Context.MODE_PRIVATE)
      .edit()
      .putBoolean(KEY_KILL_CAPTURE, enabled)
      .commit()
  }

  fun isKillDebugCaptureEnabled(context: Context): Boolean {
    return context.applicationContext
      .getSharedPreferences(DEBUG_PREFS, Context.MODE_PRIVATE)
      .getBoolean(KEY_KILL_CAPTURE, false)
  }

  fun debugLogs(context: Context): List<String> {
    val raw = context.applicationContext
      .getSharedPreferences(DEBUG_PREFS, Context.MODE_PRIVATE)
      .getString(KEY_DEBUG_LOGS, "")
      ?: ""
    if (raw.isEmpty()) return emptyList()
    return raw.split('\n').filter { it.isNotEmpty() }
  }

  fun clearDebugLogs(context: Context) {
    // Keep wake_* fields when clearing log lines only.
    val prefs = context.applicationContext.getSharedPreferences(DEBUG_PREFS, Context.MODE_PRIVATE)
    prefs.edit().remove(KEY_DEBUG_LOGS).commit()
  }

  fun setWakeService(context: Context, service: String, atIso: String, detail: String?) {
    val edit = context.applicationContext
      .getSharedPreferences(DEBUG_PREFS, Context.MODE_PRIVATE)
      .edit()
      .putString(KEY_WAKE_SERVICE, service)
      .putString(KEY_WAKE_AT, atIso)
    if (detail.isNullOrBlank()) {
      edit.remove(KEY_WAKE_DETAIL)
    } else {
      edit.putString(KEY_WAKE_DETAIL, detail)
    }
    edit.commit()
  }

  fun wakeService(context: Context): String? {
    return context.applicationContext
      .getSharedPreferences(DEBUG_PREFS, Context.MODE_PRIVATE)
      .getString(KEY_WAKE_SERVICE, null)
      ?.takeIf { it.isNotEmpty() }
  }

  fun wakeAt(context: Context): String? {
    return context.applicationContext
      .getSharedPreferences(DEBUG_PREFS, Context.MODE_PRIVATE)
      .getString(KEY_WAKE_AT, null)
      ?.takeIf { it.isNotEmpty() }
  }

  fun wakeDetail(context: Context): String? {
    return context.applicationContext
      .getSharedPreferences(DEBUG_PREFS, Context.MODE_PRIVATE)
      .getString(KEY_WAKE_DETAIL, null)
      ?.takeIf { it.isNotEmpty() }
  }
}
