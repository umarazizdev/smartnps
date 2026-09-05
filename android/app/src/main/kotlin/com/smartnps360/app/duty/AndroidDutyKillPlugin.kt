package com.smartnps360.app.duty

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AndroidDutyKillPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private var channel: MethodChannel? = null
  private var appContext: android.content.Context? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    appContext = binding.applicationContext
    val methodChannel = MethodChannel(
      binding.binaryMessenger,
      "com.smartnps360.app/android_duty_kill",
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
      result.error("no_context", "Android duty kill watch has no context", null)
      return
    }
    when (call.method) {
      "arm" -> {
        val access = call.argument<String>("accessToken")
        if (access.isNullOrEmpty()) {
          result.error("missing_token", "accessToken required", null)
          return
        }
        AndroidDutyKillWatch.arm(
          context,
          access,
          call.argument<String>("refreshToken"),
        )
        result.success(true)
      }
      "syncSession" -> {
        val access = call.argument<String>("accessToken")
        if (access.isNullOrEmpty()) {
          result.success(false)
          return
        }
        AndroidDutyKillWatch.syncSession(
          context,
          access,
          call.argument<String>("refreshToken"),
        )
        result.success(true)
      }
      "disarm" -> {
        val forceOff = call.argument<Boolean>("forceOff") == true
        AndroidDutyKillWatch.disarm(context, forceOff)
        result.success(true)
      }
      "setUnpaidBreak" -> {
        val unpaid = call.argument<Boolean>("unpaid") == true
        AndroidDutyKillStore.setUnpaidBreak(context, unpaid)
        if (unpaid) {
          AndroidDutyKillWatch.stopLocationServiceForUnpaidBreak(context)
        }
        result.success(true)
      }
      else -> result.notImplemented()
    }
  }
}
