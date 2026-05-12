package com.example.yeah

import android.content.Context
import android.content.SharedPreferences
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.yeah/native"
    
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceInfo" -> {
                    val info = mapOf(
                        "model" to android.os.Build.MODEL,
                        "version" to android.os.Build.VERSION.RELEASE,
                        "brand" to android.os.Build.BRAND
                    )
                    result.success(info)
                }
                "getNotesCount" -> {
                    val prefs = getSharedPreferences("yeah_notes", Context.MODE_PRIVATE)
                    val count = prefs.getInt("notes_count", 0)
                    result.success(count)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}