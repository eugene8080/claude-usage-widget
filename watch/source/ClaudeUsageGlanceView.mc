import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! The glance: three meters across a short horizontal band, laid out the same way as the
//! phone's one-row home-screen widget so the two read as one product.
//!
//! Glance code runs in its own small memory budget, hence (:glance) here and on everything
//! it touches. Keep this view allocation-free on the draw path.
(:glance)
class ClaudeUsageGlanceView extends WatchUi.GlanceView {

    // Claude's accent, matching @color/accent on the phone. Glances are always drawn on the
    // system's dark background, so the dark-theme variant is the right one.
    private const ACCENT = 0xE8896B;
    private const TRACK = 0x333333;
    private const STALE = 0xFFC233;

    public function initialize() {
        GlanceView.initialize();
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        if (!Snapshot.hasData()) {
            drawCentered(dc, w, h, "Open on phone");
            return;
        }

        // Two or three columns depending on whether this account has a per-model cap. The
        // divisor is the count, not a constant, so a missing third meter widens the other
        // two rather than leaving a hole.
        var count = Snapshot.hasModelWeekly() ? 3 : 2;
        var gap = w * 0.03;
        var colW = (w - (gap * (count - 1))) / count;

        drawMeter(dc, 0, colW, h, "5H", Snapshot.percent(Snapshot.K_FIVE));
        drawMeter(dc, colW + gap, colW, h, "1W", Snapshot.percent(Snapshot.K_WEEK));
        if (count == 3) {
            drawMeter(
                dc,
                (colW + gap) * 2,
                colW,
                h,
                Snapshot.modelName(),
                Snapshot.percent(Snapshot.K_MODEL)
            );
        }

        if (Snapshot.isStale()) {
            // A small dot rather than text: the numbers are still worth showing, they just
            // should not be trusted to the minute.
            dc.setColor(STALE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(w - 5, 5, 4);
        }
    }

    //! One meter: label, percentage, bar - stacked, so a long model name and "100%" never
    //! collide in a narrow column.
    private function drawMeter(
        dc as Dc,
        x as Numeric,
        colW as Numeric,
        h as Numeric,
        label as String,
        pct as Number
    ) as Void {
        var labelY = h * 0.08;
        var valueY = h * 0.36;
        var barY = h * 0.78;
        var barH = h * 0.10;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, labelY, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            x,
            valueY,
            Graphics.FONT_TINY,
            pct.toString() + "%",
            Graphics.TEXT_JUSTIFY_LEFT
        );

        dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, barY, colW, barH);

        var filled = colW * clampPct(pct) / 100.0;
        if (filled > 0) {
            dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x, barY, filled, barH);
        }
    }

    private function clampPct(pct as Number) as Number {
        if (pct < 0) { return 0; }
        if (pct > 100) { return 100; }
        return pct;
    }

    private function drawCentered(dc as Dc, w as Numeric, h as Numeric, text as String) as Void {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            w / 2,
            h / 2,
            Graphics.FONT_XTINY,
            text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }
}
