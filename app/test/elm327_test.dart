import 'package:diag_tool/obd/elm327.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cleanHexBytes', () {
    test('strips prompt, echo noise and whitespace', () {
      expect(Elm327Protocol.cleanHexBytes('41 0C 1A F8 \r\r>'), [0x41, 0x0C, 0x1A, 0xF8]);
    });
    test('handles runs with no spaces (ATS0 mode)', () {
      expect(Elm327Protocol.cleanHexBytes('410C1AF8'), [0x41, 0x0C, 0x1A, 0xF8]);
    });
    test('drops SEARCHING... banner', () {
      expect(Elm327Protocol.cleanHexBytes('SEARCHING...\r41 05 5A'), [0x41, 0x05, 0x5A]);
    });
  });

  group('mode 01 decoders', () {
    ObdPid pid(String name) => standardPids.firstWhere((p) => p.name == name);

    test('RPM: 41 0C 1A F8 -> 1726 rpm', () {
      final r = Elm327Protocol.parseMode01(pid('RPM'), '41 0C 1A F8');
      expect(r, isNotNull);
      expect(r!.value, closeTo(1726, 0.01)); // (0x1AF8)/4
      expect(r.unit, 'rpm');
    });

    test('coolant: 41 05 7B -> 83 C', () {
      final r = Elm327Protocol.parseMode01(pid('COOLANT_TEMP'), '41 05 7B');
      expect(r!.value, closeTo(123 - 40, 0.001)); // 0x7B=123 -> 83
    });

    test('speed: 41 0D 40 -> 64 km/h', () {
      expect(Elm327Protocol.parseMode01(pid('SPEED'), '41 0D 40')!.value, 64);
    });

    test('throttle %: 41 11 FF -> 100%', () {
      expect(Elm327Protocol.parseMode01(pid('THROTTLE_POS'), '41 11 FF')!.value,
          closeTo(100, 0.001));
    });

    test('fuel trim: 41 06 80 -> 0%, 41 06 90 -> +12.5%', () {
      expect(Elm327Protocol.parseMode01(pid('SHORT_FUEL_TRIM_1'), '41 06 80')!.value, 0);
      expect(Elm327Protocol.parseMode01(pid('SHORT_FUEL_TRIM_1'), '41 06 90')!.value,
          closeTo(12.5, 0.001)); // (144-128)*100/128
    });

    test('timing advance: 41 0E 80 -> 0 deg', () {
      expect(Elm327Protocol.parseMode01(pid('TIMING_ADVANCE'), '41 0E 80')!.value, 0);
    });

    test('module voltage: 41 42 36 B0 -> ~14.0 V', () {
      expect(Elm327Protocol.parseMode01(pid('CONTROL_MODULE_VOLTAGE'), '41 42 36 B0')!.value,
          closeTo(14.0, 0.01)); // 0x36B0 = 14000 /1000
    });

    test('parses even with the header echoed and extra bytes around it', () {
      final r = Elm327Protocol.parseMode01(pid('RPM'), '7E8 04 41 0C 1A F8');
      expect(r, isNotNull);
      expect(r!.value, closeTo(1726, 0.01));
    });

    test('NO DATA yields null', () {
      expect(Elm327Protocol.parseMode01(pid('RPM'), 'NO DATA'), isNull);
    });

    test('wrong pid in response yields null', () {
      expect(Elm327Protocol.parseMode01(pid('RPM'), '41 05 7B'), isNull);
    });
  });

  group('request encoding', () {
    test('builds the mode01 request string', () {
      expect(standardPidsByNumber[0x0C]!.request, '010C');
      expect(standardPidsByNumber[0x05]!.request, '0105');
    });
  });

  group('DTC parsing (mode 03)', () {
    test('decodes P0301 and P0420', () {
      // 43 02 <0301> <0420>
      final codes = Elm327Protocol.parseDtcs('43 02 03 01 04 20');
      expect(codes, containsAll(['P0301', 'P0420']));
    });

    test('maps the letter bits (U0100)', () {
      // U = 11 in top two bits -> 0xC1 0x00
      expect(Elm327Protocol.parseDtcs('43 01 C1 00'), ['U0100']);
    });

    test('skips empty 00 00 slots', () {
      expect(Elm327Protocol.parseDtcs('43 01 03 01 00 00'), ['P0301']);
    });

    test('NO DATA -> no codes', () {
      expect(Elm327Protocol.parseDtcs('NO DATA'), isEmpty);
    });
  });
}
