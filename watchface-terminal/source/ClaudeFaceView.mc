import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

//! The Claude terminal watch face.
//!
//! Layout comes straight from the HTML layout editor: a prompt line, the big time, the date, then
//! three CLI-style rows (5H / 1W / model) each with a bar, percentage and reset time, a segmented
//! battery bar, and a blinking cursor. Night Owl colours on black, in IBM Plex Mono. In always-on
//! the time drops to a thin outline HH:MM and the grey tracks and mesh go (see _lowPower).
//!
//! The values come from the published complications. We can't construct a custom complication's Id
//! directly (its identity is an internal UUID), so onShow ENUMERATES the available complications,
//! keeps the ones whose label marks them as ours, subscribes, and caches value + reset epoch;
//! onComplicationChange refreshes the cache. The reset time is carried in the complication's `unit`
//! field as raw epoch-seconds and formatted here.
class ClaudeFaceView extends WatchUi.WatchFace {

    // Night Owl theme (layout editor). The background is black (dc.clear / COLOR_BLACK); the
    // VFD time's face + glow colours are baked into the bitmaps by tools/build_glow_time.py.
    private const ACCENT = 0x82AAFF;      // prompt, bar fill, cursor
    private const VALUE = 0xD6DEEB;       // time + percentage
    private const TRACK = 0x333333;       // empty bar background
    private const DIM = 0x7F9C9C;         // date, labels, reset times
    private const NEAR_CAP = 0xEF5350;    // bar fill at 80%+
    private const DEFAULT_PROMPT = "eugene@tactix ~ $";

    // --- layout (fractions of the screen), from the editor ---
    // Prompt, time and date are centred on their x; every line is top-aligned at its y.
    private const PROMPT_X = 0.436;  private const PROMPT_Y = 0.188;
    private const TIME_X = 0.500;    private const TIME_Y = 0.247;
    private const DATE_X = 0.313;    private const DATE_Y = 0.445;
    private const ROWS_Y = 0.532;    private const ROWS_GAP = 0.113;
    private const LABEL_X = 0.148;   private const BAR_X = 0.242;   private const BAR_W = 0.287;
    private const BAR_H = 0.030;     private const BAR_DY = 0.018;
    private const PCT_X = 0.639;     private const RESET_X = 0.858;
    // The editor parks the cursor at y=2.0, below the screen: it is not shown. Kept (not deleted)
    // so moving it back on-screen in the editor is a one-constant change.
    private const CURSOR_X = 0.526;  private const CURSOR_Y = 2.000;
    private const CURSOR_W = 0.030;  private const CURSOR_H = 0.028;
    // Battery bar: the straight counterpart of Claude Grid's top battery arc, at the same scale
    // (16 segments of 10 x 15 px, 5 px apart on the 454 px screen = 235 px long). Centred on
    // BATT_X, top at BATT_Y, just below the meter rows. Sizes are fractions of the WIDTH, like
    // the meter bars, so the bar keeps its proportions on every screen size.
    private const BATT_X = 0.500;    private const BATT_Y = 0.845;
    private const BATT_SEGS = 16;
    private const BATT_SEG_W = 0.022; private const BATT_GAP = 0.011; private const BATT_H = 0.033;
    private const BATT_LOW = 20;     // at or below this %, the lit segments turn NEAR_CAP red

    // One cache slot per meter. pct is -1 until a value arrives; resetEpoch 0 means none.
    private var _labels as Array<String> = ["5H", "1W", "--"];
    private var _pcts as Array<Number> = [-1, -1, -1];
    private var _resets as Array<Number> = [0, 0, 0];
    private var _ids as Array<Complications.Id?> = [null, null, null];
    private var _subscribed as Boolean = false;
    private var _showSeconds as Boolean = true;
    private var _prompt as String = DEFAULT_PROMPT;   // PromptText setting (Garmin Connect / editor)

    // IBM Plex Mono, loaded from resources - the terminal typeface for every element, at the
    // editor's sizes: prompt 26px, date + rows 25px, time 70px.
    private var _fontText as Graphics.FontType?;
    private var _fontSmall as Graphics.FontType?;
    private var _fontTime as Graphics.FontType?;
    private var _fontTimeO as Graphics.FontType?;   // 2 px hollow outline time - always-on

    // Always-on (low power), the same scheme as Claude Grid: onEnterSleep / onExitSleep flip it.
    // The AMOLED burn-in budget wants few, thin lit pixels, so while it is set the face draws
    // the time as HH:MM in the hollow outline font (no glow bitmaps, no seconds, no per-second
    // repaint), drops the full-face mesh and every grey track (meter bar backgrounds, unlit
    // battery segments), and keeps only the text and the filled bar/battery portions.
    private var _lowPower as Boolean = false;

    public function initialize() {
        WatchFace.initialize();
    }

    public function onLayout(dc as Dc) as Void {
        _fontText = WatchUi.loadResource(Rez.Fonts.STMono) as Graphics.FontType;
        _fontSmall = WatchUi.loadResource(Rez.Fonts.STMonoSmall) as Graphics.FontType;
        _fontTime = WatchUi.loadResource(Rez.Fonts.STMonoTime) as Graphics.FontType;
        _fontTimeO = WatchUi.loadResource(Rez.Fonts.STMonoTimeOutline) as Graphics.FontType;
    }

    //! The prompt font (26px), falling back to the system font if the resource ever fails.
    private function ft() as Graphics.FontType {
        return (_fontText != null) ? _fontText : Graphics.FONT_TINY;
    }

    //! The date + meter-row font (25px), same fallback.
    private function fs() as Graphics.FontType {
        return (_fontSmall != null) ? _fontSmall : Graphics.FONT_TINY;
    }

    public function onShow() as Void {
        _lowPower = false;
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

    //! The "show seconds" toggle and the prompt text, from the watch/app settings.
    public function readSettings() as Void {
        var v = Application.Properties.getValue("ShowSeconds");
        _showSeconds = (v instanceof Boolean) ? v : true;
        var p = Application.Properties.getValue("PromptText");
        _prompt = (p instanceof String) ? p as String : DEFAULT_PROMPT;
    }

    // ---- whole-pixel drawing -----------------------------------------------------------------
    // Every position here is a fraction of the screen, i.e. a Float. With anti-aliasing on, a
    // fractional origin risks a glyph or bar edge being spread across two pixel rows/columns
    // (soft text, blurry bar ends). These helpers resolve everything to integer pixels first.

    private function px(v as Numeric) as Number {
        return Math.round(v.toFloat()).toNumber();
    }

    //! Pixel-snapped drawText with top-aligned text (the terminal's convention): the
    //! justification is resolved to an integer left edge against the measured width.
    private function text(dc as Dc, x as Numeric, y as Numeric, font as Graphics.FontType,
                          s as String, just as Number) as Void {
        var left = px(x);
        if (just == Graphics.TEXT_JUSTIFY_CENTER) {
            left -= dc.getTextWidthInPixels(s, font) / 2;
        } else if (just == Graphics.TEXT_JUSTIFY_RIGHT) {
            left -= dc.getTextWidthInPixels(s, font);
        }
        dc.drawText(left, px(y), font, s, Graphics.TEXT_JUSTIFY_LEFT);
    }

    //! Pixel-snapped filled rectangle: integer edges, so bar ends are hard.
    private function rect(dc as Dc, x as Numeric, y as Numeric, w as Numeric, h as Numeric) as Void {
        var x0 = px(x);
        var y0 = px(y);
        dc.fillRectangle(x0, y0, px(x + w) - x0, px(y + h) - y0);
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
            // Keep labels to 2 chars, uppercased, so a long model name ("Fable") shows as "FA"
            // and never overruns into the bar. "5H"/"1W" are unchanged.
            var s = sl as String;
            if (s.length() > 2) {
                var sub = s.substring(0, 2);
                if (sub != null) { s = sub; }
            }
            _labels[slot] = s.toUpper();
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

        drawHeader(dc, w, h);

        // Three CLI rows.
        for (var i = 0; i < 3; i++) {
            drawRow(dc, i, w, h, ROWS_Y + ROWS_GAP * i);
        }

        drawBattery(dc, w, h);

        // Blinking cursor (a no-op while the layout parks it off-screen). Not in always-on: a
        // once-a-minute update can't blink it.
        if (!_lowPower && System.getClockTime().sec % 2 == 0) {
            dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
            rect(dc, w * CURSOR_X - w * CURSOR_W / 2.0, h * CURSOR_Y, w * CURSOR_W, h * CURSOR_H);
        }

        // VFD build: one screen-aligned mesh over everything, drawn last (no-op otherwise).
        // Skipped in always-on, like Claude Grid: it would break up the thin outline time.
        if (!_lowPower) {
            drawMeshOverlay(dc, w, h, 0, 0, w, h);
        }
    }

    //! Always-on on: repaint once in the low-power style (see _lowPower).
    public function onEnterSleep() as Void {
        _lowPower = true;
        WatchUi.requestUpdate();
    }

    //! Back to high power: full style, and seconds resume with the next partial update.
    public function onExitSleep() as Void {
        _lowPower = false;
        WatchUi.requestUpdate();
    }

    //! Seconds tick here when the device allows partial updates; onUpdate handles the rest.
    //!
    //! Only the time's band is repainted, clipped. The band is the time's real extent (the glow
    //! bitmaps' cell in the VFD build, the font's line height otherwise), which at this layout
    //! reaches into the prompt's descenders above and the date's line box below. So inside the
    //! clip the band is blanked and the prompt, time and date are all redrawn in onUpdate's order:
    //! every pixel in the band is then painted from black exactly once, as in a full update (text
    //! drawn over its own anti-aliased edges without a blank would darken them each second).
    public function onPartialUpdate(dc as Dc) as Void {
        // No seconds in always-on (the outline time is HH:MM), so nothing to tick.
        if (!_showSeconds || _lowPower) {
            return;
        }
        var w = dc.getWidth();
        var h = dc.getHeight();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
        var band = timeBand(h);          // [top, height] in whole pixels
        // Never reach the meter rows, which are not redrawn here. On the small (260/280 px) screens
        // the time font's line box runs past the first row's top; the digit ink itself stops short.
        var rowsTop = px(h * ROWS_Y);
        if (band[0] + band[1] > rowsTop) {
            band[1] = rowsTop - band[0];
        }
        dc.setClip(0, band[0], w, band[1]);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, band[0], w, band[1]);
        drawHeader(dc, w, h);
        dc.clearClip();
        // re-mesh just the repainted band (same lattice, so it lines up with the rest)
        drawMeshOverlay(dc, w, h, 0, band[0], w, band[1]);
    }

    //! Prompt line, time and date - the three lines the seconds repaint may touch.
    private function drawHeader(dc as Dc, w as Numeric, h as Numeric) as Void {
        // Prompt line (the PromptText setting), accent colour.
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        text(dc, w * PROMPT_X, h * PROMPT_Y, ft(), _prompt, Graphics.TEXT_JUSTIFY_CENTER);

        drawTime(dc, w, h);

        // Date.
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = info.day_of_week + " " + info.month + " " + info.day.format("%d");
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        text(dc, w * DATE_X, h * DATE_Y, fs(), dateStr, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function timeFont() as Graphics.FontType {
        return (_fontTime != null) ? _fontTime : Graphics.FONT_NUMBER_MEDIUM;
    }

    //! Draws the time; the caller has already painted the background under it (the full clear in
    //! onUpdate, the clipped band blank in onPartialUpdate).
    private function drawTime(dc as Dc, w as Numeric, h as Numeric) as Void {
        var clock = System.getClockTime();
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var t = hour.format("%02d") + ":" + clock.min.format("%02d");
        var ty = px(h * TIME_Y);
        if (_lowPower) {
            // Always-on: HH:MM in the hollow outline font, never the glow bitmaps (a lit bloom
            // would blow the AMOLED burn-in budget). Same top as the solid time - the outline
            // font shares its line metrics - so the time doesn't jump on entering sleep.
            dc.setColor(VALUE, Graphics.COLOR_TRANSPARENT);
            text(dc, w * TIME_X, ty, (_fontTimeO != null) ? _fontTimeO : timeFont(), t,
                Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        if (_showSeconds) {
            t += ":" + clock.sec.format("%02d");
        }
        var font = timeFont();
        if (_fontTime != null && drawGlowTime(dc, px(w * TIME_X), ty, font, t)) {
            return;
        }
        dc.setColor(VALUE, Graphics.COLOR_TRANSPARENT);
        text(dc, w * TIME_X, ty, font, t, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ---- VFD style (optional build, selected in monkey.jungle) ---------------------------------
    // Same scheme as Claude Grid: the time drawn from pre-rendered glow bitmaps (source-glow/ +
    // resources-glow/, tools/build_glow_time.py) and one mesh tile tiled over the whole face
    // (resources-mesh/). The annotations pick the implementation compiled in.

    (:glow_time)
    private function drawGlowTime(dc as Dc, cx as Number, top as Number, font as Graphics.FontType,
                                  t as String) as Boolean {
        GlowTime.draw(dc, cx, top, font, t);
        return true;
    }

    (:font_time)
    private function drawGlowTime(dc as Dc, cx as Number, top as Number, font as Graphics.FontType,
                                  t as String) as Boolean {
        return false;
    }

    //! The rows the time occupies, as [top, height] in pixels. VFD build: the glow bitmaps' cell
    //! (glyph ink + bloom, generated into GlowTimeMetrics), unless the time font failed to load and
    //! drawTime fell back to the system font.
    (:glow_time)
    private function timeBand(h as Numeric) as Array<Number> {
        var ty = px(h * TIME_Y);
        if (_fontTime != null) {
            return [ty + GlowTimeMetrics.Y0, GlowTimeMetrics.H];
        }
        return [ty, Graphics.getFontHeight(timeFont())];
    }

    //! Plain build: the time font's line box (+1 for CIQ drawing glyphs one row low).
    (:font_time)
    private function timeBand(h as Numeric) as Array<Number> {
        return [px(h * TIME_Y), Graphics.getFontHeight(timeFont()) + 1];
    }

    (:mesh_overlay)
    private var _meshTile = null;

    //! Tile the mesh over the given screen rectangle (clipped to it), tiles anchored at the screen
    //! origin so every call hits the same lattice.
    (:mesh_overlay)
    private function drawMeshOverlay(dc as Dc, w as Number, h as Number, x as Number, y as Number,
                                     cw as Number, ch as Number) as Void {
        if (_meshTile == null) {
            _meshTile = WatchUi.loadResource(Rez.Drawables.MeshTile);
        }
        var s = (_meshTile as Graphics.BitmapReference).getWidth();
        if (s <= 0) { return; }
        dc.setClip(x, y, cw, ch);
        for (var ty = (y / s) * s; ty < y + ch; ty += s) {
            for (var tx = (x / s) * s; tx < x + cw; tx += s) {
                dc.drawBitmap(tx, ty, _meshTile);
            }
        }
        dc.clearClip();
    }

    (:plain_overlay)
    private function drawMeshOverlay(dc as Dc, w as Number, h as Number, x as Number, y as Number,
                                     cw as Number, ch as Number) as Void {
    }

    //! One row: label, bar, percentage, reset time. Columns are fixed fractions of the width so the
    //! three rows align and stay within the round bezel's safe band. Everything is snapped to whole
    //! pixels - the bars especially, whose fractional edges used to render soft.
    private function drawRow(dc as Dc, slot as Number, w as Numeric, h as Numeric, yf as Float) as Void {
        var y = h * yf;
        var pct = _pcts[slot];

        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        text(dc, w * LABEL_X, y, fs(), _labels[slot], Graphics.TEXT_JUSTIFY_LEFT);

        // Bar: integer track, and an integer-width fill measured from the same left edge.
        var bx = px(w * BAR_X);
        var bw = px(w * BAR_W);
        var by = px(y + w * BAR_DY);
        var bh = px(w * BAR_H);
        if (!_lowPower) {   // always-on keeps only the filled part (see _lowPower)
            dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx, by, bw, bh);
        }
        if (pct >= 0) {
            var clamped = (pct > 100) ? 100 : pct;
            var fw = px(bw * clamped / 100.0);
            if (fw > 0) {
                dc.setColor(pct >= 80 ? NEAR_CAP : ACCENT, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(bx, by, fw, bh);
            }
        }

        // Percentage.
        dc.setColor(VALUE, Graphics.COLOR_TRANSPARENT);
        var pctTxt = (pct >= 0) ? (pct.toString() + "%") : "--";
        text(dc, w * PCT_X, y, fs(), pctTxt, Graphics.TEXT_JUSTIFY_RIGHT);

        // Reset time.
        var reset = resetsAt(_resets[slot]);
        if (!reset.equals("")) {
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            text(dc, w * RESET_X, y, fs(), reset, Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }
    //! The watch battery as a straight row of segments - every edge on a whole pixel (integer
    //! segment width, gap and origin), so the segments are as crisp as the meter bars. A segment
    //! lights as soon as its share has started (ceil), so any charge left shows at least one;
    //! at BATT_LOW or below the lit ones turn red. Redrawn once a minute with the full update,
    //! which is plenty for a battery level.
    private function drawBattery(dc as Dc, w as Numeric, h as Numeric) as Void {
        var sw = px(w * BATT_SEG_W);
        if (sw < 1) { sw = 1; }
        var gap = px(w * BATT_GAP);
        var bh = px(w * BATT_H);
        if (bh < 1) { bh = 1; }
        var total = BATT_SEGS * sw + (BATT_SEGS - 1) * gap;
        var x0 = px(w * BATT_X) - total / 2;
        var y0 = px(h * BATT_Y);

        var pct = System.getSystemStats().battery;               // Float 0-100
        var lit = Math.ceil(BATT_SEGS * pct / 100.0).toNumber();
        if (lit > BATT_SEGS) { lit = BATT_SEGS; }
        if (lit < 0) { lit = 0; }
        var on = (pct <= BATT_LOW) ? NEAR_CAP : ACCENT;

        for (var i = 0; i < BATT_SEGS; i++) {
            if (i >= lit && _lowPower) { break; }   // always-on: lit segments only
            dc.setColor(i < lit ? on : TRACK, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x0 + i * (sw + gap), y0, sw, bh);
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
