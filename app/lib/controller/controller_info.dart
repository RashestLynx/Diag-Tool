import 'package:flutter/services.dart';

/// Native controller battery + DualSense touchpad, read over a platform channel
/// backed by Apple's GameController framework (iOS/macOS only).
///
/// On platforms without the native handler (Android, Windows, Linux) the
/// channel isn't registered, so [read] returns null and callers hide the
/// feature. Everything here is best-effort and never throws to the caller.
class ControllerInfo {
  static const _channel = MethodChannel('com.rashestlynx.diag_tool/controller_info');

  final int? batteryLevel; // percent, 0..100
  final String? batteryState; // charging | full | discharging | unknown
  final bool hasTouchpad;
  final double touchpadX; // -1..1
  final double touchpadY; // -1..1
  final bool touchpadTouching;
  final bool touchpadButton;

  const ControllerInfo({
    this.batteryLevel,
    this.batteryState,
    this.hasTouchpad = false,
    this.touchpadX = 0,
    this.touchpadY = 0,
    this.touchpadTouching = false,
    this.touchpadButton = false,
  });

  bool get hasBattery => batteryLevel != null;

  /// Returns the latest reading, or null if the platform has no native handler.
  static Future<ControllerInfo?> read() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('read');
      if (map == null || map['connected'] != true) return null;
      return ControllerInfo(
        batteryLevel: (map['batteryLevel'] as num?)?.toInt(),
        batteryState: map['batteryState'] as String?,
        hasTouchpad: map['hasTouchpad'] == true,
        touchpadX: (map['touchpadX'] as num?)?.toDouble() ?? 0,
        touchpadY: (map['touchpadY'] as num?)?.toDouble() ?? 0,
        touchpadTouching: map['touchpadTouching'] == true,
        touchpadButton: map['touchpadButton'] == true,
      );
    } on MissingPluginException {
      return null; // no native handler on this platform
    } catch (_) {
      return null;
    }
  }
}
