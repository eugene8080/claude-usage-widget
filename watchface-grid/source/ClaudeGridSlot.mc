import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! A data slot's visual style.
module SlotKind {
    enum {
        CHIP = 0,   // label over value (Data 01/02/03/06/08)
        RING = 1    // gradient ring gauge with label + value inside (Data 04/05)
    }
}

//! One user-editable data field. It draws itself (chip or ring) at a fixed centre using the
//! shared Chakra Petch fonts, and exposes a bounding box so the view can hit-test taps and the
//! native watch face editor can "pulse" the selected slot. The view feeds it a live label,
//! value and (for rings) fill fraction as the assigned complication updates.
class ClaudeGridSlot extends WatchUi.Drawable {

    public var uid as Number;           // config <complication id> == the editor's uniqueIdentifier
    public var kind as Number;
    public var cx as Number;
    public var cy as Number;
    public var ringR as Number;
    public var ringPen as Number;
    public var striped as Boolean;

    public var label as String = "";
    public var value as String = "--";
    public var frac as Float = 0.0;
    public var sweep as Float = 1.0;    // 0..1 wake-in fill multiplier (rings only)
    public var valueColor as Number = 0xFFA480;
    public var labelColor as Number = 0x888888;

    private var _fLabel as Graphics.FontType;
    private var _fValue as Graphics.FontType;   // chip -> CPValue (32px); ring -> CPRing (36px)

    // text offsets, in px (tied to the fixed bitmap-font heights)
    private const _CHIP_LABEL_DY = 22;
    private const _RING_LABEL_DY = 23;
    private const _RING_VALUE_DY = 10;

    //! @param opts :uid, :kind, :cx, :cy, :ringR, :ringPen, :striped, :fLabel, :fValue
    function initialize(opts as Dictionary) {
        Drawable.initialize({ :identifier => opts[:uid] });
        uid = opts[:uid];
        kind = opts[:kind];
        cx = opts[:cx];
        cy = opts[:cy];
        ringR = opts.hasKey(:ringR) ? opts[:ringR] : 0;
        ringPen = opts.hasKey(:ringPen) ? opts[:ringPen] : 6;
        striped = opts.hasKey(:striped) ? opts[:striped] : false;
        _fLabel = opts[:fLabel];
        _fValue = opts[:fValue];
    }

    //! Bounding box for tap hit-testing and the editor pulse animation.
    function getBoundingBox() as Graphics.BoundingBox {
        var bb = new Graphics.BoundingBox();
        if (kind == SlotKind.RING) {
            var r = ringR + ringPen + 2;
            bb.addRectangle(cx - r, cy - r, 2 * r, 2 * r);
        } else {
            var halfW = 55;
            bb.addRectangle(cx - halfW, cy - 30, 2 * halfW, 52);
        }
        return bb;
    }

    function containsPoint(x as Number, y as Number) as Boolean {
        return getBoundingBox().includesPoint(x, y);
    }

    //! Draw the slot. The gradient ring (for RING slots) is drawn here too so a pulsing editor
    //! preview shows the full gauge, not just text.
    function draw(dc as Dc) as Void {
        if (!isVisible) { return; }
        if (kind == SlotKind.RING) {
            GridDraw.gradientRing(dc, cx, cy, ringR, ringPen, frac * sweep, striped);
            dc.setColor(labelColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - _RING_LABEL_DY, _fLabel, label,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + _RING_VALUE_DY, _fValue, value,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.setColor(labelColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - _CHIP_LABEL_DY, _fLabel, label,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, _fValue, value,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}
