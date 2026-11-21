# Apple TV Remote (Flutter + Kotlin + Chaquopy + pyatv)

A Wi-Fi Apple TV remote control for Android. The UI is Flutter, the Python
[`pyatv`](https://pyatv.dev) library runs embedded on-device via
[Chaquopy](https://chaquopy.com), and a Kotlin `MethodChannel` bridges the two.

**Verified working on a real setup:** Samsung Galaxy A53 (Android) ↔ Apple TV 4K
Gen 3 ("Séjour", tvOS 27.2.1) over Wi-Fi.

## Features

- **Wi-Fi auto-discovery** — `pyatv.scan()` over mDNS/Zeroconf with a
  `WifiManager.MulticastLock` held during the scan (required on Android).
- **Pairing with on-TV PIN** — tap a discovered Apple TV; if it isn't paired
  yet, the TV displays a 4-digit PIN which you type into the app
  (AirPlay first, then Companion if the device supports it).
- **Credentials persist** — saved with pyatv's `FileStorage` in the app's
  private files directory (`files/pyatv.conf`). Pair once; never again
  (until "Unpair" in the ⋮ menu or app uninstall).
- **Automatic connect at launch** — scan (~5 s), then:
  1. remembered last TV found → connect to it;
  2. else exactly **one** TV found **and** already paired → connect
     automatically (no tap);
  3. else show the list.
- **Auto-reconnect** — dropped connections are retried with exponential
  backoff (2 → 15 s).
- **Full remote UI (dark mode)** — Siri-Remote-style layout, haptic feedback
  on every press:
  - Header: device name, live status dot, keyboard input, power button,
    switch-device and unpair menu.
  - Navigation: swipe **touchpad** (swipe = move, tap = select) or tactile
    **D-Pad** (toggleable).
  - **Hold-to-repeat**: the 4 D-Pad arrows and the volume +/− buttons repeat
    ~6–7×/sec while held (450 ms initial delay). Select/mute stay tap-only.
  - Menu (back), Home (long-press = top menu / Control Center), Play/Pause,
    Rewind / Fast-Forward (±10 s).
  - Volume up / down / mute.
  - Keyboard sheet that types directly into the Apple TV's focused field
    (`keyboard.text_set`).
- **Power toggle** — the ⏻ button sleeps and **wakes** the Apple TV:
  `power.turn_on()` → `remote_control.wakeup()` → **Wake-on-LAN magic packet**
  (MAC from the discovered config or `/proc/net/arp`; works even from deep
  sleep). Power state is tracked locally (persisted) because pyatv can't poll
  it on newer tvOS (`FetchAttentionState` fails) — the button toggles from
  the last known state.

## Architecture

```
lib/ (Dart)                      android/app/src/main/
  screens/  scanner, remote        kotlin/.../MainActivity.kt   MethodChannel bridge,
  state/    RemoteController       │                            MulticastLock,
  services/ AtvService   ◄─────────┘  com.example.appletv_remote/pyatv
  widgets/  dpad, touchpad, PIN dialog, keyboard sheet
                                   python/atv_bridge.py
                                     persistent asyncio loop, pyatv scan/pair/
                                     connect, FileStorage, auto-reconnect,
                                     power tracking, Wake-on-LAN
```

All Python calls run on a dedicated background `asyncio` event loop; Kotlin
executes them on `Dispatchers.IO` so the UI never freezes. Python → Dart async
events (connection lost / reconnecting / connected / power state) flow through
a Java callback (`EventForwarder`) into the same `MethodChannel`.

## Requirements

- Flutter SDK 3.x, Android Studio (JDK 17), Android SDK 34.
- A real Apple TV on the **same Wi-Fi** as the phone.
  (The emulator can reach Apple TVs on your LAN too — pyatv speaks plain TCP.)

## Build & run

```bash
flutter pub get
flutter run            # debug build; first build downloads pyatv wheels (slow)
```

Release APK (Chaquopy is open source since v12 — no license key needed):

```bash
flutter build apk --release
```

Install to a connected device without rebuilding:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## Version notes (load-bearing — verified by building)

- **Chaquopy `16.1.0`**, open source (MIT). Newer 17.x also works if you bump
  both the plugin and AGP range.
- **Python target `3.10`** — Chaquopy's pip runs under the build machine's
  `python`, so the target minor version must match it (this dev box has
  Python 3.10). To use 3.11+, install that Python and set
  `buildPython("C:/path/to/python3.11.exe")` in the `chaquopy` block.
- **Pinned pip requirements** (newest versions don't have Android wheels):
  - `pyatv==0.14.5` — 0.15+ requires `cryptography>=43`, but the newest
    cryptography with a Chaquopy Android wheel is **42.0.8** (pinned too).
  - `cryptography==42.0.8`
  - `pydantic>=1.10.10,<2` — pydantic v2 needs the Rust-based pydantic-core,
    which has no Android wheel.
  - `srptools==1.0.1` — srptools 2.0 changed `SRPClientSession`'s constructor,
    breaking pyatv 0.14.x pairing.
  - aiohttp/miniaudio resolve automatically to the newest Chaquopy Android
    wheels (3.10.10 / 1.59); zeroconf, protobuf, mediafile, etc. are
    pure-Python and come from PyPI.
- **Gradle layout** — Flutter 3.35 requires AGP/Kotlin declared in
  `settings.gradle`, while Chaquopy locates AGP by scanning the app module's
  `buildscript` classpath. Both are therefore declared: `settings.gradle` has
  the plugins (for Flutter), and `app/build.gradle` has a `buildscript` block
  with AGP + the Chaquopy plugin, applied via `apply plugin:`.
- **pyatv 0.14.5 API gotchas** (all handled in `atv_bridge.py`):
  - `FileStorage(filename, loop)` requires the event loop (0.15+ dropped it —
    bridge tries both).
  - Pairing mutates the storage's settings but **never saves** — the app must
    call `storage.save()` after pairing or credentials are lost every launch.
  - Storage iteration/matching is `storage.settings` matched by protocol
    identifiers (NOT `storage.configs`, which doesn't exist in 0.14.5).
  - Connecting needs a **fresh scan config** (services/ports); storage only
    supplies credentials. The app scans before auto-connecting.

## Known dev gotchas

- **Dart-only changes may not reach the APK**: this Flutter version's Gradle
  incremental build sometimes reuses a stale `kernel_blob.bin`. Verify with
  `strings` on `assets/flutter_assets/kernel_blob.bin` inside the APK; if
  stale, delete `build/app/intermediates/flutter*` and rebuild. (This bit us
  twice; always verify before installing.)
- Python changes are safe to check with `python -c "compile(...)"` — a plain
  `ast.parse` does NOT catch compile-time errors like mis-placed `global`.
- **First build is slow**: Chaquopy pip-installs pyatv and friends per ABI.
- **Scan finds nothing?** Phone and Apple TV must be on the same Wi-Fi (no AP
  isolation); some OEMs filter mDNS — disable "Private DNS" if needed. The app
  requests `NEARBY_WIFI_DEVICES` at runtime on Android 13+.
- **Unpair**: remote header menu → "Unpair this Apple TV" (removes the stored
  credentials).
- The benign log warning `Could not fetch SystemStatus, power_state will not
  work` appears on tvOS 27 with pyatv 0.14.5 — expected; power is handled via
  suspend/wakeup + Wake-on-LAN instead.

## Verification status

- `flutter analyze` — no issues.
- `flutter test` — scanner listing + full tap → PIN dialog → connected flow
  (fake AtvService).
- `gradlew :app:assembleDebug` — **BUILD SUCCESSFUL**; APK contains
  `libpython3.10.so` (arm64-v8a + x86_64), pyatv/zeroconf compiled, native
  wheels for cryptography/aiohttp/miniaudio.
- On-device (Galaxy A53 ↔ Apple TV 4K Gen 3): discovery, PIN pairing (AirPlay
  + Companion), credential persistence across restarts, auto-connect,
  touchpad/D-Pad navigation, hold-to-repeat arrows + volume, play/pause,
  menu/home, ±10 s skip, keyboard input, power sleep **and** wake (WoL).

## Key files

| File | Purpose |
|---|---|
| `android/app/src/main/python/atv_bridge.py` | pyatv backend: scan, pair (on-TV PIN), credentials save/load, connect + auto-reconnect, commands, keyboard, power tracking, Wake-on-LAN |
| `android/app/src/main/kotlin/com/example/appletv_remote/MainActivity.kt` | `MethodChannel` bridge, `MulticastLock`, JSON plumbing, event forwarding |
| `android/app/build.gradle` | Chaquopy config + pip pins, app-module `buildscript` for AGP/Chaquopy detection, minSdk 24, ABIs |
| `android/settings.gradle` | AGP/Kotlin plugin declarations (Flutter's requirement) |
| `lib/services/atv_service.dart` | typed wrapper over the `MethodChannel` |
| `lib/state/remote_controller.dart` | Provider state: scan, pairing flow, auto-connect rules, events, power-state tracking |
| `lib/screens/` | scanner + dark-mode remote screens |
| `lib/widgets/` | PIN dialog (on-TV PIN entry), D-Pad (hold-to-repeat), touchpad, keyboard sheet |
