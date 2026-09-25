"""Pre-render the Claude Terminal time glyphs (0-9 and ":") as RGBA glow bitmaps - the VFD style.

Same method as Claude Grid's tools/build_glow_digits.py: each glyph is cropped from the time
font's own atlas (resources/fonts/stm_time_0.png) so the bitmaps are pixel-for-pixel the font's
shapes and land where the font would draw them; a vertical face shade, a top-edge bevel and a
two-radius bloom are baked in (premultiplied compositing); packingFormat="png" keeps the 8-bit
alpha for the watch's alpha blending (the default packing reduces alpha to a 1-bit key, deleting
the bloom).

Every glyph is emitted on ONE uniform cell = union of all glyph boxes relative to (pen x, line
top) plus PAD, so the runtime places glyph i at pen + i*advance + X0, top + Y0 (X0/Y0 in
source-glow/GlowTimeMetrics.mc; Y0 includes +1 for CIQ drawing font glyphs one row low).

Also writes the full-face mesh tile (resources-mesh/), identical to Claude Grid's.

Outputs (relative to watchface-terminal/):
    resources-glow/drawables/drawables.xml + gt0..gt9.png + gtc.png (colon)
    resources-mesh/drawables/drawables.xml + mesh_tile.png
    source-glow/GlowTimeMetrics.mc

Run from anywhere:  python watchface-terminal/tools/build_glow_time.py [--face ffffff] [--glow d97757]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
FNT = ROOT / "resources" / "fonts" / "stm_time.fnt"
ATLAS = ROOT / "resources" / "fonts" / "stm_time_0.png"
GLOW_DIR = ROOT / "resources-glow" / "drawables"
MESH_DIR = ROOT / "resources-mesh" / "drawables"
METRICS = ROOT / "source-glow" / "GlowTimeMetrics.mc"

CHARS = "0123456789:"
PAD = 18
Y_CALIBRATION = 1            # CIQ draws font glyphs one row below line top + yoffset (measured)
GLOW_TIGHT, GLOW_WIDE = 0.60, 0.42
BEVEL = 0.30
MESH_PITCH, MESH_DIM, MESH_TILE = 3, 0.30, 114


def hex_rgb(s: str) -> tuple[int, int, int]:
    h = s.strip().lstrip("#")
    if len(h) != 6 or any(c not in "0123456789abcdefABCDEF" for c in h):
        raise ValueError("not a 6-digit hex colour: %r" % s)
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def parse_fnt():
    rows, line_h = {}, None
    for raw in FNT.read_text(encoding="utf-8").splitlines():
        p = raw.split()
        if not p:
            continue
        kv = dict(x.split("=", 1) for x in p[1:] if "=" in x)
        if p[0] == "common":
            line_h = int(kv["lineHeight"])
        elif p[0] == "char":
            rows[chr(int(kv["id"]))] = {k: int(kv[k]) for k in ("x", "y", "width", "height", "xoffset", "yoffset", "xadvance")}
    missing = [c for c in CHARS if c not in rows]
    if missing or line_h is None:
        raise SystemExit("stm_time.fnt lacks %s" % missing)
    return line_h, rows


def shift(m: np.ndarray, n: int) -> np.ndarray:
    out = np.zeros_like(m)
    if n > 0:
        out[n:] = m[:-n]
    else:
        out[:n] = m[-n:]
    return out


def render(mask: np.ndarray, face: tuple, glow: tuple) -> Image.Image:
    h, w = mask.shape
    t = np.linspace(0.0, 1.0, h)[:, None, None]
    top = np.array(face, float) / 255.0
    bot = top * 0.90                                   # faint fall-off for depth
    rgb = np.broadcast_to(top + (bot - top) * t, (h, w, 3)).copy()
    edge_top = np.clip(mask - shift(mask, 2), 0, 1)    # light on top edges
    edge_bot = np.clip(mask - shift(mask, -2), 0, 1)   # shade on bottom edges
    rgb = rgb + (1 - rgb) * (BEVEL * 0.85 * edge_top)[..., None]
    rgb = rgb * (1 - BEVEL * 0.45 * edge_bot)[..., None]
    face_p = rgb * mask[..., None]
    src = np.array(glow, float) / 255.0 * mask[..., None]
    def bloom(sig, gain):
        return (np.stack([gaussian_filter(src[..., c], sig) for c in range(3)], -1) * gain,
                gaussian_filter(mask, sig) * gain)
    p1, a1 = bloom(2.2, GLOW_TIGHT)
    p2, a2 = bloom(7.0, GLOW_WIDE)
    gp, ga = np.clip(p1 + p2, 0, 1), np.clip(a1 + a2, 0, 1)
    out_p = face_p + gp * (1 - mask[..., None])
    out_a = np.clip(mask + ga * (1 - mask), 0, 1)
    safe = np.where(out_a > 1e-6, out_a, 1.0)
    rgba = np.dstack([np.clip(out_p / safe[..., None], 0, 1) * 255, out_a * 255]).round().astype(np.uint8)
    rgba[rgba[..., 3] == 0] = 0
    return Image.fromarray(rgba, "RGBA")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--face", default="ffffff", help="time colour (hex) - the face's VALUE colour")
    ap.add_argument("--glow", default="d97757", help="bloom colour (hex) - default the accent")
    args = ap.parse_args()
    try:
        face, glow = hex_rgb(args.face), hex_rgb(args.glow)
    except ValueError as ex:
        print(ex)
        return 2

    line_h, rows = parse_fnt()
    advs = {rows[c]["xadvance"] for c in CHARS}
    if len(advs) != 1:
        print("time glyphs are not monospace (%s) - uniform placement invalid" % advs)
        return 2
    x0 = min(rows[c]["xoffset"] for c in CHARS) - PAD
    y0 = min(rows[c]["yoffset"] for c in CHARS) - PAD
    x1 = max(rows[c]["xoffset"] + rows[c]["width"] for c in CHARS) + PAD
    y1 = max(rows[c]["yoffset"] + rows[c]["height"] for c in CHARS) + PAD
    atlas_a = np.asarray(Image.open(ATLAS).getchannel("A")).astype(float) / 255.0

    GLOW_DIR.mkdir(parents=True, exist_ok=True)
    xml = ["<drawables>",
           "    <!-- Generated by tools/build_glow_time.py - do not edit. gt0-gt9 digits, gtc colon.",
           "         packingFormat=\"png\" is REQUIRED to keep the 8-bit alpha (see module docstring). -->"]
    for c in CHARS:
        g = rows[c]
        cell = np.zeros((y1 - y0, x1 - x0))
        ox, oy = g["xoffset"] - x0, g["yoffset"] - y0
        cell[oy:oy + g["height"], ox:ox + g["width"]] = atlas_a[g["y"]:g["y"] + g["height"], g["x"]:g["x"] + g["width"]]
        name = "gtc" if c == ":" else "gt" + c
        render(cell, face, glow).save(GLOW_DIR / (name + ".png"), optimize=True)
        xml.append('    <bitmap id="%s" filename="%s.png" packingFormat="png" />' % (name.upper(), name))
    xml.append("</drawables>")
    (GLOW_DIR / "drawables.xml").write_text("\n".join(xml) + "\n", encoding="utf-8", newline="\n")

    METRICS.parent.mkdir(parents=True, exist_ok=True)
    METRICS.write_text(
        "// Generated by tools/build_glow_time.py - do not edit.\n"
        "// Offset of every glow-glyph bitmap from (pen x, line top) of stm_time; Y0 includes +1 for\n"
        "// CIQ's glyph row offset.\n"
        "module GlowTimeMetrics {\n    const X0 = %d;\n    const Y0 = %d;\n}\n" % (x0, y0 + Y_CALIBRATION),
        encoding="utf-8", newline="\n")

    MESH_DIR.mkdir(parents=True, exist_ok=True)
    yy, xx = np.mgrid[0:MESH_TILE, 0:MESH_TILE]
    line = ((yy % MESH_PITCH) == MESH_PITCH - 1) | ((xx % MESH_PITCH) == MESH_PITCH - 1)
    tile = np.zeros((MESH_TILE, MESH_TILE, 4), np.uint8)
    tile[..., 3] = np.where(line, int(round(MESH_DIM * 255)), 0)
    Image.fromarray(tile, "RGBA").save(MESH_DIR / "mesh_tile.png", optimize=True)
    (MESH_DIR / "drawables.xml").write_text(
        "<drawables>\n    <!-- Generated by tools/build_glow_time.py - full-face VFD mesh tile. -->\n"
        '    <bitmap id="MeshTile" filename="mesh_tile.png" packingFormat="png" />\n</drawables>\n',
        encoding="utf-8", newline="\n")
    print("glow time: %d glyphs, cell %dx%d, X0=%d Y0=%d, face #%02x%02x%02x glow #%02x%02x%02x"
          % (len(CHARS), x1 - x0, y1 - y0, x0, y0 + Y_CALIBRATION, *face, *glow))
    return 0


if __name__ == "__main__":
    sys.exit(main())
