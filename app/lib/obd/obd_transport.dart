// A transport carries raw bytes to/from an ELM327 adapter. Keeping it an
// interface lets the OBD session logic be tested with a fake transport, with
// the real Bluetooth implementation (ble_transport.dart) swapped in at runtime.

abstract class ObdTransport {
  bool get isConnected;

  /// Write raw ASCII to the adapter (the caller appends '\r').
  Future<void> write(String data);

  /// Bytes arriving from the adapter, as they come.
  Stream<List<int>> get incoming;

  Future<void> dispose();
}
