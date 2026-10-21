import 'package:diag_tool/obd/ble_transport.dart';
import 'package:flutter_test/flutter_test.dart';

String _u16(String short) => '0000$short-0000-1000-8000-00805f9b34fb';

void main() {
  group('pickSerialPair', () {
    test('uses the FFF0 service with separate write/notify characteristics', () {
      final pick = BleObdTransport.pickSerialPair([
        BleServiceInfo(_u16('fff0'), [
          BleCharInfo(_u16('fff1'), notify: true),
          BleCharInfo(_u16('fff2'), write: true),
        ]),
      ]);
      expect(pick, (service: 0, write: 1, notify: 0));
    });

    test('ignores Generic Attribute "Service Changed" indications', () {
      final pick = BleObdTransport.pickSerialPair([
        BleServiceInfo(_u16('1801'), [BleCharInfo(_u16('2a05'), notify: true)]),
        BleServiceInfo(_u16('ffe0'), [BleCharInfo(_u16('ffe1'), write: true, notify: true)]),
      ]);
      expect(pick, (service: 1, write: 0, notify: 0));
    });

    test('prefers a known ELM327 service over an unknown one listed first', () {
      final pick = BleObdTransport.pickSerialPair([
        BleServiceInfo('12345678-1234-1234-1234-123456789abc', [
          BleCharInfo('aaaa', write: true, notify: true),
        ]),
        BleServiceInfo('E7810A71-73AE-499D-8C15-FAA9AEF0C3F2', [
          BleCharInfo('bef8d6c9-9c21-4c9e-b632-bd58c1009f9f', write: true, notify: true),
        ]),
      ]);
      expect(pick?.service, 1);
    });

    test('never splits write and notify across different services', () {
      final pick = BleObdTransport.pickSerialPair([
        BleServiceInfo('aaaa', [BleCharInfo('a1', notify: true)]),
        BleServiceInfo('bbbb', [BleCharInfo('b1', write: true)]),
      ]);
      expect(pick, isNull);
    });

    test('falls back to any unknown service that has both', () {
      final pick = BleObdTransport.pickSerialPair([
        BleServiceInfo(_u16('180a'), [BleCharInfo(_u16('2a29'))]),
        BleServiceInfo('cccc', [
          BleCharInfo('c1', write: true),
          BleCharInfo('c2', notify: true),
        ]),
      ]);
      expect(pick, (service: 1, write: 0, notify: 1));
    });
  });
}
