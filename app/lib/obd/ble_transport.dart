// Bluetooth LE transport for an ELM327 OBD-II adapter, built on
// flutter_blue_plus. This is the one piece that can't be unit-tested without a
// real adapter; the OBD session logic it feeds (ObdConnection) is fully tested.
//
// Most BLE ELM327 clones expose a serial-like service (commonly FFF0 / FFE0)
// with one characteristic for writing commands and one that notifies replies -
// sometimes the same characteristic. We auto-pick by characteristic properties,
// preferring a known ELM327 service that has both (see pickSerialPair).
//
// BLE is the only kind of adapter an iPhone can use: iOS apps can't open
// classic-Bluetooth serial (SPP) links, so classic ELM327s never show up there.

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
    final pair = pickSerialPair([
      for (final s in services)
        BleServiceInfo(s.serviceUuid.str128, [
          for (final c in s.characteristics)
            BleCharInfo(
              c.characteristicUuid.str128,
              write: c.properties.write || c.properties.writeWithoutResponse,
              notify: c.properties.notify || c.properties.indicate,
            ),
        ]),
    ]);
    if (pair != null) {
      final chars = services[pair.service].characteristics;
      _writeChar = chars[pair.write];
      _notifyChar = chars[pair.notify];
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

  /// Known ELM327 serial service UUIDs (16-bit ones in 128-bit form), best first.
  static const knownServices = [
    '0000fff0-0000-1000-8000-00805f9b34fb', // most clones
    '0000ffe0-0000-1000-8000-00805f9b34fb', // HM-10 style modules
    'e7810a71-73ae-499d-8c15-faa9aef0c3f2', // Vgate / vLinker
    '000018f0-0000-1000-8000-00805f9b34fb', // some Vgate iCar Pro units
  ];

  /// Standard services that are never the adapter's serial link.
  static const _systemServices = {
    '00001800-0000-1000-8000-00805f9b34fb', // Generic Access
    '00001801-0000-1000-8000-00805f9b34fb', // Generic Attribute
    '0000180a-0000-1000-8000-00805f9b34fb', // Device Information
    '0000180f-0000-1000-8000-00805f9b34fb', // Battery
  };

  /// Pick the write + notify characteristics to talk over. Prefers a known
  /// ELM327 service, then any other service that has both, so a stray
  /// notify characteristic in an unrelated service is never chosen.
  static ({int service, int write, int notify})? pickSerialPair(List<BleServiceInfo> services) {
    int rank(String uuid) {
      final i = knownServices.indexOf(uuid.toLowerCase());
      return i >= 0 ? i : knownServices.length;
    }

    final order = [
      for (var i = 0; i < services.length; i++)
        if (!_systemServices.contains(services[i].uuid.toLowerCase())) i,
    ]..sort((a, b) => rank(services[a].uuid).compareTo(rank(services[b].uuid)));
    for (final si in order) {
      final chars = services[si].chars;
      final w = chars.indexWhere((c) => c.write);
      final n = chars.indexWhere((c) => c.notify);
      if (w >= 0 && n >= 0) return (service: si, write: w, notify: n);
    }
    return null;
  }

  /// True if a device's advertised name looks like an OBD adapter.
  static bool looksLikeObd(String name) {
    final n = name.toLowerCase();
    return n.contains('obd') || n.contains('elm') || n.contains('vgate') ||
        n.contains('viecar') || n.contains('konnwei') || n.contains('ios-vlink') ||
        n.contains('vlink') || n.contains('scan');
  }
}

/// Plain description of a GATT service, so [BleObdTransport.pickSerialPair]
/// can be unit-tested without a real Bluetooth device.
class BleServiceInfo {
  const BleServiceInfo(this.uuid, this.chars);
  final String uuid;
  final List<BleCharInfo> chars;
}

class BleCharInfo {
  const BleCharInfo(this.uuid, {this.write = false, this.notify = false});
  final String uuid;
  final bool write;
  final bool notify;
}
