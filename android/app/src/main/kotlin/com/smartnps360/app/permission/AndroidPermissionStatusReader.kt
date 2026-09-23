package com.smartnps360.app.permission

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject

/**
 * Reads Android permission snapshot for killed-app sync.
 * Mirrors Flutter [NativePermissionStatusService] Android mapping as closely
 * as possible using OS APIs + Flutter SharedPreferences history flags.
 */
internal object AndroidPermissionStatusReader {
  private const val FLUTTER_PREFS = "FlutterSharedPreferences"
  private const val FG_EVER =
    "flutter.permission.foreground_location.ever_granted.v1"
  private const val FG_DENIED =
    "flutter.permission.foreground_location.user_denied.v1"
  private const val BG_EVER =
    "flutter.permission.background_location.ever_granted.v1"
  private const val BG_DENIED =
    "flutter.permission.background_location.user_denied.v1"

  fun buildPermissionsJson(context: Context, pushStatus: String): JSONObject {
    return JSONObject()
      .put("foregroundLocation", foregroundLocation(context))
      .put("backgroundLocation", backgroundLocation(context))
      .put("preciseLocation", preciseLocation(context))
      .put("notifications", notifications(context))
      .put("motionActivity", motionActivity(context))
      .put("batteryOptimization", batteryOptimization(context))
      .put("backgroundAppRefresh", backgroundAppRefresh(context))
      .put("push", pushStatus)
  }

  fun lowPowerModeStatus(context: Context): String {
    return try {
      val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
      if (pm.isPowerSaveMode) "enabled" else "disabled"
    } catch (_: Exception) {
      "unknown"
    }
  }

  fun batteryPercentage(context: Context): Int {
    return try {
      val intent = context.registerReceiver(
        null,
        android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED),
      )
      val level = intent?.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1) ?: -1
      val scale = intent?.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1) ?: -1
      if (level < 0 || scale <= 0) return -1
      ((level.toFloat() / scale.toFloat()) * 100f).toInt().coerceIn(0, 100)
    } catch (_: Exception) {
      -1
    }
  }

  private fun locationServicesEnabled(context: Context): Boolean {
    return try {
      val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        lm.isLocationEnabled
      } else {
        @Suppress("DEPRECATION")
        Settings.Secure.getInt(
          context.contentResolver,
          Settings.Secure.LOCATION_MODE,
          Settings.Secure.LOCATION_MODE_OFF,
        ) != Settings.Secure.LOCATION_MODE_OFF
      }
    } catch (_: Exception) {
      true
    }
  }

  private fun hasFine(context: Context): Boolean {
    return ContextCompat.checkSelfPermission(
      context,
      Manifest.permission.ACCESS_FINE_LOCATION,
    ) == PackageManager.PERMISSION_GRANTED
  }

  private fun hasCoarse(context: Context): Boolean {
    return ContextCompat.checkSelfPermission(
      context,
      Manifest.permission.ACCESS_COARSE_LOCATION,
    ) == PackageManager.PERMISSION_GRANTED
  }

  private fun hasBackground(context: Context): Boolean {
    if (!hasFine(context) && !hasCoarse(context)) return false
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      return ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.ACCESS_BACKGROUND_LOCATION,
      ) == PackageManager.PERMISSION_GRANTED
    }
    return true
  }

  private fun hasOneTimeLocation(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < 30) return false
    if (!hasFine(context) && !hasCoarse(context)) return false
    val oneTimeFlag = 0x00010000
    return (permissionFlags(context, Manifest.permission.ACCESS_FINE_LOCATION) and oneTimeFlag) != 0 ||
      (permissionFlags(context, Manifest.permission.ACCESS_COARSE_LOCATION) and oneTimeFlag) != 0
  }

  private fun permissionFlags(context: Context, permission: String): Int {
    return try {
      val method = PackageManager::class.java.getMethod(
        "getPermissionFlags",
        String::class.java,
        String::class.java,
        android.os.UserHandle::class.java,
      )
      val result = method.invoke(
        context.packageManager,
        permission,
        context.packageName,
        android.os.Process.myUserHandle(),
      )
      when (result) {
        is Int -> result
        is Number -> result.toInt()
        else -> 0
      }
    } catch (_: Exception) {
      0
    }
  }

  private fun flutterBool(context: Context, key: String): Boolean {
    return try {
      context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        .getBoolean(key, false)
    } catch (_: Exception) {
      false
    }
  }

  private fun foregroundLocation(context: Context): String {
    if (!locationServicesEnabled(context)) return "unknown"
    if (hasOneTimeLocation(context)) return "denied"
    if (hasFine(context) || hasCoarse(context)) return "granted"
    if (flutterBool(context, FG_EVER) || flutterBool(context, FG_DENIED)) {
      return "denied"
    }
    return "unknown"
  }

  private fun backgroundLocation(context: Context): String {
    if (!locationServicesEnabled(context)) {
      return remapBackground("unknown", context)
    }
    if (!hasFine(context) && !hasCoarse(context)) {
      if (flutterBool(context, FG_EVER) || flutterBool(context, FG_DENIED)) {
        return "denied"
      }
      return remapBackground("unknown", context)
    }
    val live = if (hasBackground(context)) "granted" else "unknown"
    return remapBackground(live, context)
  }

  private fun remapBackground(live: String, context: Context): String {
    if (live == "granted") return "granted"
    if (live == "denied") return "denied"
    if (flutterBool(context, BG_EVER) || flutterBool(context, BG_DENIED)) {
      return "denied"
    }
    return live
  }

  private fun preciseLocation(context: Context): String {
    if (hasOneTimeLocation(context)) return "denied"
    if (hasFine(context) || hasCoarse(context)) {
      return if (hasFine(context)) "granted" else "denied"
    }
    if (flutterBool(context, FG_EVER) || flutterBool(context, FG_DENIED)) {
      return "denied"
    }
    return "unknown"
  }

  private fun notifications(context: Context): String {
    return try {
      if (NotificationManagerCompat.from(context).areNotificationsEnabled()) {
        "granted"
      } else {
        "denied"
      }
    } catch (_: Exception) {
      "unknown"
    }
  }

  private fun motionActivity(context: Context): String {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "unknown"
    return try {
      val granted = ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.ACTIVITY_RECOGNITION,
      ) == PackageManager.PERMISSION_GRANTED
      if (granted) "granted" else "unknown"
    } catch (_: Exception) {
      "unknown"
    }
  }

  private fun batteryOptimization(context: Context): String {
    return try {
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return "granted"
      val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
      if (pm.isIgnoringBatteryOptimizations(context.packageName)) {
        "granted"
      } else {
        "unknown"
      }
    } catch (_: Exception) {
      "unknown"
    }
  }

  private fun backgroundAppRefresh(context: Context): String {
    return try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        val am =
          context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
        if (am.isBackgroundRestricted) "disabled" else "enabled"
      } else {
        "unknown"
      }
    } catch (_: Exception) {
      "unknown"
    }
  }
}
