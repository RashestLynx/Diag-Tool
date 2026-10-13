// What we know about the device the app is running on, and what's wrong with it.
//
// This file is pure Dart (no plugins), so the rules can be unit-tested.

enum Level { ok, warn, problem, info }

class Finding {
  Finding(this.level, this.title, this.detail, {this.fixes = const [], this.symptomKey});

  final Level level;
  final String title;
  final String detail;

  /// Quick fixes shown right under the finding.
  final List<String> fixes;

  /// Knowledge-base symptom with the full list of causes and fixes, if any.
  final String? symptomKey;
}

class DeviceReport {
  /// 'phone', 'tablet', 'laptop' or 'desktop' (matches knowledge.json kinds).
  String kind = 'desktop';

  /// Extra detail about the kind, e.g. 'virtual machine' or 'convertible'.
  String? kindDetail;
  String? makeModel;
  String os = '';

  int? batteryLevel; // percent
  bool? pluggedIn;
  bool? lowPowerMode;

  /// Battery health as a text grade from the OS ('good', 'overheat', 'Poor', ...).
  String? batteryHealth;

  /// Battery capacity left compared to new, in percent.
  int? batteryCapacityPct;
  double? batteryTempC;
  int? batteryCycles;

  int? diskTotal; // bytes
  int? diskFree;
  int? memTotal;
  int? memFree;

  /// 'nominal', 'fair', 'serious' or 'critical'.
  String? thermal;
  Duration? uptime;

  bool get isMobile => kind == 'phone' || kind == 'tablet';
}

String formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var n = bytes.toDouble();
  var i = 0;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  return '${n.toStringAsFixed(n < 10 && i > 0 ? 1 : 0)} ${units[i]}';
}

List<Finding> analyze(DeviceReport r) {
  final out = <Finding>[];

  // Storage
  if (r.diskTotal != null && r.diskFree != null && r.diskTotal! > 0) {
    final usedPct = 100 * (r.diskTotal! - r.diskFree!) / r.diskTotal!;
    final detail =
        '${usedPct.round()}% used - ${formatBytes(r.diskFree!)} free of ${formatBytes(r.diskTotal!)}';
    if (usedPct >= 95) {
      out.add(Finding(Level.problem, 'Storage almost full', detail,
          fixes: [
            'A nearly full device gets slow and can fail to install updates.',
            'Delete large unused apps, old videos and downloads, or move them to cloud storage.',
          ],
          symptomKey: 'storage_full'));
    } else if (usedPct >= 85) {
      out.add(Finding(Level.warn, 'Storage getting full', detail,
          fixes: ['Free up some space soon - aim for at least 15% free.'],
          symptomKey: 'storage_full'));
    } else {
      out.add(Finding(Level.ok, 'Storage', detail));
    }
  }

  // Memory. Phones and tablets deliberately keep RAM full, so only report it there.
  if (r.memTotal != null && r.memTotal! > 0) {
    if (r.memFree != null && !r.isMobile) {
      final usedPct = 100 * (r.memTotal! - r.memFree!) / r.memTotal!;
      final detail =
          '${usedPct.round()}% used - ${formatBytes(r.memFree!)} free of ${formatBytes(r.memTotal!)}';
      if (usedPct >= 90) {
        out.add(Finding(Level.problem, 'Memory (RAM) nearly full', detail,
            fixes: [
              'Close programs and browser tabs you are not using.',
              'Restart to clear memory leaks.',
              'If it is always this high, the computer needs more RAM.',
            ],
            symptomKey: 'slow'));
      } else if (usedPct >= 75) {
        out.add(Finding(Level.warn, 'Memory (RAM) busy', detail,
            fixes: ['Close unused apps if things feel slow.'], symptomKey: 'slow'));
      } else {
        out.add(Finding(Level.ok, 'Memory (RAM)', detail));
      }
    } else {
      out.add(Finding(Level.info, 'Memory (RAM)', '${formatBytes(r.memTotal!)} installed'));
    }
  }

  // Temperature
  final hotBattery = r.batteryTempC != null && r.batteryTempC! >= 45;
  if (r.thermal == 'critical' || r.thermal == 'serious' || hotBattery) {
    final parts = [
      if (r.thermal != null) 'thermal state: ${r.thermal}',
      if (r.batteryTempC != null) 'battery ${r.batteryTempC!.toStringAsFixed(0)} °C',
    ];
    out.add(Finding(
        r.thermal == 'critical' || (r.batteryTempC ?? 0) >= 50 ? Level.problem : Level.warn,
        'Running hot',
        parts.join(', '),
        fixes: [
          'Stop games/video and close heavy apps for a few minutes.',
          if (r.isMobile) 'Take it out of its case and out of the sun; unplug the charger.',
          if (!r.isMobile) 'Use it on a hard surface and make sure the vents are clear of dust.',
        ],
        symptomKey: 'overheating'));
  } else if (r.thermal != null || r.batteryTempC != null) {
    out.add(Finding(Level.ok, 'Temperature', [
      if (r.thermal != null) 'thermal state: ${r.thermal}',
      if (r.batteryTempC != null) 'battery ${r.batteryTempC!.toStringAsFixed(0)} °C',
    ].join(', ')));
  }

  // Battery
  if (r.batteryLevel != null || r.batteryHealth != null || r.batteryCapacityPct != null) {
    final parts = [
      if (r.batteryLevel != null) '${r.batteryLevel}% charged',
      if (r.pluggedIn != null) r.pluggedIn! ? 'plugged in' : 'on battery',
      if (r.lowPowerMode == true) 'low power mode on',
      if (r.batteryCapacityPct != null) 'holds ${r.batteryCapacityPct}% of its original charge',
      if (r.batteryHealth != null) 'health: ${r.batteryHealth}',
      if (r.batteryCycles != null && r.batteryCycles! >= 0) '${r.batteryCycles} charge cycles',
    ];
    final detail = parts.join(', ');
    final health = r.batteryHealth?.toLowerCase();
    if (health == 'dead' || health == 'failure' || health == 'over_voltage') {
      out.add(Finding(Level.problem, 'Battery has failed', detail,
          fixes: [
            'The system reports the battery as faulty - get it replaced.',
            'If the case is bulging, stop using and charging it now (fire risk).',
          ],
          symptomKey: 'swollen_battery'));
    } else if ((r.batteryCapacityPct != null && r.batteryCapacityPct! < 80) ||
        health == 'poor' ||
        health == 'check battery' ||
        health == 'service recommended') {
      out.add(Finding(Level.warn, 'Battery worn out', detail,
          fixes: [
            'A worn battery runs down faster and can shut the device off early.',
            'Battery replacement fixes this - usually much cheaper than a new device.',
          ],
          symptomKey: 'battery_drain'));
    } else if (r.batteryLevel != null && r.batteryLevel! <= 15 && r.pluggedIn != true) {
      out.add(Finding(Level.warn, 'Battery low', detail, fixes: ['Plug in the charger.']));
    } else {
      out.add(Finding(Level.ok, 'Battery', detail));
    }
  }

  // Uptime
  if (r.uptime != null) {
    final days = r.uptime!.inHours / 24;
    final detail = days >= 1
        ? 'on for ${days.toStringAsFixed(1)} days since the last restart'
        : 'on for ${r.uptime!.inHours} h ${r.uptime!.inMinutes % 60} min since the last restart';
    if (days >= 14) {
      out.add(Finding(Level.warn, "Hasn't restarted in a while", detail,
          fixes: ['Restart it - this clears stuck apps and memory and finishes updates.']));
    } else {
      out.add(Finding(Level.ok, 'Restarted recently', detail));
    }
  }

  return out;
}
