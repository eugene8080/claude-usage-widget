"""Regenerate the Claude Terminal bitmap fonts into resources/fonts.

Three atlases: the big time (digits + colon), the prompt text, and the date/row text (both
printable ASCII - the prompt is user-editable; the rows carry labels, percentages and reset
times). Sizes come from the layout editor; keep them in step with its Copy settings block.
The stm_* file names predate the typeface switch - they are the face's generic font slots.

The face's typeface is the (TTF, FACE, WEIGHT) setting below - swap it to change the whole face.
A terminal must be monospace, so every glyph (incl. the time's colon) gets the SAME advance.

Run from the watchface-terminal directory:  python tools/build_fonts_terminal.py
(then tools/build_glow_time.py if the time font changed - the VFD time bitmaps are cut from it).
"""
from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "resources", "fonts")
# --- the face's typeface ---------------------------------------------------------------------
TTF = os.path.join(HERE, "IBMPlexMono-Regular.ttf")   # OFL - resources/fonts/OFL.txt
FACE = "IBM Plex Mono"
WEIGHT = None       # static font; set a number (e.g. 400) for a variable TTF's weight axis

TIME_CHARS = "0123456789:"
TEXT_CHARS = "".join([chr(c) for c in range(0x20, 0x7F)])  # printable ASCII


def generate(out_base: str, size: int, chars: str, atlas_w: int = 256) -> None:
    """Rasterise `chars` into a BMFont atlas with one shared (monospace) advance.

    Coverage goes into R, G, B AND alpha: the CIQ font compiler takes a glyph pixel's ink from its
    RGB brightness and uses alpha only as an on/off mask (proved in the simulator for the Claude
    Grid). Pillow's draw.text on a transparent RGBA image leaves RGB at a flat 255 on every touched
    pixel, so without this the anti-aliased edge was thrown away and text compiled 1-bit and bold.
    """
    font = ImageFont.truetype(TTF, size)
    if WEIGHT is not None:
        font.set_variation_by_axes([WEIGHT])
    ascent, descent = font.getmetrics()
    line_h = ascent + descent
    adv = int(round(font.getlength("0")))

    pad = 1
    cell_w = max(adv, max(font.getbbox(c)[2] for c in chars)) + 2 * pad + 2
    cell_h = line_h + 2 * pad + 2
    cols = max(1, atlas_w // cell_w)
    rows = (len(chars) + cols - 1) // cols
    atlas_h = 1
    while atlas_h < rows * cell_h:
        atlas_h *= 2

    atlas = Image.new("RGBA", (atlas_w, atlas_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(atlas)
    lines = []
    for i, ch in enumerate(chars):
        gx = (i % cols) * cell_w + pad
        gy = (i // cols) * cell_h + pad
        draw.text((gx, gy), ch, font=font, fill=(255, 255, 255, 255))
        x0, y0, x1, y1 = font.getbbox(ch)
        lines.append(
            "char id=%d x=%d y=%d width=%d height=%d xoffset=%d yoffset=%d xadvance=%d page=0 chnl=15"
            % (ord(ch), gx + x0, gy + y0, max(0, x1 - x0), max(0, y1 - y0), x0, y0, adv))

    cov = atlas.getchannel("A")
    Image.merge("RGBA", (cov, cov, cov, cov)).save(out_base + "_0.png")
    with open(out_base + ".fnt", "w", newline="\n") as f:
        f.write('info face="%s" size=%d bold=0 italic=0 charset="" unicode=1 '
                'stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1 outline=0\n' % (FACE, size))
        # BMFont channel codes: 0 = glyph data - every channel carries the glyph.
        f.write("common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0 alphaChnl=0 "
                "redChnl=0 greenChnl=0 blueChnl=0\n" % (line_h, ascent, atlas_w, atlas_h))
        f.write('page id=0 file="%s_0.png"\n' % os.path.basename(out_base))
        f.write("chars count=%d\n" % len(chars))
        for ln in lines:
            f.write(ln + "\n")
    bb = Image.open(out_base + "_0.png").getchannel("A").getbbox()
    print("generated %s size=%d atlas=%dx%d adv=%d lineH=%d ink=%s"
          % (os.path.basename(out_base), size, atlas_w, atlas_h, adv, line_h, bb))
    if bb is None:
        raise SystemExit("!!! %s is blank - a blank atlas silently kills all text" % out_base)


if __name__ == "__main__":
    generate(os.path.join(OUT, "stm_time"), 70, TIME_CHARS, 256)    # editor: time size
    generate(os.path.join(OUT, "stm_text"), 26, TEXT_CHARS, 256)    # editor: prompt size
    generate(os.path.join(OUT, "stm_small"), 25, TEXT_CHARS, 256)   # editor: date + rows size
