# Claude Terminal - Garmin watch face

A terminal/CLI-styled watch face for fenix 8 class watches (incl. tactix 8), modelled on the
"Agentic Pro" look. Shows a prompt line, the time, the date, and the three Claude usage meters
(5H / 1W / model) as CLI rows with bars, percentages, and reset times, in Share Tech Mono.

Updated: 2026-09-25

## Where the data comes from

A watch face cannot receive phone pushes or read another app's storage, so it **subscribes to
the complications the companion "Claude Usage" watch-app publishes**. The percentage is the
complication value; the reset time rides in the complication's `unit` field as raw
epoch-seconds and is formatted here (keeping the background publisher free of date formatting).
Because the identity of a custom complication is an internal UUID, the face can't construct
its Id directly - it enumerates `getComplications()` and matches ours by the "Claude..." label.

So this face needs BOTH apps sideloaded: the watch-app (publisher) and this face (subscriber),
and the watch-app opened once so its 5-minute background publish is registered.

## Settings (Garmin Connect)

- **Show seconds** (off by default) - the time shows `HH:MM:SS`, ticking via `onPartialUpdate`
  when the device allows it.
- **Prompt text** - the top line (default `claude ~ %`, up to 24 characters). The layout
  editor's Prompt text is the default; the setting overrides it without a rebuild.

## Rendering

- **Sharp text.** Fonts are CIQ bitmap fonts generated from the TTF by
  `tools/build_fonts_terminal.py`. The generator writes the anti-aliased coverage into the atlas's
  **RGB as well as alpha**: the CIQ font compiler takes ink from RGB and uses alpha only as a mask,
  so a white-RGB atlas compiles 1-bit and bold (the old build rendered `claude ~ %` as `claude - %`).
- **Whole pixels.** Every text origin and every bar edge is snapped to an integer pixel
  (`text()` / `rect()` in the view), so bar ends are hard and glyphs aren't resampled.
- **Optional VFD style** - the time drawn from pre-rendered glow bitmaps and one 3 px mesh tiled
  over the whole face (same scheme as Claude Grid). Off by default; switch the three `base.*`
  lines in `monkey.jungle` as its comment shows, after generating the assets:

  ```
  python tools/build_glow_time.py --face ffffff --glow d97757
  ```

## Fonts

Share Tech Mono (OFL, `resources/fonts/OFL.txt`). To change the typeface, set `TTF` / `FACE` /
`WEIGHT` at the top of `tools/build_fonts_terminal.py` and run it (then `build_glow_time.py`
if you use the VFD build):

```
python tools/build_fonts_terminal.py
```

## Layout editor

`editor/claude-terminal-editor.html` - drag / arrow-key / Tab through the elements, themes, a
grouped font menu (incl. dot-matrix faces), a preview time & date, and a VFD preview. It places
text by the watch's own rule (line top + font ascent + 1 row), so it matches the simulator. See
`editor/README.md`.

## Build

```
monkeyc -f monkey.jungle -o dist/ClaudeFace-fenix847mm.prg \
        -y ~/.garmin-keys/developer_key.der -d fenix847mm -r
```
