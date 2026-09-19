import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

//! Shared drawing helpers + the gradient palette for the Claude Grid face. Used by both the
//! view (top battery arc, bottom seconds dial) and the editable ring slots so the gauge look
//! is identical everywhere. Colours mirror the HTML layout editor's Gradient 1 / Gradient 2.
module GridDraw {

    const TRACK = 0x3A2A22;   // ring/arc background (dark warm)
    const GRAD_A = 0xFF9255;  // Gradient 1 (warm orange) - top of the fill
    const GRAD_B = 0xFF3C3B;  // Gradient 2 (hot red)      - end of the fill

    //! Linear interpolate between two 0xRRGGBB colours.
    function lerp(a as Number, b as Number, t as Float) as Number {
        var ar = (a >> 16) & 0xFF; var ag = (a >> 8) & 0xFF; var ab = a & 0xFF;
        var br = (b >> 16) & 0xFF; var bg = (b >> 8) & 0xFF; var bb = b & 0xFF;
        var r = (ar + ((br - ar) * t)).toNumber();
        var g = (ag + ((bg - ag) * t)).toNumber();
        var bl = (ab + ((bb - ab) * t)).toNumber();
        return (r << 16) | (g << 8) | bl;
    }

    //! Ring gauge: a dim full track, then a gradient arc from the top clockwise for `frac`.
    function gradientRing(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric,
                          penW as Number, frac as Float) as Void {
        dc.setPenWidth(penW);
        dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        var steps = 36;
        var lit = (steps * frac).toNumber();
        for (var i = 0; i < lit; i++) {
            dc.setColor(lerp(GRAD_A, GRAD_B, i.toFloat() / steps), Graphics.COLOR_TRANSPARENT);
            var s = 90.0 - (i * 360.0 / steps);
            var e = 90.0 - ((i + 1) * 360.0 / steps);
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, s, e);
        }
        dc.setPenWidth(1);
    }

    //! Seconds sub-dial: 60 short radial ticks from the top clockwise, the elapsed ones lit in
    //! the gradient, the rest on the dim track. Matches the editor's tick-ring look.
    function tickRing(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, frac as Float) as Void {
        var n = 60;
        var lit = (n * frac).toNumber();
        var innerLen = 9;
        dc.setPenWidth(2);
        for (var i = 0; i < n; i++) {
            var a = (90.0 - i * 360.0 / n) * Math.PI / 180.0;
            var ca = Math.cos(a);
            var sa = Math.sin(a);
            dc.setColor(i < lit ? lerp(GRAD_A, GRAD_B, i.toFloat() / n) : TRACK,
                Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cx + r * ca, cy - r * sa, cx + (r - innerLen) * ca, cy - (r - innerLen) * sa);
        }
        dc.setPenWidth(1);
    }

    //! Segmented arc between two math-degree angles (the battery indicator across the top bezel).
    //! `penW` is the dash thickness, `dashLen` how far each dash reaches inward from `r`.
    function segmentArc(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric,
                        startDeg as Float, endDeg as Float, n as Number, frac as Float,
                        penW as Number, dashLen as Number) as Void {
        var lit = (n * frac).toNumber();
        dc.setPenWidth(penW);
        for (var i = 0; i < n; i++) {
            var a = (startDeg + (endDeg - startDeg) * i / (n - 1)) * Math.PI / 180.0;
            var ca = Math.cos(a);
            var sa = Math.sin(a);
            dc.setColor(i < lit ? lerp(GRAD_A, GRAD_B, i.toFloat() / n) : TRACK,
                Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cx + r * ca, cy - r * sa, cx + (r - dashLen) * ca, cy - (r - dashLen) * sa);
        }
        dc.setPenWidth(1);
    }
}
