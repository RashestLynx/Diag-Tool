# Diag-Tool

Tells you **what's going on** with an electronic device, **how to fix it**, and
**what kind of device it is**. Comes in two forms:

- a **command-line tool** (`diag_tool.py`, this file), and
- a **cross-platform app** for iPhone/iPad, Android, Windows and macOS, in
  [`app/`](app/) - which adds a live PS5/Xbox controller tester.

Two companion scripts handle real connected devices: `phone_info.py`
(account recovery for a locked phone you own) and `device_export.py` (read
specs and pull data off an **unlocked, trusted** phone, camera or car - see
below).

Pure Python 3.9+, no dependencies. (Optional: `pip install psutil` for fuller
`scan` results on Windows/macOS.)

## Download

**Stable release — v1.0:**

- **Android (.apk):** https://github.com/RashestLynx/Diag-Tool/releases/download/v1.0/diag-tool-android.apk
- **Windows (.zip with .exe):** https://github.com/RashestLynx/Diag-Tool/releases/download/v1.0/diag-tool-windows.zip
- **macOS (.zip with .app):** https://github.com/RashestLynx/Diag-Tool/releases/download/v1.0/diag-tool-macos.zip

**Latest build** (rebuilt automatically on every push):

- **Android (.apk):** https://github.com/RashestLynx/Diag-Tool/releases/download/latest/diag-tool-android.apk
- **Windows (.zip with .exe):** https://github.com/RashestLynx/Diag-Tool/releases/download/latest/diag-tool-windows.zip
- **macOS (.zip with .app):** https://github.com/RashestLynx/Diag-Tool/releases/download/latest/diag-tool-macos.zip
- **All releases:** https://github.com/RashestLynx/Diag-Tool/releases

> The desktop/Android builds are unsigned, so your OS will show an
> "unknown developer" prompt the first time. iPhone needs an Apple-signed
> build (see [`app/README.md`](app/README.md)).

Clone the source:

```
git clone -b ccr-2c5184d8-u5e4pj https://github.com/RashestLynx/Diag-Tool.git
```

## Building the apps

GitHub Actions builds the Android APK and Windows/macOS apps on every push
(see [`.github/workflows/build.yml`](.github/workflows/build.yml)) and uploads
them as downloadable artifacts - open the run under the repo's **Actions** tab
and grab the one you need. To build locally, see [`app/README.md`](app/README.md).

## Commands

### `scan` - check the computer you're on

```
python diag_tool.py scan
```

Works out the device type (laptop, desktop, tablet, mini PC, virtual machine,
Raspberry Pi, ...) and make/model, then checks disk space, RAM, CPU load,
temperature, battery health and uptime. Each problem comes with fix steps.
Exits with code 1 if it finds a real problem.

### `diagnose` - describe a problem in plain words

```
python diag_tool.py diagnose "my phone won't charge and gets hot"
python diag_tool.py diagnose --device laptop --symptom slow --symptom overheating
python diag_tool.py diagnose          # asks you questions
```

Detects the device type and symptoms from your description and lists likely
causes, most likely first, each with step-by-step fixes. Safety warnings
(swollen batteries, water damage) are flagged.

Covered devices: phone, tablet, laptop, desktop, console, TV/monitor, router,
headphones/speakers, printer, smartwatch.
Covered symptoms: run `python diag_tool.py list`.

### `identify` - identify a device by IMEI or serial

```
python diag_tool.py identify --imei 490154203237518
python diag_tool.py identify --serial C39XY1234567
```

Validates the IMEI checksum, pulls out the TAC (the make/model code), and
points you at official lookup pages.

## Connected devices (`device_export.py`)

Reads and copies data from a device plugged into this computer, using the
official first-party protocols. It only works on a phone that is **unlocked**
and has approved this computer ("Trust This Computer" on iPhone, the USB
"Allow" prompt on Android) - that on-device approval is the consent step, so it
cannot and does not bypass any lock.

```
python device_export.py --check                 # what backends/devices are visible
python device_export.py --auto --save report.txt  # every read-only check on everything
python device_export.py --ios --specs           # full iPhone specs (needs pymobiledevice3)
python device_export.py --android --diagnose     # battery/storage/thermal/crashes (needs adb)
python device_export.py --ios --photos --out ./iphone_photos   # pull the camera roll
python device_export.py --ios --backup --out ./iphone_backup   # full iPhone backup
python device_export.py --camera --photos --out ./cam   # a camera over PTP (needs gphoto2)
python device_export.py --car --port /dev/ttyUSB0       # full car report (codes, readiness, live)
python device_export.py --car --live                    # live sensor data (RPM, temps, fuel trims...)
python device_export.py --car --monitors                # emissions readiness + check-engine state
python device_export.py --car --clear                   # clear codes / reset the light (asks first)
python device_export.py --apple-model iPhone14,5        # offline: model + chip, no device
```

Backends are optional and only needed for the matching target: `pip install
pymobiledevice3` (iPhone), Android SDK platform-tools (`adb`), `gphoto2`
(cameras), `pip install obd` + an ELM327 adapter (cars). It also reads specs,
identifies the chipset, flags counterfeit/fake-iPhone tells, and estimates the
manufacture date of legacy Apple serials.

## Also included

`phone_info.py` - account-recovery helper for locked Apple/Samsung phones
(checklists, backup locations, ownership sheet). `diag_tool.py` reuses its
IMEI/serial checks.

## Tests

```
python -m unittest discover -s tests
```
