import 'package:diag_tool/reference/reference.dart';
import 'package:flutter_test/flutter_test.dart';

Reference _ref() => Reference.fromJson({
      'apple_models': {
        'iPhone14,5': {'model': 'iPhone 13', 'soc': 'Apple A15 Bionic'},
      },
      'qcom_platforms': {'kona': 'Snapdragon 865'},
      'dtc_fixes': {
        'P0420': {'meaning': 'Catalyst efficiency below threshold', 'fix': 'Check the O2 sensor first.'},
      },
      'apple_year_alphabet': 'CDFGHJKLMNPQRSTVWXYZ',
      'apple_week_alphabet': '123456789CDFGHJKLMNPQRTVWXY',
      'dtc_systems': {
        'P': 'Powertrain (engine/transmission)',
        'C': 'Chassis',
        'B': 'Body',
        'U': 'Network / communication',
      },
      'dtc_p_subsystems': {
        '1': 'fuel & air metering',
        '2': 'fuel & air metering (injector circuit)',
        '3': 'ignition system or misfire',
        '4': 'auxiliary emission controls',
      },
    });

void main() {
  group('Apple model lookup', () {
    final r = _ref();
    test('known product type', () {
      final m = r.appleModel('iPhone14,5');
      expect(m?.model, 'iPhone 13');
      expect(m?.soc, 'Apple A15 Bionic');
    });
    test('trims whitespace, unknown is null', () {
      expect(r.appleModel('  iPhone14,5 ')?.model, 'iPhone 13');
      expect(r.appleModel('iPhone99,9'), isNull);
    });
  });

  group('Car trouble codes', () {
    final r = _ref();
    test('case-insensitive lookup with system', () {
      final d = r.dtc('p0420');
      expect(d?.meaning, startsWith('Catalyst'));
      expect(d?.system, 'Powertrain');
    });
    test('unknown code', () {
      expect(r.dtc('P9999'), isNull);
    });
    test('describeDtc explains any well-formed code', () {
      final d = r.describeDtc('P1345');
      expect(d, contains('Powertrain'));
      expect(d, contains('manufacturer-specific'));
      expect(d, contains('ignition'));
    });
    test('describeDtc rejects junk', () {
      expect(r.describeDtc('hello'), isNull);
      expect(r.describeDtc('P042'), isNull);
    });
    test('describeDtc flags generic codes', () {
      expect(r.describeDtc('P0420'), contains('generic'));
      expect(r.describeDtc('U0100'), contains('Network'));
    });
    test('system from prefix', () {
      expect(DtcCode('C1234', '', '').system, 'Chassis');
      expect(DtcCode('U0100', '', '').system, 'Network');
      expect(DtcCode('B0010', '', '').system, 'Body');
    });
  });

  group('Apple serial date', () {
    final r = _ref();
    test('legacy serial yields a plausible year/week', () {
      final d = r.appleSerialDate('C39XY1234567');
      expect(d, isNotNull);
      expect(d!.year, inInclusiveRange(2010, 2030));
      expect(d.week, inInclusiveRange(1, 53));
    });
    test('new/short serial is not derivable', () {
      expect(r.appleSerialDate('ABCDE12345'), isNull);
    });
  });
}
