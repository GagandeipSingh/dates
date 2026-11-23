package com.blessing.dates

import android.app.ActivityManager
import android.os.Build
import android.os.Bundle
import java.lang.ref.WeakReference
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class DatesActivity : FlutterActivity() {
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
        // Recents shows today's date from the first frame, before Dart
        // sets the task's title.
        DateIcon.screen = WeakReference(this)
        refreshTaskIcon()
    }

    /**
     * The "Daily date icon" switch in Settings. Native holds the value
     * (DateIcon.dailyIcon); Dart reads it at start and writes it here.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DATE_ICON_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDailyIcon" -> result.success(DateIcon.dailyIcon(this))
                    "setDailyIcon" -> {
                        val on = call.argument<Boolean>("on")
                        if (on == null) {
                            result.error("bad_args", "on is required", null)
                        } else {
                            DateIcon.setDailyIcon(this, on)
                            result.success(DateIcon.dailyIcon(this))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        if (DateIcon.screen?.get() === this) DateIcon.screen = null
        super.onDestroy()
    }

    /** The task description Dart last set (title and colour), if any. */
    private var dartTask: ActivityManager.TaskDescription? = null

    /**
     * Flutter sets the task's title and colour with no icon; keep both
     * and add today's date icon, so Recents matches the home screen.
     */
    override fun setTaskDescription(taskDescription: ActivityManager.TaskDescription?) {
        dartTask = taskDescription
        refreshTaskIcon()
    }

    /** Re-applies the task description with today's icon. */
    fun refreshTaskIcon() {
        val openedAs = intent?.component?.className
        (DateIcon.withTodaysIcon(this, dartTask, openedAs) ?: dartTask)?.let { super.setTaskDescription(it) }
    }

    override fun onPostResume() {
        super.onPostResume()
        // The icon shows today's date. Coming to the screen only books the
        // midnight alarm; the switch itself is made as the app leaves.
        DateIcon.update(this, switchIcon = false)
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

    override fun onStop() {
        super.onStop()
        // Leaving the screen: put the icon on today's date, in case a
        // midnight alarm was held back or missed (never while on screen).
        // A stop for a rotation or other configuration change is not a
        // leave: the activity comes straight back.
        if (!isChangingConfigurations) DateIcon.update(this, leaving = true)
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

    private companion object {
        const val DATE_ICON_CHANNEL = "com.blessing.dates/date_icon"
    }
}
