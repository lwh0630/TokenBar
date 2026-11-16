import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // dart:io ignores the macOS system proxy (it only reads env vars), so
    // hand the CFNetwork configuration to Dart; see lib/services/system_proxy.dart.
    let proxyChannel = FlutterMethodChannel(
      name: "dev.tokenbar.app/system_proxy",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    proxyChannel.setMethodCallHandler { call, result in
      if call.method == "get" {
        guard
          let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue()
            as? [String: Any]
        else {
          result(nil)
          return
        }
        result(settings)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
