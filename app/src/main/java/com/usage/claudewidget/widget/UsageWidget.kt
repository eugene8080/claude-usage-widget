package com.usage.claudewidget.widget

import android.content.Context
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

    // Exact: the layout decides from the widget's REAL size. The previous Responsive buckets
    // made one home-screen row (a little under 110 dp) fall back to the 140x50 bucket, so a
    // 3x1 widget could only ever get the side-by-side layout - never the stacked one with the
    // "Claude usage" header, even though the dense stacked layout fits a single row.
    override val sizeMode = SizeMode.Exact

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
