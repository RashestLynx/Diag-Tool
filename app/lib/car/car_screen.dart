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
  bool _polling = false;

  // The PIDs we stream live. All are decoded by the tested protocol layer.
  static const _livePids = [0x0C, 0x0D, 0x04, 0x05, 0x0F, 0x11, 0x10, 0x0E,
    0x06, 0x07, 0x0B, 0x42, 0x2F];

  /// Name to show for a scan result. iOS often leaves the cached device name
  /// empty until the first connection, so fall back to the advertised name.
  static String _nameOf(ScanResult r) =>
      r.device.platformName.isNotEmpty ? r.device.platformName : r.advertisementData.advName;

  bool get _supported =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows || Platform.isLinux);

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
      final problem = await _bluetoothProblem();
      if (problem != null) {
        setState(() {
          _stage = _Stage.error;
          _error = problem;
        });
        return;
      }
      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        if (!mounted) return;
        setState(() {
          _found
            ..clear()
            ..addAll(results.where((r) => _nameOf(r).isNotEmpty));
          // Show likely OBD adapters first.
          _found.sort((a, b) {
            final ao = BleObdTransport.looksLikeObd(_nameOf(a)) ? 0 : 1;
            final bo = BleObdTransport.looksLikeObd(_nameOf(b)) ? 0 : 1;
            return ao.compareTo(bo);
          });
        });
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      // startScan returns as soon as scanning begins; wait for the timeout so
      // the button comes back once the scan is over.
      await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
      if (mounted && _stage == _Stage.scanning) setState(() => _stage = _Stage.idle);
    } catch (e) {
      setState(() {
        _stage = _Stage.error;
        _error = 'Could not start Bluetooth scan: $e';
      });
    }
  }

  /// A plain-language reason Bluetooth can't be used right now, or null if it's
  /// ready. On iOS the state starts as "unknown" for a moment, so wait briefly.
  Future<String?> _bluetoothProblem() async {
    if (!await FlutterBluePlus.isSupported) return 'This device has no Bluetooth LE.';
    final state = await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown && s != BluetoothAdapterState.turningOn)
        .first
        .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown);
    switch (state) {
      case BluetoothAdapterState.on:
        return null;
      case BluetoothAdapterState.unauthorized:
        return Platform.isIOS
            ? 'Diag Tool isn\u2019t allowed to use Bluetooth. Turn it on in '
                'Settings \u2192 Diag Tool \u2192 Bluetooth, then scan again.'
            : 'Bluetooth permission was denied. Allow it in the system settings, then scan again.';
      case BluetoothAdapterState.off:
        if (Platform.isAndroid) {
          try {
            await FlutterBluePlus.turnOn();
            return null;
          } catch (_) {}
        }
        return Platform.isIOS
            ? 'Bluetooth is off. Turn it on in Control Center or Settings \u2192 Bluetooth, then scan again.'
            : 'Bluetooth is off. Turn it on, then scan again.';
      default:
        return null; // Unknown/unavailable: let the scan try and report any error.
    }
  }

  Future<void> _connect(ScanResult result) async {
    final device = result.device;
    setState(() {
      _stage = _Stage.connecting;
      _deviceName = _nameOf(result);
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
    // Skip a tick if the last round is still running: a slow BLE link can take
    // longer than the timer period, and overlapping requests garble replies.
    if (conn == null || _polling) return;
    _polling = true;
    try {
      for (final pid in _livePids) {
        if (_conn != conn) return; // disconnected mid-round
        final def = standardPidsByNumber[pid];
        if (def == null) continue;
        final r = await conn.read(def);
        if (r != null && mounted) setState(() => _readings[r.name] = r);
      }
    } catch (_) {
      // Link dropped mid-read; the next tick (or Disconnect) handles it.
    } finally {
      _polling = false;
    }
  }

  Future<void> _disconnect() async {
    _poll?.cancel();
    final conn = _conn;
    _conn = null;
    await conn?.dispose();
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
        if (Platform.isIOS) ...[
          const SizedBox(height: 12),
          Card(
            color: scheme.secondaryContainer,
            child: const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('iPhone needs a Bluetooth LE adapter'),
              subtitle: Text('iPhones can only talk to Bluetooth LE (4.0+) OBD adapters, such as '
                  'Vgate iCar Pro BLE, vLinker MC+ / FS or OBDLink CX / MX+. Cheap '
                  'classic-Bluetooth and Wi-Fi ELM327s won\u2019t show up. Don\u2019t pair it in '
                  'iPhone Settings \u2014 just scan here.'),
            ),
          ),
        ],
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
          final name = _nameOf(r);
          final isObd = BleObdTransport.looksLikeObd(name);
          return Card(
            child: ListTile(
              leading: Icon(isObd ? Icons.car_repair : Icons.bluetooth,
                  color: isObd ? scheme.primary : null),
              title: Text(name),
              // iOS hides the real address; its per-phone UUID means nothing to people.
              subtitle: Platform.isIOS ? null : Text(r.device.remoteId.str),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _connect(r),
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
