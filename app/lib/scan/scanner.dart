// Fills a DeviceReport for whichever platform the app is running on.
//
// Uses device_info_plus and battery_plus everywhere, plus a native Win32/WMI
// probe on Windows (disk, RAM, uptime, battery wear) and extra Android battery
// details over a platform channel.

import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

import 'report.dart';
import 'windows_native.dart';

const _mb = 1024 * 1024;

// SMBIOS chassis type codes (shared by Windows WMI and Linux DMI).
const _chassisKinds = {
  3: 'desktop', 4: 'desktop', 5: 'desktop', 6: 'desktop', 7: 'desktop',
  8: 'laptop', 9: 'laptop', 10: 'laptop', 11: 'tablet', 12: 'laptop',
  13: 'desktop', 14: 'laptop', 15: 'desktop', 16: 'laptop', 17: 'desktop',
  18: 'desktop', 21: 'laptop', 24: 'desktop', 30: 'tablet', 31: 'laptop',
  32: 'tablet', 35: 'desktop', 36: 'desktop',
};
const _chassisDetail = {
  11: 'handheld', 13: 'all-in-one', 17: 'server', 30: 'tablet',
  31: 'convertible', 32: 'detachable', 35: 'mini PC', 36: 'stick PC',
};

const _vmHints = [
  'virtualbox', 'vmware', 'kvm', 'qemu', 'hyper-v', 'virtual machine', 'xen',
  'parallels', 'bochs', 'amazon ec2', 'google compute', 'firecracker',
];

/// Platform channel for a few Android battery extras the plugins don't expose.
const _androidChannel = MethodChannel('com.rashestlynx.diag_tool/android');

Future<DeviceReport> scanDevice() async {
  final report = DeviceReport();
  final info = DeviceInfoPlugin();

  if (Platform.isAndroid) {
    await _android(report, await info.androidInfo);
  } else if (Platform.isIOS) {
    _ios(report, await info.iosInfo);
  } else if (Platform.isMacOS) {
    await _macos(report, await info.macOsInfo);
  } else if (Platform.isWindows) {
    await _windows(report, await info.windowsInfo);
  } else if (Platform.isLinux) {
    await _linux(report, await info.linuxInfo);
  }

  await _battery(report);
  return report;
}

Future<void> _battery(DeviceReport r) async {
  // battery_plus works on Android, iOS, macOS, Windows and Linux.
  final battery = Battery();
  try {
    r.batteryLevel = (await battery.batteryLevel).clamp(0, 100);
  } catch (_) {/* desktop with no battery */}
  try {
    final state = await battery.batteryState;
    if (state == BatteryState.charging || state == BatteryState.full) {
      r.pluggedIn = true;
    } else if (state == BatteryState.discharging) {
      r.pluggedIn = false;
    }
  } catch (_) {}
  try {
    r.lowPowerMode = await battery.isInBatterySaveMode;
  } catch (_) {}
}

Future<void> _android(DeviceReport r, AndroidDeviceInfo a) async {
  r.kind = _looksLikeTablet(a) ? 'tablet' : 'phone';
  r.makeModel = '${_titleCase(a.manufacturer)} ${a.model}'.trim();
  r.os = 'Android ${a.version.release} (API ${a.version.sdkInt})';
  r.diskTotal = a.totalDiskSize;
  r.diskFree = a.freeDiskSize;
  r.memTotal = a.physicalRamSize * _mb;
  r.memFree = a.availableRamSize * _mb;
  if (a.isLowRamDevice) r.kindDetail = 'low-RAM device';

  // Battery temperature, health and charge-cycle count come from the OS
  // BatteryManager via a tiny platform channel (see MainActivity.kt).
  try {
    final extra = await _androidChannel.invokeMapMethod<String, dynamic>('batteryExtras');
    if (extra != null) {
      final tempTenths = extra['temperature'] as int?; // tenths of a degree C
      if (tempTenths != null && tempTenths > 0) r.batteryTempC = tempTenths / 10.0;
      r.batteryHealth = extra['health'] as String?;
      final cycles = extra['cycleCount'] as int?;
      if (cycles != null && cycles > 0) r.batteryCycles = cycles;
    }
  } catch (_) {/* older Android or channel not wired in a given build */}
}

bool _looksLikeTablet(AndroidDeviceInfo a) {
  final hay = '${a.model} ${a.device} ${a.product}'.toLowerCase();
  return hay.contains('tab') || hay.contains('pad');
}

void _ios(DeviceReport r, IosDeviceInfo i) {
  final name = i.modelName.toLowerCase();
  r.kind = name.contains('ipad') ? 'tablet' : 'phone';
  r.makeModel = 'Apple ${i.modelName}';
  r.os = '${i.systemName} ${i.systemVersion}';
  r.diskTotal = i.totalDiskSize;
  r.diskFree = i.freeDiskSize;
  r.memTotal = i.physicalRamSize * _mb;
  r.memFree = i.availableRamSize * _mb;
  if (!i.isPhysicalDevice) r.kindDetail = 'simulator';
  // iOS doesn't expose battery temperature/health to third-party apps;
  // the scan still covers storage, memory and charge level.
}

Future<void> _macos(DeviceReport r, MacOsDeviceInfo m) async {
  final model = m.model.toLowerCase();
  r.kind = model.contains('book') ? 'laptop' : 'desktop';
  r.makeModel = 'Apple ${m.modelName.isNotEmpty ? m.modelName : m.model}';
  r.os = 'macOS ${m.osRelease}';
  r.memTotal = m.memorySize;
  _diskFromStatfs(r, '/');
  _thermalFromPmset(r);
}

Future<void> _windows(DeviceReport r, WindowsDeviceInfo w) async {
  r.os = w.productName.isNotEmpty ? w.productName : 'Windows';
  r.memTotal = w.systemMemoryInMegabytes * _mb;

  final native = readWindowsInfo();
  r.diskTotal = native.diskTotal;
  r.diskFree = native.diskFree;
  r.memFree = native.memFree;
  if (native.memTotal != null) r.memTotal = native.memTotal;
  r.uptime = native.uptime;
  if (native.hasBattery) {
    r.batteryLevel = native.batteryLevel;
    r.pluggedIn = native.pluggedIn;
    r.lowPowerMode = native.batterySaver;
  }

  final wmi = await readWindowsWmi();
  if (wmi.manufacturer != null || wmi.model != null) {
    r.makeModel = [wmi.manufacturer, wmi.model].where((s) => s != null && s.isNotEmpty).join(' ');
  }
  r.batteryCapacityPct = wmi.batteryCapacityPct;
  r.batteryCycles = wmi.batteryCycles;

  final chassis = wmi.chassisType;
  r.kind = chassis != null
      ? (_chassisKinds[chassis] ?? (native.hasBattery ? 'laptop' : 'desktop'))
      : (native.hasBattery ? 'laptop' : 'desktop');
  r.kindDetail = chassis != null ? _chassisDetail[chassis] : null;
  _flagVm(r);
}

Future<void> _linux(DeviceReport r, LinuxDeviceInfo l) async {
  r.makeModel = l.prettyName;
  r.os = l.prettyName;
  _readLinuxDmi(r);
  _diskFromStatfs(r, '/');
  final mem = _readProcMeminfo();
  if (mem != null) {
    r.memTotal = mem.$1;
    r.memFree = mem.$2;
  }
  final up = _readProcUptime();
  if (up != null) r.uptime = up;
  _flagVm(r);
}

// --- Linux / Unix helpers (no plugin needed) --------------------------------

void _readLinuxDmi(DeviceReport r) {
  const base = '/sys/class/dmi/id';
  final vendor = _readFile('$base/sys_vendor');
  final product = _readFile('$base/product_name');
  final makeModel = [vendor, product].where((s) => s != null && s.isNotEmpty).join(' ');
  if (makeModel.isNotEmpty) r.makeModel = makeModel;

  final chassis = int.tryParse(_readFile('$base/chassis_type') ?? '');
  if (chassis != null) {
    r.kind = _chassisKinds[chassis] ?? r.kind;
    r.kindDetail = _chassisDetail[chassis];
  }
  if (File('/.dockerenv').existsSync()) {
    r.kind = 'desktop';
    r.kindDetail = 'container';
  }
}

void _diskFromStatfs(DeviceReport r, String path) {
  // `df -kP` is portable across Linux and macOS and needs no FFI.
  try {
    final out = Process.runSync('df', ['-kP', path]);
    if (out.exitCode != 0) return;
    final lines = (out.stdout as String).trim().split('\n');
    if (lines.length < 2) return;
    final cols = lines.last.split(RegExp(r'\s+'));
    // Filesystem, 1024-blocks, Used, Available, Capacity, Mounted
    final total = int.tryParse(cols[1]);
    final avail = int.tryParse(cols[3]);
    if (total != null) r.diskTotal = total * 1024;
    if (avail != null) r.diskFree = avail * 1024;
  } catch (_) {}
}

(int, int)? _readProcMeminfo() {
  final text = _readFile('/proc/meminfo');
  if (text == null) return null;
  int? total, avail;
  for (final line in text.split('\n')) {
    final m = RegExp(r'^(MemTotal|MemAvailable):\s+(\d+)').firstMatch(line);
    if (m == null) continue;
    final bytes = int.parse(m.group(2)!) * 1024;
    if (m.group(1) == 'MemTotal') total = bytes;
    if (m.group(1) == 'MemAvailable') avail = bytes;
  }
  return (total != null && avail != null) ? (total, avail) : null;
}

Duration? _readProcUptime() {
  final text = _readFile('/proc/uptime');
  if (text == null) return null;
  final secs = double.tryParse(text.trim().split(' ').first);
  return secs == null ? null : Duration(seconds: secs.round());
}

void _thermalFromPmset(DeviceReport r) {
  try {
    final out = Process.runSync('pmset', ['-g', 'therm']);
    if (out.exitCode != 0) return;
    final text = out.stdout as String;
    final m = RegExp(r'CPU_Speed_Limit\s*=\s*(\d+)').firstMatch(text);
    if (m != null && int.parse(m.group(1)!) < 100) {
      r.thermal = 'serious'; // the Mac is throttling the CPU to cool down
    } else {
      r.thermal = 'nominal';
    }
  } catch (_) {}
}

void _flagVm(DeviceReport r) {
  final hay = (r.makeModel ?? '').toLowerCase();
  if (_vmHints.any(hay.contains)) {
    r.kind = 'desktop';
    r.kindDetail = 'virtual machine';
  }
}

String? _readFile(String path) {
  try {
    final f = File(path);
    return f.existsSync() ? f.readAsStringSync().trim() : null;
  } catch (_) {
    return null;
  }
}

String _titleCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
