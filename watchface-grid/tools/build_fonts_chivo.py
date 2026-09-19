"""Regenerate every Chivo Mono bitmap font the Claude Grid face needs, into resources/fonts.

Chivo Mono is a variable font (weight axis); we pin one weight per atlas. Sizes come straight
from the layout editor's final numbers. Each atlas carries only the glyphs its fields draw so
the big sizes stay small (the 139px time and its outline are digits only).

Run from the watchface-grid directory:  python tools/build_fonts_chivo.py
"""
import os
from genfont import generate
from PIL import Image

HERE = os.path.dirname(__file__)
TTF = os.path.join(HERE, "ChivoMono-VariableFont_wght.ttf")
OUT = os.path.join(HERE, "..", "resources", "fonts")
FACE = "Chivo Mono"
WEIGHT = 500  # Medium - reads cleanly at watch scale, matches the editor's rendered weight

DIGITS = "0123456789"
UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
SYM = " :%/.-°"  # space, colon, percent, slash, dot, minus, degree

# (out_base, size, glyphs, atlas_w, stroke)
FONTS = [
    ("cg_time",   139, DIGITS,               512, 0),   # stacked HH / MM
    ("cg_time_o", 139, DIGITS,               512, 4),   # always-on OUTLINE time
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
]
generate(ICON_TTF, os.path.join(OUT, "cg_icon"), 24, "".join([chr(c) for c in ICONS]),
         512, "Tabler")

# --- sanity: every atlas must carry ink (a blank atlas silently kills all text) ----------
print("\n--- ink check ---")
for out_base, size, chars, atlas_w, stroke in FONTS + [("cg_icon", 24, "", 512, 0)]:
    png = os.path.join(OUT, out_base + "_0.png")
    bb = Image.open(png).getchannel("A").getbbox()
    print("%-10s %s" % (out_base, "OK ink=" + str(bb) if bb else "!!! BLANK !!!"))
