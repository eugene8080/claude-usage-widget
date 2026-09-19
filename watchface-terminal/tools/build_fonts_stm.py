"""Regenerate the Claude Terminal bitmap fonts in Share Tech Mono, into resources/fonts.

Two atlases: the big time (digits + colon) and the small terminal text (printable ASCII for the
prompt, date, meter labels, percentages and reset times). Sizes come from the layout editor.
Run from the watchface-terminal directory:  python tools/build_fonts_stm.py
"""
import os
from PIL import Image, ImageFont, ImageDraw

HERE = os.path.dirname(__file__)
TTF = os.path.join(HERE, "ShareTechMono-Regular.ttf")
OUT = os.path.join(HERE, "..", "resources", "fonts")
FACE = "Share Tech Mono"

TIME_CHARS = "0123456789:"
TEXT_CHARS = "".join([chr(c) for c in range(0x20, 0x7F)])  # printable ASCII


def generate(out_base, size, chars, atlas_w=256):
    font = ImageFont.truetype(TTF, size)
    ascent, descent = font.getmetrics()
    line_h = ascent + descent
    try:
        adv = int(round(font.getlength("0")))
    except Exception:
        adv = font.getbbox("0")[2] - font.getbbox("0")[0]

    pad = 1
    cell_w = adv + 2 * pad + 2
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

    atlas.save(out_base + "_0.png")
    with open(out_base + ".fnt", "w", newline="\n") as f:
        f.write('info face="%s" size=%d bold=0 italic=0 charset="" unicode=1 '
                'stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1 outline=0\n' % (FACE, size))
        f.write("common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0 alphaChnl=1 "
                "redChnl=0 greenChnl=0 blueChnl=0\n" % (line_h, ascent, atlas_w, atlas_h))
        f.write('page id=0 file="%s_0.png"\n' % os.path.basename(out_base))
        f.write("chars count=%d\n" % len(chars))
        for ln in lines:
            f.write(ln + "\n")
    bb = Image.open(out_base + "_0.png").getchannel("A").getbbox()
    print("generated %s size=%d atlas=%dx%d ink=%s" % (out_base, size, atlas_w, atlas_h, bb))


generate(os.path.join(OUT, "stm_time"), 90, TIME_CHARS, 256)
generate(os.path.join(OUT, "stm_text"), 26, TEXT_CHARS, 256)
