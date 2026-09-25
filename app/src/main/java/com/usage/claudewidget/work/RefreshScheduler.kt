package com.usage.claudewidget.work

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import com.usage.claudewidget.data.Const
import java.util.concurrent.TimeUnit

object RefreshScheduler {

    private val networkConstraint =
        Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

    /**
     * Periodic 15-minute refresh; survives reboot. Safe to call as often as you like.
     *
     * UPDATE, not KEEP. KEEP means "already queued - do nothing", which cannot repair the
     * failure seen on an Oppo Find N5 (ColorOS, 2026-09-25): WorkManager still held the
     * periodic work as ENQUEUED, but with no system job id and nothing registered in
     * JobScheduler, so the "15-minute" refresh only ran when the app process happened to be
     * alive (about every 1-2 hours). Something outside the app - most likely the OEM's
     * background cleaner - had dropped the JobScheduler job, and every later KEEP call left
     * that broken state in place.
     *
     * UPDATE (WorkManager 2.8+) keeps the same work and its last-enqueue time, so the
     * 15-minute cadence is not restarted, but when the work is not currently running it
     * cancels it in every scheduler, marks it not-yet-scheduled and schedules it again -
     * i.e. re-registers it with JobScheduler. When it IS running, the update simply applies
     * from the next period.
     *
     * BACKLOG GUARD. UPDATE also keeps the work's run-attempt count, and with it any retry
     * backoff. On the same Oppo, every run ColorOS froze mid-way counted as a failed attempt;
     * with exponential backoff from 1 minute, ~7 of those pushed the next run ~2 hours out,
     * and WorkManager refuses to run it early. So when the queued work's next run is more
     * than [STUCK_AFTER_MIN] minutes away - further than a healthy 15-minute schedule can
     * ever be - it is replaced instead (CANCEL_AND_REENQUEUE): a fresh work with no attempt
     * history, whose first run is due immediately. A healthy schedule is never replaced, so
     * the cadence is still not restarted by ordinary taps and app opens.
     */
    fun ensurePeriodic(context: Context) {
        val wm = WorkManager.getInstance(context)
        val infos = wm.getWorkInfosForUniqueWork(Const.WORK_NAME)
        // The query is async; decide once it completes. The listener runs on WorkManager's
        // background thread that completes the future, so get() below does not block.
        infos.addListener({
            val current = runCatching { infos.get() }.getOrNull()
                ?.firstOrNull { !it.state.isFinished }
            val policy = if (current != null && isBackedUp(current)) {
                Log.i(TAG, "periodic refresh backed up (next run in " +
                    "${(current.nextScheduleTimeMillis - System.currentTimeMillis()) / 60_000} min, " +
                    "${current.runAttemptCount} attempts) - replacing it")
                ExistingPeriodicWorkPolicy.CANCEL_AND_REENQUEUE
            } else {
                ExistingPeriodicWorkPolicy.UPDATE
            }
            wm.enqueueUniquePeriodicWork(Const.WORK_NAME, policy, periodicRequest())
        }, Runnable::run)
    }

    /** No healthy 15-minute schedule has its next run this far away. */
    private const val STUCK_AFTER_MIN = 20L

    private const val TAG = "RefreshScheduler"

    /** ENQUEUED (not running) with its next run beyond anything the period explains. */
    private fun isBackedUp(info: WorkInfo): Boolean {
        if (info.state != WorkInfo.State.ENQUEUED) return false
        val next = info.nextScheduleTimeMillis
        // Long.MAX_VALUE means "not scheduled" (e.g. waiting on a constraint) - leave it.
        if (next == Long.MAX_VALUE) return false
        return next - System.currentTimeMillis() > TimeUnit.MINUTES.toMillis(STUCK_AFTER_MIN)
    }

    private fun periodicRequest() = PeriodicWorkRequestBuilder<RefreshWorker>(
        Const.REFRESH_INTERVAL_MIN, TimeUnit.MINUTES
    )
        .setConstraints(networkConstraint)
        .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.MINUTES)
        .build()

    /**
     * Manual tap-to-refresh: run once now, ahead of the periodic schedule. Also re-asserts
     * the periodic work, so a widget tap is enough to repair a lost background schedule.
     */
    fun refreshNow(context: Context) {
        ensurePeriodic(context)
        val work = OneTimeWorkRequestBuilder<RefreshWorker>()
            .setConstraints(networkConstraint)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            "${Const.WORK_NAME}-now", ExistingWorkPolicy.REPLACE, work
        )
    }
}
