import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../obd/ble_transport.dart';
import '../obd/elm327.dart';
import '../obd/obd_connection.dart';
import '../reference/reference.dart';

/// Live car reading over a Bluetooth ELM327 adapter. Experimental: the OBD
/// protocol is tested, but the Bluetooth link needs a real adapter to verify.
class CarScreen extends StatefulWidget {
  const CarScreen({super.key, required this.reference});
  final Reference reference;

  @override
  State<CarScreen> createState() => _CarScreenState();
}

enum _Stage { idle, scanning, connecting, live, error }

class _CarScreenState extends State<CarScreen> {
  _Stage _stage = _Stage.idle;
  String? _error;
  final List<ScanResult> _found = [];
  StreamSubscription<List<ScanResult>>? _scanSub;

  ObdConnection? _conn;
  Timer? _poll;
  final Map<String, ObdReading> _readings = {};
  List<String> _dtcs = [];
  String? _deviceName;

  // The PIDs we stream live. All are decoded by the tested protocol layer.
  static const _livePids = [0x0C, 0x0D, 0x04, 0x05, 0x0F, 0x11, 0x10, 0x0E,
    0x06, 0x07, 0x0B, 0x42, 0x2F];

  bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows);

  @override
  void dispose() {
    _scanSub?.cancel();
    _poll?.cancel();
    _conn?.dispose();
    try {
      FlutterBluePlus.stopScan();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _stage = _Stage.scanning;
      _found.clear();
      _error = null;
    });
    try {
      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        setState(() {
          _found
            ..clear()
            ..addAll(results.where((r) => r.device.platformName.isNotEmpty));
          // Show likely OBD adapters first.
          _found.sort((a, b) {
            final ao = BleObdTransport.looksLikeObd(a.device.platformName) ? 0 : 1;
            final bo = BleObdTransport.looksLikeObd(b.device.platformName) ? 0 : 1;
            return ao.compareTo(bo);
          });
        });
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } catch (e) {
      setState(() {
        _stage = _Stage.error;
        _error = 'Could not start Bluetooth scan: $e';
      });
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() {
      _stage = _Stage.connecting;
      _deviceName = device.platformName;
      _error = null;
    });
    await FlutterBluePlus.stopScan();
    final transport = BleObdTransport(device);
    try {
      await transport.connect();
      final conn = ObdConnection(transport);
      final ok = await conn.initialize();
      if (!ok) throw StateError('The adapter did not respond to the ELM327 handshake.');
      _conn = conn;
      _dtcs = await conn.readDtcs();
      setState(() => _stage = _Stage.live);
      _poll = Timer.periodic(const Duration(milliseconds: 900), (_) => _pollOnce());
    } catch (e) {
      await transport.dispose();
      setState(() {
        _stage = _Stage.error;
        _error = '$e';
      });
    }
  }

  Future<void> _pollOnce() async {
    final conn = _conn;
    if (conn == null) return;
    for (final pid in _livePids) {
      final def = standardPidsByNumber[pid];
      if (def == null) continue;
      final r = await conn.read(def);
      if (r != null && mounted) setState(() => _readings[r.name] = r);
    }
  }

  Future<void> _disconnect() async {
    _poll?.cancel();
    await _conn?.dispose();
    _conn = null;
    setState(() {
      _stage = _Stage.idle;
      _readings.clear();
      _dtcs = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) {
      return _centered(Icons.directions_car_outlined, 'Car reading needs a phone or computer',
          'Open the app on Android/iOS/Windows/macOS and pair a Bluetooth OBD-II (ELM327) '
          'adapter plugged into the car.');
    }
    return switch (_stage) {
      _Stage.live => _liveView(context),
      _Stage.connecting => _busy('Connecting to $_deviceName…'),
      _Stage.scanning || _Stage.idle => _scanView(context),
      _Stage.error => _errorView(context),
    };
  }

  Widget _scanView(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Connect to your car', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Plug a Bluetooth ELM327 adapter into the OBD-II port (under the dash), '
            'turn the ignition on, then scan and tap it.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _stage == _Stage.scanning ? null : _startScan,
          icon: _stage == _Stage.scanning
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.bluetooth_searching),
          label: Text(_stage == _Stage.scanning ? 'Scanning…' : 'Scan for adapter'),
        ),
        const SizedBox(height: 16),
        ..._found.map((r) {
          final isObd = BleObdTransport.looksLikeObd(r.device.platformName);
          return Card(
            child: ListTile(
              leading: Icon(isObd ? Icons.car_repair : Icons.bluetooth,
                  color: isObd ? scheme.primary : null),
              title: Text(r.device.platformName),
              subtitle: Text(r.device.remoteId.str),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _connect(r.device),
            ),
          );
        }),
        const SizedBox(height: 12),
        Text('Experimental: the OBD decoding is tested, but the Bluetooth link '
            'depends on your specific adapter.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _liveView(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final order = _livePids
        .map((p) => standardPidsByNumber[p]?.name)
        .whereType<String>()
        .where(_readings.containsKey)
        .toList();
    return RefreshIndicator(
      onRefresh: () async => _dtcs = await (_conn?.readDtcs() ?? Future.value(_dtcs)),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Icon(Icons.directions_car, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(_deviceName ?? 'Car',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
              TextButton.icon(
                  onPressed: _disconnect, icon: const Icon(Icons.close), label: const Text('Disconnect')),
            ],
          ),
          const SizedBox(height: 12),
          _dtcCard(context),
          const SizedBox(height: 12),
          Text('Live sensors', style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (order.isEmpty)
            const Padding(padding: EdgeInsets.all(8), child: Text('Reading…'))
          else
            GridView.count(
              crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 3 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.7,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [for (final n in order) _gauge(context, _readings[n]!)],
            ),
        ],
      ),
    );
  }

  Widget _gauge(BuildContext context, ObdReading r) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(r.name.replaceAll('_', ' '),
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(r.value.toStringAsFixed(r.value.abs() < 10 ? 1 : 0),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            Text(r.unit, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _dtcCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: _dtcs.isEmpty ? scheme.primaryContainer : scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(_dtcs.isEmpty ? Icons.check_circle : Icons.warning_rounded),
              const SizedBox(width: 8),
              Text(_dtcs.isEmpty ? 'No trouble codes stored' : '${_dtcs.length} trouble code(s)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ]),
            for (final code in _dtcs) ...[
              const SizedBox(height: 10),
              _dtcRow(context, code),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dtcRow(BuildContext context, String code) {
    final known = widget.reference.dtc(code);
    final decoded = widget.reference.describeDtc(code);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$code  ${known?.meaning ?? decoded ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        if (known != null)
          Padding(padding: const EdgeInsets.only(top: 2), child: Text('Fix: ${known.fix}')),
      ],
    );
  }

  Widget _busy(String msg) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(msg),
        ]),
      );

  Widget _errorView(BuildContext context) => _centered(
        Icons.error_outline,
        'Connection problem',
        _error ?? 'Unknown error',
        action: FilledButton(onPressed: () => setState(() => _stage = _Stage.idle),
            child: const Text('Back')),
      );

  Widget _centered(IconData icon, String title, String body, {Widget? action}) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: scheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 24), action],
        ]),
      ),
    );
  }
}
