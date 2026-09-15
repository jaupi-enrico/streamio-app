package com.streamio.streamio

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Answers `streamio/platform#isTv` for lib/shared/tv.dart, and hosts the Cast
 * control channel ([CastControlChannel]).
 *
 * Flutter has no platform-reported "this is a television" signal of its own
 * (MediaQueryData.navigationMode is set by the app, not the engine), so the
 * D-pad-only UI has to ask Android directly.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "streamio/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTv" -> result.success(isTelevision())
                    else -> result.notImplemented()
                }
            }

        CastControlChannel(this, flutterEngine.dartExecutor.binaryMessenger)
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
