package com.usage.claudewidget.widget

import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.runtime.Composable
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import androidx.glance.LocalContext
import android.content.Intent
import com.usage.claudewidget.R
import com.usage.claudewidget.ui.MainActivity

/** Immutable view state handed to the composable; assembled from Storage on each render. */
data class WidgetState(
    val needsLogin: Boolean,
    val hasData: Boolean,
    val fiveHourPct: Int,
    val fiveHourResets: String,
    val sevenDayPct: Int,
    val sevenDayResets: String,
    /** False when the endpoint reports no per-model weekly cap; the row is then hidden. */
    val hasModelWeekly: Boolean,
    /** The model that window is scoped to, as the endpoint names it (e.g. "Fable"). */
    val modelWeeklyName: String,
    val modelWeeklyPct: Int,
    val modelWeeklyResets: String,
    val stale: Boolean,
    /** App version (release tag), shown so an update can be confirmed at a glance. */
    val version: String,
)

private val COMPACT_MAX_WIDTH = 130.dp
/**
 * Below this height even the dense stacked layout can't fit three meters, so the widget sets
 * them side by side instead of clipping the last one off the bottom. (One home-screen row is a
 * little under 110 dp on a Pixel - tall enough for the dense stacked layout below.)
 */
private val SHORT_MAX_HEIGHT = 70.dp
/** Below this height the stacked layout switches to its dense sizing (one-row widgets). */
private val DENSE_MAX_HEIGHT = 130.dp
/**
 * The stacked layout with its "Claude usage" header needs about this much height at its densest
 * (measured on the emulator: 77 dp of content + 12 dp padding). It keeps the header down to here.
 */
private val DENSE_MARK_MIN_HEIGHT = 89.dp
private val COMPACT_MARK_MIN_HEIGHT = 100.dp
/** Below this width the "resets" prefix is dropped and only the reset time is shown. */
private val RESET_PREFIX_MIN_WIDTH = 220.dp

// Colors come from resources so they auto-adapt to light/dark via values-night.
private val accent = ColorProvider(R.color.accent)
private fun barTrack() = ColorProvider(R.color.bar_track)

@Composable
fun UsageWidgetContent(state: WidgetState) {
    val size = LocalSize.current
    val compact = size.width < COMPACT_MAX_WIDTH
    val short = !compact && size.height < SHORT_MAX_HEIGHT
    val dense = size.height < DENSE_MAX_HEIGHT
    val context = LocalContext.current

    val tap = if (state.needsLogin) {
        actionStartActivity(Intent(context, MainActivity::class.java))
    } else {
        actionRunCallback<RefreshAction>()
    }

    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(GlanceTheme.colors.widgetBackground)
            .cornerRadius(20.dp)
            .padding(if (short || dense) 6.dp else if (compact) 8.dp else 10.dp)
            .clickable(tap),
    ) {
        when {
            state.needsLogin -> SignInPrompt(compact)
            !state.hasData -> Loading(compact)
            short -> ShortLayout(state)
            compact -> CompactLayout(state, showMark = size.height >= COMPACT_MARK_MIN_HEIGHT)
            else -> FullLayout(
                state,
                showMark = !dense || size.height >= DENSE_MARK_MIN_HEIGHT,
                showResetPrefix = size.width >= RESET_PREFIX_MIN_WIDTH,
                d = stackDims(size.height),
            )
        }
        if (state.hasData && state.stale) StaleDot()
    }
}

/**
 * Sizes for the stacked layout. REGULAR is the original roomy look (two rows and up); DENSE is
 * the same header + three meter rows with bars, tightened to fit a single home-screen row.
 * [stackDims] interpolates between them by the widget's real height, so a one-row widget fills
 * its row (a Pixel row is ~104 dp) instead of leaving a gap or clipping.
 */
private data class StackDims(
    val markDp: Float, val titleSp: Float, val versionSp: Float, val headerGap: Float,
    val labelSp: Float, val labelW: Float, val pctSp: Float, val resetSp: Float,
    val barGap: Float, val barDp: Float, val rowGap: Float,
)

private fun stackDims(height: androidx.compose.ui.unit.Dp): StackDims {
    // t = 0 at the densest height the header layout needs, 1 at the regular layout's height;
    // the dense layout grows roughly one-for-one with height between them, so it stays full.
    // (+6 dp keeps a little air under the last bar instead of packing the row edge to edge.)
    val t = ((height.value - DENSE_MARK_MIN_HEIGHT.value - 6f) /
        (DENSE_MAX_HEIGHT.value - DENSE_MARK_MIN_HEIGHT.value - 6f)).coerceIn(0f, 1f)
    fun mix(a: Float, b: Float) = a + (b - a) * t
    val a = DENSE
    val b = REGULAR
    return StackDims(
        mix(a.markDp, b.markDp), mix(a.titleSp, b.titleSp), mix(a.versionSp, b.versionSp),
        mix(a.headerGap, b.headerGap), mix(a.labelSp, b.labelSp), mix(a.labelW, b.labelW),
        mix(a.pctSp, b.pctSp), mix(a.resetSp, b.resetSp), mix(a.barGap, b.barGap),
        mix(a.barDp, b.barDp), mix(a.rowGap, b.rowGap),
    )
}

private val REGULAR = StackDims(
    markDp = 22f, titleSp = 14f, versionSp = 11f, headerGap = 8f,
    labelSp = 12f, labelW = 56f, pctSp = 13f, resetSp = 11f, barGap = 3f, barDp = 5f, rowGap = 6f,
)
private val DENSE = StackDims(
    markDp = 14f, titleSp = 11f, versionSp = 9f, headerGap = 2f,
    labelSp = 10f, labelW = 48f, pctSp = 11f, resetSp = 9f, barGap = 1f, barDp = 3f, rowGap = 2f,
)

@Composable
private fun FullLayout(s: WidgetState, showMark: Boolean, showResetPrefix: Boolean, d: StackDims) {
    Column(modifier = GlanceModifier.fillMaxSize()) {
        if (showMark) {
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                ClaudeMark(d.markDp.dp)
                Spacer(GlanceModifier.width(6.dp))
                Text(
                    "Claude usage",
                    style = TextStyle(
                        color = GlanceTheme.colors.onSurface,
                        fontWeight = FontWeight.Medium,
                        fontSize = d.titleSp.sp,
                    ),
                    maxLines = 1,
                )
                Spacer(GlanceModifier.defaultWeight())
                // Version at the right of the header, so an update is confirmable on the
                // widget itself without opening the app.
                Text(
                    "v${s.version}",
                    style = TextStyle(
                        color = GlanceTheme.colors.onSurfaceVariant,
                        fontSize = d.versionSp.sp,
                    ),
                    maxLines = 1,
                )
            }
            Spacer(GlanceModifier.height(d.headerGap.dp))
        }
        MeterRow("5H", s.fiveHourPct, s.fiveHourResets, showResetPrefix, d)
        Spacer(GlanceModifier.height(d.rowGap.dp))
        MeterRow("1W", s.sevenDayPct, s.sevenDayResets, showResetPrefix, d)
        if (s.hasModelWeekly) {
            Spacer(GlanceModifier.height(d.rowGap.dp))
            MeterRow("1W ${s.modelWeeklyName}", s.modelWeeklyPct, s.modelWeeklyResets, showResetPrefix, d)
        }
    }
}

/**
 * Three meters across, for a widget one row tall. Label over value over bar keeps
 * each cell narrow enough that a long model name and "100%" never collide.
 */
@Composable
private fun ShortLayout(s: WidgetState) {
    Row(
        modifier = GlanceModifier.fillMaxSize(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ShortMeter("5H", s.fiveHourPct, s.fiveHourResets, GlanceModifier.defaultWeight())
        Spacer(GlanceModifier.width(10.dp))
        ShortMeter("1W", s.sevenDayPct, s.sevenDayResets, GlanceModifier.defaultWeight())
        if (s.hasModelWeekly) {
            Spacer(GlanceModifier.width(10.dp))
            ShortMeter(
                s.modelWeeklyName,
                s.modelWeeklyPct,
                s.modelWeeklyResets,
                GlanceModifier.defaultWeight(),
            )
        }
    }
}

@Composable
private fun ShortMeter(label: String, pct: Int, resets: String, modifier: GlanceModifier) {
    Column(modifier = modifier) {
        Text(
            label,
            style = TextStyle(
                color = GlanceTheme.colors.onSurfaceVariant,
                fontWeight = FontWeight.Bold,
                fontSize = 10.sp,
            ),
            maxLines = 1,
        )
        Text(
            "$pct%",
            style = TextStyle(
                color = GlanceTheme.colors.onSurface,
                fontWeight = FontWeight.Bold,
                fontSize = 13.sp,
            ),
            maxLines = 1,
        )
        // The reset time, dimmed so the percentage stays the thing the eye lands on. This is
        // the one-row analogue of the watch glance's reset line.
        Text(
            resets,
            style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 9.sp),
            maxLines = 1,
        )
        Spacer(GlanceModifier.height(2.dp))
        Bar(pct, height = 4.dp)
    }
}

@Composable
private fun MeterRow(label: String, pct: Int, resets: String, showResetPrefix: Boolean, d: StackDims) {
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        Row(
            modifier = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                label,
                style = TextStyle(
                    color = GlanceTheme.colors.onSurfaceVariant,
                    fontWeight = FontWeight.Bold,
                    fontSize = d.labelSp.sp,
                ),
                maxLines = 1,
                // Wide enough for the longest label ("1W Fable") so the bars stay aligned.
                modifier = GlanceModifier.width(d.labelW.dp),
            )
            Text(
                "$pct%",
                style = TextStyle(
                    color = GlanceTheme.colors.onSurface,
                    fontWeight = FontWeight.Bold,
                    fontSize = d.pctSp.sp,
                ),
                maxLines = 1,
            )
            Spacer(GlanceModifier.defaultWeight())
            Text(
                if (showResetPrefix) "resets $resets" else resets,
                style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = d.resetSp.sp),
                maxLines = 1,
            )
        }
        Spacer(GlanceModifier.height(d.barGap.dp))
        Bar(pct, height = d.barDp.dp)
    }
}

@Composable
private fun CompactLayout(s: WidgetState, showMark: Boolean) {
    Column(modifier = GlanceModifier.fillMaxSize()) {
        if (showMark) {
            ClaudeMark(14.dp)
            Spacer(GlanceModifier.height(4.dp))
        }
        CompactMeter("5H", s.fiveHourPct)
        Spacer(GlanceModifier.height(4.dp))
        CompactMeter("1W", s.sevenDayPct)
        if (s.hasModelWeekly) {
            Spacer(GlanceModifier.height(4.dp))
            CompactMeter(s.modelWeeklyName, s.modelWeeklyPct)
        }
    }
}

@Composable
private fun CompactMeter(label: String, pct: Int) {
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        Row(modifier = GlanceModifier.fillMaxWidth()) {
            Text(
                label,
                style = TextStyle(
                    color = GlanceTheme.colors.onSurfaceVariant,
                    fontWeight = FontWeight.Bold,
                    fontSize = 11.sp,
                ),
                maxLines = 1,
            )
            Spacer(GlanceModifier.defaultWeight())
            Text(
                "$pct%",
                style = TextStyle(
                    color = GlanceTheme.colors.onSurface,
                    fontWeight = FontWeight.Bold,
                    fontSize = 11.sp,
                ),
                maxLines = 1,
            )
        }
        Spacer(GlanceModifier.height(2.dp))
        Bar(pct)
    }
}

@Composable
private fun Bar(pct: Int, height: androidx.compose.ui.unit.Dp = 5.dp) {
    LinearProgressIndicator(
        progress = (pct.coerceIn(0, 100)) / 100f,
        modifier = GlanceModifier.fillMaxWidth().height(height).cornerRadius(height / 2),
        color = accent,
        backgroundColor = barTrack(),
    )
}

@Composable
private fun ClaudeMark(s: androidx.compose.ui.unit.Dp) {
    Image(
        provider = ImageProvider(R.drawable.ic_claude),
        contentDescription = "Claude",
        modifier = GlanceModifier.size(s),
    )
}

@Composable
private fun SignInPrompt(compact: Boolean) {
    Column(
        modifier = GlanceModifier.fillMaxSize(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        ClaudeMark(if (compact) 18.dp else 24.dp)
        Spacer(GlanceModifier.height(6.dp))
        Text(
            if (compact) "Sign in" else "Tap to sign in",
            style = TextStyle(color = GlanceTheme.colors.onSurface, fontWeight = FontWeight.Medium),
        )
    }
}

@Composable
private fun Loading(compact: Boolean) {
    Column(
        modifier = GlanceModifier.fillMaxSize(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("…", style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant))
    }
}

@Composable
private fun StaleDot() {
    Box(
        modifier = GlanceModifier.fillMaxSize().padding(2.dp),
        contentAlignment = Alignment.TopEnd,
    ) {
        Box(
            modifier = GlanceModifier
                .size(8.dp)
                .cornerRadius(4.dp)
                .background(ColorProvider(R.color.stale)),
        ) {}
    }
}
