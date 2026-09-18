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
//! Layout, top to bottom on the round screen: a prompt/header line, the time, the date, then
//! three CLI-style rows (5H / 1W / model) each with a bar, percentage, and reset time, and a
//! blinking cursor. Dark background, Claude orange throughout the chrome.
//!
//! The values come from the published complications. We can't construct a custom
//! complication's Id directly (its identity is an internal UUID), so onShow ENUMERATES the
//! available complications, keeps the ones whose label marks them as ours, subscribes, and
//! caches value + reset epoch; onComplicationChange refreshes the cache. The reset time is
//! carried in the complication's `unit` field as raw epoch-seconds and formatted here.
class ClaudeFaceView extends WatchUi.WatchFace {

    private const ACCENT = 0xD97757;      // Claude orange - used for all chrome
    private const TRACK = 0x333333;       // bar background
    private const DIM = 0xAAAAAA;         // labels / secondary text
    private const NEAR_CAP = 0xFF5F5F;    // 80%+ turns red

    // One cache slot per meter. pct is -1 until a value arrives; resetEpoch 0 means none.
    private var _labels as Array<String> = ["5H", "1W", "--"];
    private var _pcts as Array<Number> = [-1, -1, -1];
    private var _resets as Array<Number> = [0, 0, 0];
    private var _ids as Array<Complications.Id?> = [null, null, null];
    private var _subscribed as Boolean = false;
    private var _showSeconds as Boolean = false;

    // JetBrains Mono, loaded from resources - the terminal typeface for every element.
    private var _fontText as Graphics.FontType?;
    private var _fontTime as Graphics.FontType?;

    public function initialize() {
        WatchFace.initialize();
    }

    public function onLayout(dc as Dc) as Void {
        _fontText = WatchUi.loadResource(Rez.Fonts.JBMono) as Graphics.FontType;
        _fontTime = WatchUi.loadResource(Rez.Fonts.JBMonoTime) as Graphics.FontType;
    }

    //! JetBrains Mono for text, falling back to the system font if the resource ever fails.
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
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var cx = w / 2;

        // Header prompt, Claude orange. Kept short so it clears the round bezel at the top of
        // the screen (its narrowest point) - the full "claude@tactix ~ %" was cut off there.
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.10, ft(), "claude ~ %", Graphics.TEXT_JUSTIFY_CENTER);

        drawTime(dc, cx, h);

        // Date.
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = info.day_of_week + " " + info.month + " " + info.day.format("%d");
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.40, ft(), dateStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Three CLI rows.
        var rowY = [h * 0.54, h * 0.645, h * 0.75];
        for (var i = 0; i < 3; i++) {
            drawRow(dc, i, w, rowY[i]);
        }

        // Blinking cursor.
        if (System.getClockTime().sec % 2 == 0) {
            dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(cx - (w * 0.01), h * 0.87, w * 0.03, h * 0.028);
        }
    }

    //! Seconds tick here when the device allows partial updates; onUpdate handles the rest.
    public function onPartialUpdate(dc as Dc) as Void {
        if (_showSeconds) {
            drawTime(dc, dc.getWidth() / 2, dc.getHeight());
        }
    }

    private function drawTime(dc as Dc, cx as Numeric, h as Numeric) as Void {
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
        // Repaint the time band first so onPartialUpdate doesn't smear seconds.
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, h * 0.14, dc.getWidth(), h * 0.24);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var font = (_fontTime != null) ? _fontTime : Graphics.FONT_NUMBER_MEDIUM;
        dc.drawText(cx, h * 0.17, font, t, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! One row: label, bar, percentage, reset time. Columns are fixed fractions of the width
    //! so the three rows align and stay within the round bezel's safe band.
    private function drawRow(dc as Dc, slot as Number, w as Numeric, y as Numeric) as Void {
        var pct = _pcts[slot];

        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 0.15, y, ft(), _labels[slot], Graphics.TEXT_JUSTIFY_LEFT);

        // Bar.
        var barLeft = w * 0.32;
        var barW = w * 0.16;
        var barY = y + (w * 0.018);
        var barH = w * 0.035;
        dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(barLeft, barY, barW, barH);
        if (pct >= 0) {
            var clamped = (pct > 100) ? 100 : pct;
            dc.setColor(pct >= 80 ? NEAR_CAP : ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(barLeft, barY, barW * clamped / 100.0, barH);
        }

        // Percentage.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var pctTxt = (pct >= 0) ? (pct.toString() + "%") : "--";
        dc.drawText(w * 0.65, y, ft(), pctTxt, Graphics.TEXT_JUSTIFY_RIGHT);

        // Reset time.
        var reset = resetsAt(_resets[slot]);
        if (!reset.equals("")) {
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w * 0.86, y, ft(), reset, Graphics.TEXT_JUSTIFY_RIGHT);
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
