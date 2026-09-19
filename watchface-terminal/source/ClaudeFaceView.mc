import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

//! The Claude terminal watch face.
//!
//! Layout comes straight from the HTML layout editor: a prompt line, the big time, the date, then
//! three CLI-style rows (5H / 1W / model) each with a bar, percentage and reset time, and a
//! blinking cursor. Dark background, Claude orange chrome, in Share Tech Mono.
//!
//! The values come from the published complications. We can't construct a custom complication's Id
//! directly (its identity is an internal UUID), so onShow ENUMERATES the available complications,
//! keeps the ones whose label marks them as ours, subscribes, and caches value + reset epoch;
//! onComplicationChange refreshes the cache. The reset time is carried in the complication's `unit`
//! field as raw epoch-seconds and formatted here.
class ClaudeFaceView extends WatchUi.WatchFace {

    private const ACCENT = 0xD97757;      // Claude orange - prompt, bar fill, cursor
    private const VALUE = 0xFFFFFF;       // time + percentage
    private const TRACK = 0x333333;       // empty bar background
    private const DIM = 0xAAAAAA;         // date, labels, reset times
    private const NEAR_CAP = 0xFF5F5F;    // bar fill at 80%+

    // --- layout (fractions of the screen), from the editor ---
    private const PROMPT_X = 0.305;  private const PROMPT_Y = 0.177;
    private const TIME_X = 0.402;    private const TIME_Y = 0.250;
    private const DATE_X = 0.305;    private const DATE_Y = 0.454;
    private const ROWS_Y = 0.556;    private const ROWS_GAP = 0.113;
    private const LABEL_X = 0.148;   private const BAR_X = 0.242;   private const BAR_W = 0.287;
    private const BAR_H = 0.030;     private const BAR_DY = 0.018;
    private const PCT_X = 0.639;     private const RESET_X = 0.858;
    private const CURSOR_X = 0.526;  private const CURSOR_Y = 0.469;
    private const CURSOR_W = 0.030;  private const CURSOR_H = 0.028;

    // One cache slot per meter. pct is -1 until a value arrives; resetEpoch 0 means none.
    private var _labels as Array<String> = ["5H", "1W", "--"];
    private var _pcts as Array<Number> = [-1, -1, -1];
    private var _resets as Array<Number> = [0, 0, 0];
    private var _ids as Array<Complications.Id?> = [null, null, null];
    private var _subscribed as Boolean = false;
    private var _showSeconds as Boolean = false;

    // Share Tech Mono, loaded from resources - the terminal typeface for every element.
    private var _fontText as Graphics.FontType?;
    private var _fontTime as Graphics.FontType?;

    public function initialize() {
        WatchFace.initialize();
    }

    public function onLayout(dc as Dc) as Void {
        _fontText = WatchUi.loadResource(Rez.Fonts.STMono) as Graphics.FontType;
        _fontTime = WatchUi.loadResource(Rez.Fonts.STMonoTime) as Graphics.FontType;
    }

    //! Share Tech Mono for text, falling back to the system font if the resource ever fails.
    private function ft() as Graphics.FontType {
        return (_fontText != null) ? _fontText : Graphics.FONT_TINY;
    }

    public function onShow() as Void {
        readSettings();
        if (!(Toybox has :Complications)) {
            return;
        }
        try {
            findAndSubscribe();
        } catch (e) {
            System.println("complication subscribe failed: " + e.getErrorMessage());
        }
    }

    //! The "show seconds" toggle, from the watch/app settings.
    private function readSettings() as Void {
        var v = Application.Properties.getValue("ShowSeconds");
        _showSeconds = (v instanceof Boolean) ? v : false;
    }

    private function findAndSubscribe() as Void {
        var iter = Complications.getComplications();
        var comp = iter.next();
        while (comp != null) {
            var long = comp.longLabel;
            if (long != null && (long as String).find("Claude") != null) {
                var slot = slotFor(long as String);
                if (slot >= 0) {
                    _ids[slot] = comp.complicationId;
                    cache(slot, comp);
                    Complications.subscribeToUpdates(comp.complicationId);
                }
            }
            comp = iter.next();
        }
        Complications.registerComplicationChangeCallback(method(:onComplicationChange));
        _subscribed = true;
    }

    private function slotFor(longLabel as String) as Number {
        if (longLabel.find("5-hour") != null) { return 0; }
        if (longLabel.find("weekly") != null && longLabel.find("model") == null) { return 1; }
        if (longLabel.find("model") != null) { return 2; }
        return -1;
    }

    public function onComplicationChange(id as Complications.Id) as Void {
        for (var i = 0; i < 3; i++) {
            if (_ids[i] != null && (_ids[i] as Complications.Id).equals(id)) {
                cache(i, Complications.getComplication(id));
                WatchUi.requestUpdate();
                return;
            }
        }
    }

    private function cache(slot as Number, comp as Complications.Complication or Null) as Void {
        if (comp == null) {
            return;
        }
        var v = comp.value;
        _pcts[slot] = (v instanceof Number) ? v : -1;
        var sl = comp.shortLabel;
        if (sl != null) {
            _labels[slot] = sl as String;
        }
        // The reset epoch rides in `unit` as a numeric string.
        _resets[slot] = parseEpoch(comp.unit);
    }

    private function parseEpoch(unit as Object or Null) as Number {
        if (unit instanceof String) {
            var n = (unit as String).toNumber();
            if (n != null) { return n; }
        }
        return 0;
    }

    public function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // Prompt line, Claude orange.
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * PROMPT_X, h * PROMPT_Y, ft(), "claude ~ %", Graphics.TEXT_JUSTIFY_CENTER);

        drawTime(dc, w, h);

        // Date.
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = info.day_of_week + " " + info.month + " " + info.day.format("%d");
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * DATE_X, h * DATE_Y, ft(), dateStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Three CLI rows.
        for (var i = 0; i < 3; i++) {
            drawRow(dc, i, w, h, ROWS_Y + ROWS_GAP * i);
        }

        // Blinking cursor.
        if (System.getClockTime().sec % 2 == 0) {
            dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(w * CURSOR_X - w * CURSOR_W / 2.0, h * CURSOR_Y, w * CURSOR_W, h * CURSOR_H);
        }
    }

    //! Seconds tick here when the device allows partial updates; onUpdate handles the rest.
    public function onPartialUpdate(dc as Dc) as Void {
        if (_showSeconds) {
            drawTime(dc, dc.getWidth(), dc.getHeight());
        }
    }

    private function drawTime(dc as Dc, w as Numeric, h as Numeric) as Void {
        var clock = System.getClockTime();
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var t = hour.format("%02d") + ":" + clock.min.format("%02d");
        if (_showSeconds) {
            t += ":" + clock.sec.format("%02d");
        }
        // Repaint just the time band first so onPartialUpdate doesn't smear seconds (kept clear of
        // the prompt above and the date below).
        var ty = h * TIME_Y;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, ty - 3, w, h * 0.200);
        dc.setColor(VALUE, Graphics.COLOR_TRANSPARENT);
        var font = (_fontTime != null) ? _fontTime : Graphics.FONT_NUMBER_MEDIUM;
        dc.drawText(w * TIME_X, ty, font, t, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! One row: label, bar, percentage, reset time. Columns are fixed fractions of the width so the
    //! three rows align and stay within the round bezel's safe band.
    private function drawRow(dc as Dc, slot as Number, w as Numeric, h as Numeric, yf as Float) as Void {
        var y = h * yf;
        var pct = _pcts[slot];

        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * LABEL_X, y, ft(), _labels[slot], Graphics.TEXT_JUSTIFY_LEFT);

        // Bar.
        var bx = w * BAR_X;
        var bw = w * BAR_W;
        var by = y + w * BAR_DY;
        var bh = w * BAR_H;
        dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(bx, by, bw, bh);
        if (pct >= 0) {
            var clamped = (pct > 100) ? 100 : pct;
            dc.setColor(pct >= 80 ? NEAR_CAP : ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx, by, bw * clamped / 100.0, bh);
        }

        // Percentage.
        dc.setColor(VALUE, Graphics.COLOR_TRANSPARENT);
        var pctTxt = (pct >= 0) ? (pct.toString() + "%") : "--";
        dc.drawText(w * PCT_X, y, ft(), pctTxt, Graphics.TEXT_JUSTIFY_RIGHT);

        // Reset time.
        var reset = resetsAt(_resets[slot]);
        if (!reset.equals("")) {
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w * RESET_X, y, ft(), reset, Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }

    //! Absolute reset time, the way the phone and glance state it: clock time within a day,
    //! weekday within the week, month/day beyond. Empty when no reset is known.
    private function resetsAt(epochSec as Number) as String {
        if (epochSec == 0) {
            return "";
        }
        var secs = epochSec - Time.now().value();
        if (secs <= 0) {
            return "now";
        }
        var moment = new Time.Moment(epochSec);
        if (secs < 86400) {
            var i = Gregorian.info(moment, Time.FORMAT_SHORT);
            var mm = i.min.format("%02d");
            if (System.getDeviceSettings().is24Hour) {
                return i.hour.format("%d") + ":" + mm;
            }
            var hr = i.hour % 12;
            if (hr == 0) { hr = 12; }
            return hr.format("%d") + ":" + mm + (i.hour < 12 ? "a" : "p");
        }
        var g = Gregorian.info(moment, Time.FORMAT_MEDIUM);
        if (secs < 7 * 86400) {
            return g.day_of_week;
        }
        return g.month + " " + g.day.format("%d");
    }

    public function onHide() as Void {
        if (_subscribed && Toybox has :Complications) {
            Complications.unsubscribeFromAllUpdates();
            _subscribed = false;
        }
    }
}
