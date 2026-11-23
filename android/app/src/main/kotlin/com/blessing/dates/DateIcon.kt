package com.blessing.dates

import android.app.ActivityManager
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.AdaptiveIconDrawable
import android.os.Build
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import java.io.File
import java.io.InputStream
import java.lang.ref.WeakReference
import java.util.Calendar
import java.util.TimeZone
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.ZipFile

/**
 * Keeps the launcher icon on today's date: the weekday in red over the day
 * of the month, in the phone's own time zone.
 *
 * Android has no call to change an app's icon. Google's and Samsung's
 * calendars get a live date only because their own home screens carry code
 * for those apps alone. Any other app switches launcher entries: the
 * manifest carries one activity-alias per weekday and date, 217 of them, all
 * off, and the app switches on today's and off the rest (tool/date_icons.py
 * writes the aliases and their icons). Telegram's and Signal's icon choosers
 * do the same.
 *
 * ONLY ON HOME SCREENS THAT KEEP A PINNED ICON ([FOLLOWING_HOMES]). Read
 * from each home screen's own code (2026-11-23): when the entry a pinned
 * icon points at is switched off and another is on, Google's (Launcher3
 * PackageUpdatedTask.updateWorkspaceItemIntent), Samsung's One UI Home
 * (PackageEventOperator.replaceComponent) and Motorola's re-point the
 * icon in place, in folders and the dock too, and save it, so it is still
 * there after the home screen restarts. vivo's re-points it only when the
 * change arrives in one piece while it is running: its start-up load maps
 * a stale entry through getApplicationEnabledSetting(class name), which
 * throws for an alias, and then deletes the icon (com.bbk.launcher2
 * LauncherLoadManager), so it keeps the static icon. Xiaomi's HyperOS home
 * (AllAppsList.updatePackage: "will be removed due to app component name
 * change") and Oppo/OnePlus/realme's ColorOS home (OplusPackageUpdatedTask:
 * deleteAndBindComponentsRemoved) DELETE it, every day. So any home screen
 * not proven to keep it gets the static icon: a fixed icon beats one that
 * leaves the home screen at midnight.
 *
 * Duolingo switches the same way. Its shipped app (read 2026-11-23) has
 * 216 launcher aliases for its streak icons and switches them daily from the
 * background, with the same calls as here, on every phone except Sony on
 * Android 10 ([STATIC_ON]). Google's home screen re-points a pinned icon to
 * the entry that is now on, in place (Launcher3
 * PackageUpdatedTask.updateWorkspaceItemIntent; seen on a device). The one
 * Samsung failure on record, a second icon in the drawer (Pocket Casts,
 * GitHub PR 5609), came from an app whose real activity kept its own
 * launcher entry; here exactly one entry is ever on. Some home screens may
 * show the old icon a moment before they reload; none is dropped.
 *
 * The rules that keep a switch from going wrong:
 *  - Today's entry is switched ON before any other is switched off (in one
 *    call on Android 13+), so there is never a moment with no entry: a home
 *    screen that sees the app with none drops its icon.
 *  - Nothing is touched that is already right; each change makes every home
 *    screen reload the app.
 *  - Never while the app is on screen: some home screens throw the user out
 *    to the home screen when the app they are in changes entries. The app
 *    switches as it leaves the screen instead (DatesActivity.onStop).
 *  - DONT_KILL_APP, and the real activity (DatesActivity) is never touched.
 *  - The task is never named after a date entry: Android drops a task from
 *    Recents when the entry that opened it is switched off, so the entries
 *    open DateEntryActivity, which re-roots the task on DatesActivity, and
 *    Recents gets today's icon from [withTodaysIcon] instead.
 *  - Below Android 10 the static entry stays. Android 8 and 9's home
 *    screens DELETE a pinned icon whose entry is switched off (Launcher3
 *    android-9.0.0_r1 PackageUpdatedTask: deleteAndBindComponentsRemoved;
 *    the re-pointing came in Android 10), and announce a change only 10 s
 *    later (PackageManagerService BROADCAST_DELAY, 1 s from Android 10).
 *    Firefox saw exactly this on a Pixel 3 XL (9) and a Galaxy S9 (8)
 *    and turned its icon chooser off below Android 10 (Mozilla bugs
 *    1982269, 1983768). Below 8 there are no adaptive icons at all.
 *
 * When it runs: at local midnight (an alarm, re-booked every run), when the
 * clock or time zone changes, after a reboot or an app update, and when the
 * app leaves the screen, which also heals whatever a missed alarm left. The
 * alarm is exact where Android allows it; elsewhere it may turn over a few
 * minutes after midnight (see [nextAlarm]), never on a wrong date.
 */
object DateIcon {
    private const val TAG = "DateIcon"
    private const val PKG = "com.blessing.dates"
    const val ACTION_MIDNIGHT = "$PKG.DATE_ICON_MIDNIGHT"

    /**
     * The static entry, on by default. It keeps the name the app's launcher
     * activity always had, so icons pinned by an older version stay put.
     */
    const val DEFAULT_ALIAS = "$PKG.MainActivity"

    /**
     * Phones where the icon stays static: Sony on Android 10 and 11.
     * Android 10 is Duolingo's own rule, read from its shipped app (2026-11-23): it
     * switches launcher entries the same way for its streak icons, daily,
     * from the background, on every other brand; it seems to accept that
     * Xiaomi's and ColorOS's home screens move or drop the pinned icon,
     * which [FOLLOWING_HOMES] does not. Android 11 is added for an open Firefox
     * report of a second icon that cannot be removed on a Sony Xperia 5 II
     * (Mozilla bug 2020161). Brand names as Build.MANUFACTURER reports
     * them, compared without case.
     */
    private val STATIC_ON = mapOf("sony" to setOf(Build.VERSION_CODES.Q, Build.VERSION_CODES.R))

    /** Weekday names in the alias names, Monday first (tool/date_icons.py). */
    val WEEKDAYS = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")

    /** Every date alias, in the order the generator writes them. */
    val DATE_ALIASES: List<String> =
        WEEKDAYS.flatMap { wd -> (1..31).map { day -> "$PKG.Date$wd$day" } }

    private val worker = Executors.newSingleThreadScheduledExecutor()

    /** The alias for the date [cal] is on, in [cal]'s own time zone. */
    fun aliasFor(cal: Calendar): String {
        // Calendar.SUNDAY = 1 .. SATURDAY = 7; the list starts on Monday.
        val wd = WEEKDAYS[(cal.get(Calendar.DAY_OF_WEEK) + 5) % 7]
        return "$PKG.Date$wd${cal.get(Calendar.DAY_OF_MONTH)}"
    }

    /**
     * The hidden, always-on entry the app's task is opened through on the
     * date [cal] is on (DateEntryActivity): Recents draws its icon.
     */
    fun taskAliasFor(cal: Calendar): String = aliasFor(cal).replace("$PKG.Date", "$PKG.Task")

    /** Every task entry, in the generator's order. */
    val TASK_ALIASES: List<String> =
        WEEKDAYS.flatMap { wd -> (1..31).map { day -> "$PKG.Task$wd$day" } }

    /**
     * Home screens whose code re-points a pinned icon to the entry now on
     * (see the class doc), each from the first Android version whose build
     * was read: AOSP's from its android-10 tag on; Pixel's builds for
     * Android 13 to 16, and 10 to 12 share AOSP's code; Samsung's One UI
     * 3.1 (Android 11) to 8; Motorola's for Android 16. Every other home
     * screen or older version, including any not yet read, keeps the
     * static icon.
     */
    val FOLLOWING_HOMES: Map<String, Int> = mapOf(
        "com.google.android.apps.nexuslauncher" to Build.VERSION_CODES.Q,
        "com.android.launcher3" to Build.VERSION_CODES.Q,
        "com.sec.android.app.launcher" to Build.VERSION_CODES.R,
        "com.motorola.launcher3" to 36,
        // Read in their builds' bytecode (2026-11-23): each takes AOSP's
        // re-point path. Nothing OS 2 to 4; Xperia's com.sonymobile.launcher
        // 10 and 15 (Sony 10/11 stay static by [STATIC_ON]; the older
        // com.sonymobile.home deletes the icon and is left out).
        "com.nothing.launcher" to Build.VERSION_CODES.Q,
        "com.sonymobile.launcher" to Build.VERSION_CODES.Q,
        // These two also put an icon on home for a NEWLY enabled entry when
        // the on and the off reach them as two broadcasts (the icon would
        // move to the last page), so only from Android 13, where [apply]
        // switches both in one call. Asus read for Android 12 and 15, Honor
        // (MagicOS) for 12 and 14. Huawei re-points too, but its 14.x builds
        // report every entry change to Huawei's security service, so it
        // stays off.
        "com.asus.launcher" to Build.VERSION_CODES.TIRAMISU,
        "com.hihonor.android.launcher" to Build.VERSION_CODES.TIRAMISU,
        // Transsion: HiOS (Tecno) and XOS (Infinix) re-point in place from
        // the builds read below ([MIN_HOME_BUILD]); their older builds are a
        // different fork that adds a second icon or deletes it.
        "com.transsion.hilauncher" to Build.VERSION_CODES.VANILLA_ICE_CREAM,
        "com.transsion.XOSLauncher" to Build.VERSION_CODES.VANILLA_ICE_CREAM,
    )

    /**
     * Home screens trusted only from a given build (versionCode): the first
     * build whose code was read. An older build, or one whose version cannot
     * be read, keeps the static icon.
     */
    val MIN_HOME_BUILD: Map<String, Long> = mapOf(
        "com.transsion.hilauncher" to 150503039L, // HiOS 15.5.3.039
        "com.transsion.XOSLauncher" to 150602067L, // XOS 15.6.2.067
    )

    /** AOSP's home screen, which white-label phones ship in old forks. */
    private const val LAUNCHER3 = "com.android.launcher3"

    /**
     * Stands in for an [LAUNCHER3] whose code predates the re-point path: not
     * in [FOLLOWING_HOMES], so the icon stays static there.
     */
    private const val OLD_LAUNCHER3 = "$LAUNCHER3#old"

    /**
     * Class names only a Launcher3 with the re-point path carries. AOSP added
     * the path in September 2018 (f9d9df7d3a, "Gracefully fallback to new
     * ComponentName") and renamed ShortcutInfo to WorkspaceItemInfo in March
     * 2019 (9589916418), so a build naming either has it; R8 keeps these
     * names (Pixel, Nothing, Asus, Moto and Sony builds all do).
     */
    private val MODERN_LAUNCHER3_MARKS = listOf(
        "Lcom/android/launcher3/model/data/WorkspaceItemInfo;",
        "Lcom/android/launcher3/WorkspaceItemInfo;",
    ).map { it.toByteArray(Charsets.US_ASCII) }

    /**
     * The entry that should be on: today's, or the static one below Android
     * 10 (see the class doc), on the phones in [STATIC_ON], and under any
     * home screen [home] not in [FOLLOWING_HOMES].
     *
     * Null when the daily icon would run but the home screen is not known
     * ([home] null or blank: none set as default, the chooser would ask, or
     * the lookup failed): then nothing is switched. Going static there would
     * itself be a switch, made under a home screen that may be one of those
     * that delete a pinned icon, and a passing failure would switch twice.
     *
     * [daily] false is the user's opt-out ("Daily date icon" off in
     * Settings): always the static entry, so app pairs, routines and
     * automation apps that name the app's entry keep working.
     */
    fun targetFor(
        manufacturer: String?,
        sdk: Int,
        home: String?,
        cal: Calendar,
        daily: Boolean = true,
    ): String? {
        if (!daily) return DEFAULT_ALIAS
        if (sdk < Build.VERSION_CODES.Q) return DEFAULT_ALIAS
        if (STATIC_ON[manufacturer?.trim()?.lowercase()]?.contains(sdk) == true) return DEFAULT_ALIAS
        val h = home?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val from = FOLLOWING_HOMES[h] ?: return DEFAULT_ALIAS
        return if (sdk >= from) aliasFor(cal) else DEFAULT_ALIAS
    }

    /**
     * [targetFor] on this phone, under its current home screen, and with the
     * user's "Daily date icon" setting: off, the static entry.
     */
    fun target(context: Context, cal: Calendar): String? {
        if (!dailyIcon(context)) return targetFor(null, 0, null, cal, daily = false)
        val home = homePackage(context)
        val checked = when {
            home == LAUNCHER3 -> when (modernLauncher3(context)) {
                true -> home
                false -> OLD_LAUNCHER3
                null -> null // not read yet, or the read failed: switch nothing
            }
            home != null && home in MIN_HOME_BUILD ->
                if (homeBuild(context, home) >= MIN_HOME_BUILD.getValue(home)) home else "$home#old"
            else -> home
        }
        return targetFor(Build.MANUFACTURER, Build.VERSION.SDK_INT, checked, cal)
    }

    /**
     * Whether the installed [LAUNCHER3] is new enough to re-point a pinned
     * icon: a system app built for Android 10+ whose code names one of
     * [MODERN_LAUNCHER3_MARKS]. Read once per launcher build and remembered;
     * null when not yet read and this is the main thread (the read is off
     * it), or when the read failed (tried again next time).
     */
    private fun modernLauncher3(context: Context): Boolean? {
        val info = try {
            context.packageManager.getPackageInfo(LAUNCHER3, 0)
        } catch (e: Exception) {
            return null
        }
        val app = info.applicationInfo ?: return null
        @Suppress("DEPRECATION")
        val key = "${info.versionCode}/${info.lastUpdateTime}"
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (prefs.getString(L3_KEY, null) == key) return prefs.getBoolean(L3_MODERN, false)
        if (Looper.myLooper() == Looper.getMainLooper()) return null
        val modern = try {
            (app.flags and ApplicationInfo.FLAG_SYSTEM) != 0 &&
                app.targetSdkVersion >= Build.VERSION_CODES.Q &&
                codeNames(app, MODERN_LAUNCHER3_MARKS)
        } catch (e: Exception) {
            Log.w(TAG, "Launcher3 read failed", e)
            return null
        }
        prefs.edit().putString(L3_KEY, key).putBoolean(L3_MODERN, modern).apply()
        return modern
    }

    /**
     * The user's "Daily date icon" switch, ON unless turned off. Native is
     * the one owner: Dart reads it at start and writes it through the
     * "com.blessing.dates/date_icon" channel (DatesActivity).
     */
    fun dailyIcon(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(DAILY_KEY, true)

    /**
     * Stores the switch and runs [update]: never a switch while the app is
     * on screen (update defers it), so turning it off goes static once the
     * user leaves (DatesActivity.onStop), and the midnight alarm is booked
     * or, once the static icon is settled, cancelled.
     */
    fun setDailyIcon(context: Context, on: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(DAILY_KEY, on).apply()
        update(context)
    }

    private const val PREFS = "date_icon"
    private const val DAILY_KEY = "daily_icon"
    /** [pkg]'s versionCode; -1 when it cannot be read (treated as too old). */
    private fun homeBuild(context: Context, pkg: String): Long = try {
        val info = context.packageManager.getPackageInfo(pkg, 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else @Suppress("DEPRECATION") info.versionCode.toLong()
    } catch (e: Exception) {
        -1L
    }

    private const val L3_KEY = "launcher3_build"
    private const val L3_MODERN = "launcher3_modern"
    private val DEX_ENTRY = Regex("""classes\d*\.dex""")

    /**
     * Whether [app]'s code holds any of [marks]: the dex files in its APKs,
     * or, for a pre-optimised system app whose APK carries none, the
     * .vdex/.odex beside it (the dex sits in those uncompressed).
     */
    private fun codeNames(app: ApplicationInfo, marks: List<ByteArray>): Boolean {
        var sawCode = false
        val apks = listOfNotNull(app.sourceDir) + (app.splitSourceDirs?.toList() ?: emptyList())
        for (apk in apks) ZipFile(apk).use { zip ->
            for (entry in zip.entries()) {
                if (!entry.name.matches(DEX_ENTRY)) continue
                sawCode = true
                if (zip.getInputStream(entry).use { holds(it, marks) }) return true
            }
        }
        if (sawCode) return false
        val oat = File(File(app.sourceDir).parentFile, "oat")
        val compiled = oat.walkTopDown().maxDepth(2)
            .filter { it.isFile && (it.name.endsWith(".vdex") || it.name.endsWith(".odex")) }
        for (file in compiled) if (file.inputStream().use { holds(it, marks) }) return true
        return false
    }

    /** Whether [input] contains any of [marks], read in chunks. */
    internal fun holds(input: InputStream, marks: List<ByteArray>): Boolean {
        val overlap = marks.maxOf { it.size } - 1
        val buf = ByteArray(1 shl 16)
        var kept = 0
        while (true) {
            val n = input.read(buf, kept, buf.size - kept)
            if (n <= 0) return false
            val end = kept + n
            for (mark in marks) if (indexOf(buf, end, mark) >= 0) return true
            kept = minOf(overlap, end)
            System.arraycopy(buf, end - kept, buf, 0, kept)
        }
    }

    private fun indexOf(buf: ByteArray, end: Int, mark: ByteArray): Int {
        outer@ for (i in 0..end - mark.size) {
            for (j in mark.indices) if (buf[i + j] != mark[j]) continue@outer
            return i
        }
        return -1
    }

    /** Whether [name] is on, given what PackageManager reports for it. */
    fun isOn(name: String, state: Int): Boolean = when (state) {
        PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
        // The manifest's own state: on for the static entry only.
        PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> name == DEFAULT_ALIAS
        else -> false
    }

    /**
     * The switches that put [target] on and every other launcher entry off,
     * in order: [target] on FIRST, so no prefix of the list (a crash part
     * way, below Android 13) ever leaves zero entries on. [on] says which
     * entry is on now; entries already right are left alone.
     */
    fun plan(target: String, on: (String) -> Boolean): List<Pair<String, Boolean>> {
        val changes = mutableListOf<Pair<String, Boolean>>()
        if (!on(target)) changes += target to true
        for (name in listOf(DEFAULT_ALIAS) + DATE_ALIASES) {
            if (name != target && on(name)) changes += name to false
        }
        return changes
    }

    /**
     * The default home screen's package; null when none is set (the chooser
     * would ask) or on any failure. The manifest's HOME query makes it
     * visible on Android 11+.
     */
    private fun homePackage(context: Context): String? = try {
        context.packageManager.resolveActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
            PackageManager.MATCH_DEFAULT_ONLY,
        )?.activityInfo?.packageName?.takeIf { it != "android" }
    } catch (e: Exception) {
        null
    }

    /**
     * The first moment of the next day in [zone], after [nowMs]. Built from
     * the calendar date rather than "now + 24 h", so a day that is 23 or 25
     * hours long (a clock change) still turns over at its own midnight; where
     * a clock change skips midnight itself, the calendar moves to the first
     * time that exists that morning.
     */
    fun nextMidnight(nowMs: Long, zone: TimeZone): Long {
        val c = Calendar.getInstance(zone)
        c.timeInMillis = nowMs
        c.add(Calendar.DAY_OF_YEAR, 1)
        c.set(Calendar.HOUR_OF_DAY, 0)
        c.set(Calendar.MINUTE, 0)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        return c.timeInMillis
    }

    /**
     * Brings the icon to today and books the next midnight, off the UI
     * thread. [switchIcon] false only books the alarm (the app is coming to
     * the screen, where no switch is made). [leaving]: called as the app's
     * screen stops. Android may still count the app as in front for a
     * moment, and the stop may not be a leave at all (a full-screen page
     * opened over it, the screen turning off), so the check waits
     * [LEAVE_SETTLE_MS] and then switches only if no app screen is in front.
     *
     * Where the static icon is settled (on, and no date entry on), the
     * midnight alarm is cancelled: nothing would change at midnight, and a
     * phone whose home screen changes is re-checked the next time the app is
     * left, after a reboot, or when the clock changes.
     */
    fun update(
        context: Context,
        switchIcon: Boolean = true,
        leaving: Boolean = false,
        done: (() -> Unit)? = null,
    ) {
        val app = context.applicationContext
        val job = Runnable {
            var settledStatic = false
            try {
                // Recents carries the icon too: re-apply it while a screen is
                // alive, on that screen's own thread, waited for. Android
                // takes it from a stopped screen (dumpsys shows the bitmap),
                // but Launcher3's Recents shows it only once its own copy is
                // dropped. It keeps one icon per task (TaskKeyLruCache) and
                // drops it only when the task is next opened (lastActiveTime),
                // removed, or the launcher clears its cache. A new task
                // description does not drop it, and neither does this switch:
                // IconProvider reloads only the calendar's and clock's icons.
                // So a Recents card already drawn keeps yesterday's date until
                // the app is opened again; no app call can move it. With the
                // process gone, nothing re-applies it: the root task entry's
                // icon (or the last bitmap set) stays. Done before the switch
                // so the bitmap is in place whenever Recents next reloads.
                if (switchIcon) refreshScreen()
                val target = target(app, Calendar.getInstance())
                if (switchIcon && target != null && !onScreen(app)) apply(app, target)
                if (target == DEFAULT_ALIAS) {
                    val pm = app.packageManager
                    settledStatic = (listOf(DEFAULT_ALIAS) + DATE_ALIASES).all { name ->
                        isOn(name, pm.getComponentEnabledSetting(ComponentName(PKG, name))) == (name == DEFAULT_ALIAS)
                    }
                }
            } catch (e: Exception) {
                // Never let the icon take the app or a broadcast down; the
                // next midnight or the next time the app leaves tries again.
                Log.w(TAG, "icon update failed", e)
            } finally {
                try {
                    if (settledStatic) cancel(app) else schedule(app)
                } catch (e: Exception) {
                    Log.w(TAG, "could not book midnight", e)
                }
                done?.invoke()
            }
        }
        if (leaving) worker.schedule(job, LEAVE_SETTLE_MS, TimeUnit.MILLISECONDS) else worker.execute(job)
    }

    /** How long after the app's screen stops the switch checks it is gone. */
    private const val LEAVE_SETTLE_MS = 1500L

    /**
     * [td], with today's icon added only when Recents would otherwise show
     * the wrong date. [openedAs] is the entry the app's task was opened
     * through. A task opened today through today's task entry already shows
     * today's icon, drawn by Recents in the phone's own style, so [td] goes
     * through untouched. A task still in Recents from an earlier day would
     * show that day: then today's icon is added as a bitmap, which Recents
     * draws smaller, inside a ring, but on the right date. Flutter sets the
     * task's label and colour from Dart with no icon; DatesActivity routes
     * every such call through here. Unchanged where the static icon is the
     * right one (a home screen without the daily icon) or on any failure.
     */
    fun withTodaysIcon(
        context: Context,
        td: ActivityManager.TaskDescription?,
        openedAs: String?,
    ): ActivityManager.TaskDescription? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return td
        return try {
            val today = Calendar.getInstance()
            val target = target(context, today)
            if (target == null || target == DEFAULT_ALIAS) return td
            if (openedAs == taskAliasFor(today)) return td
            val bitmap = taskIcon(context, target) ?: return td
            // A bitmap, not the icon's resource id: Launcher3's Recents
            // reads only an in-memory icon (TaskIconCache) and ignores a
            // resource one, which showed the static icon (seen on Android
            // 17). The bitmap constructor is the one every version reads.
            // Recents sets a bitmap icon on a disc of the task's primary
            // colour (Flutter's is the app's accent: a brown disc around a
            // white square, seen on Android 17). The icon's own background
            // colour makes the disc and the square one white face.
            val face = bitmap.getPixel(1, 1) or 0xFF000000.toInt()
            @Suppress("DEPRECATION")
            ActivityManager.TaskDescription(td?.label, bitmap, face)
        } catch (e: Exception) {
            Log.w(TAG, "task icon failed", e)
            td
        }
    }

    private var cachedIcon: Pair<String, Bitmap>? = null

    /**
     * See [taskIcon]. Measured in Recents on Android 17, before the icon
     * had its margin: at 1.55 the top of the weekday was cut off, 1.35 just
     * cleared it, 1.3 kept a margin. The margin (tool/date_icons.py) shrinks
     * the words to 0.86 and moves them down, so 1.3 / 0.86 keeps the same
     * size and clearance.
     */
    private const val RECENTS_ZOOM = 1.5f

    /**
     * [alias]'s icon as a bitmap at the launcher's icon size, for Recents.
     * Kept for the day: Dart sets the task description on every title
     * rebuild.
     */
    private fun taskIcon(context: Context, alias: String): Bitmap? {
        cachedIcon?.let { (name, bmp) -> if (name == alias) return bmp }
        val res = context.packageManager.getActivityInfo(
            ComponentName(PKG, alias),
            PackageManager.MATCH_DISABLED_COMPONENTS,
        ).icon
        if (res == 0) return null
        val drawable = context.getDrawable(res) ?: return null
        val size = context.getSystemService(ActivityManager::class.java)
            ?.launcherLargeIconSize?.takeIf { it > 0 } ?: 192
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        if (drawable is AdaptiveIconDrawable) {
            // Recents treats any bitmap as an old-style icon: it shrinks a
            // round one into a dark ring (seen on Android 17). A full-bleed
            // square is scaled to fill the phone's own icon shape instead,
            // so the icon is drawn edge to edge, unmasked. Recents then
            // shrinks the square to about 70% of its disc, so it is drawn
            // zoomed by RECENTS_ZOOM (the margin cut off is only the plain
            // background), which brings the date back to the size the home
            // screen shows. At zoom 1 the visible 72 of the icon's 108 dp
            // would fill the square.
            val out = ((size * 1.5f * RECENTS_ZOOM - size) / 2).toInt()
            for (layer in listOfNotNull(drawable.background, drawable.foreground)) {
                layer.setBounds(-out, -out, size + out, size + out)
                layer.draw(canvas)
            }
        } else {
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
        }
        cachedIcon = alias to bmp
        return bmp
    }

    /** The app's screen, told when the day turns so Recents follows. */
    @Volatile
    var screen: WeakReference<DatesActivity>? = null

    /** Has a live app screen re-apply its task icon; waits up to a second. */
    private fun refreshScreen() {
        val s = screen?.get() ?: return
        if (s.isDestroyed) return
        val done = CountDownLatch(1)
        s.runOnUiThread {
            try {
                if (!s.isDestroyed) s.refreshTaskIcon()
            } finally {
                done.countDown()
            }
        }
        done.await(1, TimeUnit.SECONDS)
    }

    /**
     * Whether one of the app's screens is in front of the user right now: in
     * front, and the screen on. With the screen off nobody is looking, and
     * the switch is safe (the task never hangs on a date entry).
     */
    private fun onScreen(context: Context): Boolean {
        val me = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(me)
        if (me.importance > ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) return false
        return context.getSystemService(PowerManager::class.java)?.isInteractive != false
    }

    private fun apply(context: Context, target: String) {
        val pm = context.packageManager
        // The target ON first, then every other entry that is on, off: never
        // zero entries, which also heals a state somehow left with none.
        val changes = plan(target) { name ->
            isOn(name, pm.getComponentEnabledSetting(ComponentName(PKG, name)))
        }
        if (changes.isEmpty()) return
        fun state(enabled: Boolean) =
            if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // One call: Android applies and announces it as a single change.
            // SYNCHRONOUS writes it to disk before returning (this runs off
            // the UI thread), so a power cut cannot bring back yesterday's.
            // Every entry carries the same flags: mixed ones throw.
            try {
                pm.setComponentEnabledSettings(changes.map { (name, enabled) ->
                    PackageManager.ComponentEnabledSetting(
                        ComponentName(PKG, name), state(enabled),
                        PackageManager.DONT_KILL_APP or PackageManager.SYNCHRONOUS,
                    )
                })
                return
            } catch (e: RuntimeException) {
                // Never seen; if some build refuses the batch, one by one,
                // in the same order, still never leaves zero entries on.
                Log.w(TAG, "batch switch refused, switching one by one", e)
            }
        }
        for ((name, enabled) in changes) {
            pm.setComponentEnabledSetting(ComponentName(PKG, name), state(enabled), PackageManager.DONT_KILL_APP)
        }
    }

    /**
     * When the next alarm should go off, from [nowMs] with [midnightMs] next.
     *
     * Without exact alarms Android may deliver an alarm up to three quarters
     * of its lead time late (capped at an hour): booked straight for a
     * midnight 14 hours away, the icon could turn over at 1 am. So the
     * alarm walks there in halves: each one books the next at half the time
     * left, which by the same rule can never land past midnight, until less
     * than [FINAL_LEAD_MS] is left. Only that last one aims at midnight:
     * Android may hold it at most three quarters of that (about a quarter
     * of an hour) and on an awake phone delivers it on time. About eight
     * wake-ups a day, each a few reads, never closer than 11 minutes apart
     * (Doze lets an app fire such alarms at most every 9).
     */
    fun nextAlarm(nowMs: Long, midnightMs: Long, exact: Boolean): Long {
        val left = midnightMs - nowMs
        if (exact || left <= FINAL_LEAD_MS) return midnightMs + 1000
        return nowMs + left / 2
    }

    private const val FINAL_LEAD_MS = 22L * 60 * 1000

    /**
     * How long after midnight the backstop alarm aims. It only ever fires if
     * the exact alarm was lost: revoking "Alarms & reminders" cancels an
     * app's exact alarms and sends it nothing (the state-changed broadcast
     * comes only on a grant), which would leave the icon on a past date
     * until the app is next opened. Inexact alarms survive that. The exact
     * one re-books the backstop before it can fire.
     */
    private const val BACKSTOP_MS = 30L * 60 * 1000

    private fun alarm(context: Context, code: Int): PendingIntent = PendingIntent.getBroadcast(
        context,
        code,
        Intent(context, DateIconReceiver::class.java).setAction(ACTION_MIDNIGHT),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun schedule(context: Context) {
        val am = context.getSystemService(AlarmManager::class.java) ?: return
        val pi = alarm(context, 0)
        // Exact where Android allows it without asking (8 to 13), or where
        // the user has allowed "Alarms & reminders"; never asked for here.
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
        val now = System.currentTimeMillis()
        val midnight = nextMidnight(now, TimeZone.getDefault())
        val at = nextAlarm(now, midnight, exact)
        // Re-booking replaces the last one (same PendingIntent).
        if (exact) {
            try {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, midnight + BACKSTOP_MS, alarm(context, 1))
                return
            } catch (e: SecurityException) {
                // The grant was withdrawn between the check and the call.
            }
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, nextAlarm(now, midnight, false), pi)
        } else {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
        // The inexact walk is its own backstop.
        am.cancel(alarm(context, 1))
    }

    /** Both alarms off: the static icon is settled and nothing turns over. */
    private fun cancel(context: Context) {
        val am = context.getSystemService(AlarmManager::class.java) ?: return
        am.cancel(alarm(context, 0))
        am.cancel(alarm(context, 1))
    }
}

/** Midnight, a clock or time-zone change, a reboot or an app update. */
class DateIconReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_TIMEZONE_CHANGED) {
            // Android hands the new zone to the broadcast and to this
            // process's default on separate paths; take it from the
            // broadcast, or a date-line crossing could book the old day.
            intent.getStringExtra("time-zone")?.let { TimeZone.setDefault(TimeZone.getTimeZone(it)) }
        }
        val pending = goAsync()
        // Finished when the update is done, or after FINISH_BY_S whatever
        // the update is doing: on a starved phone (seen on an emulator at
        // load 100) a broadcast still held at 10 s is an ANR. The update
        // itself carries on, and the next run heals what it left.
        val finished = AtomicBoolean(false)
        val finish = { if (finished.compareAndSet(false, true)) pending.finish() }
        guard.schedule(finish, FINISH_BY_S, TimeUnit.SECONDS)
        DateIcon.update(context) { finish() }
    }

    private companion object {
        const val FINISH_BY_S = 7L
        val guard = Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "DateIconGuard").apply { isDaemon = true }
        }
    }
}
