package com.usage.claudewidget.widget

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object TimeFmt {
    /**
     * When a window resets, as an absolute wall-clock time - the way the Claude usage menu
     * (and the watch glance) states it, rather than a countdown.
     *
     * Absolute rather than relative is the correct choice for a widget specifically: it only
     * re-renders on the ~15-minute refresh, so a countdown like "2h" would sit visibly wrong
     * for most of the interval between refreshes, while "5:00 PM" stays true no matter when
     * it is read. The format follows the distance, which maps onto the windows: a clock time
     * within a day (the 5-hour session), a weekday within the week, a month/day beyond that
     * (the weekly caps).
     *
     * @param is24h the device's clock setting, from DateFormat.is24HourFormat(context).
     */
    fun resetsAt(
        resetEpochMs: Long,
        now: Long = System.currentTimeMillis(),
        is24h: Boolean = false,
    ): String {
        if (resetEpochMs <= 0L) return "-"
        val diff = resetEpochMs - now
        if (diff <= 0L) return "now"
        val pattern = when {
            diff < DAY_MS -> if (is24h) "H:mm" else "h:mm a"
            diff < 7 * DAY_MS -> "EEE"      // "Tue"
            else -> "MMM d"                 // "Sep 22"
        }
        return SimpleDateFormat(pattern, Locale.getDefault()).format(Date(resetEpochMs))
    }

    private const val DAY_MS = 86_400_000L

    /** Snapshot is considered stale once older than ~2 refresh cycles. */
    fun isStale(fetchedAt: Long, now: Long = System.currentTimeMillis()): Boolean {
        if (fetchedAt <= 0L) return true
        return now - fetchedAt > 31 * 60 * 1000L // > 31 min
    }
}
