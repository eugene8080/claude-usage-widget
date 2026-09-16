# Claude Usage - Garmin watch app

A glance for fenix 8 class watches, including the **tactix 8**, showing the same three meters
as the phone widget: `5H`, `1W`, and the per-model weekly cap.

Generated: 2026-09-16

## The watch never talks to Claude

It renders numbers pushed from the Android app over BLE, and holds nothing else. Two reasons
it must work this way, either one decisive:

- **Cloudflare.** `cf_clearance` is minted by solving a JS challenge in a real browser engine,
  which is why the phone app carries a WebView. Connect IQ's `makeWebRequest` is a plain HTTP
  client with no JS engine, so claude.ai answers it with a 403.
- **Credential blast radius.** A Claude `sessionKey` in Connect IQ `Application.Storage` is
  unencrypted, on a device worn outdoors and handed to people. On the phone it sits in
  `EncryptedSharedPreferences` behind the Android keystore.

## Device profile

`fenix847mm` **is** the tactix 8 47mm/51mm profile - Garmin ships fenix 8 / tactix 8 / quatix 8
as one Connect IQ device, which the simulator title bar confirms. There is no separate
`tactix8` profile to install.

## Build

Requires the Connect IQ SDK and a developer key (both already installed on this machine -
SDK 9.2.0 under `%APPDATA%\Garmin\ConnectIQ\Sdks`, key at `~/.garmin-keys/developer_key.der`).

```
monkeyc -f monkey.jungle -o build/ClaudeUsage.prg \
        -y ~/.garmin-keys/developer_key.der -d fenix847mm
monkeydo build/ClaudeUsage.prg fenix847mm      # loads it into a running simulator
```

## Testing the phone link without a watch

The Connect IQ simulator talks to the companion app running on an Android device **or
emulator** over adb, at simulated BLE speeds - no physical watch, and no Garmin Connect
Mobile. Verified working end to end on 2026-09-16.

```
./gradlew assembleDebug -PciqTethered=true && adb install -r app/build/outputs/apk/debug/app-debug.apk
adb forward tcp:7381 tcp:7381
monkeydo watch/build/ClaudeUsage-fenix847mm.prg fenix847mm
```

**Order matters, and it is the one thing that will waste your afternoon.** The phone app is
the *server*: its SDK opens port 7381 only while a push is running, and the simulator's
connect attempt does not retry. So:

1. Trigger a refresh on the phone (tap the widget). The app logs
   `ConnectIQ-AdbConnection: Waiting for simulator connection.` and the socket is now open.
   It stays open for as long as the app process lives.
2. **Then** in the simulator: **adb Connection > Start** (Ctrl-F1). It logs
   `Simulator connected`.
3. Trigger another refresh. That one lands: `Wrote N bytes to output stream` /
   `ClaudeWatch: watch updated: Simulator`.

Clicking Start first connects to nothing and looks identical to a broken bridge.

## Layout note

Glance code is compiled into its own restricted memory space, so `Snapshot` and the glance
view are annotated `(:glance)`. Anything the glance touches needs that annotation.
