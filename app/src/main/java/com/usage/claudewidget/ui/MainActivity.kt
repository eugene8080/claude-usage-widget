package com.usage.claudewidget.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.text.format.DateUtils
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.usage.claudewidget.auth.LoginActivity
import com.usage.claudewidget.data.FetchResult
import com.usage.claudewidget.data.Storage
import com.usage.claudewidget.data.UsageRepository
import com.usage.claudewidget.watch.WatchBridge
import com.usage.claudewidget.widget.UsageWidget
import com.usage.claudewidget.work.RefreshScheduler
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Opening the app re-registers the 15-minute background refresh with the system, in
        // case the OEM's background management dropped it (see RefreshScheduler). Only once
        // signed in - before that there is nothing to fetch; sign-in schedules it itself.
        if (Storage.get(this).isLoggedIn) {
            RefreshScheduler.ensurePeriodic(this)
        }
        setContent {
            AppTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    SetupScreen()
                }
            }
        }
    }
}

/**
 * Follows the system light/dark setting. A bare `MaterialTheme {}` always uses the light
 * scheme, which is why this screen stayed white in dark mode.
 *
 * On Android 12+ the scheme is the wallpaper-derived dynamic one, the same palette the
 * home-screen widget gets from GlanceTheme, so the app and the widget match. Older devices
 * fall back to the stock Material 3 light/dark schemes.
 */
@androidx.compose.runtime.Composable
private fun AppTheme(content: @androidx.compose.runtime.Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val context = LocalContext.current
    val scheme = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        dark -> darkColorScheme()
        else -> lightColorScheme()
    }
    MaterialTheme(colorScheme = scheme, content = content)
}

@androidx.compose.runtime.Composable
private fun SetupScreen() {
    val context = LocalContext.current
    val storage = remember { Storage.get(context) }
    val scope = rememberCoroutineScope()

    var status by remember { mutableStateOf(describe(storage)) }
    var debug by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }

    val loginLauncher = androidx.activity.compose.rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        status = describe(storage)
    }

    Column(
        // safeDrawingPadding: targetSdk 35+ is always edge-to-edge, so without it the title
        // is drawn under the status-bar clock.
        modifier = Modifier.fillMaxSize().safeDrawingPadding().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Claude Usage Widget", style = MaterialTheme.typography.headlineSmall)
        // The definitive "did it update?" check. VERSION_NAME is the release tag in a
        // published build (a local debug build shows the gradle default instead).
        Text(
            "v${com.usage.claudewidget.BuildConfig.VERSION_NAME}",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(status, style = MaterialTheme.typography.bodyMedium)

        Button(onClick = { loginLauncher.launch(Intent(context, LoginActivity::class.java)) }) {
            Text(if (storage.isLoggedIn) "Re-sign in" else "Sign in")
        }

        // Runs the same fetch -> widget -> watch sequence as the background refresh, and shows
        // each step's outcome. The watch step used to be skipped here, so a watch that was
        // not receiving pushes looked fine from this button.
        OutlinedButton(enabled = !busy, onClick = {
            scope.launch {
                busy = true
                try {
                    debug = "Fetching…"
                    when (val r = UsageRepository(context).refresh()) {
                        is FetchResult.Success -> {
                            UsageWidget.updateAll(context)
                            val usage = buildString {
                                append("5H: ${r.snapshot.fiveHour.utilization}%   ")
                                append("1W: ${r.snapshot.sevenDay.utilization}%")
                                r.snapshot.modelWeekly?.let {
                                    append("   1W ${it.modelName}: ${it.window.utilization}%")
                                }
                            }
                            // The push can take up to ~35 s (one attempt, a 5 s pause, one
                            // retry), so say what is happening rather than look frozen.
                            debug = "$usage\nWatch: sending…"
                            val push = WatchBridge.push(context, r.snapshot)
                            debug = "$usage\nWatch: ${WatchBridge.describe(push)}"
                        }
                        is FetchResult.NeedsLogin -> debug = "Session expired. Sign in again."
                        is FetchResult.Soft -> debug = "Transient: ${r.reason}"
                    }
                } finally {
                    busy = false
                    status = describe(storage)
                }
            }
        }) { Text("Test fetch now") }

        OutlinedButton(onClick = { requestBatteryExemption(context) }) {
            Text("Disable battery optimization")
        }

        if (debug.isNotBlank()) {
            Text(debug, style = MaterialTheme.typography.titleMedium)
        }
    }
}

private fun describe(s: Storage): String = buildString {
    append(if (s.isLoggedIn) "Signed in ✓" else "Not signed in")
    append("\norg: ").append(s.orgId ?: "-")
    if (s.hasSnapshot) {
        append("\nlast: 5H ").append(s.fiveHourUtil.toInt()).append("%  1W ")
            .append(s.sevenDayUtil.toInt()).append("%")
        if (s.hasModelWeekly) {
            append("  1W ").append(s.modelWeeklyName).append(" ")
                .append(s.modelWeeklyUtil.toInt()).append("%")
        }
    }
    // The watch's own "not updated recently" only says THAT it is stale; this line says why.
    append("\nwatch: ")
    if (s.watchPushAt == 0L) {
        append("no push yet")
    } else {
        append(s.watchPushDetail).append(" · ").append(ago(s.watchPushAt))
        if (!s.watchPushOk) {
            append("\nlast reached watch: ")
            append(if (s.watchLastSentAt == 0L) "never" else ago(s.watchLastSentAt))
        }
    }
}

/** "5 minutes ago" / "Yesterday" - locale-aware and needs no Context. */
private fun ago(epochMs: Long): String = DateUtils.getRelativeTimeSpanString(
    epochMs, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS
).toString()

private fun requestBatteryExemption(context: Context) {
    val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    if (!pm.isIgnoringBatteryOptimizations(context.packageName)) {
        val intent = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:${context.packageName}")
        )
        context.startActivity(intent)
    }
}
