package com.usage.claudewidget.work

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
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
     */
    fun ensurePeriodic(context: Context) {
        val work = PeriodicWorkRequestBuilder<RefreshWorker>(
            Const.REFRESH_INTERVAL_MIN, TimeUnit.MINUTES
        )
            .setConstraints(networkConstraint)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.MINUTES)
            .build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            Const.WORK_NAME, ExistingPeriodicWorkPolicy.UPDATE, work
        )
    }

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
