package com.smartnps360.app

import android.Manifest
import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val settingsChannel = "com.smartnps360.app/settings"
  private var settingsMethodChannel: MethodChannel? = null
  private var powerSaveReceiverRegistered = false
  private val powerSaveModeReceiver = object : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
      if (intent?.action != PowerManager.ACTION_POWER_SAVE_MODE_CHANGED) return
      notifyLowPowerModeChanged()
    }
  }

  override fun onCreate(savedInstanceState: android.os.Bundle?) {
    super.onCreate(savedInstanceState)
    observePowerSaveModeChanges()

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val manager = getSystemService(NotificationManager::class.java)

      val pushChannel = NotificationChannel(
        "smartnps360_default",
        "SmartNPS360",
        NotificationManager.IMPORTANCE_HIGH
      )
      pushChannel.description = "SmartNPS360 notifications"
      // Channel sound is fixed at first creation; must match res/raw/alert_sound.mp3
      // and flutter_local_notifications RawResourceAndroidNotificationSound('alert_sound').
      pushChannel.setSound(
        Uri.parse("android.resource://$packageName/${R.raw.alert_sound}"),
        AudioAttributes.Builder()
          .setUsage(AudioAttributes.USAGE_NOTIFICATION)
          .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
          .build(),
      )
      manager?.createNotificationChannel(pushChannel)

      val locationChannel = NotificationChannel(
        "smartnps360_location",
        "Background location",
        NotificationManager.IMPORTANCE_LOW
      )
      locationChannel.description = "Keeps location tracking active in background"
      manager?.createNotificationChannel(locationChannel)
    }
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    val channel = MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      settingsChannel
    )
    settingsMethodChannel = channel
    channel.setMethodCallHandler { call, result ->
      when (call.method) {
        "openAppSettings" -> {
          try {
            openAppSettings()
            result.success(true)
          } catch (error: Exception) {
            result.error("open_app_settings_failed", error.message, null)
          }
        }
        "openLocationPermissionSettings" -> {
          try {
            openLocationPermissionSettings()
            result.success(true)
          } catch (error: Exception) {
            result.error("open_location_permission_settings_failed", error.message, null)
          }
        }
        "hasBackgroundLocationPermission" -> {
          result.success(hasBackgroundLocationPermission())
        }
        "hasPreciseLocationPermission" -> {
          result.success(hasPreciseLocationPermission())
        }
        "hasOneTimeLocationPermission" -> {
          result.success(hasOneTimeLocationPermission())
        }
        "isIgnoringBatteryOptimizations" -> {
          result.success(isIgnoringBatteryOptimizations())
        }
        "batteryOptimizationStatus" -> {
          result.success(batteryOptimizationStatus())
        }
        "lowPowerModeStatus" -> {
          result.success(lowPowerModeStatus())
        }
        "backgroundAppRefreshStatus" -> {
          result.success(backgroundAppRefreshStatus())
        }
        else -> result.notImplemented()
      }
    }
  }

  override fun onResume() {
    super.onResume()
    notifyLowPowerModeChanged()
  }

  override fun onDestroy() {
    if (powerSaveReceiverRegistered) {
      try {
        unregisterReceiver(powerSaveModeReceiver)
      } catch (_: Exception) {
      }
      powerSaveReceiverRegistered = false
    }
    super.onDestroy()
  }

  private fun observePowerSaveModeChanges() {
    if (powerSaveReceiverRegistered) return
    val filter = IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      registerReceiver(powerSaveModeReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
    } else {
      registerReceiver(powerSaveModeReceiver, filter)
    }
    powerSaveReceiverRegistered = true
  }

  private fun hasBackgroundLocationPermission(): Boolean {
    val fineGranted =
      checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED
    val coarseGranted =
      checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED
    if (!fineGranted && !coarseGranted) {
      return false
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      return checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
        PackageManager.PERMISSION_GRANTED
    }
    return true
  }

  private fun hasPreciseLocationPermission(): Boolean {
    return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
      PackageManager.PERMISSION_GRANTED
  }

  /// True when OS granted location only for this session ("Allow only this time").
  private fun hasOneTimeLocationPermission(): Boolean {
    // API 30+ (R). Use numeric flag — compileSdk stubs may lack
    // PackageManager.FLAG_PERMISSION_ONE_TIME / getPermissionFlags symbols.
    if (Build.VERSION.SDK_INT < 30) {
      return false
    }
    val fineGranted =
      checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED
    val coarseGranted =
      checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED
    if (!fineGranted && !coarseGranted) {
      return false
    }
    // PackageManager.FLAG_PERMISSION_ONE_TIME == 1 << 16
    val oneTimeFlag = 0x00010000
    val fineOneTime =
      (permissionFlags(Manifest.permission.ACCESS_FINE_LOCATION) and oneTimeFlag) != 0
    val coarseOneTime =
      (permissionFlags(Manifest.permission.ACCESS_COARSE_LOCATION) and oneTimeFlag) != 0
    return fineOneTime || coarseOneTime
  }

  /** Reflective read of PackageManager.getPermissionFlags (API 23+). */
  private fun permissionFlags(permission: String): Int {
    return try {
      val method = PackageManager::class.java.getMethod(
        "getPermissionFlags",
        String::class.java,
        String::class.java,
        android.os.UserHandle::class.java,
      )
      val result = method.invoke(
        packageManager,
        permission,
        packageName,
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

  private fun isIgnoringBatteryOptimizations(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
      return true
    }
    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
    return powerManager.isIgnoringBatteryOptimizations(packageName)
  }

  private fun batteryOptimizationStatus(): String {
    return try {
      if (isIgnoringBatteryOptimizations()) {
        "granted"
      } else {
        // Default optimized state — not an explicit officer denial.
        "unknown"
      }
    } catch (_: Exception) {
      "unknown"
    }
  }

  /// System Battery Saver only ([PowerManager.isPowerSaveMode]).
  /// Do not scan OEM Settings keys — on Vivo/etc those often read as on
  /// even when the user-facing Battery Saver toggle is off.
  private fun lowPowerModeStatus(): String {
    return try {
      val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
      if (powerManager.isPowerSaveMode) {
        "enabled"
      } else {
        "disabled"
      }
    } catch (_: Exception) {
      "unknown"
    }
  }

  private fun notifyLowPowerModeChanged() {
    settingsMethodChannel?.invokeMethod(
      "lowPowerModeChanged",
      mapOf("low_power_mode" to lowPowerModeStatus())
    )
  }

  /**
   * Closest Android parallel to iOS Background App Refresh:
   * [ActivityManager.isBackgroundRestricted] (API 28+) — user put the app under
   * restricted battery / background usage so background work is blocked.
   */
  private fun backgroundAppRefreshStatus(): String {
    return try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        val activityManager =
          getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        if (activityManager.isBackgroundRestricted) {
          "disabled"
        } else {
          "enabled"
        }
      } else {
        // No per-app background-restriction API below P.
        "enabled"
      }
    } catch (_: Exception) {
      "unknown"
    }
  }

  private fun openAppSettings() {
    val intent = Intent(
      Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
      Uri.parse("package:$packageName"),
    )
    startActivity(intent)
  }

  private fun openLocationPermissionSettings() {
    val pkg = packageName

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      val groupNames = listOf(
        Manifest.permission_group.LOCATION,
        "android.permission-group.LOCATION",
      )
      for (group in groupNames) {
        if (tryStartActivity(
            Intent("android.settings.MANAGE_APP_PERMISSION").apply {
              setPackage("com.android.settings")
              putExtra(Intent.EXTRA_PACKAGE_NAME, pkg)
              putExtra("android.intent.extra.PERMISSION_GROUP_NAME", group)
            },
          )) {
          return
        }
      }

      if (tryStartActivity(
          Intent("android.settings.MANAGE_APP_PERMISSION").apply {
            putExtra(Intent.EXTRA_PACKAGE_NAME, pkg)
            putExtra(
              "android.intent.extra.PERMISSION_GROUP_NAME",
              Manifest.permission_group.LOCATION,
            )
          },
        )) {
        return
      }
    }

    val permissionListIntents = listOf(
      Intent("android.settings.MANAGE_APP_PERMISSIONS").apply {
        setPackage("com.android.settings")
        putExtra(Intent.EXTRA_PACKAGE_NAME, pkg)
        putExtra("android.intent.extra.PACKAGE_NAME", pkg)
        data = Uri.parse("package:$pkg")
      },
      Intent("android.settings.MANAGE_APP_PERMISSIONS").apply {
        putExtra(Intent.EXTRA_PACKAGE_NAME, pkg)
        data = Uri.parse("package:$pkg")
      },
    )
    for (intent in permissionListIntents) {
      if (tryStartActivity(intent)) {
        return
      }
    }

    openAppSettings()
  }

  private fun tryStartActivity(intent: Intent): Boolean {
    return try {
      if (intent.resolveActivity(packageManager) == null) {
        false
      } else {
        startActivity(intent)
        true
      }
    } catch (_: Exception) {
      false
    }
  }
}
