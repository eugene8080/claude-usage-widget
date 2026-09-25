# Claude Terminal - Garmin watch face

A terminal/CLI-styled watch face for fenix 8 class watches (incl. tactix 8), modelled on the
"Agentic Pro" look. Shows a prompt line, the time, the date, and the three Claude usage meters
(5H / 1W / model) as CLI rows with bars, percentages, and reset times, in IBM Plex Mono on the
Night Owl palette, with a glowing VFD time.

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

- **Show seconds** (on by default) - the time shows `HH:MM:SS`. In high-power mode the whole
  face redraws every second. In low-power mode the seconds tick through `onPartialUpdate`, but
  only on screens that allow it: the MIP Solar models do, while the AMOLED tactix 8 holds the
  last second until you raise your wrist.
- **Prompt text** - the top line (default `eugene@tactix ~ $`, up to 24 characters). The layout
  editor's Prompt text is the default; the setting overrides it without a rebuild.
- A face that was already installed keeps its **stored** settings when you sideload a new build.
  So if it still shows the old prompt or no seconds, change them in Garmin Connect.

## Rendering

- **Sharp text.** Fonts are CIQ bitmap fonts generated from the TTF by
  `tools/build_fonts_terminal.py`. The generator writes the anti-aliased coverage into the atlas's
  **RGB as well as alpha**: the CIQ font compiler takes ink from RGB and uses alpha only as a mask,
  so a white-RGB atlas compiles 1-bit and bold (the old build rendered `claude ~ %` as `claude - %`).
- **Whole pixels.** Every text origin and every bar edge is snapped to an integer pixel
  (`text()` / `rect()` in the view), so bar ends are hard and glyphs aren't resampled.
- **VFD style (the default build)** - the time drawn from pre-rendered glow bitmaps and one 3 px
  mesh tiled over the whole face (same scheme as Claude Grid). The glow colours are baked into the
  bitmaps, so regenerate them after changing the time font or the theme:

  ```
  python tools/build_glow_time.py --face d6deeb --glow 82aaff
  ```

  To build the plain face, switch the three `base.*` lines in `monkey.jungle` as its comment shows.
  The MIP **Solar** models always get the plain face. Their 64-colour screens have no alpha
  blending, so the glow's soft alpha would draw as solid blobs.
- **Seconds repaint.** `onPartialUpdate` clips to the time's real band. In the VFD build that is
  the glow cell (`GlowTimeMetrics.Y0/H`); in the plain build it is the time font's line box. The
  band is capped at the first meter row. Inside the clip it blanks the band and redraws the
  prompt, time and date in full-update order, so a descender or a line box that crosses the band
  is never cut off or double-drawn.
- **Screen sizes.** The fonts are fixed pixel sizes laid out for the 454 px tactix 8. The 416 px
  fenix 8 43mm fits, but on the 260/280 px Solar screens the prompt and the time overrun the bezel.

## Fonts

IBM Plex Mono Regular (OFL, `resources/fonts/OFL.txt`), at the editor's sizes: prompt 26 px
(`STMono`), date + rows 25 px (`STMonoSmall`), time 70 px (`STMonoTime`). The `stm_*` file names
are the face's generic font slots, kept from the earlier Share Tech Mono build. To change the
typeface or a size, edit `TTF` / `FACE` / `WEIGHT` and the `generate(...)` calls in
`tools/build_fonts_terminal.py`, run it, then run `build_glow_time.py`:

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
