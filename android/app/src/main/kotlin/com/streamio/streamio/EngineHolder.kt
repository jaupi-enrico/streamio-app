package com.streamio.streamio

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * The one Flutter engine, owned by the process rather than by [MainActivity].
 *
 * Offline downloads run in Dart (lib/core/download/download_manager.dart).
 * A FlutterActivity normally destroys its engine — and with it the Dart
 * isolate and every download in flight — when the Activity goes, which is
 * what swiping the app out of Recents does. Holding the engine here lets it
 * outlive the Activity while [DownloadService] keeps the process alive;
 * reopening the app reattaches to the same engine, mid-download.
 *
 * With nothing downloading the engine goes with the Activity exactly as it
 * used to ([destroyIfIdle]), so a swipe-away still ends the app.
 *
 * Engine-scoped channels are registered here, once per engine, not in
 * `configureFlutterEngine`: that runs on *every* Activity attach, and the
 * [CastControlChannel] it used to build there registers a Cast session
 * listener per instance — a reattach would have doubled every event.
 */
object EngineHolder {
    private const val ENGINE_ID = "main"

    /** Set while an engine exists; the downloads channel posts through it. */
    var downloads: DownloadsChannel? = null
        private set

    fun obtain(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }

        val appContext = context.applicationContext
        val engine = FlutterEngine(appContext)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())

        downloads = DownloadsChannel(appContext, engine.dartExecutor.binaryMessenger)
        CastControlChannel(appContext, engine.dartExecutor.binaryMessenger)

        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        return engine
    }

    /**
     * Destroys the engine unless a download is keeping it. Called when the
     * Activity is destroyed, and by [DownloadService] when it stops with no
     * Activity left to come back to.
     */
    fun destroyIfIdle() {
        if (DownloadService.isRunning) return
        val engine = FlutterEngineCache.getInstance().get(ENGINE_ID) ?: return
        // An Activity still attached (one being recreated, or the user just
        // reopened the app) owns the engine now.
        if (MainActivity.isAttached) return
        FlutterEngineCache.getInstance().remove(ENGINE_ID)
        downloads = null
        engine.destroy()
    }
}
