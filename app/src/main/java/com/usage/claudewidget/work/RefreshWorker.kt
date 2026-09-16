package com.usage.claudewidget.work

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.usage.claudewidget.data.FetchResult
import com.usage.claudewidget.data.UsageRepository
import com.usage.claudewidget.watch.WatchBridge
import com.usage.claudewidget.widget.UsageWidget

/** Fetches usage in the background and fans the result out to the widget and the watch. */
class RefreshWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val result = UsageRepository(applicationContext).refresh()
        // Snapshot + authState are already persisted by the repository; just re-render.
        UsageWidget.updateAll(applicationContext)

        // The watch is a second consumer of the same snapshot, and a strictly optional one:
        // it has no credentials and cannot fetch for itself, but a watch that is out of
        // range must not turn a successful refresh into a retry. Only push on a fresh
        // fetch - re-sending an unchanged snapshot would spend radio for nothing.
        if (result is FetchResult.Success) {
            when (val push = WatchBridge.push(applicationContext, result.snapshot)) {
                is WatchBridge.PushResult.Sent -> Log.i(TAG, "watch updated: ${push.deviceName}")
                else -> Log.i(TAG, "watch not updated: $push")
            }
        }

        return when (result) {
            is FetchResult.Success, is FetchResult.NeedsLogin -> Result.success()
            is FetchResult.Soft -> Result.retry() // transient; let WorkManager back off
        }
    }

    private companion object {
        const val TAG = "ClaudeWatch"
    }
}
