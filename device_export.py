#!/usr/bin/env python3
"""device_export.py - copy photos/data off an UNLOCKED, trusted phone.

This uses the official, first-party device protocols. It can only talk to a
phone that is:
  * powered on and UNLOCKED, and
  * has approved this computer ('Trust This Computer' on iPhone, or the USB
    'Allow' / file-transfer prompt on Android).
That approval is the on-device consent step - a locked phone cannot give it,
so this tool cannot and does not bypass any lock. It is for getting YOUR data
off once you're back in.

Backends (install the one you need):
  iPhone  -> pymobiledevice3   (pip install pymobiledevice3)
  Android -> adb / platform-tools (Android SDK platform-tools)

Examples:
    python device_export.py --check
    python device_export.py --ios --photos --out ./iphone_photos
    python device_export.py --ios --backup --out ./iphone_backup
    python device_export.py --android --photos --out ./android_photos
"""

from __future__ import annotations

import argparse
import contextlib
import datetime as _dt
import io
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

IOS_TOOL = "pymobiledevice3"
ANDROID_TOOL = "adb"


def _run(cmd: list[str], timeout: int = 600, cwd: str | None = None
         ) -> subprocess.CompletedProcess:
    """Run a command, capturing output; never raise on non-zero exit."""
    return subprocess.run(
        cmd, capture_output=True, text=True, timeout=timeout, check=False, cwd=cwd
    )


def tool_available(name: str) -> bool:
    return shutil.which(name) is not None


# ---------------------------------------------------------------------------
# Environment check
# ---------------------------------------------------------------------------
def check_environment() -> None:
    print("Backend tools")
    print("-" * 13)
    for label, tool, install in [
        ("iPhone  (pymobiledevice3)", IOS_TOOL, "pip install pymobiledevice3"),
        ("Android (adb)", ANDROID_TOOL, "install Android SDK platform-tools"),
    ]:
        have = tool_available(tool)
        mark = "found" if have else "MISSING"
        print(f"  {label:<28}: {mark}")
        if not have:
            print(f"      -> install with: {install}")

    print("\nVisible devices")
    print("-" * 15)
    if tool_available(IOS_TOOL):
        _show_ios_devices()
    if tool_available(ANDROID_TOOL):
        _show_android_devices()
    if not tool_available(IOS_TOOL) and not tool_available(ANDROID_TOOL):
        print("  (no backend tools installed yet)")


def _show_ios_devices() -> None:
    res = _run([IOS_TOOL, "usbmux", "list"], timeout=30)
    if res.returncode == 0 and res.stdout.strip():
        print("  iPhone: device(s) detected (see pymobiledevice3 output).")
    else:
        print("  iPhone: none detected (plug in, unlock, tap 'Trust').")


def _show_android_devices() -> None:
    res = _run([ANDROID_TOOL, "devices"], timeout=30)
    lines = [l for l in res.stdout.splitlines()[1:] if l.strip()]
    if not lines:
        print("  Android: none detected (plug in, unlock, allow file transfer).")
        return
    for line in lines:
        serial, _, state = line.partition("\t")
        state = state.strip()
        if state == "unauthorized":
            print(f"  Android {serial}: UNAUTHORIZED -> unlock phone and tap 'Allow'.")
        elif state == "device":
            print(f"  Android {serial}: ready.")
        else:
            print(f"  Android {serial}: {state}")


# ---------------------------------------------------------------------------
# Device identifiers (serial / IMEI) - needs an unlocked, trusted device
# ---------------------------------------------------------------------------
def ios_info() -> int:
    """Read SerialNumber / IMEI from a trusted, unlocked iPhone via lockdown."""
    if not tool_available(IOS_TOOL):
        print(f"ERROR: {IOS_TOOL} not installed (pip install pymobiledevice3).")
        return 2
    res = _run([IOS_TOOL, "lockdown", "info"], timeout=60)
    if res.returncode != 0:
        sys.stderr.write(res.stderr)
        print("Could not read device. Unlock the iPhone and tap 'Trust', then retry.")
        return res.returncode
    wanted = {
        "SerialNumber": "Serial number",
        "InternationalMobileEquipmentIdentity": "IMEI",
        "InternationalMobileEquipmentIdentity2": "IMEI 2",
        "DeviceName": "Device name",
        "ProductType": "Model (product type)",
        "ProductVersion": "iOS version",
    }
    print("iPhone identifiers")
    print("-" * 18)
    text = res.stdout
    for key, label in wanted.items():
        value = _grep_value(text, key)
        if value:
            print(f"  {label:<22}: {value}")
    print("  (Also printed on the SIM tray, the box, and the receipt.)")
    return 0


def android_info() -> int:
    """Read serial / IMEI from an unlocked, authorized Android phone via adb."""
    if not tool_available(ANDROID_TOOL):
        print(f"ERROR: {ANDROID_TOOL} not installed (Android platform-tools).")
        return 2
    print("Android identifiers")
    print("-" * 19)
    serial = _run([ANDROID_TOOL, "shell", "getprop", "ro.serialno"], timeout=30)
    if serial.returncode == 0 and serial.stdout.strip():
        print(f"  Serial number         : {serial.stdout.strip()}")
    else:
        print("  Serial number         : unavailable (unlock + authorize first)")
    # IMEI retrieval is restricted on newer Android; try the legacy service call.
    imei = _run(
        [ANDROID_TOOL, "shell", "service", "call", "iphonesubinfo", "1"], timeout=30
    )
    digits = _parse_service_call_imei(imei.stdout) if imei.returncode == 0 else ""
    # Only trust a result that is a valid 15-digit IMEI; never show partial junk.
    if len(digits) == 15 and _luhn_is_valid(digits):
        print(f"  IMEI                  : {digits}")
    else:
        print("  IMEI                  : unavailable via adb on this Android version")
        print("    -> dial *#06#, or see the SIM tray / box / receipt.")
    return 0


def _grep_value(text: str, key: str) -> str:
    """Pull a value for `key` from pymobiledevice3's key/value or plist-ish output."""
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith(key):
            # handles 'Key: value' and 'Key = value' style lines
            for sep in (":", "="):
                if sep in stripped:
                    return stripped.split(sep, 1)[1].strip().strip("\"',")
    return ""


def _luhn_is_valid(number: str) -> bool:
    """Luhn checksum used to validate a candidate IMEI before trusting it."""
    if not number.isdigit():
        return False
    total = 0
    for i, ch in enumerate(number[::-1]):
        d = int(ch)
        if i % 2 == 1:
            d *= 2
            if d > 9:
                d -= 9
        total += d
    return total % 10 == 0


def _parse_service_call_imei(raw: str) -> str:
    """Decode digits from the UTF-16 hex words 'service call iphonesubinfo' prints.

    Each 32-bit word printed as 8 hex digits holds two UTF-16 code units; the
    low 16 bits are the earlier character, so read (low half, high half) and
    interpret each half directly as the code point.
    """
    digits = ""
    for token in raw.split():
        if len(token) == 8 and all(c in "0123456789abcdefABCDEF" for c in token):
            for half in (token[4:8], token[0:4]):  # low half first
                try:
                    ch = chr(int(half, 16))
                except ValueError:
                    continue
                if ch.isdigit():
                    digits += ch
    return digits


# ---------------------------------------------------------------------------
# Hardware / chipset identification
# ---------------------------------------------------------------------------
# Apple product type -> (marketing name, SoC). A partial but useful map.
APPLE_MODELS = {
    "iPhone9,1": ("iPhone 7", "Apple A10 Fusion"),
    "iPhone9,3": ("iPhone 7", "Apple A10 Fusion"),
    "iPhone10,1": ("iPhone 8", "Apple A11 Bionic"),
    "iPhone10,4": ("iPhone 8", "Apple A11 Bionic"),
    "iPhone10,3": ("iPhone X", "Apple A11 Bionic"),
    "iPhone10,6": ("iPhone X", "Apple A11 Bionic"),
    "iPhone11,2": ("iPhone XS", "Apple A12 Bionic"),
    "iPhone11,8": ("iPhone XR", "Apple A12 Bionic"),
    "iPhone12,1": ("iPhone 11", "Apple A13 Bionic"),
    "iPhone12,3": ("iPhone 11 Pro", "Apple A13 Bionic"),
    "iPhone12,8": ("iPhone SE (2nd gen)", "Apple A13 Bionic"),
    "iPhone13,1": ("iPhone 12 mini", "Apple A14 Bionic"),
    "iPhone13,2": ("iPhone 12", "Apple A14 Bionic"),
    "iPhone13,3": ("iPhone 12 Pro", "Apple A14 Bionic"),
    "iPhone14,5": ("iPhone 13", "Apple A15 Bionic"),
    "iPhone14,2": ("iPhone 13 Pro", "Apple A15 Bionic"),
    "iPhone14,6": ("iPhone SE (3rd gen)", "Apple A15 Bionic"),
    "iPhone14,7": ("iPhone 14", "Apple A15 Bionic"),
    "iPhone15,2": ("iPhone 14 Pro", "Apple A16 Bionic"),
    "iPhone15,4": ("iPhone 15", "Apple A16 Bionic"),
    "iPhone16,1": ("iPhone 15 Pro", "Apple A17 Pro"),
}

# SoC platform codename (ro.board.platform) -> marketing name. Best-effort and
# approximate - one codename sometimes covers a small family of chips. Covers
# Qualcomm Snapdragon, MediaTek Dimensity/Helio, Samsung Exynos and Google
# Tensor. The variable keeps its old name for backward compatibility.
QCOM_PLATFORMS = {
    # Qualcomm Snapdragon
    "msm8937": "Snapdragon 430/435", "msm8953": "Snapdragon 625",
    "msm8998": "Snapdragon 835", "sdm660": "Snapdragon 660",
    "sdm670": "Snapdragon 670", "sdm710": "Snapdragon 710",
    "sdm845": "Snapdragon 845", "msmnile": "Snapdragon 855",
    "lito": "Snapdragon 765/768G", "bengal": "Snapdragon 662/680",
    "atoll": "Snapdragon 720G/730", "trinket": "Snapdragon 665",
    "kona": "Snapdragon 865", "lahaina": "Snapdragon 888",
    "sm7325": "Snapdragon 778G", "sm6375": "Snapdragon 695",
    "taro": "Snapdragon 8 Gen 1", "kalama": "Snapdragon 8 Gen 2",
    "pineapple": "Snapdragon 8 Gen 3",
    # MediaTek
    "mt6765": "MediaTek Helio P35/G35", "mt6768": "MediaTek Helio G85",
    "mt6769": "MediaTek Helio G80/G85", "mt6785": "MediaTek Helio G90T",
    "mt6833": "MediaTek Dimensity 700/800U", "mt6853": "MediaTek Dimensity 720/800",
    "mt6877": "MediaTek Dimensity 900/920", "mt6893": "MediaTek Dimensity 1200",
    "mt6895": "MediaTek Dimensity 8100", "mt6983": "MediaTek Dimensity 9000",
    "mt6985": "MediaTek Dimensity 9200",
    # Samsung Exynos
    "exynos850": "Samsung Exynos 850", "exynos9611": "Samsung Exynos 9611",
    "exynos9820": "Samsung Exynos 9820", "exynos990": "Samsung Exynos 990",
    "exynos2100": "Samsung Exynos 2100", "s5e8825": "Samsung Exynos 1280",
    "s5e9925": "Samsung Exynos 2200",
    # Google Tensor
    "gs101": "Google Tensor (G1)", "gs201": "Google Tensor G2",
    "zuma": "Google Tensor G3",
}


def apple_model_lookup(product_type: str) -> tuple[str, str] | None:
    return APPLE_MODELS.get(product_type.strip())


def ios_hardware() -> int:
    """Report iPhone model + Apple SoC from lockdown info."""
    if not tool_available(IOS_TOOL):
        print(f"ERROR: {IOS_TOOL} not installed (pip install pymobiledevice3).")
        return 2
    res = _run([IOS_TOOL, "lockdown", "info"], timeout=60)
    if res.returncode != 0:
        sys.stderr.write(res.stderr)
        print("Could not read device. Unlock the iPhone and tap 'Trust', then retry.")
        return res.returncode
    product_type = _grep_value(res.stdout, "ProductType")
    arch = _grep_value(res.stdout, "CPUArchitecture")
    hw_model = _grep_value(res.stdout, "HardwareModel")
    print("iPhone hardware")
    print("-" * 15)
    print(f"  Product type   : {product_type or 'unknown'}")
    named = apple_model_lookup(product_type)
    if named:
        print(f"  Model          : {named[0]}")
        print(f"  Chip (SoC)     : {named[1]}")
    else:
        print("  Model/chip     : not in local map (see ProductType above)")
    if arch:
        print(f"  CPU arch       : {arch}")
    if hw_model:
        print(f"  Hardware model : {hw_model}")
    return 0


def android_hardware() -> int:
    """Report Android manufacturer, model, and SoC via adb getprop."""
    if not tool_available(ANDROID_TOOL):
        print(f"ERROR: {ANDROID_TOOL} not installed (Android platform-tools).")
        return 2

    def prop(name: str) -> str:
        r = _run([ANDROID_TOOL, "shell", "getprop", name], timeout=30)
        return r.stdout.strip() if r.returncode == 0 else ""

    manufacturer = prop("ro.product.manufacturer")
    model = prop("ro.product.model")
    platform = prop("ro.board.platform")
    hardware = prop("ro.hardware")
    abi = prop("ro.product.cpu.abi")
    soc_mfr = prop("ro.soc.manufacturer")   # Android 12+
    soc_model = prop("ro.soc.model")        # Android 12+

    print("Android hardware")
    print("-" * 16)
    if not any([manufacturer, model, platform, soc_model]):
        print("  (no data - unlock the phone and authorize this computer)")
        return 1
    if manufacturer or model:
        print(f"  Device         : {manufacturer} {model}".strip())
    # Prefer the explicit SoC fields; fall back to platform codename mapping.
    soc = f"{soc_mfr} {soc_model}".strip()
    if not soc:
        soc = QCOM_PLATFORMS.get(platform, "")
    if soc:
        print(f"  Chip (SoC)     : {soc}")
    if platform:
        label = QCOM_PLATFORMS.get(platform)
        print(f"  Platform code  : {platform}" + (f" ({label})" if label else ""))
    if hardware:
        print(f"  ro.hardware    : {hardware}")
    if abi:
        print(f"  CPU ABI        : {abi}")
    return 0


# ---------------------------------------------------------------------------
# Manufacture-date estimate (legacy Apple serials only)
# ---------------------------------------------------------------------------
# Apple's 2010-2020 serials encoded the build date. Serials since ~2021 are
# randomized, so the date is NOT derivable from them - use checkcoverage.
_APPLE_YEAR_ALPHABET = "CDFGHJKLMNPQRSTVWXYZ"          # 2 chars per year from 2010
_APPLE_WEEK_ALPHABET = "123456789CDFGHJKLMNPQRTVWXY"   # 1..27 within a half-year


def apple_serial_date(serial: str) -> str:
    """Estimate manufacture date from a legacy (11/12-char) Apple serial.

    Returns a human string, or a note that the date can't be derived. This is
    an ESTIMATE and only works for pre-2021 serials; checkcoverage.apple.com
    is authoritative.
    """
    s = serial.strip().upper()
    if len(s) not in (11, 12):
        return "not derivable from this serial (new-format/randomized) - " \
               "use checkcoverage.apple.com"
    year_c = s[3]
    week_c = s[4]
    if year_c not in _APPLE_YEAR_ALPHABET or week_c not in _APPLE_WEEK_ALPHABET:
        return "not a legacy-format serial - use checkcoverage.apple.com"
    pos = _APPLE_YEAR_ALPHABET.index(year_c)
    year = 2010 + pos // 2
    half = pos % 2  # 0 = first half of year, 1 = second half
    week = _APPLE_WEEK_ALPHABET.index(week_c) + 1 + (26 if half else 0)
    week = min(week, 53)
    return (
        f"IF this is a pre-2021 device: ~{year}, around week {week}. "
        "NOTE: serials from ~2021 on are randomized and look identical, so this "
        "number is meaningless for newer phones - confirm at checkcoverage.apple.com."
    )


# ---------------------------------------------------------------------------
# Authenticity / counterfeit heuristics (NOT definitive)
# ---------------------------------------------------------------------------
_DISCLAIMER = (
    "These are heuristics, not proof. Confirm at the authoritative source: "
    "Apple -> checkcoverage.apple.com; Samsung/Android -> the carrier/maker "
    "IMEI check and the Settings 'About phone' screen."
)


def ios_authenticity() -> int:
    """Cross-protocol check: a genuine iPhone speaks Apple's lockdown protocol;
    a fake 'iPhone' that is really Android does not (but answers adb)."""
    print("iPhone authenticity signals")
    print("-" * 27)
    ios_ok = tool_available(IOS_TOOL)
    speaks_lockdown = False
    text = ""
    if ios_ok:
        res = _run([IOS_TOOL, "lockdown", "info"], timeout=60)
        speaks_lockdown = res.returncode == 0 and bool(res.stdout.strip())
        text = res.stdout

    # Does it answer Android's adb instead? Strong red flag for a "fake iPhone".
    answers_adb = False
    if tool_available(ANDROID_TOOL):
        adb = _run([ANDROID_TOOL, "devices"], timeout=30)
        answers_adb = any(
            l.strip() and not l.startswith("List")
            for l in adb.stdout.splitlines()
        )

    if speaks_lockdown:
        print("  [ok ] Responds to Apple's lockdown protocol (genuine iOS trait).")
        device_class = _grep_value(text, "DeviceClass")
        product = _grep_value(text, "ProductName") or _grep_value(text, "ProductType")
        serial = _grep_value(text, "SerialNumber")
        if device_class.lower() == "iphone":
            print(f"  [ok ] Device class reports as iPhone ({product}).")
        if serial:
            print(f"  [ i ] Serial {serial} - verify it at checkcoverage.apple.com.")
            print(f"        Manufacture date estimate: {apple_serial_date(serial)}")
    elif answers_adb:
        print("  [!! ] Does NOT speak Apple's protocol but DOES answer Android adb.")
        print("        A real iPhone never does this -> very likely a FAKE iPhone")
        print("        (an Android phone dressed up to look like iOS).")
    else:
        print("  [ ? ] No response. Ensure it's unlocked + trusted, or pymobiledevice3")
        print("        is installed, then retry. Can't assess authenticity yet.")
    print(f"\n  {_DISCLAIMER}")
    return 0


def android_authenticity() -> int:
    """Consistency checks that commonly expose counterfeit Android/Samsung phones."""
    if not tool_available(ANDROID_TOOL):
        print(f"ERROR: {ANDROID_TOOL} not installed (Android platform-tools).")
        return 2

    def prop(name: str) -> str:
        r = _run([ANDROID_TOOL, "shell", "getprop", name], timeout=30)
        return r.stdout.strip() if r.returncode == 0 else ""

    brand = prop("ro.product.brand")
    manufacturer = prop("ro.product.manufacturer")
    model = prop("ro.product.model")
    fingerprint = prop("ro.build.fingerprint")
    platform = prop("ro.board.platform")
    hardware = prop("ro.hardware")
    abi = prop("ro.product.cpu.abi")
    gms = prop("ro.com.google.gmsversion")

    if not (brand or model):
        print("No data - unlock the phone and authorize this computer, then retry.")
        return 1

    print("Android authenticity signals")
    print("-" * 28)
    print(f"  Claims to be   : {manufacturer} {model} (brand '{brand}')".strip())

    # 1) Emulator / spoof environment.
    if hardware.lower() in {"goldfish", "ranchu"} or prop("ro.kernel.qemu") == "1":
        print("  [!! ] Looks like an EMULATOR, not a physical phone.")

    # 2) Build fingerprint should mention the same brand/model.
    fp = fingerprint.lower()
    if fingerprint:
        if brand and brand.lower() in fp:
            print("  [ok ] Build fingerprint brand matches the claimed brand.")
        else:
            print("  [warn] Build fingerprint brand does NOT match claimed brand:")
            print(f"         {fingerprint}")
    else:
        print("  [warn] No build fingerprint reported (unusual for a genuine ROM).")

    # 3) Samsung/flagship claim but a MediaTek SoC is a classic clone tell.
    is_mediatek = platform.lower().startswith("mt") or "mt" in hardware.lower()[:2]
    claims_premium = any(
        k in model.lower() for k in ("galaxy s", "galaxy note", "galaxy z")
    )
    if claims_premium and is_mediatek:
        print("  [!! ] Claims a Samsung flagship but runs a MediaTek SoC "
              f"(platform '{platform}') - a very common counterfeit pattern.")
    elif platform:
        label = QCOM_PLATFORMS.get(platform)
        print(f"  [ i ] SoC platform: {platform}" + (f" ({label})" if label else ""))

    # 4) Google Play certification hint.
    if gms:
        print(f"  [ok ] Google Mobile Services present (gmsversion {gms}).")
    else:
        print("  [warn] No Google Mobile Services version - check Play Protect")
        print("         certification in the Play Store (Settings -> About).")

    # 5) 64-bit ABI is expected on any genuine modern phone.
    if abi and "arm64" not in abi and "x86_64" not in abi:
        print(f"  [warn] CPU ABI is '{abi}', not 64-bit - unusual for a modern phone.")

    print(f"\n  {_DISCLAIMER}")
    return 0


# ---------------------------------------------------------------------------
# This computer (laptop/desktop) - reads the machine the script runs on.
# No phone protocol needed; the OS reports its own specs and health.
# ---------------------------------------------------------------------------
def _linux_cpu_model() -> str:
    try:
        with open("/proc/cpuinfo", encoding="utf-8") as fh:
            for line in fh:
                if line.lower().startswith("model name"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor() or "unknown"


def _total_ram_bytes() -> int | None:
    # Works on Linux and macOS via sysconf; None elsewhere.
    try:
        return os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")
    except (ValueError, AttributeError, OSError):
        return None


def computer_specs() -> int:
    uname = platform.uname()
    print("Computer specifications")
    print("-" * 23)
    print(f"  Hostname       : {uname.node}")
    print(f"  OS             : {uname.system} {uname.release}")
    print(f"  OS version     : {uname.version}")
    print(f"  Architecture   : {uname.machine}")
    print(f"  Processor      : {_linux_cpu_model()}")
    print(f"  CPU cores      : {os.cpu_count()}")
    ram = _total_ram_bytes()
    if ram:
        print(f"  RAM            : {ram / 1024**3:.1f} GB")
    try:
        du = shutil.disk_usage("/")
        print(f"  Disk (/)       : {du.total / 1024**3:.0f} GB total, "
              f"{du.free / 1024**3:.0f} GB free")
    except OSError:
        pass
    print(f"  Python         : {platform.python_version()}")
    return 0


def computer_diagnose() -> int:
    print("Computer diagnostics")
    print("-" * 20)
    found = False

    # Disk space.
    try:
        du = shutil.disk_usage("/")
        used_pct = du.used / du.total * 100
        print(f"  Disk used      : {used_pct:.0f}% of / "
              f"({du.free / 1024**3:.0f} GB free)")
        if used_pct >= 90:
            found = True
            _emit_fix("storage_full")
    except OSError:
        pass

    # CPU load (Unix).
    try:
        load1, _, _ = os.getloadavg()
        cores = os.cpu_count() or 1
        print(f"  Load (1 min)   : {load1:.2f} over {cores} cores")
        if load1 > cores * 2:
            found = True
            print("      High sustained CPU load.")
            print("      Fix: find heavy processes (Task Manager / Activity")
            print("           Monitor / top), close or update them; reboot.")
    except (OSError, AttributeError):
        pass

    # Battery (Linux sysfs; other OSes need vendor tools).
    bat = Path("/sys/class/power_supply/BAT0")
    if bat.exists():
        try:
            cap = (bat / "capacity").read_text().strip()
            status = (bat / "status").read_text().strip()
            print(f"  Battery        : {cap}% ({status})")
        except OSError:
            pass
    else:
        print("  Battery        : not readable via stdlib on this OS")
        print("      (Windows: 'powercfg /batteryreport'; macOS: System")
        print("       Information -> Power; for health use the vendor tool.)")

    if not found:
        print("\n  No disk/load faults detected in readable data.")
    print("\n  Physical/vendor diagnostics:")
    print("      Windows: 'dxdiag', vendor support assistant (Dell/HP/Lenovo).")
    print("      macOS  : Apple Diagnostics (hold D / power on startup).")
    return 0


# ---------------------------------------------------------------------------
# Diagnostics: readable faults (battery / storage / thermal / crashes) + fixes
# ---------------------------------------------------------------------------
# Suggested fixes keyed by detected condition. These are general guidance.
FIXES = {
    "battery_worn": [
        "Battery is worn (high cycle count / reduced health).",
        "Fix: schedule a battery replacement (Apple/Samsung service or an",
        "     authorized shop). Meanwhile, enable battery-saver and avoid heat.",
    ],
    "battery_unhealthy": [
        "Battery health reports a fault (not 'good').",
        "Fix: stop charging if it reads OVERHEAT/OVER_VOLTAGE; have the battery",
        "     checked/replaced by a technician before further use.",
    ],
    "overheating": [
        "Device temperature is high.",
        "Fix: remove the case, stop charging, close heavy apps, let it cool.",
        "     Persistent heat with light use suggests a battery/board fault.",
    ],
    "storage_full": [
        "Storage is nearly full - this causes crashes, slowness, update fails.",
        "Fix: delete large videos/apps, clear caches, offload photos to cloud,",
        "     then reboot. Aim to keep >10% free.",
    ],
    "low_memory": [
        "Very little free RAM - apps may be getting killed.",
        "Fix: reboot, close background apps, remove memory-heavy apps.",
    ],
    "app_crashes": [
        "Recent app/system crashes were found in the crash log.",
        "Fix: update or reinstall the crashing app(s); if system processes",
        "     crash, install pending OS updates or back up and factory reset.",
    ],
    "hardware_note": [
        "Software cannot see physical faults (screen, cameras, speakers, mic,",
        "buttons, water damage). For those, run the maker's built-in hardware",
        "test and/or visit authorized service:",
        "  Samsung: dial *#0*# for the hardware test menu (screen, sensors...).",
        "  iPhone: Apple Support app / Genius Bar diagnostics.",
    ],
}


def _emit_fix(key: str) -> None:
    for line in FIXES[key]:
        print(f"      {line}")


def android_diagnose() -> int:
    """Read battery, thermal, storage, memory and recent crashes; suggest fixes."""
    if not tool_available(ANDROID_TOOL):
        print(f"ERROR: {ANDROID_TOOL} not installed (Android platform-tools).")
        return 2

    def shell(args: list[str]) -> str:
        r = _run([ANDROID_TOOL, "shell", *args], timeout=30)
        return r.stdout if r.returncode == 0 else ""

    print("Android diagnostics")
    print("-" * 19)
    found = False

    # Battery health + temperature.
    batt = shell(["dumpsys", "battery"])
    health_map = {
        "1": "unknown", "2": "good", "3": "overheat", "4": "dead",
        "5": "over-voltage", "6": "unspecified failure", "7": "cold",
    }
    health_val = temp_c = level = None
    for line in batt.splitlines():
        s = line.strip()
        if s.startswith("health:"):
            health_val = s.split(":", 1)[1].strip()
        elif s.startswith("temperature:"):
            try:
                temp_c = int(s.split(":", 1)[1]) / 10.0
            except ValueError:
                pass
        elif s.startswith("level:"):
            level = s.split(":", 1)[1].strip()
    if health_val:
        name = health_map.get(health_val, health_val)
        print(f"  Battery health : {name}  (level {level}%, "
              f"{temp_c if temp_c is not None else '?'} C)")
        if name not in ("good", "unknown"):
            found = True
            _emit_fix("battery_unhealthy")
        if temp_c is not None and temp_c >= 43:
            found = True
            _emit_fix("overheating")

    # Storage.
    df = shell(["df", "-h", "/data"])
    for line in df.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 5 and parts[4].endswith("%"):
            try:
                used = int(parts[4].rstrip("%"))
            except ValueError:
                continue
            print(f"  Storage used   : {used}% of /data")
            if used >= 90:
                found = True
                _emit_fix("storage_full")
            break

    # Memory.
    mem = shell(["cat", "/proc/meminfo"])
    total = avail = None
    for line in mem.splitlines():
        if line.startswith("MemTotal"):
            total = int(line.split()[1])
        elif line.startswith("MemAvailable"):
            avail = int(line.split()[1])
    if total and avail:
        pct = avail / total * 100
        print(f"  Free RAM       : {avail // 1024} MB ({pct:.0f}%)")
        if pct < 8:
            found = True
            _emit_fix("low_memory")

    # Recent crashes.
    crash = _run([ANDROID_TOOL, "logcat", "-b", "crash", "-d", "-t", "400"], timeout=30)
    fatals = [l for l in crash.stdout.splitlines() if "FATAL EXCEPTION" in l]
    if fatals:
        print(f"  Crash log      : {len(fatals)} recent fatal crash entr"
              f"{'y' if len(fatals) == 1 else 'ies'}")
        found = True
        _emit_fix("app_crashes")
    else:
        print("  Crash log      : no recent fatal crashes")

    if not found:
        print("\n  No software/battery faults detected in readable data.")
    print("\n  Physical hardware check:")
    _emit_fix("hardware_note")
    return 0


def ios_diagnose() -> int:
    """Read iPhone battery (cycle count) and recent crash reports; suggest fixes."""
    if not tool_available(IOS_TOOL):
        print(f"ERROR: {IOS_TOOL} not installed (pip install pymobiledevice3).")
        return 2

    print("iPhone diagnostics")
    print("-" * 18)
    found = False

    batt = _run([IOS_TOOL, "diagnostics", "battery"], timeout=60)
    if batt.returncode == 0 and batt.stdout.strip():
        cycles = _grep_value(batt.stdout, "CycleCount")
        if cycles:
            print(f"  Battery cycles : {cycles}")
            try:
                if int(cycles) >= 800:
                    found = True
                    _emit_fix("battery_worn")
            except ValueError:
                pass
        design = _grep_value(batt.stdout, "DesignCapacity")
        actual = _grep_value(batt.stdout, "AppleRawMaxCapacity") or \
            _grep_value(batt.stdout, "NominalChargeCapacity")
        try:
            if design and actual and int(actual) < 0.8 * int(design):
                found = True
                print("  Battery health : below ~80% of design capacity")
                _emit_fix("battery_worn")
        except ValueError:
            pass
    else:
        print("  Battery        : unreadable (unlock + trust, then retry)")

    crashes = _run([IOS_TOOL, "crash", "ls"], timeout=60)
    if crashes.returncode == 0:
        reports = [l for l in crashes.stdout.splitlines() if l.strip()
                   and not l.strip().endswith("/")]
        if reports:
            print(f"  Crash reports  : {len(reports)} on device")
            found = True
            _emit_fix("app_crashes")
        else:
            print("  Crash reports  : none found")

    if not found:
        print("\n  No software/battery faults detected in readable data.")
    print("\n  Physical hardware check:")
    _emit_fix("hardware_note")
    return 0


# ---------------------------------------------------------------------------
# Full specs
# ---------------------------------------------------------------------------
def ios_specs() -> int:
    """Dump a broad set of iPhone specs from lockdown info."""
    if not tool_available(IOS_TOOL):
        print(f"ERROR: {IOS_TOOL} not installed (pip install pymobiledevice3).")
        return 2
    res = _run([IOS_TOOL, "lockdown", "info"], timeout=60)
    if res.returncode != 0:
        sys.stderr.write(res.stderr)
        print("Could not read device. Unlock the iPhone and tap 'Trust', then retry.")
        return res.returncode
    text = res.stdout
    product_type = _grep_value(text, "ProductType")
    named = apple_model_lookup(product_type)

    print("iPhone specifications")
    print("-" * 21)
    if named:
        print(f"  Model              : {named[0]}")
        print(f"  Chip (SoC)         : {named[1]}")
    fields = [
        ("ProductType", "Product type"),
        ("ModelNumber", "Model number"),
        ("RegionInfo", "Region"),
        ("ProductVersion", "iOS version"),
        ("BuildVersion", "Build"),
        ("DeviceClass", "Device class"),
        ("CPUArchitecture", "CPU architecture"),
        ("HardwareModel", "Hardware model"),
        ("DeviceColor", "Color"),
        ("TotalDiskCapacity", "Total storage (bytes)"),
        ("SerialNumber", "Serial number"),
        ("InternationalMobileEquipmentIdentity", "IMEI"),
        ("WiFiAddress", "Wi-Fi MAC"),
        ("BluetoothAddress", "Bluetooth MAC"),
    ]
    for key, label in fields:
        value = _grep_value(text, key)
        if value:
            print(f"  {label:<18} : {value}")
    return 0


def android_specs() -> int:
    """Dump a broad set of Android specs via adb getprop and shell utilities."""
    if not tool_available(ANDROID_TOOL):
        print(f"ERROR: {ANDROID_TOOL} not installed (Android platform-tools).")
        return 2

    def prop(name: str) -> str:
        r = _run([ANDROID_TOOL, "shell", "getprop", name], timeout=30)
        return r.stdout.strip() if r.returncode == 0 else ""

    def shell(args: list[str]) -> str:
        r = _run([ANDROID_TOOL, "shell", *args], timeout=30)
        return r.stdout.strip() if r.returncode == 0 else ""

    manufacturer = prop("ro.product.manufacturer")
    model = prop("ro.product.model")
    if not (manufacturer or model):
        print("No data - unlock the phone and authorize this computer, then retry.")
        return 1

    soc = f"{prop('ro.soc.manufacturer')} {prop('ro.soc.model')}".strip()
    platform = prop("ro.board.platform")
    if not soc:
        soc = QCOM_PLATFORMS.get(platform, platform)

    # Memory and storage.
    mem_total = ""
    meminfo = shell(["cat", "/proc/meminfo"])
    for line in meminfo.splitlines():
        if line.startswith("MemTotal"):
            try:
                kb = int(line.split()[1])
                mem_total = f"{kb / 1024 / 1024:.1f} GB"
            except (IndexError, ValueError):
                pass
            break
    storage = ""
    df = shell(["df", "-h", "/data"])
    for line in df.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2:
            storage = f"{parts[1]} total (/data partition)"
            break

    screen = shell(["wm", "size"]).replace("Physical size:", "").strip()
    density = shell(["wm", "density"]).replace("Physical density:", "").strip()
    cores = ""
    cpuinfo = shell(["cat", "/proc/cpuinfo"])
    if cpuinfo:
        cores = str(cpuinfo.count("processor"))

    specs = [
        ("Device", f"{manufacturer} {model}".strip()),
        ("Chip (SoC)", soc),
        ("Platform code", platform),
        ("Android version", prop("ro.build.version.release")),
        ("API level (SDK)", prop("ro.build.version.sdk")),
        ("Build ID", prop("ro.build.display.id")),
        ("Build date", prop("ro.build.date")),
        ("Security patch", prop("ro.build.version.security_patch")),
        ("CPU ABI", prop("ro.product.cpu.abi")),
        ("CPU cores", cores),
        ("RAM", mem_total),
        ("Storage", storage),
        ("Screen", screen),
        ("Density (dpi)", density),
        ("Serial", prop("ro.serialno")),
    ]
    print("Android specifications")
    print("-" * 22)
    for label, value in specs:
        if value:
            print(f"  {label:<16} : {value}")
    return 0


# ---------------------------------------------------------------------------
# iPhone export
# ---------------------------------------------------------------------------
def ios_photos(out: Path) -> int:
    """Pull the camera roll (DCIM) over AFC. Requires a trusted, unlocked phone."""
    if not tool_available(IOS_TOOL):
        print(f"ERROR: {IOS_TOOL} not installed (pip install pymobiledevice3).")
        return 2
    out.mkdir(parents=True, exist_ok=True)
    print(f"Pulling iPhone DCIM -> {out}")
    print("  (Phone must be unlocked and 'trusted' for this to work.)")
    res = _run([IOS_TOOL, "afc", "pull", "DCIM", str(out)], timeout=3600)
    sys.stdout.write(res.stdout)
    if res.returncode != 0:
        sys.stderr.write(res.stderr)
        print("\n  If this failed: unlock the phone, re-tap 'Trust', and retry.")
    return res.returncode


def ios_backup(out: Path) -> int:
    """Full encrypted-capable backup via the official backup service."""
    if not tool_available(IOS_TOOL):
        print(f"ERROR: {IOS_TOOL} not installed (pip install pymobiledevice3).")
        return 2
    out.mkdir(parents=True, exist_ok=True)
    print(f"Creating full iPhone backup -> {out}")
    print("  (Phone must be unlocked and 'trusted'.)")
    res = _run([IOS_TOOL, "backup2", "backup", "--full", str(out)], timeout=7200)
    sys.stdout.write(res.stdout)
    if res.returncode != 0:
        sys.stderr.write(res.stderr)
    return res.returncode


# ---------------------------------------------------------------------------
# Android export
# ---------------------------------------------------------------------------
def android_photos(out: Path) -> int:
    """Pull /sdcard/DCIM over adb. Requires an unlocked, authorized phone."""
    if not tool_available(ANDROID_TOOL):
        print(f"ERROR: {ANDROID_TOOL} not installed (Android platform-tools).")
        return 2

    state = _run([ANDROID_TOOL, "devices"], timeout=30)
    rows = [l for l in state.stdout.splitlines()[1:] if l.strip()]
    if not rows:
        print("No Android device detected. Plug in, unlock, allow file transfer.")
        return 1
    if all("unauthorized" in r for r in rows):
        print("Device is UNAUTHORIZED. Unlock the phone and tap 'Allow' on the")
        print("USB debugging prompt, then run this again.")
        return 1

    out.mkdir(parents=True, exist_ok=True)
    print(f"Pulling Android /sdcard/DCIM -> {out}")
    res = _run([ANDROID_TOOL, "pull", "/sdcard/DCIM", str(out)], timeout=3600)
    sys.stdout.write(res.stdout)
    if res.returncode != 0:
        sys.stderr.write(res.stderr)
    return res.returncode


# ---------------------------------------------------------------------------
# Cameras (PTP/MTP via gphoto2) - a different protocol from phones.
# ---------------------------------------------------------------------------
CAMERA_TOOL = "gphoto2"
_CAMERA_INSTALL = "install gphoto2 (Linux: apt install gphoto2; macOS: brew install gphoto2)"


def camera_info() -> int:
    """Detect a connected camera and print its model/summary via gphoto2."""
    if not tool_available(CAMERA_TOOL):
        print(f"ERROR: {CAMERA_TOOL} not installed - {_CAMERA_INSTALL}.")
        return 2
    detect = _run([CAMERA_TOOL, "--auto-detect"], timeout=60)
    sys.stdout.write(detect.stdout)
    lines = [l for l in detect.stdout.splitlines()[2:] if l.strip()]
    if not lines:
        print("No camera detected. Connect it, power on, and set USB mode to")
        print("PTP / 'PC connection' (not 'charge only' or 'mass storage').")
        return 1
    summary = _run([CAMERA_TOOL, "--summary"], timeout=60)
    print("\nCamera summary")
    print("-" * 14)
    sys.stdout.write(summary.stdout)
    if summary.returncode != 0:
        sys.stderr.write(summary.stderr)
    return 0


def camera_photos(out: Path) -> int:
    """Download all photos from the camera into `out` via gphoto2."""
    if not tool_available(CAMERA_TOOL):
        print(f"ERROR: {CAMERA_TOOL} not installed - {_CAMERA_INSTALL}.")
        return 2
    out.mkdir(parents=True, exist_ok=True)
    print(f"Downloading all camera files -> {out}")
    # Run inside the destination so gphoto2 writes there.
    res = _run([CAMERA_TOOL, "--get-all-files", "--skip-existing"],
               timeout=7200, cwd=str(out))
    sys.stdout.write(res.stdout)
    if res.returncode != 0:
        sys.stderr.write(res.stderr)
        print("\n  If it failed: set the camera's USB mode to PTP and ensure no")
        print("  other program (Photos, gvfs) has grabbed the device.")
    return res.returncode


# ---------------------------------------------------------------------------
# Cars (OBD-II via an ELM327 adapter + python-OBD) - reads trouble codes.
# ---------------------------------------------------------------------------
# A small map of common generic trouble codes to plain-language fixes.
# Generic, standardized (SAE J2012) OBD-II diagnostic trouble codes. These have
# the same meaning on every make. Manufacturer-specific codes (most P1xxx, and
# many B/C/U codes) vary by brand and are intentionally NOT guessed here - the
# app/CLI tells you to look those up for your specific make/model.
DTC_FIXES = {
    # --- Fuel & air metering (P00xx-P01xx) ---
    "P0100": ("Mass/volume air flow (MAF) circuit",
              "Check the MAF connector/wiring; clean or replace the MAF sensor."),
    "P0101": ("MAF sensor range/performance",
              "Clean the MAF with MAF-safe spray; check the air filter and intake boot."),
    "P0102": ("MAF sensor circuit low input",
              "Inspect for intake leaks after the MAF; check wiring; replace the MAF."),
    "P0103": ("MAF sensor circuit high input",
              "Check the MAF wiring/connector; replace the MAF if out of range."),
    "P0106": ("MAP/baro sensor range/performance",
              "Check the MAP sensor and its vacuum line; replace if reading is off."),
    "P0107": ("MAP sensor circuit low input",
              "Inspect MAP wiring/connector; replace the MAP sensor."),
    "P0108": ("MAP sensor circuit high input",
              "Check the MAP vacuum line and wiring; replace the MAP sensor."),
    "P0111": ("Intake air temp (IAT) sensor range/performance",
              "Inspect/replace the IAT sensor; check the connector."),
    "P0112": ("IAT sensor circuit low input",
              "Check IAT wiring for a short; replace the sensor."),
    "P0113": ("IAT sensor circuit high input",
              "Inspect the IAT sensor and wiring; replace the sensor if faulty."),
    "P0116": ("Engine coolant temp (ECT) sensor range/performance",
              "Check coolant level; inspect/replace the ECT sensor."),
    "P0117": ("ECT sensor circuit low input",
              "Check ECT wiring for a short; replace the sensor."),
    "P0118": ("ECT sensor circuit high input",
              "Inspect the ECT connector/wiring; replace the sensor."),
    "P0121": ("Throttle/pedal position sensor A range/performance",
              "Clean the throttle body; check the TPS; inspect wiring."),
    "P0122": ("Throttle/pedal position sensor A low input",
              "Check TPS wiring/connector; replace the throttle position sensor."),
    "P0123": ("Throttle/pedal position sensor A high input",
              "Check TPS wiring for a short to power; replace the TPS."),
    "P0128": ("Coolant thermostat below regulating temperature",
              "Usually a stuck-open thermostat; replace it."),
    "P0130": ("O2 sensor circuit (bank 1, sensor 1)",
              "Inspect the upstream O2 sensor and wiring; replace the sensor."),
    "P0131": ("O2 sensor circuit low voltage (B1S1)",
              "Check for an exhaust leak and O2 wiring; replace the upstream O2 sensor."),
    "P0132": ("O2 sensor circuit high voltage (B1S1)",
              "Check for a rich condition; inspect O2 wiring; replace the sensor."),
    "P0133": ("O2 sensor slow response (B1S1)",
              "The upstream O2 sensor is aging; replace it."),
    "P0134": ("O2 sensor no activity (B1S1)",
              "Check O2 heater/wiring; replace the upstream O2 sensor."),
    "P0135": ("O2 sensor heater circuit (B1S1)",
              "Check the O2 heater fuse and wiring; usually replace the O2 sensor."),
    "P0136": ("O2 sensor circuit (bank 1, sensor 2)",
              "Inspect the downstream O2 sensor and wiring; replace the sensor."),
    "P0137": ("O2 sensor circuit low voltage (B1S2)",
              "Check for an exhaust leak; inspect wiring; replace the downstream O2."),
    "P0138": ("O2 sensor circuit high voltage (B1S2)",
              "Inspect O2 wiring; replace the downstream O2 sensor."),
    "P0141": ("O2 sensor heater circuit (B1S2)",
              "Check the downstream O2 heater circuit; usually replace the O2 sensor."),
    "P0150": ("O2 sensor circuit (bank 2, sensor 1)",
              "Bank 2 equivalent of P0130; inspect/replace the upstream O2 sensor."),
    "P0151": ("O2 sensor low voltage (B2S1)",
              "Check for an exhaust leak and wiring; replace the O2 sensor."),
    "P0155": ("O2 sensor heater circuit (B2S1)",
              "Check the O2 heater circuit; replace the bank-2 upstream O2 sensor."),
    "P0161": ("O2 sensor heater circuit (B2S2)",
              "Check the O2 heater circuit; replace the bank-2 downstream O2 sensor."),
    "P0171": ("System too lean (bank 1)",
              "Look for vacuum/intake leaks, a dirty MAF sensor, or weak fuel pump."),
    "P0172": ("System too rich (bank 1)",
              "Check for a leaking injector, high fuel pressure, or a dirty MAF/O2 sensor."),
    "P0173": ("Fuel trim malfunction (bank 2)",
              "Diagnose like lean/rich on bank 2: leaks, MAF, fuel pressure."),
    "P0174": ("System too lean (bank 2)",
              "Same as P0171 but bank 2: vacuum leaks, MAF, fuel delivery."),
    "P0175": ("System too rich (bank 2)",
              "Bank 2 equivalent of P0172: leaking injector, fuel pressure, MAF/O2."),
    # --- Injector circuits (P02xx) ---
    "P0201": ("Injector circuit - cylinder 1",
              "Check injector 1 wiring/connector and resistance; replace if open/shorted."),
    "P0202": ("Injector circuit - cylinder 2",
              "Check injector 2 wiring/resistance; replace if faulty."),
    "P0203": ("Injector circuit - cylinder 3",
              "Check injector 3 wiring/resistance; replace if faulty."),
    "P0204": ("Injector circuit - cylinder 4",
              "Check injector 4 wiring/resistance; replace if faulty."),
    "P0217": ("Engine over-temperature condition",
              "Stop and let it cool. Check coolant, thermostat, water pump, radiator/fans."),
    "P0219": ("Engine overspeed condition",
              "Avoid over-revving; check for a downshift/throttle fault if unexpected."),
    # --- Ignition / misfire (P03xx) ---
    "P0300": ("Random/multiple cylinder misfire",
              "Check spark plugs, coils, and fuel delivery; look for vacuum leaks."),
    "P0301": ("Cylinder 1 misfire",
              "Swap the coil/plug for cyl 1 with a neighbour; if the misfire moves, "
              "that part is bad. Also check that injector and compression."),
    "P0302": ("Cylinder 2 misfire",
              "Swap the coil/plug with a neighbour to isolate; check injector/compression."),
    "P0303": ("Cylinder 3 misfire",
              "Swap the coil/plug with a neighbour to isolate; check injector/compression."),
    "P0304": ("Cylinder 4 misfire",
              "Swap the coil/plug with a neighbour to isolate; check injector/compression."),
    "P0305": ("Cylinder 5 misfire",
              "Swap the coil/plug with a neighbour to isolate; check injector/compression."),
    "P0306": ("Cylinder 6 misfire",
              "Swap the coil/plug with a neighbour to isolate; check injector/compression."),
    "P0307": ("Cylinder 7 misfire",
              "Swap the coil/plug with a neighbour to isolate; check injector/compression."),
    "P0308": ("Cylinder 8 misfire",
              "Swap the coil/plug with a neighbour to isolate; check injector/compression."),
    "P0313": ("Misfire detected with low fuel",
              "Refuel - misfires can set when the tank is nearly empty."),
    "P0316": ("Misfire on startup (first 1000 revs)",
              "Check plugs/coils and fuel pressure at cold start."),
    "P0325": ("Knock sensor circuit (bank 1)",
              "Inspect the knock sensor connector/wiring; replace the sensor if open/shorted."),
    "P0330": ("Knock sensor 2 circuit (bank 2)",
              "Inspect the bank-2 knock sensor and wiring; replace if faulty."),
    "P0335": ("Crankshaft position sensor circuit",
              "Check the crank sensor and wiring; replace the sensor (common no-start)."),
    "P0336": ("Crankshaft position sensor range/performance",
              "Inspect the reluctor/tone ring and crank sensor gap; replace the sensor."),
    "P0340": ("Camshaft position sensor circuit",
              "Check the cam sensor and wiring; replace the sensor; verify timing."),
    "P0341": ("Camshaft position sensor range/performance",
              "Check cam/crank correlation and timing; inspect the cam sensor."),
    # --- Emissions / aux (P04xx) ---
    "P0401": ("EGR insufficient flow",
              "Clean the EGR valve and passages; check the EGR vacuum/electrical control."),
    "P0402": ("EGR excessive flow",
              "Check for a stuck-open EGR valve or a blocked DPFE/pressure sensor line."),
    "P0404": ("EGR circuit range/performance",
              "Inspect the EGR valve position sensor and wiring; clean/replace the valve."),
    "P0411": ("Secondary air injection - incorrect flow",
              "Check the air pump, hoses and check valves for the smog/air system."),
    "P0420": ("Catalyst efficiency below threshold (bank 1)",
              "Often a failing catalytic converter or an O2 sensor; verify the O2 first."),
    "P0430": ("Catalyst efficiency below threshold (bank 2)",
              "Bank 2 equivalent of P0420; verify the rear O2 sensor before the cat."),
    "P0440": ("EVAP system (general) fault",
              "Check the gas cap and EVAP hoses; a smoke test finds the leak."),
    "P0441": ("EVAP incorrect purge flow",
              "Inspect the purge valve and hoses; replace a stuck purge valve."),
    "P0442": ("Small EVAP system leak",
              "Reseat/replace the gas cap; inspect EVAP lines for small cracks."),
    "P0443": ("EVAP purge control valve circuit",
              "Check the purge valve wiring/connector; replace the purge valve."),
    "P0446": ("EVAP vent control circuit",
              "Inspect the vent valve (often clogged with debris) and its wiring."),
    "P0455": ("Large EVAP system leak",
              "Check the gas cap first (reseat/replace), then EVAP hoses and valves."),
    "P0456": ("Very small EVAP leak",
              "Usually the gas cap seal or a tiny hose crack; smoke-test the EVAP system."),
    "P0457": ("EVAP leak - loose fuel cap",
              "Tighten or replace the fuel cap, then clear the code."),
    # --- Speed / idle / PCM (P05xx-P06xx) ---
    "P0500": ("Vehicle speed sensor",
              "Check the VSS and wiring; replace the speed sensor."),
    "P0505": ("Idle air control system",
              "Clean the throttle body and idle air control valve; check for vacuum leaks."),
    "P0506": ("Idle speed lower than expected",
              "Check for a dirty throttle body, vacuum leak, or IAC fault."),
    "P0507": ("Idle speed higher than expected",
              "Look for a vacuum leak or a stuck-open IAC/throttle plate."),
    "P0520": ("Oil pressure sensor/switch circuit",
              "Check oil level first; inspect the oil pressure sensor and wiring."),
    "P0562": ("System voltage low",
              "Test the battery and alternator; a weak battery or charging fault is common."),
    "P0563": ("System voltage high",
              "Check the alternator/voltage regulator for overcharging."),
    "P0601": ("Internal control module memory checksum error",
              "A PCM/ECM fault; reflash or replace the module (shop/dealer)."),
    "P0606": ("PCM processor fault",
              "Check module power/grounds; the ECM/PCM may need replacement."),
    # --- Transmission & comms (P07xx, U0xxx) ---
    "P0700": ("Transmission control system (malfunction)",
              "A transmission code is stored; read the TCM sub-codes with a capable scanner."),
    "P0705": ("Transmission range sensor circuit",
              "Check/adjust the neutral safety/range switch; inspect its wiring."),
    "P0715": ("Input/turbine speed sensor circuit",
              "Inspect the transmission input speed sensor and wiring."),
    "P0720": ("Output speed sensor circuit",
              "Inspect the transmission output speed sensor and wiring."),
    "P0730": ("Incorrect gear ratio",
              "Check transmission fluid level/condition; a shift/clutch fault - see a shop."),
    "P0740": ("Torque converter clutch circuit",
              "Check the TCC solenoid and fluid; a converter/solenoid fault."),
    "P0750": ("Shift solenoid A",
              "Inspect the shift solenoid and wiring; check fluid condition."),
    "U0100": ("Lost communication with ECM/PCM",
              "Check ECU power/ground and the CAN bus wiring/connectors."),
    "U0101": ("Lost communication with TCM",
              "Check the transmission module's power, grounds and CAN wiring."),
    "U0121": ("Lost communication with ABS module",
              "Check the ABS module connector, power/ground and CAN bus."),
}

# Structural decoding so ANY well-formed code can be explained, even when it
# isn't in DTC_FIXES. First letter = system; the digit after it says whether
# the definition is generic (SAE, same on every car) or manufacturer-specific;
# for P-codes the next digit names the subsystem.
DTC_SYSTEMS = {"P": "Powertrain (engine/transmission)", "C": "Chassis",
               "B": "Body", "U": "Network / communication"}
DTC_P_SUBSYSTEMS = {
    "0": "fuel/air metering & auxiliary emissions",
    "1": "fuel & air metering",
    "2": "fuel & air metering (injector circuit)",
    "3": "ignition system or misfire",
    "4": "auxiliary emission controls",
    "5": "vehicle speed control & idle control",
    "6": "computer output circuit",
    "7": "transmission",
    "8": "transmission",
    "9": "transmission / drivetrain",
}


def describe_dtc(code: str) -> str:
    """Explain the structure of any well-formed OBD-II code (e.g. P1234)."""
    c = code.strip().upper()
    if len(c) != 5 or c[0] not in DTC_SYSTEMS or not c[1:].isdigit():
        return "Not a standard 5-character OBD-II code (like P0420)."
    parts = [DTC_SYSTEMS[c[0]]]
    parts.append("manufacturer-specific" if c[1] == "1" else "generic (same on every make)")
    if c[0] == "P" and c[2] in DTC_P_SUBSYSTEMS:
        parts.append(DTC_P_SUBSYSTEMS[c[2]])
    return " / ".join(parts)


# Release year per Apple model name (the model's launch year - an honest
# "how old is this product" signal, since true manufacture dates aren't
# available to apps and new serials are randomized).
APPLE_RELEASE_YEARS = {
    "iPhone 7": 2016, "iPhone 8": 2017, "iPhone X": 2017, "iPhone XS": 2018,
    "iPhone XR": 2018, "iPhone 11": 2019, "iPhone 11 Pro": 2019,
    "iPhone SE (2nd gen)": 2020, "iPhone 12 mini": 2020, "iPhone 12": 2020,
    "iPhone 12 Pro": 2020, "iPhone 13": 2021, "iPhone 13 Pro": 2021,
    "iPhone SE (3rd gen)": 2022, "iPhone 14": 2022, "iPhone 14 Pro": 2022,
    "iPhone 15": 2023, "iPhone 15 Pro": 2023,
}


def reference_as_dict() -> dict:
    """Device-free reference data for the app (model maps, car codes, serial rules)."""
    return {
        "apple_models": {
            ptype: {"model": name, "soc": soc,
                    "year": APPLE_RELEASE_YEARS.get(name)}
            for ptype, (name, soc) in APPLE_MODELS.items()
        },
        "qcom_platforms": QCOM_PLATFORMS,
        "dtc_fixes": {
            code: {"meaning": meaning, "fix": fix}
            for code, (meaning, fix) in DTC_FIXES.items()
        },
        "apple_year_alphabet": _APPLE_YEAR_ALPHABET,
        "apple_week_alphabet": _APPLE_WEEK_ALPHABET,
        "dtc_systems": DTC_SYSTEMS,
        "dtc_p_subsystems": DTC_P_SUBSYSTEMS,
    }


def _decode_dtc_prefix(code: str) -> str:
    systems = {"P": "Powertrain", "C": "Chassis", "B": "Body", "U": "Network"}
    if not code:
        return ""
    return systems.get(code[0].upper(), "Unknown system")


# Live PIDs worth showing, in a sensible dashboard order. Each is a python-OBD
# command name; missing ones on a given car are skipped automatically.
_LIVE_PIDS = [
    "RPM", "SPEED", "ENGINE_LOAD", "ABSOLUTE_LOAD", "COOLANT_TEMP",
    "INTAKE_TEMP", "OIL_TEMP", "THROTTLE_POS", "RELATIVE_THROTTLE_POS",
    "ACCELERATOR_POS_D", "ACCELERATOR_POS_E", "MAF", "INTAKE_PRESSURE",
    "BAROMETRIC_PRESSURE", "TIMING_ADVANCE", "SHORT_FUEL_TRIM_1",
    "LONG_FUEL_TRIM_1", "SHORT_FUEL_TRIM_2", "LONG_FUEL_TRIM_2",
    "FUEL_PRESSURE", "FUEL_RAIL_PRESSURE_ABS", "FUEL_LEVEL", "FUEL_RATE",
    "COMMANDED_EGR", "EGR_ERROR", "EVAP_VAPOR_PRESSURE", "O2_B1S1", "O2_B1S2",
    "O2_B2S1", "O2_B2S2", "COMMANDED_EQUIV_RATIO", "CATALYST_TEMP_B1S1",
    "CATALYST_TEMP_B2S1", "CONTROL_MODULE_VOLTAGE", "RUN_TIME",
    "DISTANCE_W_MIL", "DISTANCE_SINCE_DTC_CLEAR", "WARMUPS_SINCE_DTC_CLEAR",
    "AMBIANT_AIR_TEMP",
]

# Mode 06 on-board monitor commands for misfires (per-cylinder where supported).
_MISFIRE_MIDS = ["MONITOR_MISFIRE_GENERAL"] + [
    f"MONITOR_MISFIRE_CYLINDER_{n}" for n in range(1, 11)
]


def analyze_obd(readings: dict, dtcs: list) -> list:
    """Correlate live sensor readings and stored DTCs into likely root causes.

    `readings` maps PID name -> numeric value (fuel trims in %, temps in C,
    volts in V). `dtcs` is a list of code strings. Returns a list of dicts:
    {severity, title, cause, suggest}. Pure/generic guidance, not a verdict.
    """
    out = []

    def num(name):
        v = readings.get(name)
        try:
            return float(v)
        except (TypeError, ValueError):
            return None

    codes = {c.upper() for c in dtcs}

    # --- Fuel trims: the single most useful live diagnostic ---
    stft1, ltft1 = num("SHORT_FUEL_TRIM_1"), num("LONG_FUEL_TRIM_1")
    total1 = sum(v for v in (stft1, ltft1) if v is not None) if (stft1 is not None or ltft1 is not None) else None
    if total1 is not None and total1 >= 10:
        out.append({
            "severity": "problem", "title": f"Running lean (bank 1, trims +{total1:.0f}%)",
            "cause": "The engine is adding fuel to compensate - usually an unmetered "
                     "air (vacuum/intake) leak, a dirty MAF sensor, a weak fuel pump/"
                     "filter, or an exhaust leak ahead of the O2 sensor.",
            "suggest": "Smoke-test the intake for leaks, clean the MAF, and check fuel "
                       "pressure. Lean + a misfire points strongly at a vacuum leak."})
    elif total1 is not None and total1 <= -10:
        out.append({
            "severity": "problem", "title": f"Running rich (bank 1, trims {total1:.0f}%)",
            "cause": "The engine is pulling fuel out - often a leaking injector, high "
                     "fuel pressure, a stuck O2 sensor, or a very dirty air filter.",
            "suggest": "Check fuel pressure/regulator and injector balance; inspect the "
                       "air filter; verify the upstream O2 sensor switches."})

    # --- Temperatures ---
    coolant = num("COOLANT_TEMP")
    if coolant is not None and coolant >= 105:
        out.append({
            "severity": "problem", "title": f"Coolant hot ({coolant:.0f} C)",
            "cause": "Overheating - low coolant, a stuck thermostat, a weak water pump, "
                     "a failing cooling fan, or a blocked radiator.",
            "suggest": "Stop and let it cool; check coolant level and that the fan runs."})
    elif coolant is not None and 0 < coolant < 60 and (num("RUN_TIME") or 0) > 300:
        out.append({
            "severity": "warn", "title": f"Engine not reaching temperature ({coolant:.0f} C)",
            "cause": "After warming up this is usually a thermostat stuck open "
                     "(matches code P0128).",
            "suggest": "Replace the thermostat; it also hurts fuel economy and heater output."})

    # --- Charging / battery ---
    volts = num("CONTROL_MODULE_VOLTAGE")
    if volts is not None and 0 < volts < 13.0 and (num("RPM") or 0) > 500:
        out.append({
            "severity": "warn", "title": f"Low charging voltage ({volts:.1f} V running)",
            "cause": "With the engine running this should be ~13.5-14.7 V. Low means a "
                     "weak alternator, a bad voltage regulator, or a loose belt.",
            "suggest": "Load-test the alternator and battery; check the drive belt."})

    # --- Misfire codes -> specific cylinder guidance ---
    for n in range(1, 11):
        if f"P030{n}" in codes or f"P03{n:02d}" in codes:
            out.append({
                "severity": "problem", "title": f"Misfire on cylinder {n}",
                "cause": "That cylinder isn't firing cleanly - coil, spark plug, "
                         "injector, or low compression on cylinder " + str(n) + ".",
                "suggest": f"Swap the coil/plug for cyl {n} with a neighbour; if the "
                           "misfire follows the part, replace it. Else check the "
                           "injector and do a compression test."})
    if "P0300" in codes:
        out.append({
            "severity": "problem", "title": "Random/multiple-cylinder misfire",
            "cause": "Affects several cylinders - a vacuum leak, weak fuel pressure, "
                     "bad fuel, or worn plugs across the board.",
            "suggest": "Check fuel pressure and for vacuum leaks before parts-swapping; "
                       "high lean fuel trims here confirm a vacuum leak."})

    # --- Catalyst ---
    if "P0420" in codes or "P0430" in codes:
        out.append({
            "severity": "warn", "title": "Catalytic converter efficiency low",
            "cause": "Either a worn catalytic converter or a lazy downstream O2 sensor "
                     "(the cheaper thing to rule out first).",
            "suggest": "Verify the rear O2 sensor switches correctly before buying a cat."})

    # Any stored code we have a detailed fix for and haven't covered above.
    for c in sorted(codes):
        if c in DTC_FIXES and not any(c[-1] in o["title"] for o in out):
            meaning, fix = DTC_FIXES[c]
            out.append({"severity": "info", "title": f"{c}: {meaning}",
                        "cause": "Stored trouble code.", "suggest": fix})

    if not out:
        out.append({"severity": "info", "title": "No obvious fault in the readable data",
                    "cause": "Live sensors and stored codes look within normal range.",
                    "suggest": "If a symptom persists, capture a drive with --watch --log "
                               "and graph it to catch intermittent events."})
    return out


def _obd_connect(port: str | None):
    """Import python-OBD and open a connection. Returns (obd, conn) or (None, None)."""
    try:
        import obd  # python-OBD; talks to an ELM327 adapter
    except ImportError:
        print("ERROR: python-OBD not installed (pip install obd).")
        print("You also need an ELM327 OBD-II adapter plugged into the car's")
        print("OBD-II port (usually under the dashboard) and the ignition on.")
        return None, None
    conn = obd.OBD(port) if port else obd.OBD()
    if not conn.is_connected():
        print("Could not connect to the vehicle. Check that:")
        print("  - the ELM327 adapter is seated in the OBD-II port,")
        print("  - the ignition is ON (engine running for live data),")
        print("  - the right serial port is given via --port (e.g. /dev/ttyUSB0,")
        print("    COM3, or a Bluetooth rfcomm device).")
        return obd, None
    return obd, conn


def _print_dtcs(obd, conn) -> list:
    """Print stored DTCs with meanings/fixes. Returns the list of code strings."""
    codes = conn.query(obd.commands.GET_DTC).value or []
    if not codes:
        print("  Trouble codes  : none stored.")
        return []
    print(f"  Trouble codes  : {len(codes)} stored")
    for code, desc in codes:
        print(f"\n  {code}  [{describe_dtc(code)}]")
        if desc:
            print(f"      Meaning: {desc}")
        if code in DTC_FIXES:
            meaning, fix = DTC_FIXES[code]
            print(f"      ({meaning})")
            print(f"      Fix: {fix}")
        else:
            print("      Fix: look up this exact code for your make/model; a")
            print("           scan-tool live-data check pinpoints the part.")
    return [code for code, _ in codes]


def _print_status(obd, conn) -> None:
    """Readiness monitors + MIL state (the emissions 'I/M readiness' picture)."""
    resp = conn.query(obd.commands.STATUS)
    s = resp.value
    if s is None:
        print("  Readiness      : not reported by this vehicle.")
        return
    print(f"  Check-engine   : {'ON' if s.MIL else 'off'}  "
          f"(ECU reports {s.DTC_count} code(s))")
    print("  Readiness monitors (must be 'ready' to pass an emissions test):")
    for name in dir(s):
        test = getattr(s, name)
        # python-OBD exposes each monitor as a Test with .available/.complete.
        if hasattr(test, "available") and hasattr(test, "complete"):
            if not test.available:
                continue
            state = "ready" if test.complete else "NOT ready"
            print(f"      {name:<28}: {state}")


def car_report(port: str | None, live: bool, monitors: bool, freeze: bool,
               all_sensors: bool = False) -> int:
    """Full read: VIN, DTCs, (optionally) readiness, freeze-frame, live data,
    and a root-cause analysis of what the readings + codes point to."""
    obd, conn = _obd_connect(port)
    if conn is None:
        return 1 if obd is not None else 2

    print("Car OBD-II report")
    print("-" * 17)
    vin = conn.query(obd.commands.VIN)
    if vin.value:
        print(f"  VIN            : {vin.value}")
    dtcs = _print_dtcs(obd, conn)

    if monitors:
        print("\nReadiness / monitors")
        print("-" * 20)
        _print_status(obd, conn)
        print("\n  Misfire monitors (Mode 06):")
        _print_misfires(obd, conn)

    if freeze:
        print("\nFreeze frame (conditions when the code set)")
        print("-" * 43)
        fz = conn.query(obd.commands.GET_FREEZE_DTC)
        if fz.value:
            print(f"  Triggered by   : {fz.value}")
        else:
            print("  No freeze-frame code stored.")

    readings = {}
    if live or all_sensors:
        # `--all` reads every PID the ECU reports supporting; otherwise the
        # curated headline set.
        if all_sensors:
            cmds = [(c.name, c) for c in sorted(conn.supported_commands, key=lambda c: c.name)
                    if getattr(c, "mode", None) == 1]
            print(f"\nAll live sensors ({len(cmds)} supported)")
        else:
            cmds = [(n, getattr(obd.commands, n, None)) for n in _LIVE_PIDS]
            print("\nLive data")
        print("-" * 9)
        shown = 0
        for name, cmd in cmds:
            if cmd is None or not conn.supports(cmd):
                continue
            r = conn.query(cmd)
            if r.is_null():
                continue
            print(f"  {name:<26}: {r.value}")
            readings[name] = getattr(r.value, "magnitude", r.value)
            shown += 1
        if shown == 0:
            print("  (no live PIDs available - is the engine running?)")

    print("\nWhat's likely going on")
    print("-" * 22)
    for f in analyze_obd(readings, dtcs):
        tag = {"problem": "[!!]", "warn": "[warn]", "info": "[ i]"}.get(f["severity"], "[ i]")
        print(f"\n  {tag} {f['title']}")
        print(f"      Cause : {f['cause']}")
        print(f"      Check : {f['suggest']}")

    conn.close()
    print("\n  Note: this points to likely causes from the readable data - confirm")
    print("  with live tests before replacing parts.")
    return 0


def _print_misfires(obd, conn) -> None:
    """Mode 06 misfire monitor results, per cylinder where the car supports it."""
    any_shown = False
    for name in _MISFIRE_MIDS:
        cmd = getattr(obd.commands, name, None)
        if cmd is None or not conn.supports(cmd):
            continue
        r = conn.query(cmd)
        if r.is_null():
            continue
        label = name.replace("MONITOR_MISFIRE_", "").replace("_", " ").title()
        # A MonitorTest has .value, .min, .max and .passed on recent python-OBD.
        tests = r.value if isinstance(r.value, list) else [r.value]
        for t in tests:
            val = getattr(t, "value", t)
            passed = getattr(t, "passed", None)
            mark = "" if passed is None else ("  [ok]" if passed else "  [FAIL]")
            print(f"      {label:<14}: {val}{mark}")
            any_shown = True
    if not any_shown:
        print("      (no Mode 06 misfire data - many cars expose this only via")
        print("       manufacturer-specific monitors; check P030x codes instead.)")


def car_watch(port: str | None, interval: float, duration: float,
              log_path: str | None) -> int:
    """Stream live data on a loop, printing a refreshing snapshot and optionally
    logging every sample to a CSV for later graphing."""
    obd, conn = _obd_connect(port)
    if conn is None:
        return 1 if obd is not None else 2

    cmds = []
    for name in _LIVE_PIDS:
        cmd = getattr(obd.commands, name, None)
        if cmd is not None and conn.supports(cmd):
            cmds.append((name, cmd))
    if not cmds:
        print("No live PIDs supported/returning data. Is the engine running?")
        conn.close()
        return 1

    writer = fh = None
    if log_path:
        fh = open(log_path, "w", newline="", encoding="utf-8")
        import csv
        writer = csv.writer(fh)
        writer.writerow(["elapsed_s"] + [n for n, _ in cmds])

    print(f"Streaming {len(cmds)} PIDs every {interval}s for {duration}s "
          f"(Ctrl-C to stop){' -> ' + log_path if log_path else ''}")
    import time as _time
    start = _time.time()
    try:
        while _time.time() - start < duration:
            elapsed = round(_time.time() - start, 2)
            row = [elapsed]
            for name, cmd in cmds:
                r = conn.query(cmd)
                v = None if r.is_null() else getattr(r.value, "magnitude", r.value)
                row.append(v)
            if writer:
                writer.writerow(row)
            # Compact rolling readout of a few headline values.
            head = ", ".join(
                f"{n}={row[i + 1]}" for i, (n, _) in enumerate(cmds)
                if n in ("RPM", "SPEED", "COOLANT_TEMP", "TIMING_ADVANCE",
                         "SHORT_FUEL_TRIM_1", "ENGINE_LOAD")
            )
            print(f"  t={elapsed:>6}s  {head}")
            _time.sleep(interval)
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        if fh:
            fh.close()
            print(f"Logged to {log_path}. Graph it with: "
                  f"python device_export.py --graph {log_path}")
        conn.close()
    return 0


# ---------------------------------------------------------------------------
# Offline: turn a logged OBD CSV into a self-contained HTML chart dashboard.
# Pure stdlib + inline SVG, so it needs no plotting library and no car.
# ---------------------------------------------------------------------------
def _svg_line_chart(label: str, xs: list[float], ys: list[float],
                    width: int = 680, height: int = 160) -> str:
    pad = 32
    pts = [(x, y) for x, y in zip(xs, ys) if y is not None]
    if len(pts) < 2:
        return f"<div class='chart'><h3>{label}</h3><p>no data</p></div>"
    xmin, xmax = pts[0][0], pts[-1][0]
    ymin = min(p[1] for p in pts)
    ymax = max(p[1] for p in pts)
    xspan = (xmax - xmin) or 1
    yspan = (ymax - ymin) or 1

    def sx(x: float) -> float:
        return pad + (x - xmin) / xspan * (width - 2 * pad)

    def sy(y: float) -> float:
        return height - pad - (y - ymin) / yspan * (height - 2 * pad)

    poly = " ".join(f"{sx(x):.1f},{sy(y):.1f}" for x, y in pts)
    return (
        f"<div class='chart'><h3>{label}</h3>"
        f"<svg viewBox='0 0 {width} {height}' preserveAspectRatio='none'>"
        f"<polyline fill='none' stroke='#2e7d6b' stroke-width='2' points='{poly}'/>"
        f"<text x='{pad}' y='12' class='lbl'>{ymax:g}</text>"
        f"<text x='{pad}' y='{height - pad + 12}' class='lbl'>{ymin:g}</text>"
        f"<text x='{width - pad}' y='{height - 6}' class='lbl' text-anchor='end'>"
        f"{xmax:g}s</text></svg></div>"
    )


def render_obd_html(headers: list[str], rows: list[list]) -> str:
    """Build a standalone HTML dashboard (one line chart per numeric column)."""
    xs = [float(r[0]) for r in rows] if rows else []
    charts = []
    for ci in range(1, len(headers)):
        ys: list[float | None] = []
        numeric = False
        for r in rows:
            try:
                ys.append(float(r[ci]))
                numeric = True
            except (ValueError, TypeError, IndexError):
                ys.append(None)
        if numeric:
            charts.append(_svg_line_chart(headers[ci], xs, ys))
    body = "\n".join(charts) if charts else "<p>No numeric data columns found.</p>"
    return (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width, initial-scale=1'>"
        "<title>OBD-II log</title><style>"
        "body{font-family:system-ui,sans-serif;margin:16px;background:#faf9f7;color:#1a1a1a}"
        "h1{font-size:20px}.chart{background:#fff;border:1px solid #e3e3e3;border-radius:12px;"
        "padding:10px 14px;margin:12px 0}.chart h3{margin:0 0 6px;font-size:14px}"
        ".chart svg{width:100%;height:160px}.lbl{fill:#888;font-size:10px}"
        "@media(prefers-color-scheme:dark){body{background:#1a1a1a;color:#eee}"
        ".chart{background:#262626;border-color:#333}}"
        "</style></head><body>"
        f"<h1>OBD-II session - {len(rows)} samples, {len(charts)} signals</h1>"
        f"{body}</body></html>"
    )


def car_graph(csv_path: str, out_path: str | None) -> int:
    """Read a logged OBD CSV and write an HTML chart dashboard next to it."""
    import csv
    try:
        with open(csv_path, newline="", encoding="utf-8") as fh:
            reader = csv.reader(fh)
            headers = next(reader, [])
            rows = [r for r in reader if r]
    except OSError as exc:
        print(f"Could not read {csv_path}: {exc}")
        return 1
    if not headers:
        print(f"{csv_path} is empty.")
        return 1
    out = out_path or (csv_path.rsplit(".", 1)[0] + ".html")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(render_obd_html(headers, rows))
    print(f"Wrote chart dashboard -> {out}  (open it in any browser)")
    return 0


def car_clear(port: str | None, assume_yes: bool) -> int:
    """Clear stored DTCs and turn off the check-engine light (mode 04).

    This is a WRITE to the car: it erases codes AND resets emissions readiness
    monitors, so an emissions test will fail until you re-drive the cycle.
    """
    print("Clear car trouble codes")
    print("-" * 23)
    print("WARNING: this erases stored codes and resets emissions readiness.")
    print("Only do it after you've noted the codes and fixed the cause.")
    if not assume_yes:
        try:
            if input("Type 'yes' to clear: ").strip().lower() != "yes":
                print("Aborted - nothing changed.")
                return 1
        except EOFError:
            print("No confirmation (non-interactive). Re-run with --yes to clear.")
            return 1
    obd, conn = _obd_connect(port)
    if conn is None:
        return 1 if obd is not None else 2
    conn.query(obd.commands.CLEAR_DTC)
    conn.close()
    print("Done. The light may take a drive cycle to fully clear; if the fault")
    print("remains, the code will come back - that's the car telling you it's real.")
    return 0


def car_diagnose(port: str | None) -> int:
    """Back-compat wrapper: DTCs plus readiness monitors."""
    return car_report(port, live=False, monitors=True, freeze=False)


# ---------------------------------------------------------------------------
# Auto: detect connected devices and run every read-only check on each
# ---------------------------------------------------------------------------
def _ios_device_present() -> bool:
    if not tool_available(IOS_TOOL):
        return False
    res = _run([IOS_TOOL, "usbmux", "list"], timeout=30)
    out = res.stdout.strip()
    return res.returncode == 0 and out not in ("", "[]")


def _android_targets() -> list[str]:
    if not tool_available(ANDROID_TOOL):
        return []
    res = _run([ANDROID_TOOL, "devices"], timeout=30)
    targets = []
    for line in res.stdout.splitlines()[1:]:
        line = line.strip()
        if line.endswith("\tdevice") or line.endswith(" device"):
            targets.append(line.split()[0])
    return targets


def auto_report(save: str | None = None) -> int:
    """Detect every reachable target and run all read-only checks on each."""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        print("=" * 60)
        print("AUTOMATIC DEVICE REPORT")
        print(f"Generated: {_dt.datetime.now().isoformat(timespec='seconds')}")
        print("Read-only checks. Phones must be unlocked + trusted to read.")
        print("=" * 60)

        # This computer is always available.
        print("\n########## THIS COMPUTER ##########")
        computer_specs()
        print()
        computer_diagnose()

        # iPhone.
        print("\n########## iPHONE (Apple) ##########")
        if not tool_available(IOS_TOOL):
            print("  pymobiledevice3 not installed - skipping iPhone checks.")
        elif not _ios_device_present():
            print("  No iPhone detected (plug in, unlock, tap 'Trust').")
        else:
            for fn in (ios_hardware, ios_specs, ios_info, ios_authenticity,
                       ios_diagnose):
                print()
                fn()

        # Android (phones, TVs, boxes).
        print("\n########## ANDROID ##########")
        if not tool_available(ANDROID_TOOL):
            print("  adb not installed - skipping Android checks.")
        else:
            targets = _android_targets()
            if not targets:
                print("  No authorized Android device (unlock + allow USB/ADB).")
            else:
                print(f"  Detected: {', '.join(targets)}")
                for fn in (android_hardware, android_specs, android_info,
                           android_authenticity, android_diagnose):
                    print()
                    fn()

        print("\n" + "=" * 60)
        print("END OF REPORT")
        print("=" * 60)

    text = buf.getvalue()
    sys.stdout.write(text)
    if save:
        try:
            with open(save, "w", encoding="utf-8") as fh:
                fh.write(text)
            print(f"\n(Report saved to {save})")
        except OSError as exc:
            print(f"\nCould not save report: {exc}")
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--auto", action="store_true",
                   help="detect all connected devices and run every check")
    p.add_argument("--save", metavar="FILE",
                   help="also write the --auto report to this file")
    p.add_argument("--check", action="store_true",
                   help="report installed backends and visible devices")
    p.add_argument("--ios", action="store_true", help="target an iPhone")
    p.add_argument("--android", action="store_true",
                   help="target an Android device (phone, TV, box, head-unit)")
    p.add_argument("--computer", action="store_true",
                   help="target THIS laptop/desktop (reads its own OS)")
    p.add_argument("--camera", action="store_true",
                   help="target a camera over PTP/MTP (needs gphoto2)")
    p.add_argument("--car", action="store_true",
                   help="target a car over OBD-II (needs python-OBD + ELM327)")
    p.add_argument("--port", metavar="DEV",
                   help="serial port for --car (e.g. /dev/ttyUSB0, COM3)")
    p.add_argument("--live", action="store_true",
                   help="--car: stream live sensor data (RPM, temps, fuel trims, O2, ...)")
    p.add_argument("--monitors", action="store_true",
                   help="--car: show emissions readiness monitors + check-engine state")
    p.add_argument("--freeze", action="store_true",
                   help="--car: show freeze-frame (conditions when a code set)")
    p.add_argument("--clear", action="store_true",
                   help="--car: clear stored codes / reset the check-engine light")
    p.add_argument("--yes", action="store_true",
                   help="skip the confirmation prompt for --clear")
    p.add_argument("--watch", action="store_true",
                   help="--car: stream live data on a loop (use with --log to record)")
    p.add_argument("--interval", type=float, default=0.5,
                   help="--watch sample interval in seconds (default 0.5)")
    p.add_argument("--duration", type=float, default=60.0,
                   help="--watch duration in seconds (default 60)")
    p.add_argument("--log", metavar="FILE",
                   help="--watch: record each sample to this CSV for graphing")
    p.add_argument("--graph", metavar="CSV",
                   help="offline: turn a logged OBD CSV into an HTML chart dashboard")
    p.add_argument("--all", action="store_true", dest="all_sensors",
                   help="--car: read EVERY live sensor the ECU reports supporting")
    p.add_argument("--net", metavar="HOST[:PORT]",
                   help="connect adb over the network first (Android TV / Fire TV "
                        "/ boxes); e.g. --net 192.168.1.50:5555")
    p.add_argument("--info", action="store_true",
                   help="read serial / IMEI from the unlocked, trusted device")
    p.add_argument("--hardware", action="store_true",
                   help="report model + chipset (SoC) from the connected device")
    p.add_argument("--specs", action="store_true",
                   help="dump full specs (OS, RAM, storage, screen, SoC, ...)")
    p.add_argument("--apple-model", dest="apple_model", metavar="PRODUCTTYPE",
                   help="offline: map an Apple product type (e.g. iPhone12,1) to "
                        "its model name and chip - no device needed")
    p.add_argument("--apple-serial-date", dest="apple_serial_date", metavar="SERIAL",
                   help="offline: estimate manufacture date from a legacy Apple "
                        "serial - no device needed")
    p.add_argument("--authenticity", action="store_true",
                   help="run counterfeit/authenticity heuristics on the device")
    p.add_argument("--diagnose", action="store_true",
                   help="check battery/storage/thermal/crashes and suggest fixes")
    p.add_argument("--photos", action="store_true", help="pull the camera roll (DCIM)")
    p.add_argument("--backup", action="store_true", help="full iPhone backup (iOS only)")
    p.add_argument("--out", type=Path, default=Path("./export"),
                   help="destination folder (default: ./export)")
    args = p.parse_args(argv)

    # Auto: detect everything and run all checks.
    if args.auto:
        return auto_report(save=args.save)

    # Offline lookup needs no device and no backend tools.
    if args.apple_model:
        named = apple_model_lookup(args.apple_model)
        print(f"Apple product type: {args.apple_model}")
        if named:
            print(f"  Model : {named[0]}")
            print(f"  Chip  : {named[1]}")
        else:
            print("  Not in the local map. Cross-check at checkcoverage.apple.com.")
        return 0

    if args.apple_serial_date:
        print(f"Apple serial: {args.apple_serial_date}")
        print(f"  Manufacture date: {apple_serial_date(args.apple_serial_date)}")
        return 0

    # Offline: graph a previously logged OBD CSV (no car/adapter needed).
    if args.graph:
        return car_graph(args.graph, args.out if str(args.out) != "export" else None)

    # This computer: no device, no protocol - reads the local OS.
    if args.computer:
        if args.diagnose:
            return computer_diagnose()
        return computer_specs()  # default to specs

    # Camera over PTP/MTP (gphoto2).
    if args.camera:
        if args.photos:
            return camera_photos(args.out)
        return camera_info()  # default: detect + summary

    # Car over OBD-II (python-OBD + ELM327 adapter).
    if args.car:
        if args.clear:
            return car_clear(args.port, args.yes)
        if args.watch:
            return car_watch(args.port, args.interval, args.duration, args.log)
        # Default to a full report; --live/--monitors/--freeze narrow or extend it.
        any_car_action = args.live or args.monitors or args.freeze or args.all_sensors
        return car_report(
            args.port,
            live=args.live or not any_car_action,
            monitors=args.monitors or not any_car_action,
            freeze=args.freeze or not any_car_action,
            all_sensors=args.all_sensors,
        )

    # Network adb for Android TVs / boxes / head-units.
    if args.net:
        if not tool_available(ANDROID_TOOL):
            print(f"ERROR: {ANDROID_TOOL} not installed (needed for --net).")
            return 2
        target = args.net if ":" in args.net else f"{args.net}:5555"
        conn = _run([ANDROID_TOOL, "connect", target], timeout=30)
        sys.stdout.write(conn.stdout)
        if "connected" not in conn.stdout.lower():
            print("Could not connect. On the device, enable Developer options ->")
            print("'ADB debugging' / 'Network debugging' and confirm the IP:port.")
            return 1
        args.android = True  # treat it as an Android target from here on

    any_target = args.ios or args.android or args.computer or args.camera or args.car
    if args.check or not any_target:
        check_environment()
        if not any_target:
            print("\nNothing to do. Pick a target (--ios / --android / --computer"
                  " / --camera / --car) and an action (--info/--hardware/--specs/"
                  "--authenticity/--diagnose/--photos), or --auto / --apple-model.")
        return 0

    if args.ios and args.info:
        return ios_info()
    if args.android and args.info:
        return android_info()
    if args.ios and args.hardware:
        return ios_hardware()
    if args.android and args.hardware:
        return android_hardware()
    if args.ios and args.specs:
        return ios_specs()
    if args.android and args.specs:
        return android_specs()
    if args.ios and args.authenticity:
        return ios_authenticity()
    if args.android and args.authenticity:
        return android_authenticity()
    if args.ios and args.diagnose:
        return ios_diagnose()
    if args.android and args.diagnose:
        return android_diagnose()
    if args.ios and args.backup:
        return ios_backup(args.out)
    if args.ios and args.photos:
        return ios_photos(args.out)
    if args.android and args.photos:
        return android_photos(args.out)
    if args.android and args.backup:
        print("Full-image backup over adb varies by device; use --photos, or")
        print("use Samsung Smart Switch on the desktop for a complete backup.")
        return 2

    p.error("choose an action: --info, --hardware, --specs, --authenticity, "
            "--diagnose, --photos (or --backup for iOS)")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
