// Bluetooth LE transport for an ELM327 OBD-II adapter, built on
// flutter_blue_plus. This is the one piece that can't be unit-tested without a
// real adapter; the OBD session logic it feeds (ObdConnection) is fully tested.
//
// Most BLE ELM327 clones expose a serial-like service (commonly FFF0 / FFE0)
// with one characteristic for writing commands and one that notifies replies -
// sometimes the same characteristic. We auto-pick by characteristic properties.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'obd_transport.dart';

class BleObdTransport implements ObdTransport {
  BleObdTransport(this.device);

  final BluetoothDevice device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>? _notifySub;
  final _incoming = StreamController<List<int>>.broadcast();
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  /// Connect, discover services, and wire up the read/write characteristics.
  /// Throws if no usable characteristics are found.
  Future<void> connect({Duration timeout = const Duration(seconds: 15)}) async {
    await device.connect(license: License.nonprofit, timeout: timeout, autoConnect: false);
    final services = await device.discoverServices();
    for (final s in services) {
      for (final c in s.characteristics) {
        final p = c.properties;
        if (_notifyChar == null && (p.notify || p.indicate)) _notifyChar = c;
        if (_writeChar == null && (p.write || p.writeWithoutResponse)) _writeChar = c;
      }
    }
    if (_writeChar == null || _notifyChar == null) {
      await device.disconnect();
      throw StateError('No ELM327-style serial characteristics found on this device.');
    }
    await _notifyChar!.setNotifyValue(true);
    _notifySub = _notifyChar!.lastValueStream.listen((v) {
      if (v.isNotEmpty) _incoming.add(v);
    });
    _connected = true;
  }

  @override
  Future<void> write(String data) async {
    final c = _writeChar;
    if (c == null) throw StateError('Not connected.');
    final withoutResponse = c.properties.writeWithoutResponse && !c.properties.write;
    await c.write(ascii.encode(data), withoutResponse: withoutResponse);
  }

  @override
  Future<void> dispose() async {
    _connected = false;
    await _notifySub?.cancel();
    _notifySub = null;
    try {
      await device.disconnect();
    } catch (_) {}
    await _incoming.close();
  }

  /// True if a device's advertised name looks like an OBD adapter.
  static bool looksLikeObd(String name) {
    final n = name.toLowerCase();
    return n.contains('obd') || n.contains('elm') || n.contains('vgate') ||
        n.contains('viecar') || n.contains('konnwei') || n.contains('ios-vlink') ||
        n.contains('vlink') || n.contains('scan');
  }
}
