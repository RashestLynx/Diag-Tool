// Pure-Dart ELM327 / OBD-II protocol layer.
//
// This has NO Bluetooth/serial dependency: it turns OBD requests into the ASCII
// commands an ELM327 expects, and parses the hex responses back into values.
// A transport (BLE or serial) feeds bytes in and sends bytes out; keeping the
// protocol separate means it can be fully unit-tested without any hardware.
//
// References: ELM327 datasheet + SAE J1979 (OBD-II mode 01/03/04).

/// A single OBD-II PID we know how to request and decode (mode 01).
class ObdPid {
  const ObdPid(this.pid, this.name, this.unit, this.decode, {this.description = ''});

  /// The PID byte, e.g. 0x0C for engine RPM.
  final int pid;
  final String name;
  final String unit;
  final String description;

  /// Decode the data bytes (the A, B, C... bytes after the mode+pid echo).
  final double Function(List<int> data) decode;

  /// The request line sent to the ELM327, e.g. "010C".
  String get request => '01${pid.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

double _a(List<int> d) => d.isNotEmpty ? d[0].toDouble() : 0;

/// The standard decoders for the common mode-01 PIDs (SAE J1979 formulas).
const List<ObdPid> standardPids = [
  ObdPid(0x04, 'ENGINE_LOAD', '%', _pctA, description: 'Calculated engine load'),
  ObdPid(0x05, 'COOLANT_TEMP', '°C', _tempA, description: 'Coolant temperature'),
  ObdPid(0x06, 'SHORT_FUEL_TRIM_1', '%', _trim, description: 'Short-term fuel trim b1'),
  ObdPid(0x07, 'LONG_FUEL_TRIM_1', '%', _trim, description: 'Long-term fuel trim b1'),
  ObdPid(0x08, 'SHORT_FUEL_TRIM_2', '%', _trim, description: 'Short-term fuel trim b2'),
  ObdPid(0x09, 'LONG_FUEL_TRIM_2', '%', _trim, description: 'Long-term fuel trim b2'),
  ObdPid(0x0A, 'FUEL_PRESSURE', 'kPa', _fuelPressure, description: 'Fuel pressure'),
  ObdPid(0x0B, 'INTAKE_PRESSURE', 'kPa', _a, description: 'Intake manifold pressure'),
  ObdPid(0x0C, 'RPM', 'rpm', _rpm, description: 'Engine RPM'),
  ObdPid(0x0D, 'SPEED', 'km/h', _a, description: 'Vehicle speed'),
  ObdPid(0x0E, 'TIMING_ADVANCE', '°', _timing, description: 'Ignition timing advance'),
  ObdPid(0x0F, 'INTAKE_TEMP', '°C', _tempA, description: 'Intake air temperature'),
  ObdPid(0x10, 'MAF', 'g/s', _maf, description: 'Mass air flow'),
  ObdPid(0x11, 'THROTTLE_POS', '%', _pctA, description: 'Throttle position'),
  ObdPid(0x2F, 'FUEL_LEVEL', '%', _pctA, description: 'Fuel tank level'),
  ObdPid(0x33, 'BAROMETRIC_PRESSURE', 'kPa', _a, description: 'Barometric pressure'),
  ObdPid(0x42, 'CONTROL_MODULE_VOLTAGE', 'V', _moduleVolts, description: 'Module voltage'),
  ObdPid(0x46, 'AMBIANT_AIR_TEMP', '°C', _tempA, description: 'Ambient air temp'),
  ObdPid(0x5C, 'OIL_TEMP', '°C', _tempOil, description: 'Engine oil temperature'),
];

double _pctA(List<int> d) => d.isNotEmpty ? d[0] * 100 / 255 : 0;
double _tempA(List<int> d) => d.isNotEmpty ? d[0] - 40.0 : 0;
double _tempOil(List<int> d) => d.isNotEmpty ? d[0] - 40.0 : 0;
double _trim(List<int> d) => d.isNotEmpty ? (d[0] - 128) * 100 / 128 : 0;
double _fuelPressure(List<int> d) => d.isNotEmpty ? d[0] * 3.0 : 0;
double _rpm(List<int> d) => d.length >= 2 ? (d[0] * 256 + d[1]) / 4 : 0;
double _timing(List<int> d) => d.isNotEmpty ? d[0] / 2 - 64 : 0;
double _maf(List<int> d) => d.length >= 2 ? (d[0] * 256 + d[1]) / 100 : 0;
double _moduleVolts(List<int> d) => d.length >= 2 ? (d[0] * 256 + d[1]) / 1000 : 0;

final Map<int, ObdPid> standardPidsByNumber = {for (final p in standardPids) p.pid: p};

/// A decoded live reading.
class ObdReading {
  ObdReading(this.pid, this.name, this.value, this.unit);
  final int pid;
  final String name;
  final double value;
  final String unit;
  @override
  String toString() => '$name = ${value.toStringAsFixed(2)} $unit';
}

/// Parsing helpers for raw ELM327 responses (the protocol's heart).
class Elm327Protocol {
  /// Strip ELM327 noise: whitespace, the echoed command, 'SEARCHING...',
  /// and the trailing '>' prompt. Returns the hex byte stream, upper-case.
  static List<int> cleanHexBytes(String raw) {
    var text = raw.replaceAll('\r', ' ').replaceAll('\n', ' ').replaceAll('>', ' ');
    text = text.replaceAll(RegExp(r'SEARCHING\.\.\.', caseSensitive: false), ' ');
    final tokens = text.trim().split(RegExp(r'\s+'));
    final bytes = <int>[];
    for (final t in tokens) {
      if (t.length == 2 && RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(t)) {
        bytes.add(int.parse(t, radix: 16));
      } else if (t.length > 2 && t.length.isEven && RegExp(r'^[0-9A-Fa-f]+$').hasMatch(t)) {
        for (var i = 0; i < t.length; i += 2) {
          bytes.add(int.parse(t.substring(i, i + 2), radix: 16));
        }
      }
    }
    return bytes;
  }

  /// True if the adapter/ECU reported no data or an error for a request.
  static bool isNoData(String raw) {
    final u = raw.toUpperCase();
    return u.contains('NO DATA') || u.contains('UNABLE TO CONNECT') ||
        u.contains('CAN ERROR') || u.contains('BUS INIT') && u.contains('ERROR') ||
        u.contains('?');
  }

  /// Parse a mode-01 response for [pid]. Returns null if it isn't present.
  /// Accepts the response with or without the `41 <pid>` echo header.
  static ObdReading? parseMode01(ObdPid pid, String raw) {
    if (isNoData(raw)) return null;
    final bytes = cleanHexBytes(raw);
    if (bytes.isEmpty) return null;
    // Find the "41 <pid>" header; the data bytes follow it.
    for (var i = 0; i + 1 < bytes.length; i++) {
      if (bytes[i] == 0x41 && bytes[i + 1] == pid.pid) {
        final data = bytes.sublist(i + 2);
        return ObdReading(pid.pid, pid.name, pid.decode(data), pid.unit);
      }
    }
    return null;
  }

  /// Parse a mode-03 (stored DTC) response into code strings like "P0301".
  static List<String> parseDtcs(String raw) {
    if (isNoData(raw)) return [];
    final bytes = cleanHexBytes(raw);
    // Drop everything up to and including the 0x43 mode echo.
    var i = 0;
    while (i < bytes.length && bytes[i] != 0x43) {
      i++;
    }
    if (i < bytes.length) i++; // skip 0x43
    // Some adapters insert a DTC-count byte before the pairs; it makes the
    // remaining length odd, so skip one byte when that's the case.
    if ((bytes.length - i).isOdd) i++;
    final codes = <String>[];
    for (var j = i; j + 1 < bytes.length; j += 2) {
      final a = bytes[j];
      final b = bytes[j + 1];
      if (a == 0 && b == 0) continue; // padding / empty slot
      codes.add(_dtcFromBytes(a, b));
    }
    return codes;
  }

  static String _dtcFromBytes(int a, int b) {
    const letters = ['P', 'C', 'B', 'U'];
    final letter = letters[(a & 0xC0) >> 6];
    final d1 = (a & 0x30) >> 4;
    final d2 = a & 0x0F;
    final d3 = (b & 0xF0) >> 4;
    final d4 = b & 0x0F;
    return '$letter$d1${d2.toRadixString(16)}${d3.toRadixString(16)}${d4.toRadixString(16)}'
        .toUpperCase();
  }
}

/// The handshake an ELM327 needs before it will answer OBD requests.
/// (A transport sends each and waits for the prompt.)
const List<String> elm327InitSequence = [
  'ATZ', // reset
  'ATE0', // echo off
  'ATL0', // linefeeds off
  'ATS0', // spaces off
  'ATH0', // headers off
  'ATSP0', // auto protocol
];
