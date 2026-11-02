import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // TokenBar lives in the menu bar: closing the window hides it (see
  // DesktopIntegration.onWindowClose) and the app keeps running. Quit comes from
  // the tray menu or Cmd+Q, which the Dart side handles.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // macOS already keeps a single instance of the app; launching it again (Finder,
  // Dock icon, `open`) only "reopens" the running one. Since the window is hidden
  // while the app lives in the menu bar, bring it back here. Dart restores the
  // window (it knows about tray-panel mode); fall back to a plain native show.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    guard !flag else { return true }
    let flutterWindow = NSApp.windows.first { $0.contentViewController is FlutterViewController }
    guard let controller = flutterWindow?.contentViewController as? FlutterViewController else {
      return true
    }
    let channel = FlutterMethodChannel(
      name: "tokenbar/instance", binaryMessenger: controller.engine.binaryMessenger)
    channel.invokeMethod("activate", arguments: nil) { result in
      if let error = result as? FlutterError {
        NSLog("TokenBar: activate failed: \(error.message ?? "")")
      }
      if (result as? NSObject) === FlutterMethodNotImplemented {
        NSApp.activate(ignoringOtherApps: true)
        flutterWindow?.makeKeyAndOrderFront(nil)
      }
    }
    return true
  }
}
