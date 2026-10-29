package com.streamio.streamio

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * `streamio/downloads`, for lib/core/download/download_foreground.dart.
 *
 * Dart decides *when* the process needs keeping alive (anything downloading)
 * and what the notification says; this only drives [DownloadService]. The one
 * call the other way is `pauseAll`, from the notification's Pause action or
 * the Android 15 `dataSync` time limit.
 *
 * Engine-scoped (built by [EngineHolder]), so it keeps working with no
 * Activity attached — which is exactly when it matters.
 */
class DownloadsChannel(context: Context, messenger: BinaryMessenger) {

    companion object {
        private const val TAG = "StreamioDownloads"
        private const val CHANNEL = "streamio/downloads"
        private const val NOTIFICATION_PERMISSION_REQUEST = 4101
    }

    private val appContext = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> result.success(DownloadService.start(appContext, progressFrom(call.arguments)))
                "update" -> {
                    DownloadService.update(appContext, progressFrom(call.arguments))
                    result.success(null)
                }
                "stop" -> {
                    DownloadService.stop(appContext)
                    result.success(null)
                }
                "requestNotificationPermission" -> {
                    requestNotificationPermission()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Asks Dart to pause every running download, saving where each got to. */
    fun pauseAll() {
        main.post {
            try {
                channel.invokeMethod("pauseAll", null)
            } catch (e: Exception) {
                Log.w(TAG, "pauseAll did not reach Dart", e)
            }
        }
    }

    /**
     * Android 13+ hides a foreground service's notification without this
     * permission. The service still runs either way, so a refusal costs only
     * the progress display — never ask in a way that blocks a download.
     */
    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            appContext, Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) return
        val activity = MainActivity.current ?: return
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    private fun progressFrom(arguments: Any?): DownloadService.Progress {
        val map = arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        return DownloadService.Progress(
            title = map["title"] as? String,
            count = (map["count"] as? Number)?.toInt() ?: 0,
            progress = (map["progress"] as? Number)?.toDouble(),
        )
    }
}
