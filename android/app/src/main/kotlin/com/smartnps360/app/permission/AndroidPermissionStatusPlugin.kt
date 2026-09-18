package com.smartnps360.app.permission

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AndroidPermissionStatusPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private var channel: MethodChannel? = null
  private var appContext: android.content.Context? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    appContext = binding.applicationContext
    val methodChannel = MethodChannel(
      binding.binaryMessenger,
      "com.smartnps360.app/android_permission_status",
    )
    methodChannel.setMethodCallHandler(this)
    channel = methodChannel
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel?.setMethodCallHandler(null)
    channel = null
    appContext = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    val context = appContext
    if (context == null) {
      result.error("no_context", "Android permission status watch has no context", null)
      return
    }
    when (call.method) {
      "arm" -> {
        val access = call.argument<String>("accessToken")
        val apiBaseUrl = call.argument<String>("apiBaseUrl")
        val deviceId = call.argument<String>("deviceId")
        val appVersion = call.argument<String>("appVersion")
        val build = call.argument<String>("build")
        if (access.isNullOrEmpty() ||
          apiBaseUrl.isNullOrEmpty() ||
          deviceId.isNullOrEmpty() ||
          appVersion.isNullOrEmpty() ||
          build.isNullOrEmpty()
        ) {
          result.error("missing_args", "accessToken/apiBaseUrl/deviceId/appVersion/build required", null)
          return
        }
        AndroidPermissionStatusWatch.arm(
          context = context,
          accessToken = access,
          refreshToken = call.argument<String>("refreshToken"),
          apiBaseUrl = apiBaseUrl,
          deviceId = deviceId,
          deviceName = call.argument<String>("deviceName"),
          appVersion = appVersion,
          build = build,
          pushStatus = call.argument<String>("pushStatus") ?: "enabled",
          fingerprint = null,
        )
        if (call.argument<Boolean>("markSynced") == true) {
          AndroidPermissionStatusWatch.noteCurrentSynced(context)
        }
        result.success(true)
      }
      "syncSession" -> {
        val access = call.argument<String>("accessToken")
        if (access.isNullOrEmpty()) {
          result.success(false)
          return
        }
        AndroidPermissionStatusWatch.syncSession(
          context = context,
          accessToken = access,
          refreshToken = call.argument<String>("refreshToken"),
          apiBaseUrl = call.argument<String>("apiBaseUrl"),
          pushStatus = call.argument<String>("pushStatus"),
        )
        if (call.argument<Boolean>("markSynced") == true) {
          AndroidPermissionStatusWatch.noteCurrentSynced(context)
        }
        result.success(true)
      }
      "noteCurrentSynced" -> {
        AndroidPermissionStatusWatch.noteCurrentSynced(context)
        result.success(true)
      }
      "disarm" -> {
        AndroidPermissionStatusWatch.disarm(context)
        result.success(true)
      }
      else -> result.notImplemented()
    }
  }
}
