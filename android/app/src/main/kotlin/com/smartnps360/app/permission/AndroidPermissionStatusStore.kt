package com.smartnps360.app.permission

import android.content.Context

internal object AndroidPermissionStatusStore {
  private const val PREFS = "smartnps360_android_permission_status"
  private const val KEY_ARMED = "armed"
  private const val KEY_ACCESS = "access_token"
  private const val KEY_REFRESH = "refresh_token"
  private const val KEY_API_BASE = "api_base_url"
  private const val KEY_DEVICE_ID = "device_id"
  private const val KEY_DEVICE_NAME = "device_name"
  private const val KEY_APP_VERSION = "app_version"
  private const val KEY_BUILD = "build"
  private const val KEY_PUSH = "push_status"
  private const val KEY_FINGERPRINT = "last_fingerprint"
  private const val KEY_FULL_PERMISSIONS_JSON = "full_permissions_json"
  private const val KEY_CACHED_BATTERY_PERCENTAGE = "cached_battery_percentage"
  private const val KEY_CACHED_LOW_POWER_MODE = "cached_low_power_mode"

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
    val editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .putBoolean(KEY_ARMED, true)
      .putString(KEY_ACCESS, accessToken)
      .putString(KEY_REFRESH, refreshToken ?: "")
      .putString(KEY_API_BASE, apiBaseUrl)
      .putString(KEY_DEVICE_ID, deviceId)
      .putString(KEY_DEVICE_NAME, deviceName ?: "")
      .putString(KEY_APP_VERSION, appVersion)
      .putString(KEY_BUILD, build)
      .putString(KEY_PUSH, pushStatus)
    if (!fingerprint.isNullOrEmpty()) {
      editor.putString(KEY_FINGERPRINT, fingerprint)
    }
    editor.apply()
  }

  fun syncSession(
    context: Context,
    accessToken: String,
    refreshToken: String?,
    apiBaseUrl: String?,
    pushStatus: String?,
    fingerprint: String?,
  ) {
    val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    if (!prefs.getBoolean(KEY_ARMED, false)) return
    val editor = prefs.edit()
      .putString(KEY_ACCESS, accessToken)
      .putString(KEY_REFRESH, refreshToken ?: "")
    if (!apiBaseUrl.isNullOrEmpty()) {
      editor.putString(KEY_API_BASE, apiBaseUrl)
    }
    if (!pushStatus.isNullOrEmpty()) {
      editor.putString(KEY_PUSH, pushStatus)
    }
    if (!fingerprint.isNullOrEmpty()) {
      editor.putString(KEY_FINGERPRINT, fingerprint)
    }
    editor.apply()
  }

  fun disarm(context: Context) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .clear()
      .apply()
  }

  fun isArmed(context: Context): Boolean {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getBoolean(KEY_ARMED, false)
  }

  fun accessToken(context: Context): String? {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(KEY_ACCESS, null)
      ?.takeIf { it.isNotEmpty() }
  }

  fun refreshToken(context: Context): String? {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(KEY_REFRESH, null)
      ?.takeIf { it.isNotEmpty() }
  }

  fun writeAccessToken(context: Context, token: String) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .putString(KEY_ACCESS, token)
      .apply()
  }

  fun writeRefreshToken(context: Context, token: String) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .putString(KEY_REFRESH, token)
      .apply()
  }

  fun apiBaseUrl(context: Context): String {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(KEY_API_BASE, null)
      ?.takeIf { it.isNotEmpty() }
      ?: "https://smartnps360.com/api"
  }

  fun deviceId(context: Context): String {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(KEY_DEVICE_ID, null)
      ?.takeIf { it.isNotEmpty() }
      ?: "android-unknown"
  }

  fun deviceName(context: Context): String? {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(KEY_DEVICE_NAME, null)
      ?.takeIf { it.isNotEmpty() }
  }

  fun appVersion(context: Context): String {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(KEY_APP_VERSION, null)
      ?.takeIf { it.isNotEmpty() }
      ?: "1.0.0"
  }

  fun build(context: Context): String {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(KEY_BUILD, null)
      ?.takeIf { it.isNotEmpty() }
      ?: "1"
  }

  fun pushStatus(context: Context): String {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(KEY_PUSH, null)
      ?.takeIf { it.isNotEmpty() }
      ?: "enabled"
  }

  fun lastFingerprint(context: Context): String? {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(KEY_FINGERPRINT, null)
      ?.takeIf { it.isNotEmpty() }
  }

  fun writeFingerprint(context: Context, fingerprint: String) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .putString(KEY_FINGERPRINT, fingerprint)
      .apply()
  }

  fun writeFullPermissionsCache(context: Context, permissions: Map<String, String>) {
    if (permissions.isEmpty()) return
    val obj = org.json.JSONObject()
    for ((key, value) in permissions) {
      obj.put(key, value)
    }
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .putString(KEY_FULL_PERMISSIONS_JSON, obj.toString())
      .apply()
    android.util.Log.i("AndroidPermStatus", "cached full permission snapshot (${permissions.size} keys)")
  }

  fun readFullPermissionsCache(context: Context): Map<String, String>? {
    val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(KEY_FULL_PERMISSIONS_JSON, null)
      ?.takeIf { it.isNotEmpty() }
      ?: return null
    return try {
      val obj = org.json.JSONObject(raw)
      val out = linkedMapOf<String, String>()
      val keys = obj.keys()
      while (keys.hasNext()) {
        val key = keys.next()
        val value = obj.optString(key, "").trim()
        if (value.isNotEmpty()) out[key] = value
      }
      out.takeIf { it.isNotEmpty() }
    } catch (_: Exception) {
      null
    }
  }

  fun writeBatteryCache(
    context: Context,
    batteryPercentage: Int?,
    lowPowerMode: String?,
  ) {
    val editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
    if (batteryPercentage != null && batteryPercentage in 0..100) {
      editor.putInt(KEY_CACHED_BATTERY_PERCENTAGE, batteryPercentage)
    }
    if (!lowPowerMode.isNullOrBlank()) {
      editor.putString(KEY_CACHED_LOW_POWER_MODE, lowPowerMode.trim())
    }
    editor.apply()
    android.util.Log.i(
      "AndroidPermStatus",
      "cached battery percentage=$batteryPercentage low_power_mode=$lowPowerMode",
    )
  }

  fun readCachedBatteryPercentage(context: Context): Int? {
    val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    if (!prefs.contains(KEY_CACHED_BATTERY_PERCENTAGE)) return null
    val value = prefs.getInt(KEY_CACHED_BATTERY_PERCENTAGE, -1)
    return value.takeIf { it in 0..100 }
  }

  fun readCachedLowPowerMode(context: Context): String? {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(KEY_CACHED_LOW_POWER_MODE, null)
      ?.trim()
      ?.takeIf { it.isNotEmpty() }
  }
}
