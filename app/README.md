# Diag-Tool app

A cross-platform app that diagnoses problems with electronics. One Flutter
codebase builds native apps for **iPhone/iPad, Android, Windows and macOS**.

Three tabs:

- **Scan** - identifies the device it's running on (phone, tablet, laptop,
  desktop), including chip/CPU, GPU (where the OS exposes it), architecture,
  core count and - for Apple devices - model and release year, then checks
  storage, memory, battery health, temperature and uptime, with fixes. It reads
  only what the OS gives an app.
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
  - **Report timing:** reports/sec, average gap, jitter and worst gap for the
    controller->app link (not full press-to-screen lag, which needs a camera).
  - **Battery & touchpad (iOS/macOS only):** controller battery level/charge
    state, and a live DualSense touchpad finger view, via Apple's GameController
    framework. Hidden on platforms that don't provide them.
- **Recovery** - the account-recovery guidance from `phone_info.py`, in the UI:
  official first-party services (tappable links), step-by-step recovery
  checklists, where backups live, how to copy data off an unlocked device, and
  a builder for an ownership-proof sheet you can hand to Apple/Samsung support.
  This recovers the account you own - it does not remove anyone's lock.
- **Identify** - validate an IMEI (checksum + make/model TAC) or a serial
  number, with links to official lookup pages. Also: Apple product-type ->
  model + chip lookup, an Android Qualcomm platform-code -> Snapdragon lookup,
  and a manufacture-date estimate for legacy Apple serials.
- **Diagnose** also includes a **car trouble-code (OBD-II)** lookup: enter a
  check-engine code like P0420 for its meaning and fix. It has ~90 standardized
  generic codes in detail, and decodes the structure of any other valid code
  (system, generic vs manufacturer-specific, subsystem). Live reading from the
  car's OBD-II port is done by `device_export.py --car` with an ELM327 adapter.

The diagnosis advice (`assets/knowledge.json`), account-recovery guidance
(`assets/recovery.json`) and device reference data (`assets/reference.json` -
Apple model map, Qualcomm platforms, car codes) are all generated from the
project's Python code (`diag_tool.py`, `phone_info.py`, `device_export.py`) so
the app and the command line stay in sync:

```
cd ..            # repo root
python diag_tool.py export-json   # writes knowledge.json, recovery.json, reference.json
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

Controller battery level and DualSense touchpad position come from a native
platform channel using Apple's GameController framework, so they appear on
**iOS and macOS only** (`ios/Runner/ControllerInfoReader.swift` and the macOS
copy). Android doesn't expose a gamepad's battery or touchpad to apps, and on
Windows it would require raw HID parsing; on those platforms the card is hidden.
The Dart side (`lib/controller/controller_info.dart`) returns null when no
native handler is present, so nothing breaks.

> Note: the native Swift must be compiled on a Mac (Xcode) to take effect; it
> can't be built in a Linux CI runner or this project's Linux dev container.

## Tests

```
flutter test
```

Covers device/symptom detection, IMEI/serial checks and the scan analysis
rules (all pure Dart, no device needed).
