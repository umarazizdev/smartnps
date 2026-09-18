package com.smartnps360.app.permission

import android.content.Context

/**
 * Session for killed-app permission-status sync.
 * Independent from duty kill-watch so this never starts location FGS.
 */
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
}
