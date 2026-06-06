import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
  var window: NSWindow!
  let displayManager = DisplayManager()
  private var isApplyingTerminationPolicy = false

  private func moveWindowToExternalDisplay() {
    guard let window = window else { return }
    if let externalScreen = NSScreen.screens.first(where: {
      guard
        let screenNumber = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
          as? CGDirectDisplayID
      else { return false }
      return CGDisplayIsBuiltin(screenNumber) == 0
    }) {
      let screenFrame = externalScreen.visibleFrame
      let windowSize = window.frame.size
      let x = screenFrame.midX - windowSize.width / 2
      let y = screenFrame.midY - windowSize.height / 2
      window.setFrameOrigin(NSPoint(x: x, y: y))
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Single instance check: if already running, activate the existing instance and quit
    let bundleID = Bundle.main.bundleIdentifier ?? "com.local.DisableMainDisplay"
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    if running.count > 1 {
      // Another instance is already running — activate it and quit this one
      for app in running where app != NSRunningApplication.current {
        app.activate()
      }
      NSApp.terminate(nil)
      return
    }

    let contentView = ContentView(displayManager: displayManager)

    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 380, height: 250),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "DisableMainDisplay"
    window.contentView = NSHostingView(rootView: contentView)

    // Place window on an external display (not the built-in)
    moveWindowToExternalDisplay()

    // When lid opens, move window to external display
    displayManager.onBuiltInDisplayAppeared = { [weak self] in
      self?.moveWindowToExternalDisplay()
    }

    window.makeKeyAndOrderFront(nil)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !isApplyingTerminationPolicy else { return .terminateNow }

    isApplyingTerminationPolicy = true
    displayManager.applyExternalDisplayOnlyPolicy {
      sender.reply(toApplicationShouldTerminate: true)
    }

    return .terminateLater
  }

  func applicationWillTerminate(_ notification: Notification) {
    // The second-option policy has already been applied in applicationShouldTerminate.
  }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.activate(ignoringOtherApps: true)
app.run()
