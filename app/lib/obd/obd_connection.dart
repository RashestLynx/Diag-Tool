// An OBD-II session on top of any ObdTransport: runs the ELM327 handshake,
// sends requests, and decodes responses with the tested Elm327Protocol parser.
//
// All I/O goes through the injected transport, so this whole class is unit-
// testable with a fake transport (no Bluetooth, no car).

import 'dart:async';
import 'dart:convert';

import 'elm327.dart';
import 'obd_transport.dart';

class ObdConnection {
  ObdConnection(this._transport);

  final ObdTransport _transport;
  final _buffer = StringBuffer();
  StreamSubscription<List<int>>? _sub;
  Completer<String>? _pending;

  bool get isConnected => _transport.isConnected;

  void _attach() {
    _sub ??= _transport.incoming.listen((bytes) {
      _buffer.write(ascii.decode(bytes, allowInvalid: true));
      // The ELM327 ends every response with the '>' prompt.
      if (_buffer.toString().contains('>')) {
        final full = _buffer.toString();
        _buffer.clear();
        final p = _pending;
        _pending = null;
        p?.complete(full.replaceAll('>', '').trim());
      }
    });
  }

  /// Send one command and wait for the adapter's response (up to [timeout]).
  Future<String> command(String cmd, {Duration timeout = const Duration(seconds: 5)}) async {
    _attach();
    if (_pending != null) {
      // Serialize: never two in flight at once.
      try {
        await _pending!.future.timeout(timeout);
      } catch (_) {}
    }
    _buffer.clear();
    final completer = Completer<String>();
    _pending = completer;
    await _transport.write('$cmd\r');
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pending = null;
      return '';
    }
  }

  /// Run the ELM327 init handshake. Returns true if the adapter answered.
  Future<bool> initialize() async {
    var answered = false;
    for (final cmd in elm327InitSequence) {
      final resp = await command(cmd);
      if (resp.isNotEmpty) answered = true;
    }
    return answered;
  }

  /// Read one live PID, or null if the car doesn't report it.
  Future<ObdReading?> read(ObdPid pid) async {
    final resp = await command(pid.request);
    return Elm327Protocol.parseMode01(pid, resp);
  }

  /// Read several PIDs in sequence, skipping ones that don't respond.
  Future<List<ObdReading>> readAll(Iterable<ObdPid> pids) async {
    final out = <ObdReading>[];
    for (final pid in pids) {
      final r = await read(pid);
      if (r != null) out.add(r);
    }
    return out;
  }

  /// Read stored diagnostic trouble codes (mode 03).
  Future<List<String>> readDtcs() async {
    final resp = await command('03');
    return Elm327Protocol.parseDtcs(resp);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _transport.dispose();
  }
}
