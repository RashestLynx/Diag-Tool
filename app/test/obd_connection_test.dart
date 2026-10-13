import 'dart:async';
import 'dart:convert';

import 'package:diag_tool/obd/elm327.dart';
import 'package:diag_tool/obd/obd_connection.dart';
import 'package:diag_tool/obd/obd_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake adapter: for each command written, it replies with a canned string
/// (plus the '>' prompt) so the session logic can be tested with no hardware.
class FakeTransport implements ObdTransport {
  FakeTransport(this.replies);
  final Map<String, String> replies;
  final _ctrl = StreamController<List<int>>.broadcast();
  final writes = <String>[];

  @override
  bool get isConnected => true;

  @override
  Stream<List<int>> get incoming => _ctrl.stream;

  @override
  Future<void> write(String data) async {
    writes.add(data.trim());
    final reply = replies[data.trim()] ?? 'NO DATA';
    // Deliver asynchronously, ending with the ELM327 prompt.
    scheduleMicrotask(() => _ctrl.add(ascii.encode('$reply\r>')));
  }

  @override
  Future<void> dispose() async => _ctrl.close();
}

void main() {
  test('initialize runs the handshake and reports the adapter answered', () async {
    final t = FakeTransport({for (final c in elm327InitSequence) c: 'OK'});
    final conn = ObdConnection(t);
    expect(await conn.initialize(), isTrue);
    expect(t.writes, containsAll(elm327InitSequence));
    await conn.dispose();
  });

  test('read decodes a live PID', () async {
    final t = FakeTransport({'010C': '41 0C 1A F8'}); // RPM 1726
    final conn = ObdConnection(t);
    final r = await conn.read(standardPidsByNumber[0x0C]!);
    expect(r, isNotNull);
    expect(r!.value, closeTo(1726, 0.01));
    await conn.dispose();
  });

  test('read returns null when the car has no such PID', () async {
    final t = FakeTransport({'0105': 'NO DATA'});
    final conn = ObdConnection(t);
    expect(await conn.read(standardPidsByNumber[0x05]!), isNull);
    await conn.dispose();
  });

  test('readAll skips unsupported PIDs', () async {
    final t = FakeTransport({
      '010C': '41 0C 1A F8', // RPM ok
      '010D': 'NO DATA', // speed missing
      '0105': '41 05 7B', // coolant 83C
    });
    final conn = ObdConnection(t);
    final out = await conn.readAll([
      standardPidsByNumber[0x0C]!,
      standardPidsByNumber[0x0D]!,
      standardPidsByNumber[0x05]!,
    ]);
    expect(out.map((r) => r.name), ['RPM', 'COOLANT_TEMP']);
    await conn.dispose();
  });

  test('readDtcs parses stored codes', () async {
    final t = FakeTransport({'03': '43 02 03 01 04 20'});
    final conn = ObdConnection(t);
    expect(await conn.readDtcs(), containsAll(['P0301', 'P0420']));
    await conn.dispose();
  });

  test('command times out cleanly when the adapter never answers', () async {
    final t = FakeTransport({}); // every unknown cmd -> 'NO DATA', but test an ignored one
    // Override write to swallow (simulate silence) for this case:
    final conn = ObdConnection(_SilentTransport());
    final resp = await conn.command('0100', timeout: const Duration(milliseconds: 50));
    expect(resp, '');
    await conn.dispose();
    await t.dispose();
  });
}

class _SilentTransport implements ObdTransport {
  final _ctrl = StreamController<List<int>>.broadcast();
  @override
  bool get isConnected => true;
  @override
  Stream<List<int>> get incoming => _ctrl.stream;
  @override
  Future<void> write(String data) async {} // never replies
  @override
  Future<void> dispose() async => _ctrl.close();
}
