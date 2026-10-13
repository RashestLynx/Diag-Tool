// Device-free reference data (Apple model map, Qualcomm platforms, car trouble
// codes, Apple serial-date rules), loaded from assets/reference.json.
//
// Generated from device_export.py via `python diag_tool.py export-json`.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class AppleModel {
  AppleModel(this.productType, this.model, this.soc, this.year);
  final String productType;
  final String model;
  final String soc;
  final int? year; // model release year, or null if unknown
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
    required this.dtcSystems,
    required this.dtcPSubsystems,
  });

  final Map<String, AppleModel> appleModels;
  final Map<String, String> qcomPlatforms;
  final Map<String, DtcCode> dtcFixes;
  final String appleYearAlphabet;
  final String appleWeekAlphabet;
  final Map<String, String> dtcSystems;
  final Map<String, String> dtcPSubsystems;

  static Future<Reference> load() async =>
      Reference.fromJson(jsonDecode(await rootBundle.loadString('assets/reference.json')));

  factory Reference.fromJson(Map<String, dynamic> j) => Reference(
        appleModels: {
          for (final e in (j['apple_models'] as Map<String, dynamic>).entries)
            e.key: AppleModel(e.key, e.value['model'] as String, e.value['soc'] as String,
                (e.value['year'] as num?)?.toInt()),
        },
        qcomPlatforms: Map<String, String>.from(j['qcom_platforms'] as Map),
        dtcFixes: {
          for (final e in (j['dtc_fixes'] as Map<String, dynamic>).entries)
            e.key: DtcCode(e.key, e.value['meaning'] as String, e.value['fix'] as String),
        },
        appleYearAlphabet: j['apple_year_alphabet'] as String,
        appleWeekAlphabet: j['apple_week_alphabet'] as String,
        dtcSystems: Map<String, String>.from(j['dtc_systems'] as Map),
        dtcPSubsystems: Map<String, String>.from(j['dtc_p_subsystems'] as Map),
      );

  /// Look up an Apple product type like "iPhone14,5" (case/space-insensitive).
  AppleModel? appleModel(String productType) => appleModels[productType.trim()];

  /// Release year for an Apple product type, or null if unknown.
  int? appleReleaseYear(String productType) => appleModels[productType.trim()]?.year;

  /// Look up a car trouble code like "p0420" (normalized to upper-case).
  DtcCode? dtc(String code) => dtcFixes[code.trim().toUpperCase()];

  /// Explain the structure of ANY well-formed code, for ones not in [dtcFixes].
  /// Returns null if the text isn't a valid 5-character OBD-II code.
  String? describeDtc(String code) {
    final c = code.trim().toUpperCase();
    if (c.length != 5) return null;
    final sys = dtcSystems[c[0]];
    if (sys == null || !RegExp(r'^\d{4}$').hasMatch(c.substring(1))) return null;
    final parts = <String>[
      sys,
      c[1] == '1' ? 'manufacturer-specific' : 'generic (same on every make)',
    ];
    if (c[0] == 'P' && dtcPSubsystems.containsKey(c[2])) {
      parts.add(dtcPSubsystems[c[2]]!);
    }
    return parts.join(' · ');
  }

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
