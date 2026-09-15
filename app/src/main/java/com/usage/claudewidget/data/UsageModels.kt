package com.usage.claudewidget.data

import org.json.JSONObject

/** One usage window (5-hour or 7-day). */
data class Window(
    val utilization: Float,      // percent, 0..100
    val resetsAtEpochMs: Long,   // absolute reset time
)

/** Parsed snapshot of the /usage endpoint. */
data class UsageSnapshot(
    val fiveHour: Window,
    val sevenDay: Window,
    /** Weekly cap for the top-tier (Fable) model; null when the plan doesn't meter one. */
    val sevenDayFable: Window?,
    val fetchedAtEpochMs: Long,
) {
    companion object {
        /**
         * Keys the endpoint has used for the top-tier model's weekly window, newest first.
         * It was `seven_day_opus` while Opus was the frontier model; we read whichever of
         * these is present so the widget keeps working across a rename.
         */
        private val FABLE_KEYS = listOf("seven_day_fable", "seven_day_opus")

        fun parse(body: String, now: Long): UsageSnapshot {
            val root = JSONObject(body)
            return UsageSnapshot(
                fiveHour = root.getJSONObject("five_hour").toWindow(),
                sevenDay = root.getJSONObject("seven_day").toWindow(),
                sevenDayFable = FABLE_KEYS.firstNotNullOfOrNull { root.optJSONObject(it) }?.toWindow(),
                fetchedAtEpochMs = now,
            )
        }

        private fun JSONObject.toWindow(): Window {
            val util = optDouble("utilization", 0.0).toFloat()
            val reset = optString("resets_at", "")
            return Window(util, Iso8601.toEpochMs(reset))
        }
    }
}
