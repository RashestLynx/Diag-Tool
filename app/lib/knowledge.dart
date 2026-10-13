// Device + symptom knowledge base, loaded from assets/knowledge.json.
//
// The JSON is generated from the command-line tool (`python diag_tool.py
// export-json`), so the app and the CLI give the same advice.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class Cause {
  Cause({
    required this.name,
    required this.likelihood,
    required this.fixes,
    this.devices,
    this.warning,
  });

  final String name;

  /// 1 (rare) .. 5 (very common).
  final int likelihood;
  final List<String> fixes;

  /// Device kinds this cause applies to; null means every kind.
  final Set<String>? devices;
  final String? warning;

  String get likelihoodLabel => switch (likelihood) {
        5 => 'Very likely',
        4 => 'Likely',
        3 => 'Possible',
        2 => 'Less likely',
        _ => 'Rare',
      };

  factory Cause.fromJson(Map<String, dynamic> j) => Cause(
        name: j['name'] as String,
        likelihood: j['likelihood'] as int,
        fixes: List<String>.from(j['fixes'] as List),
        devices: j['devices'] == null ? null : Set<String>.from(j['devices'] as List),
        warning: j['warning'] as String?,
      );
}

class Symptom {
  Symptom({
    required this.key,
    required this.title,
    required this.keywords,
    required this.causes,
    this.devices,
  });

  final String key;
  final String title;
  final List<String> keywords;
  final List<Cause> causes;
  final Set<String>? devices;

  bool appliesTo(String? device) =>
      device == null || devices == null || devices!.contains(device);

  /// Causes that apply to [device], most likely first.
  List<Cause> causesFor(String? device) {
    final list = causes
        .where((c) => device == null || c.devices == null || c.devices!.contains(device))
        .toList();
    list.sort((a, b) => b.likelihood.compareTo(a.likelihood));
    return list;
  }

  factory Symptom.fromJson(Map<String, dynamic> j) => Symptom(
        key: j['key'] as String,
        title: j['title'] as String,
        keywords: List<String>.from(j['keywords'] as List),
        causes: [for (final c in j['causes'] as List) Cause.fromJson(c as Map<String, dynamic>)],
        devices: j['devices'] == null ? null : Set<String>.from(j['devices'] as List),
      );
}

const deviceLabels = {
  'phone': 'Phone',
  'tablet': 'Tablet',
  'laptop': 'Laptop',
  'desktop': 'Desktop PC',
  'console': 'Game console',
  'tv': 'TV / monitor',
  'router': 'Router / modem',
  'headphones': 'Headphones / speaker',
  'printer': 'Printer',
  'smartwatch': 'Smartwatch',
};

class Knowledge {
  Knowledge({required this.devices, required this.symptoms});

  /// Device kind -> keywords that identify it in free text.
  final Map<String, List<String>> devices;
  final List<Symptom> symptoms;

  static Future<Knowledge> load() async =>
      Knowledge.fromJson(jsonDecode(await rootBundle.loadString('assets/knowledge.json')));

  factory Knowledge.fromJson(Map<String, dynamic> j) => Knowledge(
        devices: {
          for (final e in (j['devices'] as Map<String, dynamic>).entries)
            e.key: List<String>.from(e.value as List),
        },
        symptoms: [
          for (final s in j['symptoms'] as List) Symptom.fromJson(s as Map<String, dynamic>)
        ],
      );

  Symptom? symptom(String key) {
    for (final s in symptoms) {
      if (s.key == key) return s;
    }
    return null;
  }

  /// The device kind mentioned in [text]; the longest matching keyword wins.
  String? detectDevice(String text) {
    final t = _normalize(text);
    String? best;
    var bestLen = 0;
    devices.forEach((device, keywords) {
      for (final kw in keywords) {
        if (kw.length > bestLen && _contains(t, kw)) {
          best = device;
          bestLen = kw.length;
        }
      }
    });
    return best;
  }

  /// Symptoms mentioned in [text], strongest match first.
  List<Symptom> detectSymptoms(String text) {
    final t = _normalize(text);
    final scored = <(int, Symptom)>[];
    for (final s in symptoms) {
      final score = s.keywords.where((kw) => _contains(t, kw)).fold(0, (n, kw) => n + kw.length);
      if (score > 0) scored.add((score, s));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final (_, s) in scored) s];
  }

  static String _normalize(String text) =>
      ' ${text.toLowerCase().replaceAll('’', "'").replaceAll(RegExp(r'\s+'), ' ')} ';

  /// Whole-word / whole-phrase match, so 'pc' doesn't match 'pcie'.
  static bool _contains(String text, String keyword) =>
      RegExp('(?<![a-z0-9])${RegExp.escape(keyword)}(?![a-z0-9])').hasMatch(text);
}
