package com.example.remote_patient_monitoring

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service that maintains BLE connections when app is in background.
 * This service creates a persistent notification to inform the user that the app
 * is running in the background and keeping BLE connections active.
 */
class BleBackgroundService : Service() {
    private val binder = LocalBinder()
    private val CHANNEL_ID = "BleBackgroundServiceChannel"
    private val NOTIFICATION_ID = 1
    private var wakeLock: PowerManager.WakeLock? = null

    inner class LocalBinder : Binder() {
        fun getService(): BleBackgroundService = this@BleBackgroundService
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        
        // Acquire partial wake lock to maintain BLE connection
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "BleBackgroundService::WakeLock"
        )
        // Acquire with timeout to prevent battery drain but long enough for BLE operations
        wakeLock?.acquire(30*60*1000L) // 30 minutes timeout
        Log.d("BleBackgroundService", "Wake lock acquired with 30-minute timeout")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("BleBackgroundService", "onStartCommand called")
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Mobile Health Active")
            .setContentText("Monitoring for connected devices")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true) // Make notification persistent
            .build()

        startForeground(NOTIFICATION_ID, notification)
        return START_REDELIVER_INTENT // Ensures service restarts with same intent
    }

    override fun onBind(intent: Intent?): IBinder {
        return binder
    }

    override fun onDestroy() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "BLE Background Service"
            val descriptionText = "Keeps BLE connections active in background"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
}
