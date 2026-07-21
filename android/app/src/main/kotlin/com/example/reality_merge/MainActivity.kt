package com.example.reality_merge

import android.graphics.Rect
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Handles the "reality_merge/gesture_exclusion" channel so Dart can
/// reserve a strip of the screen (e.g. the left edge, for the
/// Explore-tab drawer) from Android's gesture-navigation back swipe.
/// Without this, a swipe starting near the left edge on gesture-nav
/// devices is intercepted by the OS as "go back" before it ever
/// reaches Flutter's Drawer edge-drag recognizer.
class MainActivity : FlutterActivity() {
    private val channelName = "reality_merge/gesture_exclusion"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setLeftEdgeExclusion" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        setLeftEdgeExclusion(enabled)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun setLeftEdgeExclusion(enabled: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val decorView = window?.decorView ?: return
        if (!enabled) {
            decorView.systemGestureExclusionRects = emptyList()
            return
        }
        // Reserve a strip along the full height of the left edge, wide
        // enough to comfortably win the drag-to-open-drawer gesture.
        val width = decorView.width
        val height = decorView.height
        if (width <= 0 || height <= 0) {
            // Layout hasn't happened yet — try again next frame.
            decorView.post { setLeftEdgeExclusion(true) }
            return
        }
        val exclusionWidthPx = (40 * resources.displayMetrics.density).toInt()
        decorView.systemGestureExclusionRects =
            listOf(Rect(0, 0, exclusionWidthPx, height))
    }
}
