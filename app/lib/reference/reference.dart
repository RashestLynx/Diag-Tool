// Device-free reference data (Apple model map, Qualcomm platforms, car trouble
// codes, Apple serial-date rules), loaded from assets/reference.json.
//
// Generated from device_export.py via `python diag_tool.py export-json`.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class AppleModel {
  AppleModel(this.productType, this.model, this.soc);
  final String productType;
  final String model;
  final String soc;
}

class DtcCode {
  DtcCode(this.code, this.meaning, this.fix);
  final String code;
  final String meaning;
  final String fix;

  String get system => switch (code.isEmpty ? '' : code[0].toUpperCase()) {
        'P' => 'Powertrain',
        'C' => 'Chassis',
        'B' => 'Body',
        'U' => 'Network',
        _ => 'Unknown system',
      };
}

class Reference {
  Reference({
    required this.appleModels,
    required this.qcomPlatforms,
    required this.dtcFixes,
    required this.appleYearAlphabet,
    required this.appleWeekAlphabet,
  });

  final Map<String, AppleModel> appleModels;
  final Map<String, String> qcomPlatforms;
  final Map<String, DtcCode> dtcFixes;
  final String appleYearAlphabet;
  final String appleWeekAlphabet;

  static Future<Reference> load() async =>
      Reference.fromJson(jsonDecode(await rootBundle.loadString('assets/reference.json')));

  factory Reference.fromJson(Map<String, dynamic> j) => Reference(
        appleModels: {
          for (final e in (j['apple_models'] as Map<String, dynamic>).entries)
            e.key: AppleModel(e.key, e.value['model'] as String, e.value['soc'] as String),
        },
        qcomPlatforms: Map<String, String>.from(j['qcom_platforms'] as Map),
        dtcFixes: {
          for (final e in (j['dtc_fixes'] as Map<String, dynamic>).entries)
            e.key: DtcCode(e.key, e.value['meaning'] as String, e.value['fix'] as String),
        },
        appleYearAlphabet: j['apple_year_alphabet'] as String,
        appleWeekAlphabet: j['apple_week_alphabet'] as String,
      );

  /// Look up an Apple product type like "iPhone14,5" (case/space-insensitive).
  AppleModel? appleModel(String productType) => appleModels[productType.trim()];

  /// Look up a car trouble code like "p0420" (normalized to upper-case).
  DtcCode? dtc(String code) => dtcFixes[code.trim().toUpperCase()];

  /// Estimate the manufacture date from a legacy (11/12-char) Apple serial.
  /// Mirrors device_export.apple_serial_date. Returns null when not derivable.
  ({int year, int week})? appleSerialDate(String serial) {
    final s = serial.trim().toUpperCase();
    if (s.length != 11 && s.length != 12) return null;
    final yearC = s[3];
    final weekC = s[4];
    final yPos = appleYearAlphabet.indexOf(yearC);
    final wPos = appleWeekAlphabet.indexOf(weekC);
    if (yPos < 0 || wPos < 0) return null;
    final year = 2010 + yPos ~/ 2;
    final half = yPos % 2;
    var week = wPos + 1 + (half == 1 ? 26 : 0);
    if (week > 53) week = 53;
    return (year: year, week: week);
  }
}
