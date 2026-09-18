package com.usage.claudewidget.widget

import android.content.Context
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceTheme
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import com.usage.claudewidget.data.AuthState
import com.usage.claudewidget.data.Storage
import kotlin.math.roundToInt

class UsageWidget : GlanceAppWidget() {

    // Reusable buckets; Glance maps any real size to the nearest one.
    override val sizeMode = SizeMode.Responsive(
        setOf(
            DpSize(60.dp, 60.dp),    // Compact (~1x1), three mini meters
            DpSize(60.dp, 110.dp),   // Compact + Claude mark
            DpSize(140.dp, 50.dp),   // One row tall (~1x2 and 1x3), meters side by side
            DpSize(180.dp, 110.dp),  // Full, three meters only
            DpSize(180.dp, 150.dp),  // Full + Claude mark and title
        )
    )

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            GlanceTheme {
                UsageWidgetContent(readState(context))
            }
        }
    }

    private fun readState(context: Context): WidgetState {
        val s = Storage.get(context)
        val now = System.currentTimeMillis()
        // The device clock setting decides 12/24-hour reset times, matching how every other
        // time on the phone is shown.
        val is24h = android.text.format.DateFormat.is24HourFormat(context)
        return WidgetState(
            needsLogin = !s.isLoggedIn || s.authState == AuthState.NEEDS_LOGIN,
            hasData = s.hasSnapshot,
            fiveHourPct = s.fiveHourUtil.coerceAtLeast(0f).roundToInt(),
            fiveHourResets = TimeFmt.resetsAt(s.fiveHourReset, now, is24h),
            sevenDayPct = s.sevenDayUtil.coerceAtLeast(0f).roundToInt(),
            sevenDayResets = TimeFmt.resetsAt(s.sevenDayReset, now, is24h),
            hasModelWeekly = s.hasModelWeekly,
            modelWeeklyName = s.modelWeeklyName,
            modelWeeklyPct = s.modelWeeklyUtil.coerceAtLeast(0f).roundToInt(),
            modelWeeklyResets = TimeFmt.resetsAt(s.modelWeeklyReset, now, is24h),
            stale = TimeFmt.isStale(s.fetchedAt, now),
            version = com.usage.claudewidget.BuildConfig.VERSION_NAME,
        )
    }

    companion object {
        suspend fun updateAll(context: Context) = UsageWidget().updateAll(context)
    }
}
