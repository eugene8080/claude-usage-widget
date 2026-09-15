package com.usage.claudewidget.data

import org.json.JSONObject

/** One usage window. */
data class Window(
    val utilization: Float,      // percent, 0..100
    val resetsAtEpochMs: Long,   // absolute reset time; 0 when the API reports none
)

/**
 * A per-model weekly sub-cap — Fable today, whatever Anthropic meters next after that.
 * The endpoint names the model itself, so the label travels with the window instead of
 * being hardcoded here.
 */
data class ModelWindow(
    val modelName: String,
    val window: Window,
)

/** Parsed snapshot of the /usage endpoint. */
data class UsageSnapshot(
    val fiveHour: Window,
    val sevenDay: Window,
    val modelWeekly: ModelWindow?,
    val fetchedAtEpochMs: Long,
) {
    companion object {
        private const val FABLE = "Fable"

        /**
         * The endpoint serves two shapes. The current one is a top-level `limits` array of
         * `{kind, percent, resets_at, scope}` entries; the older one is a fixed set of named
         * `five_hour` / `seven_day` / `seven_day_<model>` objects keyed on `utilization`.
         * Read the array when it's there and fall back to the named keys when it isn't.
         */
        fun parse(body: String, now: Long): UsageSnapshot {
            val root = JSONObject(body)
            return parseLimits(root, now) ?: parseLegacy(root, now)
        }

        private fun parseLimits(root: JSONObject, now: Long): UsageSnapshot? {
            val limits = root.optJSONArray("limits") ?: return null
            var session: Window? = null
            var weeklyAll: Window? = null
            var scoped: ModelWindow? = null

            for (i in 0 until limits.length()) {
                val entry = limits.optJSONObject(i) ?: continue
                val window = Window(
                    entry.optDouble("percent", 0.0).toFloat(),
                    Iso8601.toEpochMs(entry.optString("resets_at", "")),
                )
                when (entry.optString("kind")) {
                    "session" -> session = window
                    "weekly_all" -> weeklyAll = window
                    "weekly_scoped" -> {
                        val name = entry.optJSONObject("scope")
                            ?.optJSONObject("model")
                            ?.optString("display_name").orEmpty()
                        // An account can be capped on several models at once, and there is only
                        // room for one extra row: prefer Fable, else take the first one offered.
                        if (name.isNotBlank() && (scoped == null || name.equals(FABLE, true))) {
                            scoped = ModelWindow(name, window)
                        }
                    }
                }
            }
            // Not the modern shape (or not a usage payload at all) — let the caller try the rest.
            if (session == null && weeklyAll == null) return null

            val weekly = weeklyAll ?: Window(0f, 0L)
            return UsageSnapshot(
                fiveHour = session ?: Window(0f, 0L),
                sevenDay = weekly,
                modelWeekly = scoped?.inheritReset(weekly),
                fetchedAtEpochMs = now,
            )
        }

        /** Legacy `seven_day_<model>` keys, newest first; the suffix is the model's name. */
        private val LEGACY_SCOPED_KEYS = listOf("seven_day_fable" to FABLE, "seven_day_opus" to "Opus")

        private fun parseLegacy(root: JSONObject, now: Long): UsageSnapshot {
            val fiveHour = root.optJSONObject("five_hour")
            val sevenDay = root.optJSONObject("seven_day")
            // Neither shape is present, so this isn't a usage payload. Throwing keeps the
            // fetch a soft failure and leaves the last good snapshot on the widget.
            require(fiveHour != null || sevenDay != null) { "no usage windows in payload" }

            val weekly = sevenDay.toWindow()
            val scoped = LEGACY_SCOPED_KEYS.firstNotNullOfOrNull { (key, name) ->
                root.optJSONObject(key)?.let { ModelWindow(name, it.toWindow()) }
            }
            return UsageSnapshot(
                fiveHour = fiveHour.toWindow(),
                sevenDay = weekly,
                modelWeekly = scoped?.inheritReset(weekly),
                fetchedAtEpochMs = now,
            )
        }

        /**
         * A per-model window is a sub-cap on the weekly pool, not a pool of its own, and the
         * API leaves its `resets_at` null until that model is used in the period. Borrow the
         * pooled reset so the row doesn't show a blank countdown.
         */
        private fun ModelWindow.inheritReset(pooled: Window): ModelWindow =
            if (window.resetsAtEpochMs != 0L) this
            else copy(window = window.copy(resetsAtEpochMs = pooled.resetsAtEpochMs))

        private fun JSONObject?.toWindow(): Window {
            if (this == null) return Window(0f, 0L)
            return Window(
                optDouble("utilization", 0.0).toFloat(),
                Iso8601.toEpochMs(optString("resets_at", "")),
            )
        }
    }
}
