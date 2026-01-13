package com.example.application_mobile

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
  private val CHANNEL = "optiPark/secure_screen"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "enable" -> {
            window.setFlags(
              WindowManager.LayoutParams.FLAG_SECURE,
              WindowManager.LayoutParams.FLAG_SECURE
            )
            result.success(true)
          }
          "disable" -> {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            result.success(true)
          }
          else -> result.notImplemented()
        }
      }
  }
}