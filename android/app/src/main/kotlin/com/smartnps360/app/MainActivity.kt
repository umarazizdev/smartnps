package com.smartnps360.app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
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

  override fun onCreate(savedInstanceState: android.os.Bundle?) {
    super.onCreate(savedInstanceState)

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

    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      settingsChannel
    ).setMethodCallHandler { call, result ->
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
        "isIgnoringBatteryOptimizations" -> {
          result.success(isIgnoringBatteryOptimizations())
        }
        else -> result.notImplemented()
      }
    }
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

  private fun isIgnoringBatteryOptimizations(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
      return true
    }
    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
    return powerManager.isIgnoringBatteryOptimizations(packageName)
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
