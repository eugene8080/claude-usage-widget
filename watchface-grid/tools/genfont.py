"""Generate a Connect IQ bitmap font (BMFont .fnt + PNG atlas) from a TTF.

Unlike the monospace generator in ../../watchface/tools, this preserves each glyph's own
horizontal advance, so a *proportional* face (Chakra Petch) sets its natural letter spacing
instead of being forced onto one column width.

CIQ tints the glyph by the text colour, so glyphs are drawn white on transparency and the
alpha channel carries the shape.

Callable as `generate(...)` (see tools/build_fonts.py) or from the CLI:
    python genfont.py <ttf> <out_base> <size> <chars> [atlas_w] [face_name]
"""
import os
import sys
from PIL import Image, ImageFont, ImageDraw


def generate(ttf, out_base, size, chars, atlas_w=256, face_name="Chakra Petch"):
    font = ImageFont.truetype(ttf, size)
    ascent, descent = font.getmetrics()
    line_h = ascent + descent

    pad = 1
    # Uniform grid cell sized to the widest glyph in the set (keeps packing trivial); each
    # glyph still records its OWN xadvance below, so rendered spacing stays proportional.
    max_w = 0
    for ch in chars:
        bb = font.getbbox(ch)
        max_w = max(max_w, bb[2] - bb[0], int(round(font.getlength(ch))))

    cell_w = max_w + 2 * pad + 2
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
        col = i % cols
        row = i // cols
        gx = col * cell_w + pad
        gy = row * cell_h + pad
        draw.text((gx, gy), ch, font=font, fill=(255, 255, 255, 255))
        x0, y0, x1, y1 = font.getbbox(ch)
        gw = max(0, x1 - x0)
        gh = max(0, y1 - y0)
        adv = int(round(font.getlength(ch)))
        lines.append(
            "char id=%d x=%d y=%d width=%d height=%d xoffset=%d yoffset=%d xadvance=%d page=0 chnl=15"
            % (ord(ch), gx + x0, gy + y0, gw, gh, x0, y0, adv)
        )

    atlas.save(out_base + "_0.png")
    with open(out_base + ".fnt", "w", newline="\n") as f:
        f.write('info face="%s" size=%d bold=0 italic=0 charset="" unicode=1 '
                'stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1 outline=0\n' % (face_name, size))
        f.write("common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0 alphaChnl=1 "
                "redChnl=0 greenChnl=0 blueChnl=0\n" % (line_h, ascent, atlas_w, atlas_h))
        f.write('page id=0 file="%s_0.png"\n' % os.path.basename(out_base))
        f.write("chars count=%d\n" % len(chars))
        for ln in lines:
            f.write(ln + "\n")
    print("generated %s size=%d atlas=%dx%d cols=%d rows=%d cell=%dx%d"
          % (out_base, size, atlas_w, atlas_h, cols, rows, cell_w, cell_h))


if __name__ == "__main__":
    generate(sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4],
             int(sys.argv[5]) if len(sys.argv) > 5 else 256,
             sys.argv[6] if len(sys.argv) > 6 else "Chakra Petch")
