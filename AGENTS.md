# Apple TV Remote — Agent Guide

> Separate project from the ATUM web platform in the parent folder. This is a
> Flutter + Kotlin + Chaquopy (embedded Python/pyatv) Android app.
> Human docs: [`README.md`](README.md) — this file holds agent-only knowledge.

## Status

Working end-to-end on a real setup: Samsung Galaxy A53 ↔ Apple TV 4K Gen 3
(tvOS 27.2.1). Discovery, PIN pairing (AirPlay + Companion), credential
persistence across app restarts, auto-connect at launch, full remote controls,
hold-to-repeat arrows/volume, keyboard input, power sleep + wake (Wake-on-LAN).

## Hard-won facts (do not relearn these the hard way)

### Build system
- **Flutter 3.35 + Chaquopy 16.1.0 + AGP 8.9.1 + Kotlin 2.1.0, Gradle 8.12.**
- **Plugin layout is load-bearing:** Flutter needs AGP/Kotlin declared in
  `android/settings.gradle` (`plugins {}` block); Chaquopy finds AGP by
  scanning the **app module's `buildscript` classpath**. So `app/build.gradle`
  has BOTH a `buildscript { classpath AGP + chaquopy }` block AND
  `apply plugin: "com.chaquo.python"` (the `plugins {}` DSL cannot resolve
  plugins from a same-file buildscript classpath). Removing either half breaks
  the build ("Failed to find plugin com.android.tools.build:gradle" from
  Chaquopy, or Kotlin decoration errors from mixing layouts).
- **Python target = 3.10** because Chaquopy runs pip under the build machine's
  `python` (3.10 on this box) and requires matching minor versions. cp310
  Chaquopy wheels exist for all of pyatv 0.14.5's binary deps. To move to
  3.11+: install that Python and set `buildPython(...)` in the chaquopy block.
- **Groovy DSL trap:** inside `chaquopy { defaultConfig { py -> ... } }`, a
  bare `version = "3.10"` binds to `Project.version` (Groovy closure owner
  wins). Always write `py.version = "3.10"`. The old
  `defaultPythonVersion "..."` DSL does not exist in 16.x.
- **pip pins are load-bearing** (see `app/build.gradle`): `pyatv==0.14.5`,
  `cryptography==42.0.8`, `pydantic<2`, `srptools==1.0.1`. Newer versions of
  these either need Android wheels that don't exist (cryptography ≥43,
  pydantic-core/Rust) or broke APIs (srptools 2.0 SRPClientSession).
- **No explicit Chaquopy runtime dependency** — the plugin injects its
  `target`/`python` artifacts automatically.

### pyatv 0.14.5 API (verified against source; the bridge encodes all of this)
- `FileStorage(filename, loop)` — takes the event loop (removed in 0.15+;
  bridge tries both signatures).
- **Pairing does NOT persist anything** — it mutates the storage's settings
  object; the app MUST call `storage.save()` afterwards, or the user re-pairs
  every launch. (atvremote does it in a `finally`.)
- Storage iteration is `storage.settings` (NOT `storage.configs` — AttributeError).
  Match devices by protocol identifiers (`settings.protocols.<proto>.identifier`)
  against a scan config's `all_identifiers`, or by `settings.info.name`.
- `connect()` needs a **fresh scan config** (services/ports); storage only
  supplies credentials via `get_settings` + `config.apply(settings)`. The app
  therefore scans BEFORE auto-connecting.
- On tvOS 27, `FetchAttentionState` fails at connect ("power_state will not
  work") — expected; don't try to rely on `atv.power.power_state`. Power is
  tracked locally (last command + persisted) and wake uses
  turn_on → wakeup → **Wake-on-LAN** (MAC from scan identifiers or
  `/proc/net/arp`; broadcast 255.255.255.255 + subnet-directed).

### Dart build trap
- This Flutter version's Gradle incremental build sometimes reuses a stale
  `kernel_blob.bin` for **Dart-only changes** (silently — build succeeds, old
  code ships). ALWAYS verify before installing:
  read `assets/flutter_assets/kernel_blob.bin` from the APK and check for a
  new symbol (e.g. a new class/key name). If stale:
  `Remove-Item -Recurse build/app/intermediates/flutter*` then rebuild.

### Python checking
- `ast.parse` is NOT enough — it misses compile-time errors (e.g. `global`
  declared after assignment). Always `compile(src, 'x', 'exec')`.

## Commands

```powershell
# Dart checks
C:\src\flutter\bin\flutter.bat analyze
C:\src\flutter\bin\flutter.bat test

# Android build (JDK from Android Studio; java is not on PATH)
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
cd android; .\gradlew.bat --console=plain :app:assembleDebug

# Deploy over Wi-Fi adb (device is usually at 192.168.1.163:5555)
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb connect 192.168.1.163:5555
& $adb -s 192.168.1.163:5555 install -r ..\build\app\outputs\flutter-apk\app-debug.apk

# Live debugging
& $adb -s 192.168.1.163:5555 logcat -s python.stderr:* AndroidRuntime:E   # Python + crashes
& $adb -s 192.168.1.163:5555 shell screencap -p /sdcard/s.png             # screenshot
& $adb -s 192.168.1.163:5555 pull /sdcard/s.png .
& $adb -s 192.168.1.163:5555 shell run-as com.example.appletv_remote cat files/pyatv.conf  # credentials
& $adb -s 192.168.1.163:5555 shell input tap <x> <y>                      # tap the UI remotely
```

## Architecture map

- `lib/state/remote_controller.dart` — single Provider. Owns: device list,
  status enum, pairing flow (multi-protocol PIN loop via prompt callback),
  auto-connect rules (last device → single paired device → list), optimistic
  + persisted power-state tracking, native event handling.
- `lib/services/atv_service.dart` — `MethodChannel('com.example.appletv_remote/pyatv')`
  wrapper; listens for `onEvent` (same channel, from Python via Kotlin's EventForwarder).
- `android/.../MainActivity.kt` — all Python calls on `Dispatchers.IO`;
  `WifiManager.MulticastLock` acquired only during scans.
- `android/app/src/main/python/atv_bridge.py` — synchronous functions on a
  persistent background asyncio loop (`_submit` = run_coroutine_threadsafe +
  block). Global state: `_atv`, `_connected_identifier`, `_power_state`,
  `_last_scan`, `_storage` (FileStorage at `files/pyatv.conf`), `_pairing*`.
- Events Python → Dart: `connected`, `connection_lost`, `reconnecting`,
  `disconnected`, `power_state`, `pairing_complete`, `error`.

## Rules for changes

- **Verify before declaring done:** `flutter analyze` clean + APK rebuilt +
  (for Dart-only changes) kernel symbol check + install + confirm on device
  via screenshot/logcat when a device is reachable.
- Keep pip pins and the Gradle plugin layout untouched unless replacing them
  deliberately (then re-run the full on-device verification).
- Every new user-facing string goes through the existing widgets' style; the
  app is single-screen dark mode (colors in `lib/theme.dart`).
- Never commit/push or run git mutations without an explicit ask.
