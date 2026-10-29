package com.streamio.streamio

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * Answers `streamio/platform#isTv` for lib/shared/tv.dart, and attaches to
 * the process-owned engine in [EngineHolder] instead of creating its own —
 * so a download in flight survives this Activity being swiped away.
 *
 * Flutter has no platform-reported "this is a television" signal of its own
 * (MediaQueryData.navigationMode is set by the app, not the engine), so the
 * D-pad-only UI has to ask Android directly.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private var currentRef: WeakReference<MainActivity>? = null

        /** The live Activity, for the one call that needs one (a permission prompt). */
        val current: MainActivity? get() = currentRef?.get()

        val isAttached: Boolean get() = current != null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        currentRef = WeakReference(this)
        super.onCreate(savedInstanceState)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine = EngineHolder.obtain(context)

    /** Never with the Activity: [onDestroy] hands the decision to [EngineHolder]. */
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onDestroy() {
        super.onDestroy()
        if (current === this) currentRef = null
        // A recreated Activity reattaches to the same engine; otherwise the
        // engine goes now unless a download still needs it.
        if (!isChangingConfigurations) EngineHolder.destroyIfIdle()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Re-set on every attach, which is harmless: it only replaces the
        // handler. Engine-scoped channels live in EngineHolder.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "streamio/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTv" -> result.success(isTelevision())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Three signals, any of which is enough:
     *  - UiModeManager reports the TV ui mode — the canonical check, and the
     *    one Android TV / Google TV set;
     *  - the leanback or television system feature is present (Fire TV and
     *    some set-top boxes report the feature but not always the ui mode);
     *  - there is no touchscreen at all, which leaves the D-pad as the only
     *    way in whatever the device calls itself.
     */
    private fun isTelevision(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        if (uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) return true

        val pm = packageManager
        return pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            pm.hasSystemFeature(PackageManager.FEATURE_TELEVISION) ||
            !pm.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
    }
}
