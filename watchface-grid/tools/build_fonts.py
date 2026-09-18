"""Regenerate every Chakra Petch bitmap font the Claude Grid face needs, into resources/fonts.

Each font carries only the glyphs its fields actually draw, so the big sizes stay small:
the 120px time and 36px ring fonts are digits only; value/small/label carry letters + symbols.
Run from the watchface-grid directory:  python tools/build_fonts.py
"""
import os
from genfont import generate

TTF = os.path.join(os.path.dirname(__file__), "ChakraPetch-SemiBold.ttf")
OUT = os.path.join(os.path.dirname(__file__), "..", "resources", "fonts")

DIGITS = "0123456789"
UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
LOWER = "abcdefghijklmnopqrstuvwxyz"
DEG = "°"  # degree sign, for the "C" (temperature) label

# (out_base, size, glyphs, atlas_w) -- sizes come straight from the layout editor:
#   time 64*1.88, ring value 22*1.64, chip/date value 22*1.4-1.48, small(batt/week) 22, label 11*1.5.
FONTS = [
    ("cp_time",  120, DIGITS,                             512),  # stacked HH / MM
    ("cp_ring",   36, DIGITS,                             256),  # HR / BB / SEC values
    ("cp_value",  32, DIGITS + UPPER + " ",               256),  # chip values + date (SEP / 18)
    ("cp_small",  22, DIGITS + UPPER + "% ",              256),  # battery %, weekday letters
    ("cp_label",  16, DIGITS + UPPER + LOWER + DEG + " ", 256),  # field labels (ST, HR, mb, VO2, degC...)
]

for out_base, size, chars, atlas_w in FONTS:
    generate(TTF, os.path.join(OUT, out_base), size, chars, atlas_w)
