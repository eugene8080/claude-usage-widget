import Toybox.Application;
import Toybox.Application.WatchFaceConfig;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.Weather;

//! "Claude Grid" - a data face in Chivo Mono built to the HTML layout editor's finalized design.
//! Big stacked time (solid white hour over a Gradient 1->2 minute), a brand line, a battery arc
//! on the bezel, a live 60-tick seconds sub-dial, a second time zone (New York, via LocalMoment
//! so DST is automatic), the date flanking the dial, a curved weekday strip, and six user-editable
//! complication slots (Data 01-06).
//!
//! Six of the fields (Data 01-06) are complication slots configured with Garmin's native on-device
//! editor; the assigned complication's icon + value are drawn at the slot, and the two ring slots
//! (04/05) also gauge it. The seconds dial (Data 07) and the alt-time-zone (Data 08) are fixed.
//! Accent and data colours are editable natively; the rest of the palette is baked from the editor.
class ClaudeGridView extends WatchUi.WatchFace {

    // --- palette (from the layout editor) ---------------------------------------------------
    private const TEXT2 = 0xFFFFFF;               // ring values + date
    private const TEXT3 = 0x9A9A9A;               // icons, labels, weekday strip, brand, SEC
    private const HOUR_COL = 0xFFFFFF;            // hour digits (solid)
    private const _DEFAULT_ACCENT = 0xFF531A;    // today's weekday + seconds value
    private const _DEFAULT_DATA = 0xFF9C75;      // chip values (Text 1)

    private const TIME_GAP = 56;                 // HH / MM each this far from the vertical centre

    private var _fTime as Graphics.FontType?;    // 139px digits  - the clock
    private var _fTimeO as Graphics.FontType?;   // 139px outline - always-on clock
    private var _fBig as Graphics.FontType?;     // 36px          - ring values, brand, date
    private var _fMed as Graphics.FontType?;     // 30px          - chip values, alt-tz, seconds
    private var _fWeek as Graphics.FontType?;    // 27px          - weekday letters
    private var _fSmall as Graphics.FontType?;   // 24px          - battery %, SEC, text labels
    private var _fIcon as Graphics.FontType?;    // 24px          - Tabler per-field icons

    private var _editMode as Boolean = false;
    private var _lowPower as Boolean = false;    // always-on / ambient mode
    private var _accentColor as Number = _DEFAULT_ACCENT;
    private var _dataColor as Number = _DEFAULT_DATA;

    private var _alarmChar as String = "";       // Tabler alarm glyph
    private var _worldChar as String = "";       // Tabler globe glyph (alt time zone)

    //! 0..1 multiplier that sweeps the ring gauges + seconds in on wake. Public so WatchUi.animate()
    //! can drive it by symbol. Defaults to 1.0 so nothing is stuck empty if animation is unavailable.
    public var ringSweep as Float = 1.0;

    private var _slots as Array<ClaudeGridSlot> = [];
    private var _slotIds as Dictionary = {};     // uid (Number) -> Complications.Id

    // edit-mode preview state
    private var _editingSlot as Boolean = false;
    private var _selectedUid as Number? = null;

    public function initialize(editMode as Boolean) {
        WatchFace.initialize();
        _editMode = editMode;
        _alarmChar = (0xea04).toChar().toString();
        _worldChar = (0xeb54).toChar().toString();
    }

    public function onLayout(dc as Dc) as Void {
        _fTime  = WatchUi.loadResource(Rez.Fonts.CGTime) as Graphics.FontType;
        _fTimeO = WatchUi.loadResource(Rez.Fonts.CGTimeOutline) as Graphics.FontType;
        _fBig   = WatchUi.loadResource(Rez.Fonts.CGBig) as Graphics.FontType;
        _fMed   = WatchUi.loadResource(Rez.Fonts.CGMed) as Graphics.FontType;
        _fWeek  = WatchUi.loadResource(Rez.Fonts.CGWeek) as Graphics.FontType;
        _fSmall = WatchUi.loadResource(Rez.Fonts.CGSmall) as Graphics.FontType;
        _fIcon  = WatchUi.loadResource(Rez.Fonts.TablerIcon) as Graphics.FontType;

        buildSlots(dc.getWidth(), dc.getHeight());

        for (var i = 0; i < _slots.size(); i++) {
            updateSlotText(_slots[i].uid);
        }

        var settings = WatchFaceConfig.getSettings(null);
        if (settings != null) {
            updateConfiguration(settings, null);
        }

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

    //! Create the six editable slots at their editor grid positions and record each one's default
    //! complication type. Claude usage meters (Fable / 5-hour / weekly) are custom complications
    //! the user assigns on-watch, so those slots seed a sensible standard default here.
    private function buildSlots(w as Number, h as Number) as Void {
        var ringR = (w * 0.123).toNumber();      // editor ring = 56px @ 454
        // uid, kind, fx, fy, ringR, pen, horizontal, defaultType
        var specs = [
            [1, SlotKind.CHIP, 0.500, 0.092, 0,     0, true,  Complications.COMPLICATION_TYPE_BATTERY],
            [2, SlotKind.CHIP, 0.166, 0.299, 0,     0, false, Complications.COMPLICATION_TYPE_HIGH_LOW_TEMPERATURE],
            [3, SlotKind.CHIP, 0.834, 0.299, 0,     0, false, Complications.COMPLICATION_TYPE_STEPS],
            [4, SlotKind.RING, 0.135, 0.500, ringR, 6, false, Complications.COMPLICATION_TYPE_HEART_RATE],
            [5, SlotKind.RING, 0.865, 0.500, ringR, 6, false, Complications.COMPLICATION_TYPE_BODY_BATTERY],
            [6, SlotKind.CHIP, 0.166, 0.724, 0,     0, false, Complications.COMPLICATION_TYPE_CURRENT_WEATHER]
        ];

        _slots = [];
        _slotIds = {};
        var cxf = w / 2.0;
        var cyf = h / 2.0;
        var R = w / 2.0;
        for (var i = 0; i < specs.size(); i++) {
            var s = specs[i];
            var uid = s[0] as Number;
            var isRing = (s[1] == SlotKind.RING);
            var isHoriz = s[6] as Boolean;
            var slotX = (s[2] as Float) * w;
            // Width budget that respects the round bezel: half-chord to the near edge.
            var dyy = ((s[3] as Float) * h) - cyf;
            var chordArg = (R * R) - (dyy * dyy);
            var chordHalf = (chordArg > 0) ? Math.sqrt(chordArg) : 0.0;
            var near = (slotX <= cxf) ? (slotX - (cxf - chordHalf)) : ((cxf + chordHalf) - slotX);
            var maxW = isRing ? ((s[4] as Number) * 1.6).toNumber() : (2.0 * (near - 8)).toNumber();
            if (maxW < 40) { maxW = 40; }

            var valueFonts = isRing ? [_fBig, _fMed]
                                    : (isHoriz ? [_fSmall] : [_fMed, _fSmall]);
            var slot = new ClaudeGridSlot({
                :uid => uid,
                :kind => s[1],
                :cx => slotX.toNumber(),
                :cy => ((s[3] as Float) * h).toNumber(),
                :ringR => s[4],
                :ringPen => s[5],
                :striped => false,
                :horizontal => isHoriz,
                :fLabel => _fSmall,
                :fIcon => _fIcon,
                :valueFonts => valueFonts,
                :fStacked => _fSmall,
                :valueMaxW => maxW
            });
            slot.labelColor = TEXT3;
            slot.valueColor = isRing ? TEXT2 : _dataColor;   // rings=white, chips=Text 1
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

    //! Pull the current icon / value / fill for the complication assigned to a slot.
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
            var raw = c.value;
            // Sea-level pressure arrives in Pa (~101000); show hPa/mb to match and fit.
            if ((t == Complications.COMPLICATION_TYPE_SEA_LEVEL_PRESSURE) && (raw != null)
                && (raw instanceof Lang.Number || raw instanceof Lang.Float || raw instanceof Lang.Double)
                && (raw > 2000)) {
                raw = (raw / 100.0 + 0.5).toNumber();
            }
            var vs = valStr(raw);
            if ((c.value != null) && (isPercentUsage(t, c.longLabel)
                    || (t == Complications.COMPLICATION_TYPE_BATTERY))) {
                vs = vs + "%";
            }
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
    //! slot's assigned complication. Ring values stay white (Text 2); only chips take the data colour.
    public function updateConfiguration(config as WatchFaceConfig.Settings, editedType as WatchFaceConfigType?) as Void {
        var accent = config.accentColor;
        _accentColor = ((accent != null) && (accent.color != null)) ? accent.color as Number : _DEFAULT_ACCENT;

        var data = config.complicationColor;
        _dataColor = ((data != null) && (data.color != null)) ? data.color as Number : _DEFAULT_DATA;
        for (var i = 0; i < _slots.size(); i++) {
            if (_slots[i].kind == SlotKind.CHIP) { _slots[i].valueColor = _dataColor; }
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

        // Battery arc on the bezel (always system battery).
        var battery = System.getSystemStats().battery;
        GridDraw.segmentArc(dc, cx, cy, cx - 3, 122.5, 57.5, 16, battery / 100.0, 10, 15);

        // The six editable slots (skip the one the editor is currently pulsing).
        for (var i = 0; i < _slots.size(); i++) {
            var slot = _slots[i];
            slot.sweep = ringSweep;
            slot.lowPower = _lowPower;
            if (_editingSlot && _selectedUid != null && slot.uid == _selectedUid) { continue; }
            slot.draw(dc);
        }

        drawTime(dc, cx, cy);
        drawBrand(dc, cx, (h * 0.169).toNumber());
        drawIndicators(dc, w, h);
        drawAltTz(dc, (w * 0.834).toNumber(), (h * 0.724).toNumber());

        var dialY = (h * 0.832).toNumber();
        if (_lowPower) {
            drawDateCollapsed(dc, cx, dialY);
        } else {
            drawSeconds(dc, cx, dialY, 50);
            drawDate(dc, cx, dialY);
        }
        drawWeekCurved(dc, cx, cy, (h * 0.980).toNumber() - cy);
    }

    //! Stacked hours over minutes (no colon). Hour is solid; minute is a vertical Gradient 1->2.
    //! In always-on the digits switch to the hollow outline font.
    private function drawTime(dc as Dc, tx as Numeric, cy as Numeric) as Void {
        var clock = System.getClockTime();
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var tf = _lowPower ? ((_fTimeO != null) ? _fTimeO : _fTime) : _fTime;
        if (tf == null) { tf = Graphics.FONT_NUMBER_THAI_HOT; }
        dc.setColor(HOUR_COL, Graphics.COLOR_TRANSPARENT);
        dc.drawText(tx, cy - TIME_GAP, tf, hour.format("%02d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        drawGradientText(dc, tx, cy + TIME_GAP, tf, clock.min.format("%02d"),
            GridDraw.GRAD_A, GridDraw.GRAD_B);
    }

    //! Draw `text` centred at (x, yc) with a top->bottom colour gradient, by re-drawing it inside
    //! a stack of horizontal clip bands. `fade` (0.44) keeps the top solid Gradient 1 and the
    //! bottom solid Gradient 2 with a soft transition between.
    private function drawGradientText(dc as Dc, x as Numeric, yc as Numeric, font as Graphics.FontType,
                                      text as String, cTop as Number, cBot as Number) as Void {
        var halfW = (dc.getTextWidthInPixels(text, font) / 2) + 8;
        var halfH = 58;
        var bands = 12;
        var lo = 0.5 - 0.44 / 2.0;
        var hi = 0.5 + 0.44 / 2.0;
        var bandH = (2.0 * halfH) / bands;
        for (var i = 0; i < bands; i++) {
            var topF = yc - halfH + i * bandH;
            var f = (i + 0.5) / bands.toFloat();
            var t = 0.0;
            if (f <= lo) { t = 0.0; }
            else if (f >= hi) { t = 1.0; }
            else { t = (f - lo) / (hi - lo); }
            dc.setClip(x - halfW, topF.toNumber(), 2 * halfW, (bandH + 2).toNumber());
            dc.setColor(GridDraw.lerp(cTop, cBot, t), Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, yc, font, text,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        dc.clearClip();
    }

    private function drawBrand(dc as Dc, cx as Numeric, y as Numeric) as Void {
        dc.setColor(TEXT3, Graphics.COLOR_TRANSPARENT);
        var f = (_fBig != null) ? _fBig : Graphics.FONT_TINY;
        dc.drawText(cx, y, f, "TACTIX",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Top-corner status icons. Alarm shows when alarms are set (the platform exposes alarm count);
    //! the stopwatch has no public "running" state, so its corner is left empty.
    private function drawIndicators(dc as Dc, w as Numeric, h as Numeric) as Void {
        if (_fIcon == null) { return; }
        var ds = System.getDeviceSettings();
        if (ds.alarmCount != null && ds.alarmCount > 0) {
            dc.setColor(TEXT3, Graphics.COLOR_TRANSPARENT);
            dc.drawText((w * 0.166).toNumber(), (h * 0.169).toNumber(), _fIcon, _alarmChar,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! Data 08: a second time zone (New York), globe icon over HH:MM. LocalMoment handles DST from
    //! the coordinates, so this stays correct year-round without an offset to maintain.
    private function drawAltTz(dc as Dc, x as Numeric, y as Numeric) as Void {
        if (_fIcon != null) {
            dc.setColor(TEXT3, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y - 28, _fIcon, _worldChar,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        dc.setColor(_dataColor, Graphics.COLOR_TRANSPARENT);
        var f = (_fMed != null) ? _fMed : Graphics.FONT_TINY;
        dc.drawText(x, y, f, altTimeStr(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function altTimeStr() as String {
        try {
            var loc = new Position.Location({
                :latitude => 40.7128, :longitude => -74.0060, :format => :degrees
            });
            var lm = Gregorian.localMoment(loc, Time.now());
            if (lm == null) { return "--:--"; }
            var info = Gregorian.info(lm, Time.FORMAT_SHORT);
            return info.hour.format("%02d") + ":" + info.min.format("%02d");
        } catch (ex) {
            return "--:--";
        }
    }

    //! Data 07: the fixed live seconds dial (60-tick gradient ring), not an editable slot.
    private function drawSeconds(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric) as Void {
        var sec = System.getClockTime().sec;
        GridDraw.tickRing(dc, cx, cy, r, (sec / 60.0) * ringSweep);
        dc.setColor(TEXT3, Graphics.COLOR_TRANSPARENT);
        var sf = (_fSmall != null) ? _fSmall : Graphics.FONT_XTINY;
        dc.drawText(cx, cy - 24, sf, "SEC",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(_accentColor, Graphics.COLOR_TRANSPARENT);
        var vf = (_fMed != null) ? _fMed : Graphics.FONT_MEDIUM;
        dc.drawText(cx, cy + 11, vf, sec.format("%02d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Month and day flanking the seconds dial (high-power).
    private function drawDate(dc as Dc, cx as Numeric, y as Numeric) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        dc.setColor(TEXT2, Graphics.COLOR_TRANSPARENT);
        var f = (_fBig != null) ? _fBig : Graphics.FONT_TINY;
        dc.drawText(cx - 81, y, f, (info.month as String).toUpper(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx + 81, y, f, info.day.format("%d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Always-on: the date collapses to a stacked day / month at the centre where the dial was.
    private function drawDateCollapsed(dc as Dc, cx as Numeric, y as Numeric) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        dc.setColor(TEXT2, Graphics.COLOR_TRANSPARENT);
        var f = (_fMed != null) ? _fMed : Graphics.FONT_TINY;
        dc.drawText(cx, y - 16, f, info.day.format("%d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, y + 16, f, (info.month as String).toUpper(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Weekday letters curved along the bottom bezel (52 deg span centred on the bottom), today accent.
    private function drawWeekCurved(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric) as Void {
        var letters = ["S", "M", "T", "W", "T", "F", "S"];
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT).day_of_week; // 1=Sun..7=Sat
        var wf = (_fWeek != null) ? _fWeek : Graphics.FONT_XTINY;
        for (var i = 0; i < 7; i++) {
            var a = (244.0 + (52.0 / 6.0) * i) * Math.PI / 180.0;
            var x = cx + r * Math.cos(a);
            var y = cy - r * Math.sin(a);
            dc.setColor((i == today - 1) ? _accentColor : TEXT3, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, wf, letters[i],
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! Always-on: redraw only the seconds dial each second, clipped so it doesn't smear. Skipped in
    //! ambient mode where the dial is hidden.
    public function onPartialUpdate(dc as Dc) as Void {
        if (_lowPower) { return; }
        var w = dc.getWidth();
        var h = dc.getHeight();
        var scx = w / 2;
        var scy = (h * 0.832).toNumber();
        var r = 50;
        var pad = r + 10;
        dc.setClip(scx - pad, scy - pad, 2 * pad, 2 * pad);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        drawSeconds(dc, scx, scy, r);
        dc.clearClip();
    }

    // ---- ring fill animation (sweeps in on wake) ----

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

    public function onSweepDone() as Void {
        ringSweep = 1.0;
        WatchUi.requestUpdate();
    }

    public function onShow() as Void {
        _lowPower = false;
        startSweep();
    }

    public function onExitSleep() as Void {
        _lowPower = false;
        startSweep();
    }

    public function onEnterSleep() as Void {
        _lowPower = true;
        WatchUi.cancelAllAnimations();
        ringSweep = 1.0;
        WatchUi.requestUpdate();
    }

    // ---- value helpers ----

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

    private function isPercentUsage(t as Complications.Type or Null, longLabel as String or Null) as Boolean {
        if (t == Complications.COMPLICATION_TYPE_INVALID) { return true; }
        if (longLabel != null) {
            var s = longLabel as String;
            if ((s.find("Claude") != null) || (s.find("usage") != null)) { return true; }
        }
        return false;
    }

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

    private function valStr(v as Complications.Value or Null) as String {
        if (v == null) { return "--"; }
        if (v instanceof Lang.Float || v instanceof Lang.Double) {
            return v.format("%.0f");
        }
        return v.toString();
    }

    private function defaultLabel(uid as Number) as String {
        if (uid == 1) { return "BAT"; }
        if (uid == 2) { return ""; }
        if (uid == 3) { return "ST"; }
        if (uid == 4) { return "HR"; }
        if (uid == 5) { return "BB"; }
        return "WX";
    }

    private function iconCharFor(t as Complications.Type or Null) as String {
        var cp = iconCodeFor(t);
        if (cp == 0) { return ""; }
        return cp.toChar().toString();
    }

    //! Complication type -> Tabler codepoint (0 = no icon, falls back to a text label). Only glyphs
    //! present in cg_icon are returned; VO2 / pressure / temperature use their text label instead
    //! (matching the editor's "no icon" treatment).
    private function iconCodeFor(t as Complications.Type or Null) as Number {
        if (t == null) { return 0; }
        if (t == Complications.COMPLICATION_TYPE_BATTERY) { return 0xea34; }
        if (t == Complications.COMPLICATION_TYPE_STEPS) { return 0x10265; }
        if (t == Complications.COMPLICATION_TYPE_HEART_RATE) { return 0xef92; }
        if (t == Complications.COMPLICATION_TYPE_BODY_BATTERY) { return 0xea38; }
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
        if (t == Complications.COMPLICATION_TYPE_SLEEP_SCORE) { return 0xeaf8; }
        if (t == Complications.COMPLICATION_TYPE_RECOVERY_TIME) { return 0xf228; }
        if (t == Complications.COMPLICATION_TYPE_SOLAR_INPUT) { return 0xeb30; }
        return 0;
    }

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

    private function weatherGlyph(c as Number) as Number {
        if (c == Weather.CONDITION_CLEAR || c == Weather.CONDITION_FAIR
         || c == Weather.CONDITION_MOSTLY_CLEAR || c == Weather.CONDITION_PARTLY_CLEAR) {
            return 0xeb30;
        }
        if (c == Weather.CONDITION_THUNDERSTORMS || c == Weather.CONDITION_SCATTERED_THUNDERSTORMS
         || c == Weather.CONDITION_CHANCE_OF_THUNDERSTORMS || c == Weather.CONDITION_HURRICANE
         || c == Weather.CONDITION_TROPICAL_STORM || c == Weather.CONDITION_TORNADO) {
            return 0xea74;
        }
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
        if (c == Weather.CONDITION_RAIN || c == Weather.CONDITION_LIGHT_RAIN
         || c == Weather.CONDITION_HEAVY_RAIN || c == Weather.CONDITION_SHOWERS
         || c == Weather.CONDITION_LIGHT_SHOWERS || c == Weather.CONDITION_HEAVY_SHOWERS
         || c == Weather.CONDITION_SCATTERED_SHOWERS || c == Weather.CONDITION_CHANCE_OF_SHOWERS
         || c == Weather.CONDITION_DRIZZLE || c == Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN
         || c == Weather.CONDITION_UNKNOWN_PRECIPITATION) {
            return 0xea72;
        }
        if (c == Weather.CONDITION_FOG || c == Weather.CONDITION_HAZY || c == Weather.CONDITION_HAZE
         || c == Weather.CONDITION_MIST || c == Weather.CONDITION_SMOKE || c == Weather.CONDITION_DUST
         || c == Weather.CONDITION_SAND || c == Weather.CONDITION_SANDSTORM
         || c == Weather.CONDITION_VOLCANIC_ASH) {
            return 0xecd9;
        }
        if (c == Weather.CONDITION_WINDY || c == Weather.CONDITION_SQUALL) {
            return 0xec34;
        }
        return 0xea76; // cloud (and unknown)
    }
}
