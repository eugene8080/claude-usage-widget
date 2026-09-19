import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! A data slot's visual style.
module SlotKind {
    enum {
        CHIP = 0,   // icon over value (Data 01/02/03/06)
        RING = 1    // gradient ring gauge with icon + value inside (Data 04/05)
    }
}

//! One user-editable data field. Draws itself (chip or ring) at a fixed centre using the shared
//! Chivo Mono bitmap fonts, and exposes a bounding box so the view can hit-test taps and the
//! native watch face editor can "pulse" the selected slot. The view feeds it a live icon, value
//! and (for rings) fill fraction as the assigned complication updates.
//!
//! The value auto-fits: it is drawn with the largest of `_valueFonts` (largest -> smallest) that
//! fits `_valueMaxW`, so wide readings shrink instead of overflowing. High/low temperature draws
//! stacked (two lines + divider). In always-on (`lowPower`) the ring circle is dropped, leaving
//! just the icon + value inside, matching the editor's low-power preview.
class ClaudeGridSlot extends WatchUi.Drawable {

    public var uid as Number;
    public var kind as Number;
    public var cx as Number;
    public var cy as Number;
    public var ringR as Number;
    public var ringPen as Number;
    public var striped as Boolean;
    public var horizontal as Boolean = false;  // battery: icon beside the value on one row
    public var lowPower as Boolean = false;     // always-on: drop the ring circle

    public var label as String = "";
    public var value as String = "--";     // single-line reading
    public var valueTop as String = "";    // stacked (hi/low temp): top line
    public var valueBot as String = "";    // stacked: bottom line
    public var iconChar as String = "";    // icon glyph for the assigned complication ("" = none)
    public var frac as Float = 0.0;
    public var sweep as Float = 1.0;       // 0..1 wake-in fill multiplier (rings only)
    public var valueColor as Number = 0xFF9C75;
    public var labelColor as Number = 0x9A9A9A;

    private var _fLabel as Graphics.FontType;
    private var _fIcon as Graphics.FontType?;    // Tabler icon glyph (may be null)
    private var _fStacked as Graphics.FontType;  // compact font for the two stacked temp lines
    private var _valueFonts as Array;            // largest -> smallest, for auto-fit
    private var _valueMaxW as Number;            // width budget for the value

    // text offsets, in px (tied to the fixed bitmap-font heights; from the layout editor)
    private const _CHIP_ICON_DY = 28;    // icon lifted above the value
    private const _CHIP_LABEL_DY = 22;   // text label (no-icon fallback) lift
    private const _CHIP_STACK_DY = 14;   // hi/low temp: each line this far from centre
    private const _RING_ICON_DY = 23;
    private const _RING_VALUE_DY = 10;

    //! @param opts :uid, :kind, :cx, :cy, :ringR, :ringPen, :striped, :horizontal, :fLabel,
    //!             :fIcon, :valueFonts (Array), :fStacked, :valueMaxW
    function initialize(opts as Dictionary) {
        Drawable.initialize({ :identifier => opts[:uid] });
        uid = opts[:uid];
        kind = opts[:kind];
        cx = opts[:cx];
        cy = opts[:cy];
        ringR = opts.hasKey(:ringR) ? opts[:ringR] : 0;
        ringPen = opts.hasKey(:ringPen) ? opts[:ringPen] : 6;
        striped = opts.hasKey(:striped) ? opts[:striped] : false;
        horizontal = opts.hasKey(:horizontal) ? opts[:horizontal] : false;
        _fLabel = opts[:fLabel];
        _fIcon = opts[:fIcon];
        _valueFonts = opts[:valueFonts];
        _fStacked = opts[:fStacked];
        _valueMaxW = opts[:valueMaxW];
    }

    //! Bounding box for tap hit-testing and the editor pulse animation.
    function getBoundingBox() as Graphics.BoundingBox {
        var bb = new Graphics.BoundingBox();
        if (kind == SlotKind.RING) {
            var r = ringR + ringPen + 2;
            bb.addRectangle(cx - r, cy - r, 2 * r, 2 * r);
        } else {
            var halfW = 52;
            bb.addRectangle(cx - halfW, cy - 36, 2 * halfW, 66);
        }
        return bb;
    }

    function containsPoint(x as Number, y as Number) as Boolean {
        return getBoundingBox().includesPoint(x, y);
    }

    //! Largest value font whose rendering of `text` fits the width budget.
    private function pickFont(dc as Dc, text as String) as Graphics.FontType {
        for (var i = 0; i < _valueFonts.size(); i++) {
            if (dc.getTextWidthInPixels(text, _valueFonts[i]) <= _valueMaxW) {
                return _valueFonts[i];
            }
        }
        return _valueFonts[_valueFonts.size() - 1];
    }

    //! Draw the field marker (icon if we have one + the icon font, else the text label).
    private function drawMarker(dc as Dc, x as Numeric, y as Numeric) as Void {
        dc.setColor(labelColor, Graphics.COLOR_TRANSPARENT);
        if (!iconChar.equals("") && _fIcon != null) {
            dc.drawText(x, y, _fIcon, iconChar,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else if (!label.equals("")) {
            dc.drawText(x, y, _fLabel, label,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    function draw(dc as Dc) as Void {
        if (!isVisible) { return; }
        var hasIcon = (!iconChar.equals("") && _fIcon != null);
        var stacked = !valueTop.equals("");

        if (kind == SlotKind.RING) {
            if (!lowPower) {
                GridDraw.gradientRing(dc, cx, cy, ringR, ringPen, frac * sweep);
            }
            drawMarker(dc, cx, cy - _RING_ICON_DY);
            dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + _RING_VALUE_DY, pickFont(dc, value), value,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else if (horizontal) {
            // Battery-style: an icon - or the text LABEL when the complication has no icon (the
            // Claude usage meters are icon-less, so this is what shows "FABLE" beside "55%") -
            // beside the value on one row, the pair centred on cx.
            var vf = pickFont(dc, value);
            var vw = dc.getTextWidthInPixels(value, vf);
            var mFont = hasIcon ? _fIcon : _fLabel;
            var marker = hasIcon ? iconChar : label;
            var mw = marker.equals("") ? 0 : dc.getTextWidthInPixels(marker, mFont);
            var gap = (mw > 0) ? 7 : 0;
            var sx = cx - (mw + gap + vw) / 2;
            if (mw > 0) {
                dc.setColor(labelColor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(sx, cy, mFont, marker,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            }
            dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sx + mw + gap, cy, vf, value,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        } else if (stacked) {
            // hi/low temperature: two numbers with a thin divider, no icon/label (editor look).
            if (hasIcon) { drawMarker(dc, cx, cy - _CHIP_ICON_DY - 6); }
            dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - _CHIP_STACK_DY, _fStacked, valueTop,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(cx, cy + _CHIP_STACK_DY, _fStacked, valueBot,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(labelColor, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawLine(cx - 16, cy, cx + 16, cy);
        } else {
            drawMarker(dc, cx, cy - (hasIcon ? _CHIP_ICON_DY : _CHIP_LABEL_DY));
            dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, pickFont(dc, value), value,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}
