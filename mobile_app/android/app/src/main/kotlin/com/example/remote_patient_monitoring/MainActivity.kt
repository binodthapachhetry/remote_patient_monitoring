package com.example.remote_patient_monitoring // Match applicationId

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Main activity that hosts the Flutter UI and provides native platform channel
 * methods for controlling the background service.
 */
class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.remote_patient_monitoring/background_service"
    private val TAG = "MainActivity"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Set up method channel for communication with Flutter code
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    Log.d(TAG, "Starting background service")
                    val serviceIntent = Intent(this, BleBackgroundService::class.java)
                    
                    // Use appropriate method based on Android version
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                    result.success(true)
                }
                "stopService" -> {
                    Log.d(TAG, "Stopping background service")
                    val serviceIntent = Intent(this, BleBackgroundService::class.java)
                    stopService(serviceIntent)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
