import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

//! "Claude Grid" - an Iron Grit-style data face in JetBrains Mono. Field naming follows the
//! Iron Grit "Data Position" chart: Data 01 top-centre (battery), 02/04/06 down the left,
//! 03/05/08 down the right, 07 bottom-centre (seconds), plus Time, Date, Week.
//!
//! Data 04/05 carry a gradient "closing ring" gauge; Data 07 a striped gradient ring for the
//! seconds. The weekday strip curves along the bottom bezel and mirrors the battery arc.
//!
//! This pass nails structure + rings + the battery glyph. Full per-field artwork (and
//! weather-reactive icons) is the next step; non-icon fields use short labels for now.
class ClaudeGridView extends WatchUi.WatchFace {

    private const ACCENT = 0xD97757;   // Claude orange
    private const BRIGHT = 0xF2A98C;   // lighter orange for values
    private const DIM = 0x888888;      // labels / inactive
    private const TRACK = 0x3A2A22;    // ring/arc background (dark warm)
    private const GRAD_A = 0xB5502F;   // ring gradient start (deep orange)
    private const GRAD_B = 0xFFC08A;   // ring gradient end (light amber)

    private var _fontText as Graphics.FontType?;
    private var _fontTime as Graphics.FontType?;

    public function initialize() {
        WatchFace.initialize();
    }

    public function onLayout(dc as Dc) as Void {
        _fontText = WatchUi.loadResource(Rez.Fonts.JBMono) as Graphics.FontType;
        _fontTime = WatchUi.loadResource(Rez.Fonts.JBMonoTime) as Graphics.FontType;
    }

    private function ft() as Graphics.FontType {
        return (_fontText != null) ? _fontText : Graphics.FONT_TINY;
    }

    public function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var battery = System.getSystemStats().battery;

        // Top battery arc - shortened (narrower span) to leave room for Data 02/03.
        drawSegmentArc(dc, cx, cy, w * 0.455, 125.0, 55.0, 16, battery / 100.0, false);

        // Data 01: battery glyph + single-row percent, pushed up into the arc's gap.
        drawBattery01(dc, cx, h * 0.15, battery);

        // Left column (02/04/06) lined up and hugging the left; right column (03/05/08) right.
        var lx = w * 0.19;
        var rx = w * 0.81;
        var steps = 0;
        var ai = ActivityMonitor.getInfo();
        if (ai has :steps && ai.steps != null) { steps = ai.steps; }

        field(dc, lx, h * 0.30, "ST", steps.toString());          // Data 02
        field(dc, rx, h * 0.30, "VO2", "52");                     // Data 03
        ringField(dc, lx, cy, w * 0.115, "HR", "80", 0.53, false); // Data 04 (closing ring)
        ringField(dc, rx, cy, w * 0.115, "BB", "120", 0.75, false);// Data 05 (closing ring)
        field(dc, lx, h * 0.70, "mb", "1019");                    // Data 06
        field(dc, rx, h * 0.70, "°C", "37");                 // Data 08

        drawTime(dc, cx, h);
        drawSeconds07(dc, cx, h * 0.72, w * 0.085);               // Data 07 (striped ring)
        drawDate(dc, cx, h);
        drawWeekCurved(dc, cx, cy, w * 0.44);
    }

    // ---- Data 01: battery ----

    private function drawBattery01(dc as Dc, cx as Numeric, y as Numeric, pct as Float) as Void {
        var bw = 26;
        var bh = 13;
        var pctStr = (pct + 0.5).toNumber().toString() + "%";
        var textW = dc.getTextWidthInPixels(pctStr, ft());
        var total = bw + 8 + textW;
        var bx = cx - (total / 2);
        var by = y - (bh / 2);
        // battery body + terminal
        dc.setColor(BRIGHT, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRectangle(bx, by, bw, bh);
        dc.fillRectangle(bx + bw, by + 3, 3, bh - 6);
        dc.setPenWidth(1);
        // fill
        var fillW = ((bw - 4) * pct / 100.0).toNumber();
        if (fillW > 0) {
            dc.fillRectangle(bx + 2, by + 2, fillW, bh - 4);
        }
        // one-row percent
        dc.setColor(BRIGHT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(bx + bw + 8, y, ft(), pctStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ---- plain fields ----

    private function field(dc as Dc, x as Numeric, y as Numeric, label as String,
                           value as String) as Void {
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y - 22, ft(), label, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(BRIGHT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, ft(), value, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! A data field ringed by a gradient closing gauge (Data 04 / 05).
    private function ringField(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric,
                               label as String, value as String, frac as Float,
                               striped as Boolean) as Void {
        drawGradientRing(dc, cx, cy, r, 6, frac, striped);
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 20, ft(), label, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(BRIGHT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 2, ft(), value, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ---- Data 07: seconds with a striped gradient ring ----

    private function drawSeconds07(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric) as Void {
        var sec = System.getClockTime().sec;
        drawGradientRing(dc, cx, cy, r, 5, sec / 60.0, true);
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 17, ft(), "SEC", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 3, ft(), sec.format("%02d"), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ---- ring + arc helpers ----

    //! A ring gauge: dim full track, then a gradient arc from the top clockwise for `frac`.
    //! `striped` leaves gaps for the Iron Grit "striped" look (Data 07).
    private function drawGradientRing(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric,
                                      penW as Number, frac as Float, striped as Boolean) as Void {
        dc.setPenWidth(penW);
        dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        var steps = 36;
        var lit = (steps * frac).toNumber();
        for (var i = 0; i < lit; i++) {
            if (striped && (i % 2 == 0)) { continue; }
            dc.setColor(lerp(GRAD_A, GRAD_B, i.toFloat() / steps), Graphics.COLOR_TRANSPARENT);
            var s = 90.0 - (i * 360.0 / steps);
            var e = 90.0 - ((i + 1) * 360.0 / steps);
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, s, e);
        }
        dc.setPenWidth(1);
    }

    //! Segmented arc (battery indicator at the top) between two math-degree angles.
    private function drawSegmentArc(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric,
                                    startDeg as Float, endDeg as Float, n as Number,
                                    frac as Float, striped as Boolean) as Void {
        var lit = (n * frac).toNumber();
        dc.setPenWidth(4);
        for (var i = 0; i < n; i++) {
            var a = (startDeg + (endDeg - startDeg) * i / (n - 1)) * Math.PI / 180.0;
            var cosA = Math.cos(a);
            var sinA = Math.sin(a);
            dc.setColor(i < lit ? lerp(GRAD_A, GRAD_B, i.toFloat() / n) : TRACK,
                Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cx + r * cosA, cy - r * sinA, cx + (r - 13) * cosA, cy - (r - 13) * sinA);
        }
        dc.setPenWidth(1);
    }

    //! Linear interpolate between two 0xRRGGBB colors.
    private function lerp(a as Number, b as Number, t as Float) as Number {
        var ar = (a >> 16) & 0xFF; var ag = (a >> 8) & 0xFF; var ab = a & 0xFF;
        var br = (b >> 16) & 0xFF; var bg = (b >> 8) & 0xFF; var bb = b & 0xFF;
        var r = (ar + ((br - ar) * t)).toNumber();
        var g = (ag + ((bg - ag) * t)).toNumber();
        var bl = (ab + ((bb - ab) * t)).toNumber();
        return (r << 16) | (g << 8) | bl;
    }

    // ---- time / date / week ----

    private function drawTime(dc as Dc, cx as Numeric, h as Numeric) as Void {
        var clock = System.getClockTime();
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(cx - (dc.getWidth() * 0.20), h * 0.30, dc.getWidth() * 0.40, h * 0.28);
        var font = (_fontTime != null) ? _fontTime : Graphics.FONT_NUMBER_MEDIUM;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.32, font,
            hour.format("%02d") + ":" + clock.min.format("%02d"), Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawDate(dc as Dc, cx as Numeric, h as Numeric) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        dc.setColor(BRIGHT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - (dc.getWidth() * 0.175), h * 0.71, ft(),
            info.month.toUpper(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx + (dc.getWidth() * 0.175), h * 0.71, ft(),
            info.day.format("%d"), Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Weekday letters curved along the bottom bezel, today in orange.
    private function drawWeekCurved(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric) as Void {
        var letters = ["S", "M", "T", "W", "T", "F", "S"];
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT).day_of_week; // 1=Sun..7=Sat
        // Span the bottom arc: math degrees 235 (lower-left) -> 305 (lower-right).
        var startDeg = 235.0;
        var endDeg = 305.0;
        for (var i = 0; i < 7; i++) {
            var a = (startDeg + (endDeg - startDeg) * i / 6) * Math.PI / 180.0;
            var x = cx + r * Math.cos(a);
            var y = cy - r * Math.sin(a);
            dc.setColor((i == today - 1) ? ACCENT : DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, ft(), letters[i],
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    public function onPartialUpdate(dc as Dc) as Void {
        drawSeconds07(dc, dc.getWidth() / 2, dc.getHeight() * 0.72, dc.getWidth() * 0.085);
    }
}
