// Windows system info through the Win32 API (dart:ffi), plus a PowerShell
// query for the things Win32 doesn't expose simply (chassis type, battery wear).
//
// Only call these when Platform.isWindows.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class _MemoryStatusEx extends Struct {
  @Uint32()
  external int dwLength;
  @Uint32()
  external int dwMemoryLoad;
  @Uint64()
  external int ullTotalPhys;
  @Uint64()
  external int ullAvailPhys;
  @Uint64()
  external int ullTotalPageFile;
  @Uint64()
  external int ullAvailPageFile;
  @Uint64()
  external int ullTotalVirtual;
  @Uint64()
  external int ullAvailVirtual;
  @Uint64()
  external int ullAvailExtendedVirtual;
}

final class _SystemPowerStatus extends Struct {
  @Uint8()
  external int acLineStatus;
  @Uint8()
  external int batteryFlag;
  @Uint8()
  external int batteryLifePercent;
  @Uint8()
  external int systemStatusFlag;
  @Uint32()
  external int batteryLifeTime;
  @Uint32()
  external int batteryFullLifeTime;
}

class WindowsInfo {
  int? diskTotal;
  int? diskFree;
  int? memTotal;
  int? memFree;
  Duration? uptime;
  bool hasBattery = false;
  int? batteryLevel;
  bool? pluggedIn;
  bool? batterySaver;
}

WindowsInfo readWindowsInfo() {
  final info = WindowsInfo();
  final kernel32 = DynamicLibrary.open('kernel32.dll');

  final getDiskFreeSpaceEx = kernel32.lookupFunction<
      Int32 Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>),
      int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>,
          Pointer<Uint64>)>('GetDiskFreeSpaceExW');
  final globalMemoryStatusEx = kernel32.lookupFunction<Int32 Function(Pointer<_MemoryStatusEx>),
      int Function(Pointer<_MemoryStatusEx>)>('GlobalMemoryStatusEx');
  final getTickCount64 =
      kernel32.lookupFunction<Uint64 Function(), int Function()>('GetTickCount64');
  final getSystemPowerStatus = kernel32.lookupFunction<
      Int32 Function(Pointer<_SystemPowerStatus>),
      int Function(Pointer<_SystemPowerStatus>)>('GetSystemPowerStatus');

  using((arena) {
    final drive = '${Platform.environment['SystemDrive'] ?? 'C:'}\\'.toNativeUtf16(allocator: arena);
    final freeToUser = arena<Uint64>();
    final total = arena<Uint64>();
    final totalFree = arena<Uint64>();
    if (getDiskFreeSpaceEx(drive, freeToUser, total, totalFree) != 0) {
      info.diskTotal = total.value;
      info.diskFree = freeToUser.value;
    }

    final mem = arena<_MemoryStatusEx>();
    mem.ref.dwLength = sizeOf<_MemoryStatusEx>();
    if (globalMemoryStatusEx(mem) != 0) {
      info.memTotal = mem.ref.ullTotalPhys;
      info.memFree = mem.ref.ullAvailPhys;
    }

    info.uptime = Duration(milliseconds: getTickCount64());

    final power = arena<_SystemPowerStatus>();
    if (getSystemPowerStatus(power) != 0) {
      final flag = power.ref.batteryFlag;
      // 128 = no system battery, 255 = unknown.
      info.hasBattery = flag != 128 && flag != 255;
      if (info.hasBattery) {
        final pct = power.ref.batteryLifePercent;
        info.batteryLevel = pct <= 100 ? pct : null;
        info.pluggedIn = power.ref.acLineStatus == 1;
        info.batterySaver = power.ref.systemStatusFlag == 1;
      }
    }
  });
  return info;
}

class WindowsWmiInfo {
  String? manufacturer;
  String? model;
  int? chassisType;
  int? batteryCapacityPct;
  int? batteryCycles;
  String? cpu;
  String? gpu;
  int? cpuCores;
}

/// Slower details from WMI via PowerShell. Every field is best-effort.
Future<WindowsWmiInfo> readWindowsWmi() async {
  const script = r'''
$ErrorActionPreference = 'SilentlyContinue'
$cs = Get-CimInstance Win32_ComputerSystem
$en = Get-CimInstance Win32_SystemEnclosure
$full = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity | Select-Object -First 1).FullChargedCapacity
$design = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData | Select-Object -First 1).DesignedCapacity
$cycles = (Get-CimInstance -Namespace root\wmi -ClassName BatteryCycleCount | Select-Object -First 1).CycleCount
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpu = (Get-CimInstance Win32_VideoController | Where-Object { $_.Name } | Select-Object -First 1).Name
@{ manufacturer = $cs.Manufacturer; model = $cs.Model; chassis = @($en.ChassisTypes)[0];
   full = $full; design = $design; cycles = $cycles;
   cpu = $cpu.Name; cores = $cpu.NumberOfLogicalProcessors; gpu = $gpu } | ConvertTo-Json -Compress
''';
  final info = WindowsWmiInfo();
  try {
    final result = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script],
    ).timeout(const Duration(seconds: 15));
    if (result.exitCode != 0) return info;
    final j = jsonDecode((result.stdout as String).trim()) as Map<String, dynamic>;
    info.manufacturer = (j['manufacturer'] as String?)?.trim();
    info.model = (j['model'] as String?)?.trim();
    info.chassisType = (j['chassis'] as num?)?.toInt();
    final full = (j['full'] as num?)?.toInt();
    final design = (j['design'] as num?)?.toInt();
    if (full != null && design != null && design > 0) {
      info.batteryCapacityPct = (100 * full / design).round().clamp(0, 100);
    }
    final cycles = (j['cycles'] as num?)?.toInt();
    if (cycles != null && cycles > 0) info.batteryCycles = cycles;
    info.cpu = (j['cpu'] as String?)?.trim();
    info.gpu = (j['gpu'] as String?)?.trim();
    info.cpuCores = (j['cores'] as num?)?.toInt();
  } catch (_) {
    // PowerShell missing, blocked or slow - just show less detail.
  }
  return info;
}
