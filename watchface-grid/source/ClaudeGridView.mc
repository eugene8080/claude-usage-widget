import Toybox.Application;
import Toybox.Application.WatchFaceConfig;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.Weather;

//! "Claude Grid" - Iron Grit-style data face in Chakra Petch. Field naming follows the Iron
//! Grit "Data Position" chart: Data 01 top-centre, 02/04/06 down the left, 03/05/08 down the
//! right, 07 bottom-centre, plus Time (stacked HH/MM), Date and Week.
//!
//! Seven of the fields (Data 01-06, 08) are user-editable complication slots configured with
//! Garmin's native on-device editor; the assigned complication's label + value are drawn at the
//! slot, and the two ring slots (04/05) also gauge it. Data 07 is a fixed live seconds dial.
//! The top battery arc is ambient (always system battery). Accent and data colours are editable.
class ClaudeGridView extends WatchUi.WatchFace {

    private const DIM = 0x888888;                 // labels / inactive
    private const _DEFAULT_ACCENT = 0xE95625;     // Claude orange R233 G86 B37
    private const _DEFAULT_DATA = 0xFFA480;       // peach - data values

    private const TIME_GAP = 54;                  // HH / MM each this far from the vertical centre

    private var _fTime as Graphics.FontType?;     // 120px digits - the clock
    private var _fRing as Graphics.FontType?;     // 36px digits  - ring values
    private var _fValue as Graphics.FontType?;    // 32px         - chip values + date
    private var _fSmall as Graphics.FontType?;    // 22px         - battery %, weekday letters
    private var _fLabel as Graphics.FontType?;    // 16px         - field labels
    private var _fIcon as Graphics.FontType?;     // 24px         - Tabler per-field icons

    private var _editMode as Boolean = false;
    private var _accentColor as Number = _DEFAULT_ACCENT;
    private var _dataColor as Number = _DEFAULT_DATA;

    //! 0..1 multiplier that sweeps the ring gauges in on wake. Public so WatchUi.animate() can
    //! drive it by symbol. Defaults to 1.0 (fully drawn) so the rings are never stuck empty if
    //! animation is unavailable on the device.
    public var ringSweep as Float = 1.0;

    private var _slots as Array<ClaudeGridSlot> = [];
    private var _slotIds as Dictionary = {};      // uid (Number) -> Complications.Id

    // edit-mode preview state
    private var _editingSlot as Boolean = false;
    private var _selectedUid as Number? = null;

    public function initialize(editMode as Boolean) {
        WatchFace.initialize();
        _editMode = editMode;
    }

    public function onLayout(dc as Dc) as Void {
        _fTime = WatchUi.loadResource(Rez.Fonts.CPTime) as Graphics.FontType;
        _fRing = WatchUi.loadResource(Rez.Fonts.CPRing) as Graphics.FontType;
        _fValue = WatchUi.loadResource(Rez.Fonts.CPValue) as Graphics.FontType;
        _fSmall = WatchUi.loadResource(Rez.Fonts.CPSmall) as Graphics.FontType;
        _fLabel = WatchUi.loadResource(Rez.Fonts.CPLabel) as Graphics.FontType;
        _fIcon = WatchUi.loadResource(Rez.Fonts.TablerIcon) as Graphics.FontType;

        buildSlots(dc.getWidth(), dc.getHeight());

        // Seed every slot with its sensible default, then let the saved config override.
        for (var i = 0; i < _slots.size(); i++) {
            var uid = _slots[i].uid;
            updateSlotText(uid);
        }

        var settings = WatchFaceConfig.getSettings(null);
        if (settings != null) {
            updateConfiguration(settings, null);
        }

        // Live updates only matter outside the editor (the editor uses current snapshots).
        if (!_editMode) {
            for (var i = 0; i < _slots.size(); i++) {
                var id = _slotIds[_slots[i].uid] as Complications.Id;
                if (id != null) {
                    try { Complications.subscribeToUpdates(id); } catch (e) {}
                }
            }
            Complications.registerComplicationChangeCallback(method(:onComplicationChange));
        }
    }

    //! Create the seven editable slots at their grid positions and record each one's default
    //! complication type. Positions and sizes are the layout editor's final numbers.
    private function buildSlots(w as Number, h as Number) as Void {
        var ringR = (w * 0.115 * 0.92).toNumber();
        // uid, kind, fx, fy, ringR, pen, striped, defaultType
        var specs = [
            [1, SlotKind.CHIP, 0.500, 0.127, 0,     0, false, Complications.COMPLICATION_TYPE_BATTERY],
            [2, SlotKind.CHIP, 0.166, 0.282, 0,     0, false, Complications.COMPLICATION_TYPE_STEPS],
            [3, SlotKind.CHIP, 0.834, 0.282, 0,     0, false, Complications.COMPLICATION_TYPE_VO2MAX_RUN],
            [4, SlotKind.RING, 0.129, 0.497, ringR, 6, false, Complications.COMPLICATION_TYPE_HEART_RATE],
            [5, SlotKind.RING, 0.871, 0.497, ringR, 6, false, Complications.COMPLICATION_TYPE_BODY_BATTERY],
            [6, SlotKind.CHIP, 0.154, 0.742, 0,     0, false, Complications.COMPLICATION_TYPE_SEA_LEVEL_PRESSURE],
            [8, SlotKind.CHIP, 0.846, 0.742, 0,     0, false, Complications.COMPLICATION_TYPE_CURRENT_TEMPERATURE]
        ];

        _slots = [];
        _slotIds = {};
        for (var i = 0; i < specs.size(); i++) {
            var s = specs[i];
            var uid = s[0] as Number;
            var isRing = (s[1] == SlotKind.RING);
            var slot = new ClaudeGridSlot({
                :uid => uid,
                :kind => s[1],
                :cx => (s[2] * w).toNumber(),
                :cy => (s[3] * h).toNumber(),
                :ringR => s[4],
                :ringPen => s[5],
                :striped => s[6],
                :fLabel => _fLabel,
                :fIcon => _fIcon,
                :valueFonts => (isRing ? [_fRing, _fSmall] : [_fValue, _fSmall, _fLabel]),
                :fStacked => _fSmall,
                :valueMaxW => (isRing ? (s[4] * 1.6).toNumber() : (w * 0.22).toNumber())
            });
            slot.labelColor = DIM;
            slot.valueColor = _dataColor;
            _slots.add(slot);
            _slotIds[uid] = new Complications.Id(s[7] as Complications.Type);
        }
    }

    private function slotFor(uid as Number) as ClaudeGridSlot? {
        for (var i = 0; i < _slots.size(); i++) {
            if (_slots[i].uid == uid) { return _slots[i]; }
        }
        return null;
    }

    //! Pull the current label / value / fill for the complication assigned to a slot.
    public function updateSlotText(uid as Number) as Void {
        var slot = slotFor(uid);
        if (slot == null) { return; }
        var id = _slotIds[uid];
        if (id == null) { return; }
        var cid = id as Complications.Id;
        var t = cid.getType();
        slot.iconChar = iconCharFor(t);
        try {
            var c = Complications.getComplication(cid);
            var lbl = c.shortLabel;
            if (lbl == null) { lbl = c.longLabel; }
            if (lbl == null) { lbl = defaultLabel(uid); }
            slot.label = (lbl as String).toUpper();
            var vs = valStr(c.value);
            // The Claude usage meters are percent-used - show a "%".
            if ((c.value != null) && isPercentUsage(t, c.longLabel)) {
                vs = vs + "%";
            }
            // High/low temperature stacks (high over low) instead of one wide line.
            slot.valueTop = "";
            slot.valueBot = "";
            if (t == Complications.COMPLICATION_TYPE_HIGH_LOW_TEMPERATURE) {
                var parts = splitTwo(vs);
                if (parts != null) {
                    slot.valueTop = parts[0];
                    slot.valueBot = parts[1];
                    slot.value = "";
                } else {
                    slot.value = vs;
                }
            } else {
                slot.value = vs;
            }
            if (slot.kind == SlotKind.RING) {
                slot.frac = ringFrac(cid, c.value);
            }
        } catch (e) {
            slot.label = defaultLabel(uid);
            slot.value = "--";
            slot.valueTop = "";
            slot.valueBot = "";
            slot.frac = 0.0;
        }
    }

    //! Apply an edited (or freshly read) configuration: accent colour, data colour, and each
    //! slot's assigned complication.
    public function updateConfiguration(config as WatchFaceConfig.Settings, editedType as WatchFaceConfigType?) as Void {
        var accent = config.accentColor;
        if ((accent != null) && (accent.color != null)) {
            _accentColor = accent.color as Number;
        } else {
            _accentColor = _DEFAULT_ACCENT;
        }

        var data = config.complicationColor;
        if ((data != null) && (data.color != null)) {
            _dataColor = data.color as Number;
        } else {
            _dataColor = _DEFAULT_DATA;
        }
        for (var i = 0; i < _slots.size(); i++) {
            _slots[i].valueColor = _dataColor;
        }

        var comps = config.complicationSettings;
        if (comps != null) {
            for (var i = 0; i < comps.size(); i++) {
                var entry = comps[i];
                var uid = entry.uniqueIdentifier;
                if (uid == null) { continue; }
                var id = entry.complicationId;
                if (id == null) { continue; }  // unset -> keep the seeded default
                _slotIds[uid] = id;
                updateSlotText(uid);
            }
        }

        _editingSlot = (editedType == WatchUi.WATCH_FACE_CONFIG_TYPE_COMPLICATION);
        WatchUi.requestUpdate();
    }

    //! A subscribed complication changed - refresh whichever slot holds it.
    public function onComplicationChange(id as Complications.Id) as Void {
        for (var i = 0; i < _slots.size(); i++) {
            var slotId = _slotIds[_slots[i].uid] as Complications.Id;
            if (slotId != null && id.equals(slotId)) {
                updateSlotText(_slots[i].uid);
            }
        }
        WatchUi.requestUpdate();
    }

    // ---- editor interaction ----

    public function getTappedComplication(x as Number, y as Number) as Number? {
        for (var i = 0; i < _slots.size(); i++) {
            if (_slots[i].containsPoint(x, y)) { return _slots[i].uid; }
        }
        return null;
    }

    public function getComplication(complication as ComplicationRef) as ComplicationDrawableRef or Null {
        var slot = slotFor(complication.uniqueIdentifier);
        if (slot == null) { return null; }
        _editingSlot = true;
        _selectedUid = slot.uid;
        WatchUi.requestUpdate();
        return new WatchUi.ComplicationDrawableRef({
            :drawable => slot,
            :boundingBox => slot.getBoundingBox()
        });
    }

    // ---- drawing ----

    public function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // Ambient top battery arc (always system battery).
        var battery = System.getSystemStats().battery;
        GridDraw.segmentArc(dc, cx, cy, w * 0.455, 125.0, 55.0, 16, battery / 100.0);

        // The seven editable slots (skip the one the editor is currently pulsing).
        for (var i = 0; i < _slots.size(); i++) {
            var slot = _slots[i];
            slot.sweep = ringSweep;
            if (_editingSlot && _selectedUid != null && slot.uid == _selectedUid) { continue; }
            slot.draw(dc);
        }

        // Centre-column elements all share the true vertical axis (cx). The date halves flank
        // the seconds dial symmetrically at one height. (Left/right column slots are untouched.)
        drawTime(dc, cx, cy);
        drawSeconds07(dc, cx, h * 0.829, w * 0.085);
        drawDate(dc, cx - w * 0.184, h * 0.815, cx + w * 0.184, h * 0.815);
        drawWeekCurved(dc, cx, cy, h * 0.964 - cy);
    }

    //! Data 07: the fixed live seconds dial (striped gradient ring), not an editable slot.
    private function drawSeconds07(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric) as Void {
        var sec = System.getClockTime().sec;
        GridDraw.gradientRing(dc, cx, cy, r, 5, (sec / 60.0) * ringSweep, true);
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 23, labelFont(), "SEC",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(_accentColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 10, ringFont(), sec.format("%02d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Stacked hours over minutes (no colon), centred on `tx` at the vertical middle.
    private function drawTime(dc as Dc, tx as Numeric, cy as Numeric) as Void {
        var clock = System.getClockTime();
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var font = (_fTime != null) ? _fTime : Graphics.FONT_NUMBER_THAI_HOT;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(tx, cy - TIME_GAP, font, hour.format("%02d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(tx, cy + TIME_GAP, font, clock.min.format("%02d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawDate(dc as Dc, monX as Numeric, monY as Numeric,
                              dayX as Numeric, dayY as Numeric) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        dc.setColor(_dataColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(monX, monY, valueFont(), info.month.toUpper(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(dayX, dayY, valueFont(), info.day.format("%d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Weekday letters curved along the bottom bezel (math degrees 240 -> 300), today in accent.
    private function drawWeekCurved(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric) as Void {
        var letters = ["S", "M", "T", "W", "T", "F", "S"];
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT).day_of_week; // 1=Sun..7=Sat
        for (var i = 0; i < 7; i++) {
            var a = (240.0 + 60.0 * i / 6) * Math.PI / 180.0;
            var x = cx + r * Math.cos(a);
            var y = cy - r * Math.sin(a);
            dc.setColor((i == today - 1) ? _accentColor : DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, smallFont(), letters[i],
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! Always-on: redraw only the seconds dial each second, clipped so it doesn't smear.
    public function onPartialUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var scx = w * 0.499;
        var scy = h * 0.829;
        var r = w * 0.085;
        var pad = r + 8;
        dc.setClip(scx - pad, scy - pad, 2 * pad, 2 * pad);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        drawSeconds07(dc, scx, scy, r);
        dc.clearClip();
    }

    // ---- ring fill animation (sweeps in on wake) ----

    //! Sweep the ring gauges from empty to their value. Runs only in the high-power window
    //! (wrist raise / face shown), never during editing. Guarded so a device without watch-face
    //! animation just shows full rings.
    public function startSweep() as Void {
        if (_editMode) { ringSweep = 1.0; return; }
        try {
            ringSweep = 0.0;
            WatchUi.animate(self, :ringSweep, WatchUi.ANIM_TYPE_EASE_OUT, 0.0, 1.0, 0.7,
                method(:onSweepDone));
        } catch (ex) {
            ringSweep = 1.0;
            WatchUi.requestUpdate();
        }
    }

    //! Animation finished (or was cancelled) - pin the rings to their true value.
    public function onSweepDone() as Void {
        ringSweep = 1.0;
        WatchUi.requestUpdate();
    }

    public function onShow() as Void {
        startSweep();
    }

    //! Wrist raise: entering high-power mode - replay the sweep.
    public function onExitSleep() as Void {
        startSweep();
    }

    //! Going to always-on/low-power: stop animating and show full rings.
    public function onEnterSleep() as Void {
        WatchUi.cancelAllAnimations();
        ringSweep = 1.0;
        WatchUi.requestUpdate();
    }

    // ---- value helpers ----

    //! Fill fraction for a ring slot: real 0-100 metrics gauge their value; open-ended metrics
    //! (heart rate, etc.) get a fixed decorative arc.
    private function ringFrac(id as Complications.Id, v as Complications.Value or Null) as Float {
        var t = id.getType();
        if (v != null && (t == Complications.COMPLICATION_TYPE_BODY_BATTERY
                       || t == Complications.COMPLICATION_TYPE_BATTERY
                       || t == Complications.COMPLICATION_TYPE_PULSE_OX
                       || t == Complications.COMPLICATION_TYPE_STRESS
                       || t == Complications.COMPLICATION_TYPE_SLEEP_SCORE
                       || t == Complications.COMPLICATION_TYPE_INVALID)) {  // Claude % meters
            var f = 0.0;
            if (v instanceof Lang.Float || v instanceof Lang.Double) {
                f = v.toFloat() / 100.0;
            } else if (v instanceof Lang.Number || v instanceof Lang.Long) {
                f = v.toFloat() / 100.0;
            }
            if (f < 0.0) { f = 0.0; }
            if (f > 1.0) { f = 1.0; }
            return f;
        }
        return 0.66;
    }

    //! The Claude usage meters are custom (INVALID-type) complications whose value is a
    //! percent-used, so their reading gets a trailing "%". The "Claude ... usage" long label is
    //! matched as a fallback in case a device reports a non-INVALID type for them.
    private function isPercentUsage(t as Complications.Type or Null, longLabel as String or Null) as Boolean {
        if (t == Complications.COMPLICATION_TYPE_INVALID) { return true; }
        if (longLabel != null) {
            var s = longLabel as String;
            if ((s.find("Claude") != null) || (s.find("usage") != null)) { return true; }
        }
        return false;
    }

    //! Split a "high<sep>low" reading into two parts on '/' or whitespace. Returns null if it
    //! can't be split cleanly (then it's shown as a single auto-fitted line).
    private function splitTwo(s as String) as Array<String>? {
        var sep = s.find("/");
        if (sep == null) { sep = s.find(" "); }
        if (sep == null) { return null; }
        var a = s.substring(0, sep);
        var b = s.substring(sep + 1, s.length());
        if ((a == null) || (b == null) || (a.length() == 0) || (b.length() == 0)) {
            return null;
        }
        return [a, b];
    }

    //! Render a complication value compactly (whole numbers; floats rounded).
    private function valStr(v as Complications.Value or Null) as String {
        if (v == null) { return "--"; }
        if (v instanceof Lang.Float || v instanceof Lang.Double) {
            return v.format("%.0f");
        }
        return v.toString();
    }

    //! Fallback short label per slot when a complication exposes none.
    private function defaultLabel(uid as Number) as String {
        if (uid == 1) { return "BAT"; }
        if (uid == 2) { return "ST"; }
        if (uid == 3) { return "VO2"; }
        if (uid == 4) { return "HR"; }
        if (uid == 5) { return "BB"; }
        if (uid == 6) { return "mb"; }
        return "°C";
    }

    //! Tabler icon glyph for a complication type, or "" to fall back to the text label.
    private function iconCharFor(t as Complications.Type or Null) as String {
        var cp = iconCodeFor(t);
        if (cp == 0) { return ""; }
        return cp.toChar().toString();
    }

    //! Complication type -> Tabler codepoint (0 = no icon). Weather uses a static cloud here;
    //! the weather-reactive picker refines it per condition.
    private function iconCodeFor(t as Complications.Type or Null) as Number {
        if (t == null) { return 0; }
        if (t == Complications.COMPLICATION_TYPE_BATTERY) { return 0xea34; }
        if (t == Complications.COMPLICATION_TYPE_STEPS) { return 0xec87; }
        if (t == Complications.COMPLICATION_TYPE_HEART_RATE) { return 0xef92; }
        if (t == Complications.COMPLICATION_TYPE_BODY_BATTERY) { return 0xea38; }
        if (t == Complications.COMPLICATION_TYPE_VO2MAX_RUN
         || t == Complications.COMPLICATION_TYPE_VO2MAX_BIKE) { return 0xef62; }
        if (t == Complications.COMPLICATION_TYPE_RESPIRATION_RATE) { return 0xef62; }
        if (t == Complications.COMPLICATION_TYPE_SEA_LEVEL_PRESSURE) { return 0xeab1; }
        if (t == Complications.COMPLICATION_TYPE_CURRENT_TEMPERATURE
         || t == Complications.COMPLICATION_TYPE_HIGH_LOW_TEMPERATURE) { return 0xeb38; }
        if (t == Complications.COMPLICATION_TYPE_CALORIES) { return 0xec2c; }
        if (t == Complications.COMPLICATION_TYPE_FLOORS_CLIMBED) { return 0xeca5; }
        if (t == Complications.COMPLICATION_TYPE_ALTITUDE) { return 0xef97; }
        if (t == Complications.COMPLICATION_TYPE_STRESS) { return 0xf0db; }
        if (t == Complications.COMPLICATION_TYPE_PULSE_OX) { return 0xea97; }
        if (t == Complications.COMPLICATION_TYPE_INTENSITY_MINUTES) { return 0xff9b; }
        if (t == Complications.COMPLICATION_TYPE_NOTIFICATION_COUNT) { return 0xea35; }
        if (t == Complications.COMPLICATION_TYPE_SUNRISE) { return 0xef1c; }
        if (t == Complications.COMPLICATION_TYPE_SUNSET) { return 0xec31; }
        if (t == Complications.COMPLICATION_TYPE_CURRENT_WEATHER
         || t == Complications.COMPLICATION_TYPE_FORECAST_WEATHER_1DAY
         || t == Complications.COMPLICATION_TYPE_FORECAST_WEATHER_2DAY
         || t == Complications.COMPLICATION_TYPE_FORECAST_WEATHER_3DAY) { return weatherCode(); }
        if (t == Complications.COMPLICATION_TYPE_DATE
         || t == Complications.COMPLICATION_TYPE_WEEKDAY_MONTHDAY) { return 0xea53; }
        if (t == Complications.COMPLICATION_TYPE_SLEEP_SCORE) { return 0xeaf8; }
        if (t == Complications.COMPLICATION_TYPE_RECOVERY_TIME) { return 0xf228; }
        if (t == Complications.COMPLICATION_TYPE_SOLAR_INPUT) { return 0xeb30; }
        return 0;
    }

    //! Current-conditions weather glyph, so a weather field's icon changes with the weather.
    //! Falls back to a plain cloud when conditions are unavailable.
    private function weatherCode() as Number {
        try {
            var cc = Weather.getCurrentConditions();
            if (cc != null && cc.condition != null) {
                return weatherGlyph(cc.condition);
            }
        } catch (ex) {
        }
        return 0xea76; // cloud
    }

    //! Map a Weather.CONDITION_* value to a Tabler weather glyph.
    private function weatherGlyph(c as Number) as Number {
        // clear / fair -> sun
        if (c == Weather.CONDITION_CLEAR || c == Weather.CONDITION_FAIR
         || c == Weather.CONDITION_MOSTLY_CLEAR || c == Weather.CONDITION_PARTLY_CLEAR) {
            return 0xeb30;
        }
        // severe -> storm
        if (c == Weather.CONDITION_THUNDERSTORMS || c == Weather.CONDITION_SCATTERED_THUNDERSTORMS
         || c == Weather.CONDITION_CHANCE_OF_THUNDERSTORMS || c == Weather.CONDITION_HURRICANE
         || c == Weather.CONDITION_TROPICAL_STORM || c == Weather.CONDITION_TORNADO) {
            return 0xea74;
        }
        // snow / ice / mix -> cloud-snow
        if (c == Weather.CONDITION_SNOW || c == Weather.CONDITION_LIGHT_SNOW
         || c == Weather.CONDITION_HEAVY_SNOW || c == Weather.CONDITION_FLURRIES
         || c == Weather.CONDITION_CHANCE_OF_SNOW || c == Weather.CONDITION_CLOUDY_CHANCE_OF_SNOW
         || c == Weather.CONDITION_WINTRY_MIX || c == Weather.CONDITION_RAIN_SNOW
         || c == Weather.CONDITION_LIGHT_RAIN_SNOW || c == Weather.CONDITION_HEAVY_RAIN_SNOW
         || c == Weather.CONDITION_CHANCE_OF_RAIN_SNOW || c == Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN_SNOW
         || c == Weather.CONDITION_SLEET || c == Weather.CONDITION_ICE
         || c == Weather.CONDITION_ICE_SNOW || c == Weather.CONDITION_HAIL
         || c == Weather.CONDITION_FREEZING_RAIN) {
            return 0xea73;
        }
        // rain / showers / drizzle -> cloud-rain
        if (c == Weather.CONDITION_RAIN || c == Weather.CONDITION_LIGHT_RAIN
         || c == Weather.CONDITION_HEAVY_RAIN || c == Weather.CONDITION_SHOWERS
         || c == Weather.CONDITION_LIGHT_SHOWERS || c == Weather.CONDITION_HEAVY_SHOWERS
         || c == Weather.CONDITION_SCATTERED_SHOWERS || c == Weather.CONDITION_CHANCE_OF_SHOWERS
         || c == Weather.CONDITION_DRIZZLE || c == Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN
         || c == Weather.CONDITION_UNKNOWN_PRECIPITATION) {
            return 0xea72;
        }
        // fog / haze / smoke / dust -> cloud-fog
        if (c == Weather.CONDITION_FOG || c == Weather.CONDITION_HAZY || c == Weather.CONDITION_HAZE
         || c == Weather.CONDITION_MIST || c == Weather.CONDITION_SMOKE || c == Weather.CONDITION_DUST
         || c == Weather.CONDITION_SAND || c == Weather.CONDITION_SANDSTORM
         || c == Weather.CONDITION_VOLCANIC_ASH) {
            return 0xecd9;
        }
        // windy -> wind
        if (c == Weather.CONDITION_WINDY || c == Weather.CONDITION_SQUALL) {
            return 0xec34;
        }
        // everything cloudy (and unknown) -> cloud
        return 0xea76;
    }

    private function labelFont() as Graphics.FontType {
        return (_fLabel != null) ? _fLabel : Graphics.FONT_XTINY;
    }
    private function valueFont() as Graphics.FontType {
        return (_fValue != null) ? _fValue : Graphics.FONT_TINY;
    }
    private function ringFont() as Graphics.FontType {
        return (_fRing != null) ? _fRing : Graphics.FONT_MEDIUM;
    }
    private function smallFont() as Graphics.FontType {
        return (_fSmall != null) ? _fSmall : Graphics.FONT_XTINY;
    }
}
