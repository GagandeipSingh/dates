package com.blessing.dates

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Edge to edge from the first frame, before Dart sets the same: the
        // app draws under clear system bars and pads for them itself, with no
        // grey scrim behind 3-button navigation.
        @Suppress("DEPRECATION")
        window.statusBarColor = android.graphics.Color.TRANSPARENT
        @Suppress("DEPRECATION")
        window.navigationBarColor = android.graphics.Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
        lockHighRefreshRate()
    }

    private fun lockHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            }
            display?.let { d ->
                val highestMode = d.supportedModes.maxByOrNull { it.refreshRate }
                highestMode?.let { mode ->
                    val layoutParams = window.attributes
                    layoutParams.preferredDisplayModeId = mode.modeId
                    window.attributes = layoutParams
                }
            }
        }
    }
}
