package com.blessing.dates

import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Edge to edge from the first frame, before Dart sets the same: the
        // app draws under clear system bars and pads for them itself, with no
        // grey scrim behind 3-button navigation.
        //
        // setDecorFitsSystemWindows is what makes this true on Android 9 and
        // older: Dart's SystemUiMode.edgeToEdge does nothing below Android 10,
        // so without it the app stopped short of both bars. A white strip
        // showed under a dark app, and headings sat cramped under the status
        // bar because the status bar padding read as zero.
        WindowCompat.setDecorFitsSystemWindows(window, false)
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

    override fun onPostResume() {
        super.onPostResume()
        // Flutter's PlatformPlugin rewrites the decor flags on every resume to
        // LAYOUT_STABLE | LAYOUT_FULLSCREEN, dropping LAYOUT_HIDE_NAVIGATION
        // below Android 10 (its edge-to-edge mode returns early there). The
        // app then stopped above an opaque white navigation bar. Put the flag
        // back after it. Seen on an Android 9 emulator, 360 x 640.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            val decor = window.decorView
            @Suppress("DEPRECATION")
            decor.systemUiVisibility = decor.systemUiVisibility or
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            // Then ask for the insets again once the window is laid out.
            // Below Android 11 Flutter guesses "keyboard" when the bottom
            // inset is 18% or more of the root view height, and on the
            // first pass that height is still 0: the 48 dp nav bar reads
            // as a keyboard and the Scaffold shrinks, clipping the page
            // above an empty strip. Light mode hid it (setting the light
            // nav-icon flag re-sends the insets); dark kept the wrong value.
            decor.post { decor.requestApplyInsets() }
        }
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
