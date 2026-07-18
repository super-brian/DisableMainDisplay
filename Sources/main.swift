import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  var window: NSWindow!
  var displayManager: DisplayManager!
  var loginItemManager: LoginItemManager!
  private var statusItem: NSStatusItem?
  private var isApplyingTerminationPolicy = false
  private var skipTerminationPolicy = false

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

  /// True when macOS launched us as a login item after reboot / login.
  private func isLaunchedAsLoginItem() -> Bool {
    guard let event = NSAppleEventManager.shared().currentAppleEvent else {
      return false
    }
    // keyAELaunchedAsLogInItem = 'bgps'
    let loginItemKey = AEKeyword(UInt32(bigEndian: 0x62677073))
    return event.paramDescriptor(forKeyword: loginItemKey) != nil
  }

  private func setupStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = item.button {
      button.image = NSImage(
        systemSymbolName: "display",
        accessibilityDescription: "DisableMainDisplay"
      )
    }

    let menu = NSMenu()
    menu.addItem(
      NSMenuItem(
        title: "Show Window",
        action: #selector(showMainWindow),
        keyEquivalent: ""
      )
    )
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      NSMenuItem(
        title: "Quit DisableMainDisplay",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
      )
    )
    item.menu = menu
    statusItem = item
  }

  @objc func showMainWindow() {
    guard let window = window else { return }
    moveWindowToExternalDisplay()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Single instance check before constructing managers (avoids display/login side effects).
    let bundleID = Bundle.main.bundleIdentifier ?? "com.local.DisableMainDisplay"
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    if running.count > 1 {
      for app in running where app != NSRunningApplication.current {
        app.activate()
      }
      skipTerminationPolicy = true
      NSApp.terminate(nil)
      return
    }

    // Prefer the Applications symlink/app so Open at Login registers a stable path.
    if LoginItemManager.relaunchViaApplicationsIfNeeded() {
      skipTerminationPolicy = true
      NSApp.terminate(nil)
      return
    }

    displayManager = DisplayManager()
    loginItemManager = LoginItemManager()

    let launchedAtLogin = isLaunchedAsLoginItem()

    let contentView = ContentView(
      displayManager: displayManager,
      loginItemManager: loginItemManager
    )

    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 360),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "DisableMainDisplay"
    window.contentView = NSHostingView(rootView: contentView)
    window.delegate = self

    setupStatusItem()

    // Place window on an external display (not the built-in)
    moveWindowToExternalDisplay()

    // When lid opens, move window to external display
    displayManager.onBuiltInDisplayAppeared = { [weak self] in
      self?.moveWindowToExternalDisplay()
    }

    // After reboot, stay in the menu bar and apply policy quietly.
    if launchedAtLogin {
      window.orderOut(nil)
    } else {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // Keep running in the menu bar; closing only hides the window.
    sender.orderOut(nil)
    return false
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      showMainWindow()
    }
    return true
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if skipTerminationPolicy || displayManager == nil {
      return .terminateNow
    }

    guard !isApplyingTerminationPolicy else { return .terminateNow }

    isApplyingTerminationPolicy = true
    displayManager.applyExternalDisplayOnlyPolicy {
      sender.reply(toApplicationShouldTerminate: true)
    }

    return .terminateLater
  }

  func applicationWillTerminate(_ notification: Notification) {
    // The external-only policy has already been applied in applicationShouldTerminate.
  }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
