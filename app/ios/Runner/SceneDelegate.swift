import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // Attach the controller-info channel to the FlutterViewController that
    // FlutterSceneDelegate just set up as the window's root.
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.rashestlynx.diag_tool/controller_info",
        binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        if call.method == "read" {
          result(ControllerInfoReader.read())
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
