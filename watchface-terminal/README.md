# Claude Terminal - Garmin watch face

A terminal/CLI-styled watch face for fenix 8 class watches (incl. tactix 8), modelled on the
"Agentic Pro" look. Shows the time, date, and the three Claude usage meters (5H / 1W / model)
as CLI rows with bars, percentages, and reset times, in JetBrains Mono and Claude orange.

Generated: 2026-09-18

## Where the data comes from

A watch face cannot receive phone pushes or read another app's storage, so it **subscribes to
the complications the companion "Claude Usage" watch-app publishes**. The percentage is the
complication value; the reset time rides in the complication's `unit` field as raw
epoch-seconds and is formatted here (keeping the background publisher free of date formatting).
Because the identity of a custom complication is an internal UUID, the face can't construct
its Id directly - it enumerates `getComplications()` and matches ours by the "Claude..." label.

So this face needs BOTH apps sideloaded: the watch-app (publisher) and this face (subscriber),
and the watch-app opened once so its 5-minute background publish is registered.

## Settings

`Show seconds` (off by default) - when on, the time shows `HH:MM:SS`, ticking via
`onPartialUpdate` when the device allows it.

## Fonts

JetBrains Mono (OFL), converted from the TTF into Connect IQ bitmap fonts with
`tools/genfont.py`:

```
python tools/genfont.py JetBrainsMono-Regular.ttf resources/fonts/jbmono 26 "<printable ascii>"
python tools/genfont.py JetBrainsMono-Regular.ttf resources/fonts/jbmono_time 58 "0123456789:"
```

## Build

```
monkeyc -f monkey.jungle -o dist/ClaudeFace-fenix847mm.prg \
        -y ~/.garmin-keys/developer_key.der -d fenix847mm -r
```
