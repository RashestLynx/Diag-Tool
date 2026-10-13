// Account-recovery knowledge base, loaded from assets/recovery.json.
//
// Generated from phone_info.py (`python diag_tool.py export-json`), so the app
// and the Python tool give the same recovery guidance.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class RecoveryService {
  RecoveryService(this.name, this.url);
  final String name;
  final String url;
}

class Recovery {
  Recovery({
    required this.services,
    required this.checklists,
    required this.backups,
    required this.connect,
    required this.ownershipFields,
  });

  /// Platform ('apple' / 'samsung') -> official recovery services.
  final Map<String, List<RecoveryService>> services;

  /// Platform -> step-by-step account-recovery checklist lines.
  final Map<String, List<String>> checklists;

  /// Platform -> where backups usually live.
  final Map<String, List<String>> backups;

  /// Platform -> official, approval-based data pull from an UNLOCKED device.
  final Map<String, List<String>> connect;

  /// Labels for the ownership-proof sheet.
  final List<String> ownershipFields;

  List<String> get platforms => services.keys.toList();

  static Future<Recovery> load() async =>
      Recovery.fromJson(jsonDecode(await rootBundle.loadString('assets/recovery.json')));

  factory Recovery.fromJson(Map<String, dynamic> j) {
    Map<String, List<String>> lines(String key) => {
          for (final e in (j[key] as Map<String, dynamic>).entries)
            e.key: List<String>.from(e.value as List),
        };
    return Recovery(
      services: {
        for (final e in (j['services'] as Map<String, dynamic>).entries)
          e.key: [
            for (final s in e.value as List)
              RecoveryService(s['name'] as String, s['url'] as String),
          ],
      },
      checklists: lines('checklists'),
      backups: lines('backups'),
      connect: lines('connect'),
      ownershipFields: List<String>.from(j['ownership_fields'] as List),
    );
  }
}

const recoveryPlatformLabels = {'apple': 'Apple (iPhone / iPad)', 'samsung': 'Samsung / Android'};
