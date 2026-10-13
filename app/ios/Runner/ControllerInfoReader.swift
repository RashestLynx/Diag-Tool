import Foundation
import GameController

// Reads controller battery and DualSense touchpad position through Apple's
// GameController framework (iOS 14+ / macOS 11+ for battery). Shared verbatim
// by the iOS and macOS Runner targets.
//
// Returns nil fields when a value isn't available (e.g. battery on an older OS,
// or touchpad on a non-DualSense controller), so the Dart side can degrade.
enum ControllerInfoReader {
  static func read() -> [String: Any] {
    var result: [String: Any] = [:]

    // Prefer the controller the system considers current, else the first one.
    let controller = GCController.current ?? GCController.controllers().first
    guard let controller = controller else {
      result["connected"] = false
      return result
    }
    result["connected"] = true
    result["name"] = controller.vendorName ?? "Controller"

    if #available(iOS 14.0, macOS 11.0, tvOS 14.0, *) {
      if let battery = controller.battery {
        let level = battery.batteryLevel // 0.0...1.0, or negative if unknown
        if level >= 0 {
          result["batteryLevel"] = Int((level * 100).rounded())
        }
        switch battery.batteryState {
        case .charging: result["batteryState"] = "charging"
        case .full: result["batteryState"] = "full"
        case .discharging: result["batteryState"] = "discharging"
        default: result["batteryState"] = "unknown"
        }
      }
    }

    // DualSense touchpad: a direction-pad element with x/y in -1...1.
    if let dualSense = controller.extendedGamepad as? GCDualSenseGamepad {
      let pad = dualSense.touchpadPrimary
      let x = pad.xAxis.value
      let y = pad.yAxis.value
      result["touchpadX"] = x
      result["touchpadY"] = y
      result["touchpadTouching"] = (x != 0 || y != 0)
      result["touchpadButton"] = dualSense.touchpadButton.isPressed
      result["hasTouchpad"] = true
    } else {
      result["hasTouchpad"] = false
    }

    return result
  }
}
