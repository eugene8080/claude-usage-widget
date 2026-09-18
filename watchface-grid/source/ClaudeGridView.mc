import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

//! "Claude Grid" - an Iron Grit-style data face laid out in JetBrains Mono.
//!
//! Composition (round screen, fractions of width/height):
//!   - a segmented battery arc across the top
//!   - eight data-field positions: two upper corners, two mid sides, two lower corners, one
//!     top-centre (battery), one bottom-centre (seconds subdial)
//!   - the big time in the middle, the date (month / day) flanking the seconds, and a
//!     weekday strip along the bottom with today picked out
//!
//! This version fills the fields with representative values plus the trivially-real ones
//! (battery, steps, seconds, time, date, weekday). Wiring each field to a user-selectable
//! Garmin complication via the native editor is the planned next step.
class ClaudeGridView extends WatchUi.WatchFace {

    private const ACCENT = 0xD97757;   // Claude orange
    private const BRIGHT = 0xF2A98C;   // lighter orange for field values
    private const DIM = 0x888888;      // labels / inactive
    private const TRACK = 0x333333;

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
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        drawBatteryArc(dc, cx, h * 0.5, w * 0.46);

        // Eight data fields. label, value, x-fraction, y-fraction.
        var stats = System.getSystemStats();
        var batt = (stats.battery + 0.5).toNumber();
        var steps = 0;
        var ai = ActivityMonitor.getInfo();
        if (ai has :steps && ai.steps != null) { steps = ai.steps; }

        field(dc, w, h, "BAT", batt.toString() + "%", 0.50, 0.155, true);   // Data 01 top-centre
        field(dc, w, h, "ST",  steps.toString(),        0.25, 0.30,  false);  // Data 02 top-left
        field(dc, w, h, "VO2", "52",                    0.75, 0.30,  false);  // Data 03 top-right
        field(dc, w, h, "HR",  "80",                    0.155, 0.47, false);  // Data 04 mid-left
        field(dc, w, h, "BB",  "120",                   0.845, 0.47, false);  // Data 05 mid-right
        field(dc, w, h, "mb",  "1019",                  0.25, 0.645, false);  // Data 06 bottom-left
        field(dc, w, h, "°C",  "37",                    0.75, 0.645, false);  // Data 08 bottom-right

        drawTime(dc, cx, h);
        drawSecondsAndDate(dc, cx, h);      // Data 07 (seconds) + date
        drawWeek(dc, cx, w, h);
    }

    //! Segmented arc across the top, filled to the battery level.
    private function drawBatteryArc(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric) as Void {
        var n = 20;
        var startDeg = 145.0;   // upper-left (math degrees, 90 = top)
        var endDeg = 35.0;      // upper-right
        var lit = (n * System.getSystemStats().battery / 100.0).toNumber();
        for (var i = 0; i < n; i++) {
            var a = (startDeg + (endDeg - startDeg) * i / (n - 1)) * Math.PI / 180.0;
            var cosA = Math.cos(a);
            var sinA = Math.sin(a);
            dc.setColor(i < lit ? ACCENT : TRACK, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(3);
            dc.drawLine(cx + r * cosA, cy - r * sinA,
                        cx + (r - 12) * cosA, cy - (r - 12) * sinA);
        }
        dc.setPenWidth(1);
    }

    //! One data field: small label above a value, centred on (fx,fy).
    private function field(dc as Dc, w as Numeric, h as Numeric, label as String,
                           value as String, fx as Float, fy as Float, big as Boolean) as Void {
        var x = w * fx;
        var y = h * fy;
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y - (h * 0.055), ft(), label, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(big ? ACCENT : BRIGHT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, ft(), value, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawTime(dc as Dc, cx as Numeric, h as Numeric) as Void {
        var clock = System.getClockTime();
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        // Repaint the centre band first so onPartialUpdate can refresh cleanly.
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(cx - (dc.getWidth() * 0.22), h * 0.30, dc.getWidth() * 0.44, h * 0.28);
        var font = (_fontTime != null) ? _fontTime : Graphics.FONT_NUMBER_MEDIUM;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.32, font,
            hour.format("%02d") + ":" + clock.min.format("%02d"),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Bottom-centre seconds subdial (Data 07) with the month and day flanking it.
    private function drawSecondsAndDate(dc as Dc, cx as Numeric, h as Numeric) as Void {
        var clock = System.getClockTime();
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);

        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.66, ft(), "SEC", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.71, ft(), clock.sec.format("%02d"), Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(BRIGHT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - (dc.getWidth() * 0.17), h * 0.70, ft(),
            info.month.toUpper(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx + (dc.getWidth() * 0.17), h * 0.70, ft(),
            info.day.format("%d"), Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Weekday strip, today in orange.
    private function drawWeek(dc as Dc, cx as Numeric, w as Numeric, h as Numeric) as Void {
        var letters = ["S", "M", "T", "W", "T", "F", "S"];
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT).day_of_week; // 1=Sun..7=Sat
        var span = w * 0.52;
        var step = span / 6;
        var x0 = cx - (span / 2);
        for (var i = 0; i < 7; i++) {
            dc.setColor((i == today - 1) ? ACCENT : DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x0 + (i * step), h * 0.83, ft(), letters[i], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    public function onPartialUpdate(dc as Dc) as Void {
        // Refresh only the seconds subdial each tick.
        var clock = System.getClockTime();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(dc.getWidth() * 0.40, dc.getHeight() * 0.71,
            dc.getWidth() * 0.20, dc.getHeight() * 0.06);
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() * 0.71, ft(),
            clock.sec.format("%02d"), Graphics.TEXT_JUSTIFY_CENTER);
    }
}
