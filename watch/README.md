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

The Connect IQ simulator can talk to a companion app running on an Android device **or
emulator** over adb, at simulated BLE speeds - no physical watch, and no Garmin Connect Mobile:

1. Companion calls `ConnectIQ.getInstance(context, IQConnectType.TETHERED)` (the ADB edition).
2. `adb forward tcp:7381 tcp:7381`
3. Simulator: **adb Connection > Start** (Ctrl-F1).

## Layout note

Glance code is compiled into its own restricted memory space, so `Snapshot` and the glance
view are annotated `(:glance)`. Anything the glance touches needs that annotation.
