package com.smartnps360.motion_activity

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger

class SmartnpsMotionActivityPlugin : FlutterPlugin {
  private var manager: MotionActivityManager? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val existing = manager
    if (existing != null) {
      existing.dispose()
    }
    val created = MotionActivityManager(binding.applicationContext)
    created.register(binding.binaryMessenger)
    manager = created
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    manager?.dispose()
    manager = null
  }

  companion object {

    fun registerWith(messenger: BinaryMessenger, manager: MotionActivityManager) {
      manager.register(messenger)
    }
  }
}
