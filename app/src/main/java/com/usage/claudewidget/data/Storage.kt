package com.usage.claudewidget.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Two-tier storage:
 *  - [secure]   EncryptedSharedPreferences for credentials (sessionKey, cf_clearance, UA, orgId).
 *  - [snapshot] Plain prefs for the non-secret usage snapshot the widget renders on every frame.
 */
class Storage private constructor(
    private val secure: SharedPreferences,
    private val snapshot: SharedPreferences,
) {
    // ---- credentials (encrypted) ----
    var sessionKey: String?
        get() = secure.getString("sessionKey", null)
        set(v) = secure.edit().putString("sessionKey", v).apply()

    var cfClearance: String?
        get() = secure.getString("cf_clearance", null)
        set(v) = secure.edit().putString("cf_clearance", v).apply()

    var userAgent: String?
        get() = secure.getString("user_agent", null)
        set(v) = secure.edit().putString("user_agent", v).apply()

    var orgId: String?
        get() = secure.getString("org_id", null)
        set(v) = secure.edit().putString("org_id", v).apply()

    val isLoggedIn: Boolean get() = !sessionKey.isNullOrBlank()

    fun clearCredentials() {
        secure.edit().clear().apply()
    }

    // ---- usage snapshot (plain, read by the widget) ----
    var fiveHourUtil: Float
        get() = snapshot.getFloat("fh_util", -1f)
        set(v) = snapshot.edit().putFloat("fh_util", v).apply()

    var fiveHourReset: Long
        get() = snapshot.getLong("fh_reset", 0L)
        set(v) = snapshot.edit().putLong("fh_reset", v).apply()

    var sevenDayUtil: Float
        get() = snapshot.getFloat("wk_util", -1f)
        set(v) = snapshot.edit().putFloat("wk_util", v).apply()

    var sevenDayReset: Long
        get() = snapshot.getLong("wk_reset", 0L)
        set(v) = snapshot.edit().putLong("wk_reset", v).apply()

    /** Per-model weekly window; -1 means the endpoint reported none for this account. */
    var modelWeeklyUtil: Float
        get() = snapshot.getFloat("mw_util", -1f)
        set(v) = snapshot.edit().putFloat("mw_util", v).apply()

    var modelWeeklyReset: Long
        get() = snapshot.getLong("mw_reset", 0L)
        set(v) = snapshot.edit().putLong("mw_reset", v).apply()

    /** The model the endpoint named for that window, e.g. "Fable". */
    var modelWeeklyName: String
        get() = snapshot.getString("mw_name", "").orEmpty()
        set(v) = snapshot.edit().putString("mw_name", v).apply()

    val hasModelWeekly: Boolean get() = modelWeeklyUtil >= 0f && modelWeeklyName.isNotBlank()

    var fetchedAt: Long
        get() = snapshot.getLong("fetched_at", 0L)
        set(v) = snapshot.edit().putLong("fetched_at", v).apply()

    /** AuthState ordinal; widget shows "Tap to sign in" when NEEDS_LOGIN. */
    var authState: AuthState
        get() = AuthState.entries.getOrElse(snapshot.getInt("auth_state", 0)) { AuthState.OK }
        set(v) = snapshot.edit().putInt("auth_state", v.ordinal).apply()

    val hasSnapshot: Boolean get() = fiveHourUtil >= 0f

    fun saveSnapshot(s: UsageSnapshot) {
        snapshot.edit()
            .putFloat("fh_util", s.fiveHour.utilization)
            .putLong("fh_reset", s.fiveHour.resetsAtEpochMs)
            .putFloat("wk_util", s.sevenDay.utilization)
            .putLong("wk_reset", s.sevenDay.resetsAtEpochMs)
            // Write -1 when absent so an account that loses the per-model window stops
            // showing a stale row.
            .putFloat("mw_util", s.modelWeekly?.window?.utilization ?: -1f)
            .putLong("mw_reset", s.modelWeekly?.window?.resetsAtEpochMs ?: 0L)
            .putString("mw_name", s.modelWeekly?.modelName.orEmpty())
            .putLong("fetched_at", s.fetchedAtEpochMs)
            .apply()
    }

    // ---- last watch push (plain, diagnostics for the phone app's status line) ----
    //
    // The push to the Garmin watch fails silently by design (it must never fail a widget
    // refresh), which made "why is the watch stale?" unanswerable without a USB cable and
    // logcat. Recording the last outcome lets the app itself answer it.

    /** When the last push attempt finished, epoch ms; 0 when none has run. */
    val watchPushAt: Long get() = snapshot.getLong("watch_push_at", 0L)

    /** Whether that attempt reached a watch. */
    val watchPushOk: Boolean get() = snapshot.getBoolean("watch_push_ok", false)

    /** Human-readable outcome, e.g. "sent to tactix 8" or "failed (timeout)". */
    val watchPushDetail: String get() = snapshot.getString("watch_push_detail", "").orEmpty()

    /** When a push last actually reached a watch, epoch ms; 0 when never. */
    val watchLastSentAt: Long get() = snapshot.getLong("watch_last_sent_at", 0L)

    /**
     * Whether the last push was cut off by the phone's own background management (the job
     * was stopped mid-send) - the one failure that a phone setting, not the watch, fixes.
     */
    val watchPushStoppedBySystem: Boolean
        get() = snapshot.getBoolean("watch_push_stopped_by_system", false)

    fun saveWatchPush(atEpochMs: Long, ok: Boolean, detail: String, stoppedBySystem: Boolean = false) {
        val edit = snapshot.edit()
            .putLong("watch_push_at", atEpochMs)
            .putBoolean("watch_push_ok", ok)
            .putString("watch_push_detail", detail)
            .putBoolean("watch_push_stopped_by_system", stoppedBySystem)
        if (ok) {
            edit.putLong("watch_last_sent_at", atEpochMs)
        }
        edit.apply()
    }

    /**
     * When the user confirmed they allowed background activity in the "Keep it running in
     * the background" prompt, epoch ms; 0 when never. The prompt stays away after that
     * unless a later watch push is stopped by the system again.
     */
    var backgroundHelpAckAt: Long
        get() = snapshot.getLong("background_help_ack_at", 0L)
        set(v) = snapshot.edit().putLong("background_help_ack_at", v).apply()

    companion object {
        @Volatile private var instance: Storage? = null

        fun get(context: Context): Storage = instance ?: synchronized(this) {
            instance ?: build(context.applicationContext).also { instance = it }
        }

        private fun build(app: Context): Storage {
            val masterKey = MasterKey.Builder(app)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            val secure = EncryptedSharedPreferences.create(
                app,
                "claude_secure",
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
            val snapshot = app.getSharedPreferences("claude_usage", Context.MODE_PRIVATE)
            return Storage(secure, snapshot)
        }
    }
}

enum class AuthState { OK, NEEDS_LOGIN }
