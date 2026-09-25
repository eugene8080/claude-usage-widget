"""Regenerate every Chivo Mono bitmap font the Claude Grid face needs, into resources/fonts.

Chivo Mono is a variable font (weight axis); we pin one weight per atlas. Sizes come straight
from the layout editor's final numbers. Each atlas carries only the glyphs its fields draw so
the big sizes stay small (the 139px time and its outline are digits only).

Run from the watchface-grid directory:  python tools/build_fonts_chivo.py
"""
import os
from genfont import generate
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(__file__)
TTF = os.path.join(HERE, "ChivoMono-VariableFont_wght.ttf")
OUT = os.path.join(HERE, "..", "resources", "fonts")
FACE = "Chivo Mono"
WEIGHT = 500  # Medium - reads cleanly at watch scale, matches the editor's rendered weight

DIGITS = "0123456789"
UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
# space, colon, percent, slash, dot, minus, degree + the punctuation complication values can carry.
# The fonts have NO lowercase: the face upper-cases every value/label, so anything missing here
# would draw as a tofu box (e.g. "Fri"/"Sep" before values were upper-cased).
SYM = " :%/.-°,+'()!?&#"

# (out_base, size, glyphs, atlas_w, stroke)
FONTS = [
    ("cg_time",   139, DIGITS,               512, 0),   # stacked HH / MM
    ("cg_time_o", 139, DIGITS,               512, 2),   # always-on OUTLINE time: 2 px, anti-aliased (Iron Grit weight)
    ("cg_big",     36, DIGITS + UPPER + SYM, 512, 0),   # ring values, brand text, date
    ("cg_med",     30, DIGITS + UPPER + SYM, 512, 0),   # chip values, alt-tz, seconds value
    ("cg_week",    27, UPPER,                256, 0),   # weekday strip letters
    ("cg_small",   24, DIGITS + UPPER + SYM, 256, 0),   # battery %, SEC label
]

for out_base, size, chars, atlas_w, stroke in FONTS:
    generate(TTF, os.path.join(OUT, out_base), size, chars, atlas_w, FACE,
             weight=WEIGHT, stroke=stroke)

# --- per-field icon font, from Tabler Icons (MIT). Same set the editor embeds, incl. the
# footprints (steps), globe (alt time zone) and alarm-clock (indicator) glyphs. ------------
ICON_TTF = os.path.join(HERE, "tabler-icons.ttf")
ICONS = [
    0xea34,   # battery
    0x10265,  # footprints          -> STEPS (editor artwork)
    0xef92,   # heartbeat           -> HEART_RATE
    0xea38,   # bolt                -> BODY_BATTERY
    0xea97,   # droplet             -> PULSE_OX fallback
    0xec2c,   # flame               -> CALORIES
    0xeca5,   # stairs-up           -> FLOORS_CLIMBED
    0xef97,   # mountain            -> ALTITUDE
    0xf0db,   # activity-heartbeat  -> STRESS
    0xff9b,   # stopwatch           -> INTENSITY_MINUTES / stopwatch indicator
    0xea35,   # bell                -> NOTIFICATION_COUNT
    0xef1c,   # sunrise             -> SUNRISE
    0xec31,   # sunset              -> SUNSET
    0xea76,   # cloud               -> WEATHER default
    0xeaf8,   # moon                -> SLEEP_SCORE
    0xf228,   # zzz                 -> RECOVERY_TIME
    0xeb30,   # sun                 -> SOLAR / weather clear
    0xec34,   # wind                -> weather windy
    0xea72,   # cloud-rain          -> weather rain
    0xea73,   # cloud-snow          -> weather snow
    0xea74,   # cloud-storm         -> weather thunderstorm
    0xecd9,   # cloud-fog           -> weather fog/haze
    0xec0b,   # snowflake           -> weather cold
    0xeb54,   # world               -> ALT TIME ZONE
    0xea04,   # alarm               -> alarm indicator
    0xef62,   # lungs               -> RESPIRATION_RATE
    0xeb38,   # temperature         -> CURRENT_TEMPERATURE
]
# CIQ addresses font glyphs by 16-bit code only, so anything Tabler files above U+FFFF is
# re-filed under a free BMP private-use code (source glyph -> emitted id). The face must ask for
# the EMITTED code: ClaudeGridView.iconCodeFor returns 0xE000 for steps.
ICON_REMAP = {
    0x10265: 0xE000,  # footprints (steps) - drew as a tofu box when filed under U+10265
}

# --- composite weather icons ------------------------------------------------------------------
# This Tabler build has no "cloud-sun" / "cloud-moon", which "partly cloudy" needs. They are
# composed here: a small sun (or moon) in the upper right, sitting BEHIND the cloud - the cloud's
# filled silhouette plus a 1 px moat is cut out of the sun so the two outlines never touch.
# Drawn at 4x and box-filtered to 24 px, in the same frame draw.text uses, so they align with the
# real Tabler glyphs. The face asks for them by these codes (ClaudeGridView.weatherGlyph).
CLOUD_SUN = 0xE001
CLOUD_MOON = 0xE002


def composite_icon(back_cp, size=24, ss=4):
    import numpy as np
    from scipy.ndimage import binary_dilation, binary_fill_holes
    big = ImageFont.truetype(ICON_TTF, int(size * ss * 0.86))      # cloud, slightly reduced
    small = ImageFont.truetype(ICON_TTF, int(size * ss * 0.62))    # sun / moon
    asc, desc = ImageFont.truetype(ICON_TTF, size).getmetrics()
    adv = int(round(ImageFont.truetype(ICON_TTF, size).getlength(chr(0xea76))))
    W, H = adv * ss, (asc + desc) * ss

    def layer(font, cp, dx, dy):
        im = Image.new("L", (W, H), 0)
        ImageDraw.Draw(im).text((dx, dy), chr(cp), font=font, fill=255)
        return np.asarray(im).astype(np.float64) / 255.0

    cloud = layer(big, 0xea76, 0, int(4.5 * ss))                 # lower left
    back = layer(small, back_cp, int(W * 0.40), int(-0.5 * ss))  # upper right, mostly clear of it
    body = binary_fill_holes(cloud > 0.35)                        # cloud silhouette (outline + inside)
    cut = binary_dilation(body, iterations=ss)                    # + 1 px moat at 24 px
    out = np.maximum(cloud, np.where(cut, 0.0, back))
    img = Image.fromarray(np.round(out * 255).astype(np.uint8), "L")
    return img.resize((W // ss, H // ss), Image.BOX), adv


extras = [(CLOUD_SUN,) + composite_icon(0xeb30),   # sun  behind cloud -> partly cloudy (day)
          (CLOUD_MOON,) + composite_icon(0xeaf8)]  # moon behind cloud -> partly cloudy (night)
generate(ICON_TTF, os.path.join(OUT, "cg_icon"), 24, "".join([chr(c) for c in ICONS]),
         512, "Tabler", emit_ids=[ICON_REMAP.get(c, c) for c in ICONS], extra=extras)

# --- sanity: every atlas must carry ink (a blank atlas silently kills all text) ----------
print("\n--- ink check ---")
for out_base, size, chars, atlas_w, stroke in FONTS + [("cg_icon", 24, "", 512, 0)]:
    png = os.path.join(OUT, out_base + "_0.png")
    bb = Image.open(png).getchannel("A").getbbox()
    print("%-10s %s" % (out_base, "OK ink=" + str(bb) if bb else "!!! BLANK !!!"))
