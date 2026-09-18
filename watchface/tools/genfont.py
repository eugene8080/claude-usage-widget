"""Generate a Connect IQ bitmap font (BMFont .fnt + PNG atlas) from a TTF.

CIQ tints the glyph by the text colour, so glyphs are rendered white on transparency and the
alpha channel carries the shape. Monospace, so every glyph shares one xadvance.
"""
import sys
from PIL import Image, ImageFont, ImageDraw

ttf, out_base, size_s, chars = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
size = int(size_s)
font = ImageFont.truetype(ttf, size)
ascent, descent = font.getmetrics()
line_h = ascent + descent

# Monospace advance: width of a reference glyph.
adv = font.getbbox("0")[2] - font.getbbox("0")[0]
try:
    adv = int(round(font.getlength("0")))
except Exception:
    pass

pad = 1
# Lay glyphs in a grid sized to fit; atlas width fixed, height grows.
cell_w = adv + 2 * pad + 2
cell_h = line_h + 2 * pad + 2
cols = max(1, 256 // cell_w)
rows = (len(chars) + cols - 1) // cols
atlas_w = 256
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
    # Draw the glyph white; use the font's own left/top bearing via anchor at baseline.
    draw.text((gx, gy), ch, font=font, fill=(255, 255, 255, 255))
    # Tight bbox of what we drew, within the cell.
    bbox = font.getbbox(ch)
    x0, y0, x1, y1 = bbox
    gw = max(0, x1 - x0)
    gh = max(0, y1 - y0)
    # BMFont char: position in atlas is where we drew (gx+x0, gy+y0); offsets place it on the line.
    lines.append(
        "char id=%d x=%d y=%d width=%d height=%d xoffset=%d yoffset=%d xadvance=%d page=0 chnl=15"
        % (ord(ch), gx + x0, gy + y0, gw, gh, x0, y0, adv)
    )

atlas.save(out_base + "_0.png")
with open(out_base + ".fnt", "w", newline="\n") as f:
    f.write('info face="JetBrains Mono" size=%d bold=0 italic=0 charset="" unicode=1 '
            'stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1 outline=0\n' % size)
    f.write("common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0 alphaChnl=1 "
            "redChnl=0 greenChnl=0 blueChnl=0\n" % (line_h, ascent, atlas_w, atlas_h))
    f.write('page id=0 file="%s_0.png"\n' % out_base.split("/")[-1])
    f.write("chars count=%d\n" % len(chars))
    for ln in lines:
        f.write(ln + "\n")
print("generated", out_base, "size", size, "advance", adv, "line", line_h, "atlas", atlas_w, atlas_h)
