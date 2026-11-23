package com.blessing.dates

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import java.util.Calendar

/**
 * Where every launcher entry opens: the date entries (DateMon1 .. DateSun31)
 * and the static .MainActivity alike. The static one is switched off too,
 * the first time a phone leaves the app after installing or updating, and
 * a task opened from it would vanish from Recents then.
 *
 * Where the daily icon does not run (below Android 10, Sony on 10 and 11,
 * home screens that would drop a pinned icon)
 * nothing is ever switched off, so it opens DatesActivity itself, whose
 * icon is the static one the launcher shows. Draws
 * nothing: it hands straight over to [DatesActivity].
 *
 * Why it exists: Android names a task after the entry that opened it, and
 * when that entry is switched off it drops the task from Recents
 * (RecentTasks.cleanupDisabledPackageTasksLocked matches the task's launch
 * intent against the entries just disabled). The icon moves to the next
 * date at midnight and as the app leaves the screen, so a task opened from
 * today's entry would vanish from Recents the moment the user left it.
 *
 * So on a fresh task this starts DatesActivity as the task's root, through
 * today's hidden task entry (TaskMon1 .. TaskSun31): never switched off, so
 * the task is never dropped, and Recents draws the task's icon from it in
 * the phone's own style. Both share one taskAffinity, so
 * CLEAR_TASK reuses this task rather than opening a second one; this
 * activity's relinquishTaskIdentity (manifest) is what lets the task take
 * DatesActivity's name, which Android otherwise never changes. And
 * RESET_TASK_IF_NEEDED marks the root as reset, so a later tap on the icon
 * only brings the task forward and never renames it back to the entry.
 *
 * When the task already holds the app, the launcher brings it forward
 * without starting this at all; if some launcher starts it on top anyway,
 * it only closes, and the app underneath keeps its state.
 */
class DateEntryActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (isTaskRoot) {
            // A fresh launcher intent, never the incoming one passed on:
            // forwarding an intent this activity received is what Play's
            // "Intent Redirection" check flags, and the entries carry
            // nothing but MAIN/LAUNCHER anyway.
            startActivity(
                Intent(Intent.ACTION_MAIN)
                    .addCategory(Intent.CATEGORY_LAUNCHER)
                    // Through today's hidden task entry, which targets
                    // DatesActivity: Recents draws the task's icon from it.
                    .setComponent(ComponentName(packageName, root()))
                    .addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_CLEAR_TASK or
                            Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED,
                    ),
            )
        }
        // Theme.NoDisplay requires finishing before onResume.
        finish()
    }

    private fun root(): String {
        val today = Calendar.getInstance()
        // Unknown (no default home screen): the real activity, which is
        // never switched off either.
        val target = DateIcon.target(this, today)
        val daily = target != null && target != DateIcon.DEFAULT_ALIAS
        return if (daily) DateIcon.taskAliasFor(today) else DatesActivity::class.java.name
    }
}
