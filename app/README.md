# Diag-Tool app

A cross-platform app that diagnoses problems with electronics. One Flutter
codebase builds native apps for **iPhone/iPad, Android, Windows and macOS**.

Three tabs:

- **Scan** - identifies the device it's running on (phone, tablet, laptop,
  desktop) and checks storage, memory, battery health, temperature and uptime,
  with fixes for anything that needs attention.
- **Diagnose** - describe a problem in plain words, or pick a device and tap a
  symptom. Shows likely causes, most likely first, each with step-by-step
  fixes. Safety issues (swollen battery, liquid damage) are flagged.
- **Controller** - full test suite for a connected PS5 (DualSense) or Xbox
  controller. Labels switch to PlayStation or Xbox names automatically.
  - **Live view:** each analog stick on a pad, trigger travel bars, and every
    button lighting up as you press it.
  - **Stick drift test:** watches the sticks at rest and reports drift with the
    dead zone a game would need to hide it.
  - **Stick range test:** confirms each stick reaches the rim in every
    direction (a worn stick can't).
  - **Full input check:** a checklist that turns green once every button,
    trigger and stick direction has responded - finds anything dead.
  - **Vibration test:** buzzes the low motor, high motor or both.
  - **Live polling rate:** shows how many updates/sec the controller sends.
- **Identify** - validate an IMEI (checksum + make/model TAC) or a serial
  number, with links to official lookup pages.

The diagnosis advice lives in `assets/knowledge.json`, generated from the
project's Python CLI so the app and the command line stay in sync:

```
cd ..            # repo root
python diag_tool.py export-json
```

## Running and building

Needs the [Flutter SDK](https://docs.flutter.dev/get-started/install).

```
flutter pub get
flutter run                 # on a connected device, simulator or emulator

flutter build apk           # Android
flutter build ios           # iPhone/iPad  (needs a Mac + Xcode)
flutter build macos         # macOS        (needs a Mac + Xcode)
flutter build windows       # Windows      (needs Visual Studio)
```

iOS and macOS must be built on a Mac; Windows on a Windows machine with the
"Desktop development with C++" workload. Android can be built anywhere with the
Android SDK installed.

## How the scan gets its data

- **Everywhere:** `device_info_plus` and `battery_plus` for device identity,
  storage, memory and charge level.
- **Android:** a small platform channel (`MainActivity.kt`) adds battery
  temperature, health and charge-cycle count from the OS `BatteryManager`.
- **Windows:** a native Win32/WMI probe (`lib/scan/windows_native.dart`) for
  disk, RAM, uptime, chassis type and battery wear.
- **macOS/Linux:** `df` and (macOS) `pmset` for disk and thermal state. Under
  the macOS App Sandbox these may be unavailable; the scan degrades gracefully
  and still reports what the plugins provide.

iOS does not expose battery temperature or health to third-party apps, so the
scan there covers storage, memory and charge level.

## Controller testing

Uses the `gamepads` plugin, which reads controllers on Android, iOS, macOS,
Windows and Linux and normalizes PS5/Xbox inputs to one standard layout
(sticks -1..1, triggers 0..1, buttons). Connect the controller by USB or
Bluetooth first. The drift verdict is based on how far a stick wanders from
centre while at rest: under 5% is healthy, 5-10% is slight wear, and over 10%
is drift. The vibration test uses the plugin's rumble support (often only over
USB, not Bluetooth).

The plugin does not expose controller battery level or raw touchpad finger
position, so those are not shown.

## Tests

```
flutter test
```

Covers device/symptom detection, IMEI/serial checks and the scan analysis
rules (all pure Dart, no device needed).
