package com.blessing.dates

import java.io.File
import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DateIconTest {
    private fun cal(zone: String, y: Int, m: Int, d: Int, h: Int = 12): Calendar =
        Calendar.getInstance(TimeZone.getTimeZone(zone)).apply {
            clear()
            set(y, m - 1, d, h, 0, 0)
        }

    @Test
    fun aliasNamesTheWeekdayAndDate() {
        assertEquals("com.blessing.dates.DateSun22", DateIcon.aliasFor(cal("UTC", 2026, 11, 22)))
        assertEquals("com.blessing.dates.DateWed28", DateIcon.aliasFor(cal("UTC", 2026, 1, 28)))
        assertEquals("com.blessing.dates.DateMon1", DateIcon.aliasFor(cal("UTC", 2026, 6, 1)))
        assertEquals("com.blessing.dates.DateSat31", DateIcon.aliasFor(cal("UTC", 2026, 10, 31)))
    }

    @Test
    fun theSameInstantIsADifferentDayInAnotherZone() {
        // 20:00 UTC on Sun 22 Nov is already Mon 23 Nov in India.
        val utc = cal("UTC", 2026, 11, 22, 20)
        val india = Calendar.getInstance(TimeZone.getTimeZone("Asia/Kolkata"))
        india.timeInMillis = utc.timeInMillis
        assertEquals("com.blessing.dates.DateSun22", DateIcon.aliasFor(utc))
        assertEquals("com.blessing.dates.DateMon23", DateIcon.aliasFor(india))
    }

    /**
     * From every hour of two years, in zones with and without clock changes
     * (including Chile and Paraguay, where a change skips midnight itself, and
     * Lord Howe's half-hour shift): the alarm lands on the NEXT day, within a
     * day and a bit, and never on the day it was booked from.
     */
    @Test
    fun nextMidnightIsAlwaysTheStartOfTomorrow() {
        val zones = listOf(
            "Asia/Kolkata", "Europe/Berlin", "America/New_York", "America/Santiago",
            "America/Asuncion", "Australia/Lord_Howe", "Pacific/Apia", "UTC",
        )
        for (id in zones) {
            val zone = TimeZone.getTimeZone(id)
            val start = cal(id, 2026, 1, 1, 0).timeInMillis
            var now = start
            while (now < start + 730L * 24 * 3600 * 1000) {
                val at = DateIcon.nextMidnight(now, zone) + 1000
                val today = Calendar.getInstance(zone).apply { timeInMillis = now }
                val then = Calendar.getInstance(zone).apply { timeInMillis = at }
                val tomorrow = (today.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, 1) }
                assertEquals("$id from ${today.time}", tomorrow.get(Calendar.DAY_OF_YEAR), then.get(Calendar.DAY_OF_YEAR))
                assertTrue("$id early", at > now)
                assertTrue("$id late", at - now <= 26L * 3600 * 1000)
                assertTrue("$id not near midnight", then.get(Calendar.HOUR_OF_DAY) <= 1)
                now += 3600L * 1000
            }
        }
    }

    /**
     * The alarm chain, against Android's worst case for an inexact alarm
     * (three quarters of its lead late, at most an hour): from every minute
     * of a day, no step lands past midnight, steps are at least 9 minutes
     * apart (Doze's limit), and the last lands within 17 minutes of it.
     */
    @Test
    fun theAlarmChainNeverOvershootsMidnight() {
        val midnight = 1_000_000_000_000L
        for (minute in 0 until 24 * 60) {
            var now = midnight - (minute + 1) * 60_000L
            var steps = 0
            while (true) {
                val at = DateIcon.nextAlarm(now, midnight, exact = false)
                assertTrue(at > now)
                val late = minOf((at - now) * 3 / 4, 3_600_000L)
                val fired = at + late
                if (at > midnight) {
                    assertTrue("final ${fired - midnight} ms late", fired - midnight <= 17 * 60_000L)
                    break
                }
                assertTrue("a step overshot midnight", fired < midnight)
                assertTrue("steps too close", at - now >= 9 * 60_000L)
                now = fired
                steps++
                assertTrue(steps < 20)
            }
        }
        assertEquals(midnight + 1000, DateIcon.nextAlarm(midnight - 9 * 3_600_000L, midnight, exact = true))
    }

    // Run from android/app (Gradle's working directory for unit tests).
    private val main = File("src/main")
    private val manifest by lazy { File(main, "AndroidManifest.xml").readText() }

    @Test
    fun everyDateHasItsLauncherEntryAndIcon() {
        assertEquals(217, DateIcon.DATE_ALIASES.size)
        assertEquals(217, DateIcon.DATE_ALIASES.toSet().size)
        for (full in DateIcon.DATE_ALIASES) {
            val name = full.removePrefix("com.blessing.dates.")
            val block = Regex(
                """<activity-alias\s+android:name="\.$name"(.*?)</activity-alias>""",
                RegexOption.DOT_MATCHES_ALL,
            ).find(manifest)?.groupValues?.get(1)
            assertTrue("no alias $name", block != null)
            assertTrue("$name must start off", block!!.contains("""android:enabled="false""""))
            assertTrue("$name must open DateEntryActivity", block.contains("""android:targetActivity=".DateEntryActivity""""))
            assertTrue("$name must be a launcher entry", block.contains("android.intent.category.LAUNCHER"))
            val icon = Regex("""android:icon="@mipmap/(\w+)"""").find(block)!!.groupValues[1]
            assertTrue("$icon missing", File(main, "res/mipmap-anydpi-v26/$icon.xml").exists())
        }
        for (wd in DateIcon.WEEKDAYS) {
            assertTrue(File(main, "res/drawable/date_wd_${wd.lowercase()}.xml").exists())
        }
        for (day in 1..31) assertTrue(File(main, "res/drawable/date_day_$day.xml").exists())
    }

    @Test
    fun exactlyOneEntryIsOnAtInstall() {
        // The static entry, and only it: two would put two icons in the drawer.
        val launchers = Regex("""<activity(?:-alias)?\s[^>]*?(?:/>|[^/]>.*?</activity(?:-alias)?>)""", RegexOption.DOT_MATCHES_ALL)
            .findAll(manifest).map { it.value }.filter { it.contains("category.LAUNCHER") }.toList()
        val on = launchers.filter { !it.contains("""android:enabled="false"""") }
        assertEquals(1, on.size)
        // Named .MainActivity, the launcher activity's name before the date
        // icons: icons pinned by older versions point at this name.
        assertTrue(on.single().contains("""android:name=".MainActivity""""))
        assertEquals("com.blessing.dates.MainActivity", DateIcon.DEFAULT_ALIAS)
        // The real activity is not a launcher entry, or it would be a second
        // icon; and it is never one of the entries switched off.
        val real = Regex("""<activity\s+android:name="\.DatesActivity".*?</activity>""", RegexOption.DOT_MATCHES_ALL)
            .find(manifest)!!.value
        assertFalse(real.contains("category.LAUNCHER"))
        assertFalse(DateIcon.DATE_ALIASES.any { it.endsWith(".DatesActivity") })
    }

    /**
     * Recents keeps the app across a switch: a task named after an entry
     * that is switched off is dropped, so the date entries open the
     * hand-off, which restarts DatesActivity as the root of the SAME task
     * (same non-empty affinity: an empty one opens a second task).
     */
    @Test
    fun theTaskIsNeverNamedAfterADateEntry() {
        fun activity(name: String) = Regex(
            """<activity\s+android:name="\.$name".*?(?:/>|</activity>)""",
            RegexOption.DOT_MATCHES_ALL,
        ).find(manifest)!!.value
        fun affinity(block: String) =
            Regex("""android:taskAffinity="([^"]*)"""").find(block)?.groupValues?.get(1)
        val real = activity("DatesActivity")
        val entry = activity("DateEntryActivity")
        assertTrue("an empty affinity opens a second task", !affinity(real).isNullOrEmpty())
        assertEquals(affinity(real), affinity(entry))
        assertTrue(entry.contains("""android:exported="false""""))
        assertTrue(entry.contains("Theme.NoDisplay"))
        // Without it the task keeps the entry's name for good.
        assertTrue(entry.contains("""android:relinquishTaskIdentity="true""""))
        // The static entry is switched off too, the first time the app is
        // left after an install or update, so it opens the hand-off as well.
        val static = Regex("""<activity-alias\s+android:name="\.MainActivity".*?</activity-alias>""", RegexOption.DOT_MATCHES_ALL)
            .find(manifest)!!.value
        assertTrue(static.contains("""android:targetActivity=".DateEntryActivity""""))
        // The hand-off re-roots the task and never passes the incoming
        // intent on (Play's intent-redirection check).
        val src = File(main, "kotlin/com/blessing/dates/DateEntryActivity.kt").readText()
        for (flag in listOf("FLAG_ACTIVITY_NEW_TASK", "FLAG_ACTIVITY_CLEAR_TASK", "FLAG_ACTIVITY_RESET_TASK_IF_NEEDED", "isTaskRoot")) {
            assertTrue(flag, src.contains(flag))
        }
        assertFalse("must not forward the incoming intent", src.contains("Intent(intent)"))
        assertTrue("opens through today's task entry", src.contains("DateIcon.taskAliasFor("))
        // Where nothing is ever switched off, straight to the real activity.
        assertTrue(src.contains("DateIcon.target(this, "))
        assertTrue(src.contains("DatesActivity::class.java.name"))
    }

    /**
     * Every icon carries the same margin as the static one, foreground and
     * themed (monochrome) alike, so the icon never changes size at a switch
     * (tool/date_icons.py writes both; flutter_launcher_icons would reset
     * the static one to an even inset).
     */
    @Test
    fun everyIconHasTheStaticIconsMargin() {
        fun insets(xml: String) = Regex("""android:inset(Left|Top|Right|Bottom)="([^"]+)"""")
            .findAll(xml).map { it.groupValues[1] + "=" + it.groupValues[2] }.toList()
        val static = insets(File(main, "res/mipmap-anydpi-v26/ic_launcher.xml").readText())
        assertEquals("foreground and monochrome, four sides each", 8, static.size)
        assertFalse("the words need a margin", static.any { it.endsWith("=0%") })
        for (wd in DateIcon.WEEKDAYS) for (day in 1..31) {
            val icon = File(main, "res/mipmap-anydpi-v26/ic_date_${wd.lowercase()}_$day.xml").readText()
            assertEquals("ic_date_${wd.lowercase()}_$day", static, insets(icon))
        }
    }

    /**
     * The hidden task entries: one per date, always on (the switch must never
     * touch them, or Recents drops the task), invisible (no intent filter,
     * not exported), opening DatesActivity, with that date's icon.
     */
    @Test
    fun everyDateHasAHiddenTaskEntry() {
        assertEquals(217, DateIcon.TASK_ALIASES.toSet().size)
        assertEquals("com.blessing.dates.TaskWed25", DateIcon.taskAliasFor(cal("UTC", 2026, 11, 25)))
        assertEquals("com.blessing.dates.TaskMon1", DateIcon.taskAliasFor(cal("UTC", 2026, 6, 1)))
        for (full in DateIcon.TASK_ALIASES) {
            val name = full.removePrefix("com.blessing.dates.")
            val block = Regex("""<activity-alias\s+android:name="\.$name"(.*?)/>""", RegexOption.DOT_MATCHES_ALL)
                .find(manifest)?.groupValues?.get(1)
            assertTrue("no alias $name", block != null)
            assertFalse("$name must stay on", block!!.contains("android:enabled"))
            assertFalse("$name must be hidden", block.contains("intent-filter"))
            assertTrue(block.contains("""android:exported="false""""))
            assertTrue(block.contains("""android:targetActivity=".DatesActivity""""))
            val date = name.removePrefix("Task")
            val icon = "ic_date_${date.take(3).lowercase()}_${date.drop(3)}"
            assertTrue("$name icon", block.contains("@mipmap/$icon\""))
        }
        // The switch only ever touches the static entry and the date entries.
        val src = File(main, "kotlin/com/blessing/dates/DateIcon.kt").readText()
        assertTrue(src.contains("listOf(DEFAULT_ALIAS) + DATE_ALIASES"))
        assertFalse(Regex("""TASK_ALIASES\s*\)""").containsMatchIn(src.substringAfter("private fun apply(")))
    }

    /**
     * The day's turn re-applies the task icon from a live screen, before the
     * switch, and the screen is only forgotten when it is destroyed (never
     * on stop): a stopped screen is the one that still has to set it.
     */
    @Test
    fun theDayTurnReappliesTheTaskIconBeforeTheSwitch() {
        val src = File(main, "kotlin/com/blessing/dates/DateIcon.kt").readText()
        val job = src.substringAfter("fun update(").substringBefore("private const val LEAVE_SETTLE_MS")
        val refresh = job.indexOf("if (switchIcon) refreshScreen()")
        val switch = job.indexOf("apply(app, target)")
        assertTrue("refresh missing", refresh >= 0)
        assertTrue("switch missing", switch >= 0)
        assertTrue("refresh must come before the switch", refresh < switch)
        val activity = File(main, "kotlin/com/blessing/dates/DatesActivity.kt").readText()
        assertTrue(activity.contains("DateIcon.screen = WeakReference(this)"))
        val stop = activity.substringAfter("override fun onStop()").substringBefore("private fun ")
        assertFalse("onStop must not drop the screen", stop.contains("DateIcon.screen = null"))
        val destroy = activity.substringAfter("override fun onDestroy()").substringBefore("}\n")
        assertTrue(destroy.contains("DateIcon.screen = null"))
    }

    /**
     * The daily icon only under home screens whose code keeps a pinned icon
     * through a switch, from Android 10 (Android 8 and 9's delete it), and
     * never on Sony on Android 10 (Duolingo's exception) or 11 (a Firefox
     * report). Xiaomi's and ColorOS's home screens delete the pinned icon,
     * and any home screen not yet read is treated the same.
     */
    @Test
    fun theDateIconRunsOnlyUnderHomeScreensThatKeepThePinnedIcon() {
        val day = cal("UTC", 2026, 11, 23)
        val today = "com.blessing.dates.DateMon23"
        // Each home screen from the first Android version whose code was read.
        val since = mapOf(
            "com.google.android.apps.nexuslauncher" to 29, "com.android.launcher3" to 29,
            "com.sec.android.app.launcher" to 30, "com.motorola.launcher3" to 36,
            "com.nothing.launcher" to 29, "com.sonymobile.launcher" to 29,
            // They add an icon for a newly enabled entry when the switch
            // arrives as two broadcasts: only where it is one call (13+).
            "com.asus.launcher" to 33, "com.hihonor.android.launcher" to 33,
            "com.transsion.hilauncher" to 35, "com.transsion.XOSLauncher" to 35,
        )
        assertEquals(since, DateIcon.FOLLOWING_HOMES)
        for ((home, from) in since) for (sdk in 29..37) {
            val want = if (sdk >= from) today else DateIcon.DEFAULT_ALIAS
            assertEquals("$home on $sdk", want, DateIcon.targetFor("Google", sdk, home, day))
        }
        val keep = listOf("com.google.android.apps.nexuslauncher", "com.android.launcher3")
        val drop = listOf(
            "com.miui.home", "com.mi.android.globallauncher", "com.android.launcher",
            "com.oppo.launcher", "com.teslacoilsw.launcher", "com.huawei.android.launcher",
            "com.sonymobile.home", "app.lawnchair", "android", "com.bbk.launcher2",
            "com.android.launcher3#old", "com.hihonor.android.launcher.old",
            "com.transsion.hilauncher#old", "com.transsion.XOSLauncher#old", "com.transsion.itel.launcher",
            "net.oneplus.launcher", "com.zte.mifavor.launcher",
        )
        // No home screen known: nothing is switched either way.
        for (home in listOf(null, "", "  ")) {
            assertEquals("unknown home '$home'", null, DateIcon.targetFor("Google", 34, home, day))
            assertEquals("static stays static '$home'", DateIcon.DEFAULT_ALIAS, DateIcon.targetFor("Google", 28, home, day))
        }
        val brands = listOf("Google", "samsung", "motorola", "vivo", "Xiaomi", "OPPO", "Nothing", null)
        for (brand in brands) for (sdk in listOf(29, 30, 31, 33, 34, 36, 37)) {
            for (home in keep) assertEquals("$brand $sdk $home", today, DateIcon.targetFor(brand, sdk, home, day))
            for (home in drop) assertEquals("$brand $sdk $home", DateIcon.DEFAULT_ALIAS, DateIcon.targetFor(brand, sdk, home, day))
        }
        for (home in keep) for (sdk in listOf(24, 25, 26, 27, 28)) {
            assertEquals("$home on $sdk", DateIcon.DEFAULT_ALIAS, DateIcon.targetFor("Google", sdk, home, day))
        }
        for (sony in listOf("Sony", "sony", " SONY ")) for (sdk in listOf(29, 30)) {
            assertEquals("$sony $sdk", DateIcon.DEFAULT_ALIAS, DateIcon.targetFor(sony, sdk, "com.android.launcher3", day))
        }
        for (sdk in listOf(31, 33, 36)) {
            assertEquals("Sony $sdk", today, DateIcon.targetFor("Sony", sdk, "com.android.launcher3", day))
        }
        // Every caller asks through the phone's own home screen.
        val src = File(main, "kotlin/com/blessing/dates/DateIcon.kt").readText()
        assertTrue(src.contains("Intent.CATEGORY_HOME"))
        // withTodaysIcon and update: both decide through target().
        assertEquals(2, Regex("""\btarget\((context|app), """).findAll(src).count())
        assertTrue(src.contains("apply(app, target)"))
        assertTrue(manifest.contains("android.intent.category.HOME"))
        // An old Launcher3 fork (code before the re-point path) is static, and
        // one not yet read switches nothing.
        assertTrue(src.contains("false -> OLD_LAUNCHER3"))
        assertTrue(src.contains("null -> null"))
        assertTrue(src.contains("Lcom/android/launcher3/model/data/WorkspaceItemInfo;"))
        assertTrue(src.contains("Lcom/android/launcher3/WorkspaceItemInfo;"))
        assertTrue(src.contains("ApplicationInfo.FLAG_SYSTEM"))
        // Transsion only from the builds read; older or unreadable is static.
        assertEquals(
            mapOf("com.transsion.hilauncher" to 150503039L, "com.transsion.XOSLauncher" to 150602067L),
            DateIcon.MIN_HOME_BUILD,
        )
        assertTrue(src.contains("if (homeBuild(context, home) >= MIN_HOME_BUILD.getValue(home)) home else \"\$home#old\""))
        assertTrue(src.contains("-1L"))
        assertTrue(src.contains("Looper.myLooper() == Looper.getMainLooper()) return null"))
    }

    /** The class-name scan finds a mark wherever it falls, chunk edges too. */
    @Test
    fun theLauncherCodeScanFindsTheMarkAcrossChunks() {
        val mark = "Lcom/android/launcher3/WorkspaceItemInfo;".toByteArray()
        val other = "Lcom/android/launcher3/ShortcutInfo;".toByteArray()
        val chunk = 1 shl 16
        for (at in listOf(0, 1, chunk - mark.size, chunk - 7, chunk - 1, chunk, chunk + 5, 3 * chunk - 2)) {
            val bytes = ByteArray(3 * chunk + 100) { 'x'.code.toByte() }
            System.arraycopy(mark, 0, bytes, at, mark.size)
            assertTrue("mark at $at", DateIcon.holds(bytes.inputStream(), listOf(other, mark)))
        }
        val old = ByteArray(2 * chunk) { 'x'.code.toByte() }
        System.arraycopy(other, 0, old, chunk - 3, other.size)
        assertFalse("only the old name", DateIcon.holds(old.inputStream(), listOf(mark)))
        assertFalse("empty", DateIcon.holds(ByteArray(0).inputStream(), listOf(mark)))
    }

    /** The switch plan: today's entry on first, so no prefix leaves none on. */
    @Test
    fun theSwitchTurnsTheNewEntryOnBeforeAnyOff() {
        val all = listOf(DateIcon.DEFAULT_ALIAS) + DateIcon.DATE_ALIASES
        val today = "com.blessing.dates.DateTue24"
        val states = listOf(
            setOf(DateIcon.DEFAULT_ALIAS),                                   // fresh install
            setOf("com.blessing.dates.DateMon23"),                           // yesterday
            setOf("com.blessing.dates.DateMon23", DateIcon.DEFAULT_ALIAS),   // two on (healed)
            emptySet(),                                                      // none on (healed)
            setOf(today),                                                    // already right
        )
        for (target in listOf(today, DateIcon.DEFAULT_ALIAS)) for (start in states) {
            val plan = DateIcon.plan(target) { it in start }
            val on = start.toMutableSet()
            for ((name, enable) in plan) {
                if (enable) on += name else on -= name
                assertTrue("$start -> $target: zero entries on after $name", on.isNotEmpty())
            }
            assertEquals("$start -> $target", setOf(target), on)
            if (plan.isNotEmpty() && target !in start) assertEquals(target to true, plan.first())
            assertTrue("nothing already right is touched", plan.none { (n, e) -> (n in start) == e })
            assertTrue(plan.all { it.first in all })
        }
        assertTrue(DateIcon.plan(today) { it == today }.isEmpty())
    }

    /** What PackageManager reports, read as on or off. */
    @Test
    fun theManifestStateCountsAsOnOnlyForTheStaticEntry() {
        val ENABLED = 1; val DISABLED = 2; val DEFAULT = 0; val DISABLED_USER = 3
        assertTrue(DateIcon.isOn(DateIcon.DEFAULT_ALIAS, DEFAULT))
        assertFalse(DateIcon.isOn("com.blessing.dates.DateMon1", DEFAULT))
        for (n in listOf(DateIcon.DEFAULT_ALIAS, "com.blessing.dates.DateMon1")) {
            assertTrue(DateIcon.isOn(n, ENABLED))
            assertFalse(DateIcon.isOn(n, DISABLED))
            assertFalse(DateIcon.isOn(n, DISABLED_USER))
        }
    }

    /**
     * The guards from review: no switch on a configuration change, the
     * leave is checked after it settles and with the screen on, a lost exact
     * alarm has an inexact backstop, a settled static icon books nothing,
     * the real activity is not open to other apps, and a time-zone change
     * takes the zone from the broadcast.
     */
    @Test
    fun theReviewGuardsStayInPlace() {
        val icon = File(main, "kotlin/com/blessing/dates/DateIcon.kt").readText()
        val screen = File(main, "kotlin/com/blessing/dates/DatesActivity.kt").readText()
        assertTrue(screen.contains("if (!isChangingConfigurations) DateIcon.update(this, leaving = true)"))
        assertTrue(icon.contains("worker.schedule(job, LEAVE_SETTLE_MS"))
        assertFalse("a leave must not skip the on-screen check", icon.contains("leaving || !onScreen"))
        assertTrue(icon.contains("isInteractive"))
        assertTrue(icon.contains("midnight + BACKSTOP_MS, alarm(context, 1)"))
        assertTrue(icon.contains("if (settledStatic) cancel(app) else schedule(app)"))
        assertTrue(icon.contains("getStringExtra(\"time-zone\")"))
        // A broadcast is finished within Android's 10 s whatever the update does.
        assertTrue(icon.contains("guard.schedule(finish, FINISH_BY_S, TimeUnit.SECONDS)"))
        assertTrue(Regex("""FINISH_BY_S = [1-9]L""").containsMatchIn(icon))
        val real = Regex("""<activity\s+android:name="\.DatesActivity"[^>]*>""").find(manifest)!!.value
        assertTrue(real.contains("""android:exported="false""""))
    }

    /**
     * "Daily date icon" off is always the static entry, whatever the phone
     * and home screen (even one not known yet), so Samsung app pairs,
     * Modes & Routines and Tasker keep the entry they name.
     */
    @Test
    fun theOptOutAlwaysGivesTheStaticEntry() {
        val day = cal("UTC", 2026, 11, 23)
        val homes = listOf(
            "com.google.android.apps.nexuslauncher", "com.sec.android.app.launcher",
            "com.android.launcher3", "com.miui.home", null, "",
        )
        for (brand in listOf("Google", "samsung", "Sony", null)) for (sdk in 24..37) for (home in homes) {
            assertEquals("$brand $sdk $home", DateIcon.DEFAULT_ALIAS, DateIcon.targetFor(brand, sdk, home, day, daily = false))
        }
        // On by default: the same phone that goes static when opted out
        // follows the date when not.
        assertEquals("com.blessing.dates.DateMon23", DateIcon.targetFor("samsung", 34, "com.sec.android.app.launcher", day))
        assertEquals("com.blessing.dates.DateMon23", DateIcon.targetFor("samsung", 34, "com.sec.android.app.launcher", day, daily = true))
    }

    /**
     * target() (which update, withTodaysIcon and DateEntryActivity.root all
     * decide through) reads the stored switch before anything else, from the
     * "date_icon" prefs, ON by default; the channel stores it and runs update.
     */
    @Test
    fun theOptOutIsReadByTargetAndWiredToFlutter() {
        val src = File(main, "kotlin/com/blessing/dates/DateIcon.kt").readText()
        val target = src.substringAfter("fun target(context: Context, cal: Calendar): String? {")
            .substringBefore(END)
        val firstLine = target.trim().lineSequence().first()
        assertEquals("if (!dailyIcon(context)) return targetFor(null, 0, null, cal, daily = false)", firstLine.trim())
        val targetFor = src.substringAfter("fun targetFor(").substringBefore(END)
        assertTrue(targetFor.contains("if (!daily) return DEFAULT_ALIAS"))
        assertTrue(src.contains("private const val PREFS = \"date_icon\""))
        assertTrue(src.contains("getBoolean(DAILY_KEY, true)"))
        val set = src.substringAfter("fun setDailyIcon(").substringBefore(END)
        assertTrue(set.contains("putBoolean(DAILY_KEY, on)"))
        assertTrue(set.contains("update(context)"))
        val screen = File(main, "kotlin/com/blessing/dates/DatesActivity.kt").readText()
        assertTrue(screen.contains("\"com.blessing.dates/date_icon\""))
        assertTrue(screen.contains("\"getDailyIcon\" -> result.success(DateIcon.dailyIcon(this))"))
        assertTrue(screen.contains("DateIcon.setDailyIcon(this, on)"))
        val entry = File(main, "kotlin/com/blessing/dates/DateEntryActivity.kt").readText()
        assertTrue(entry.contains("DateIcon.target(this, today)"))
        // Dart talks to the same channel.
        val dart = File("../../lib/state/settings.dart").readText()
        assertTrue(dart.contains("MethodChannel('com.blessing.dates/date_icon')"))
    }

    /** The end of a member function's body in DateIcon.kt. */
    private val END = "\n    }"
}
