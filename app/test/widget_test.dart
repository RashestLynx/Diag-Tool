import 'package:diag_tool/identify.dart';
import 'package:diag_tool/knowledge.dart';
import 'package:diag_tool/scan/report.dart';
import 'package:flutter_test/flutter_test.dart';

// A small knowledge base so the detection/matching tests don't need assets.
Knowledge _kb() => Knowledge.fromJson({
      'devices': {
        'phone': ['phone', 'iphone'],
        'laptop': ['laptop', 'macbook'],
        'router': ['router'],
      },
      'symptoms': [
        {
          'key': 'not_charging',
          'title': "Won't charge",
          'keywords': ["won't charge", 'not charging'],
          'devices': ['phone', 'laptop'],
          'causes': [
            {'name': 'Lint in port', 'likelihood': 5, 'fixes': ['Clean it'], 'devices': ['phone'], 'warning': null},
            {'name': 'Bad cable', 'likelihood': 4, 'fixes': ['Swap cable'], 'devices': null, 'warning': null},
          ],
        },
        {
          'key': 'no_power',
          'title': "Won't turn on",
          'keywords': ['dead', "won't turn on"],
          'devices': null,
          'causes': [
            {'name': 'PSU', 'likelihood': 3, 'fixes': ['Test PSU'], 'devices': ['router'], 'warning': null},
            {'name': 'Battery', 'likelihood': 5, 'fixes': ['Charge it'], 'devices': ['phone'], 'warning': null},
          ],
        },
      ],
    });

void main() {
  group('device detection', () {
    final kb = _kb();
    test('finds the device kind', () {
      expect(kb.detectDevice("my iphone won't charge"), 'phone');
      expect(kb.detectDevice('the router is dead'), 'router');
    });
    test('whole-word only', () {
      expect(kb.detectDevice('iphoneography'), isNull);
    });
    test('unknown returns null', () {
      expect(kb.detectDevice('it broke'), isNull);
    });
  });

  group('symptom detection', () {
    final kb = _kb();
    test('matches keywords', () {
      final keys = kb.detectSymptoms("won't charge").map((s) => s.key);
      expect(keys, contains('not_charging'));
    });
    test('curly apostrophe normalized', () {
      final keys = kb.detectSymptoms('laptop won’t turn on').map((s) => s.key);
      expect(keys, contains('no_power'));
    });
    test('no match', () {
      expect(kb.detectSymptoms('blah'), isEmpty);
    });
  });

  group('causesFor', () {
    final kb = _kb();
    test('sorted by likelihood, filtered by device', () {
      final causes = kb.symptom('no_power')!.causesFor('phone');
      expect(causes.map((c) => c.name), ['Battery']); // PSU is router-only
      expect(causes.first.likelihoodLabel, 'Very likely');
    });
    test('null device keeps everything', () {
      expect(kb.symptom('no_power')!.causesFor(null).length, 2);
    });
  });

  group('IMEI / serial', () {
    test('valid IMEI', () {
      final info = ImeiInfo.parse('49-015420-323751-8');
      expect(info.digits, '490154203237518');
      expect(info.lengthOk, isTrue);
      expect(info.validChecksum, isTrue);
      expect(info.tac, '49015420');
    });
    test('bad checksum', () {
      expect(ImeiInfo.parse('490154203237519').validChecksum, isFalse);
    });
    test('apple serial plausibility', () {
      expect(SerialInfo('c39xy1234567').plausibleApple, isTrue);
      expect(SerialInfo('short').plausibleApple, isFalse);
      expect(SerialInfo('c39xy1234567').normalized, 'C39XY1234567');
    });
  });

  group('scan analysis', () {
    test('flags a nearly full disk', () {
      final r = DeviceReport()
        ..diskTotal = 100 * 1024 * 1024 * 1024
        ..diskFree = 2 * 1024 * 1024 * 1024;
      final problem = analyze(r).firstWhere((f) => f.title == 'Storage almost full');
      expect(problem.level, Level.problem);
      expect(problem.symptomKey, 'storage_full');
    });
    test('healthy disk is OK', () {
      final r = DeviceReport()
        ..diskTotal = 100 * 1024 * 1024 * 1024
        ..diskFree = 60 * 1024 * 1024 * 1024;
      expect(analyze(r).firstWhere((f) => f.title == 'Storage').level, Level.ok);
    });
    test('worn battery warned', () {
      final r = DeviceReport()..batteryCapacityPct = 62..batteryLevel = 90;
      expect(analyze(r).firstWhere((f) => f.title == 'Battery worn out').level, Level.warn);
    });
    test('skips RAM detail on phones', () {
      final r = DeviceReport()
        ..kind = 'phone'
        ..memTotal = 8 * 1024 * 1024 * 1024
        ..memFree = 200 * 1024 * 1024;
      // mobile: shows installed RAM as info, never a "nearly full" problem
      expect(analyze(r).where((f) => f.title.contains('RAM') && f.level == Level.problem), isEmpty);
    });
    test('formatBytes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(5 * 1024 * 1024 * 1024), '5.0 GB');
    });
  });
}
