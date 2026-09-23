package com.smartnps360.app.duty

import android.content.Context

internal object AndroidDutyKillStore {
  private const val NATIVE_PREFS = "smartnps360_android_duty_kill"
  private const val FLUTTER_PREFS = "FlutterSharedPreferences"
  private const val KEY_ARMED = "armed"
  private const val KEY_ACCESS = "access_token"
  private const val KEY_REFRESH = "refresh_token"
  const val FLUTTER_FORCE_OFF = "flutter.android_duty.kill.force_off"
  const val FLUTTER_ARMED = "flutter.android_duty.kill.armed"
  const val FLUTTER_API_ON_DUTY_UNTIL = "flutter.android_duty.kill.api_on_duty_until"
  const val FLUTTER_UNPAID_BREAK = "flutter.android_duty.kill.unpaid_break"

  private const val API_ON_DUTY_GRACE_MS = 30L * 60L * 1000L

  fun arm(context: Context, accessToken: String, refreshToken: String?) {
    context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
      .edit()
      .putBoolean(KEY_ARMED, true)
      .putString(KEY_ACCESS, accessToken)
      .putString(KEY_REFRESH, refreshToken ?: "")
      .apply()
    writeFlutterBoolean(context, FLUTTER_FORCE_OFF, false)
    writeFlutterBoolean(context, FLUTTER_ARMED, true)
  }

  fun syncSession(context: Context, accessToken: String, refreshToken: String?) {
    val prefs = context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
    if (!prefs.getBoolean(KEY_ARMED, false)) return
    prefs.edit()
      .putString(KEY_ACCESS, accessToken)
      .putString(KEY_REFRESH, refreshToken ?: "")
      .apply()
  }

  fun disarm(context: Context, forceOff: Boolean) {
    context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
      .edit()
      .putBoolean(KEY_ARMED, false)
      .remove(KEY_ACCESS)
      .remove(KEY_REFRESH)
      .apply()
    writeFlutterBoolean(context, FLUTTER_FORCE_OFF, forceOff)
    writeFlutterBoolean(context, FLUTTER_ARMED, false)
    writeFlutterBoolean(context, FLUTTER_UNPAID_BREAK, false)
    if (forceOff) {
      writeFlutterString(context, FLUTTER_API_ON_DUTY_UNTIL, "0")
    }
  }

  fun isArmed(context: Context): Boolean {
    return context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
      .getBoolean(KEY_ARMED, false)
  }

  fun isForceOff(context: Context): Boolean {
    return context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
      .getBoolean(FLUTTER_FORCE_OFF, false)
  }

  fun isUnpaidBreak(context: Context): Boolean {
    return context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
      .getBoolean(FLUTTER_UNPAID_BREAK, false)
  }

  fun setUnpaidBreak(context: Context, unpaid: Boolean) {
    writeFlutterBoolean(context, FLUTTER_UNPAID_BREAK, unpaid)
    if (unpaid) {
      writeFlutterString(context, FLUTTER_API_ON_DUTY_UNTIL, "0")
    }
  }

  fun accessToken(context: Context): String? {
    return context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
      .getString(KEY_ACCESS, null)
      ?.takeIf { it.isNotEmpty() }
  }

  fun refreshToken(context: Context): String? {
    return context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
      .getString(KEY_REFRESH, null)
      ?.takeIf { it.isNotEmpty() }
  }

  fun writeAccessToken(context: Context, token: String) {
    context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
      .edit()
      .putString(KEY_ACCESS, token)
      .apply()
  }

  fun writeRefreshToken(context: Context, token: String) {
    context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
      .edit()
      .putString(KEY_REFRESH, token)
      .apply()
  }

  fun markApiOnDuty(context: Context) {
    writeFlutterBoolean(context, FLUTTER_FORCE_OFF, false)
    writeFlutterString(
      context,
      FLUTTER_API_ON_DUTY_UNTIL,
      (System.currentTimeMillis() + API_ON_DUTY_GRACE_MS).toString(),
    )
  }

  private fun writeFlutterBoolean(context: Context, key: String, value: Boolean) {
    context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
      .edit()
      .putBoolean(key, value)
      .commit()
  }

  private fun writeFlutterString(context: Context, key: String, value: String) {
    context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
      .edit()
      .putString(key, value)
      .commit()
  }
}
