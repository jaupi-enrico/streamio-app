package com.streamio.streamio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Keeps the process — and the Flutter engine [EngineHolder] keeps in it —
 * alive while offline downloads run, with the progress notification Android
 * requires of a foreground service.
 *
 * It downloads nothing itself: the work stays in Dart's DownloadManager,
 * which starts and stops this through [DownloadsChannel]. The service only
 * guarantees there is still a process for that Dart code to run in once the
 * app is backgrounded, the screen is off, or the Activity was swiped away.
 *
 * `dataSync` type. Android 15 caps that at six hours a day; [onTimeout]
 * pauses everything cleanly rather than letting the system kill the process
 * mid-segment (a paused download resumes where it stopped).
 */
class DownloadService : Service() {

    data class Progress(val title: String?, val count: Int, val progress: Double?)

    companion object {
        private const val TAG = "StreamioDownloads"
        private const val CHANNEL_ID = "downloads"
        private const val NOTIFICATION_ID = 4100
        private const val ACTION_PAUSE_ALL = "com.streamio.streamio.downloads.PAUSE_ALL"

        @Volatile
        var isRunning = false
            private set

        private var instance: DownloadService? = null

        /** Latest progress, read by onCreate and every later update. */
        @Volatile
        private var latest = Progress(null, 0, null)

        /**
         * Starts the service. False when Android refuses — a foreground
         * service can't be started from the background on Android 12+, which
         * only matters if a download begins with the app already hidden.
         */
        fun start(context: Context, progress: Progress): Boolean {
            latest = progress
            if (isRunning) {
                instance?.refresh()
                return true
            }
            return try {
                ContextCompat.startForegroundService(context, Intent(context, DownloadService::class.java))
                true
            } catch (e: Exception) {
                Log.w(TAG, "could not start the download service", e)
                false
            }
        }

        fun update(context: Context, progress: Progress) {
            latest = progress
            instance?.refresh()
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, DownloadService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        isRunning = true
        ensureChannel()
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            buildNotification(),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0,
        )
        acquireLocks()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_PAUSE_ALL) EngineHolder.downloads?.pauseAll()
        // Not sticky: a restart after the process died would have no engine
        // and no download state to keep alive. The next launch resumes
        // interrupted downloads itself.
        return START_NOT_STICKY
    }

    /** Android 15's daily `dataSync` budget is spent. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        Log.w(TAG, "dataSync time limit reached, pausing downloads")
        EngineHolder.downloads?.pauseAll()
        stopSelf()
    }

    override fun onDestroy() {
        releaseLocks()
        instance = null
        isRunning = false
        // Downloads finished (or were paused) after the Activity was swiped
        // away: nothing is left to keep the engine for, so let the app end
        // the way it would have without downloads.
        Handler(Looper.getMainLooper()).post { EngineHolder.destroyIfIdle() }
        super.onDestroy()
    }

    private fun refresh() {
        getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Downloads", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Progress of offline downloads"
                setShowBadge(false)
            }
        )
    }

    private fun buildNotification(): Notification {
        val progress = latest
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val pause = PendingIntent.getService(
            this,
            1,
            Intent(this, DownloadService::class.java).setAction(ACTION_PAUSE_ALL),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val heading = when {
            progress.count > 1 -> "Downloading ${progress.count} titles"
            else -> "Downloading"
        }
        val percent = progress.progress?.let { (it.coerceIn(0.0, 1.0) * 100).toInt() }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(if (percent != null) "$heading · $percent%" else heading)
            .setContentText(progress.title)
            .setProgress(100, percent ?: 0, percent == null)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(open)
            .addAction(0, "Pause all", pause)
            .build()
    }

    private fun acquireLocks() {
        // The screen going off must not stall a download: the CPU stays up
        // while segments are fetched, and Wi-Fi isn't dropped to power-save.
        wakeLock = getSystemService(PowerManager::class.java)
            ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "streamio:downloads")
            ?.apply { setReferenceCounted(false); acquire() }
        @Suppress("DEPRECATION")
        wifiLock = applicationContext.getSystemService(WifiManager::class.java)
            ?.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "streamio:downloads")
            ?.apply { setReferenceCounted(false); acquire() }
    }

    private fun releaseLocks() {
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        wifiLock?.takeIf { it.isHeld }?.release()
        wifiLock = null
    }
}
