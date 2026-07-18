import AppKit
import Foundation
import ServiceManagement

/// Registers the app as a macOS login item so it starts after reboot.
final class LoginItemManager: ObservableObject {
  private static let desiredKey = "openAtLoginDesired"
  private static let relaunchFlagKey = "didRelaunchFromApplications"

  @Published private(set) var isEnabled = false
  @Published private(set) var statusDetail = ""

  /// User preference; defaults to on so the app keeps running across restarts.
  var isDesired: Bool {
    get {
      if UserDefaults.standard.object(forKey: Self.desiredKey) == nil {
        return true
      }
      return UserDefaults.standard.bool(forKey: Self.desiredKey)
    }
    set {
      UserDefaults.standard.set(newValue, forKey: Self.desiredKey)
    }
  }

  /// `/Applications` or `~/Applications` bundle URL if present.
  static func applicationsAppURL() -> URL? {
    let home = NSHomeDirectory()
    let candidates = [
      "/Applications/DisableMainDisplay.app",
      "\(home)/Applications/DisableMainDisplay.app",
    ]
    for path in candidates where FileManager.default.fileExists(atPath: path) {
      return URL(fileURLWithPath: path)
    }
    return nil
  }

  /// True when this process was started from an Applications folder path.
  static func isRunningFromApplicationsFolder() -> Bool {
    let path = Bundle.main.bundlePath
    let homeApps = NSHomeDirectory() + "/Applications/"
    return path.hasPrefix("/Applications/") || path.hasPrefix(homeApps)
  }

  /// If Applications symlink/app points at this build but we were launched from
  /// DerivedData/Xcode, reopen via Applications so Open at Login sticks to that path.
  static func relaunchViaApplicationsIfNeeded() -> Bool {
    if isRunningFromApplicationsFolder() {
      UserDefaults.standard.set(false, forKey: relaunchFlagKey)
      return false
    }
    guard let appURL = applicationsAppURL() else { return false }

    let current = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
    let target = appURL.resolvingSymlinksInPath().standardizedFileURL
    guard current == target else { return false }

    // Avoid relaunch loops.
    if UserDefaults.standard.bool(forKey: relaunchFlagKey) {
      UserDefaults.standard.set(false, forKey: relaunchFlagKey)
      return false
    }
    UserDefaults.standard.set(true, forKey: relaunchFlagKey)

    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in }
    return true
  }

  init(registerIfDesired: Bool = true) {
    refresh()
    if registerIfDesired && isDesired {
      enable()
    }
  }

  func setEnabled(_ enabled: Bool) {
    isDesired = enabled
    if enabled {
      enable()
    } else {
      disable()
    }
  }

  func refresh() {
    switch SMAppService.mainApp.status {
    case .enabled:
      isEnabled = true
      if Self.isRunningFromApplicationsFolder() {
        statusDetail = "Starts automatically when you log in."
      } else {
        statusDetail =
          "Login item is on, but this build was not launched from Applications. "
          + "Open /Applications/DisableMainDisplay.app once for a stable login path."
      }
    case .requiresApproval:
      isEnabled = false
      statusDetail =
        "Pending approval — enable DisableMainDisplay in System Settings → General → Login Items."
    case .notFound:
      isEnabled = false
      statusDetail =
        "Run DisableMainDisplay.app (not the raw executable) to use Open at Login."
    case .notRegistered:
      isEnabled = false
      if isDesired {
        if Self.isRunningFromApplicationsFolder() {
          statusDetail = "Not registered yet."
        } else {
          statusDetail =
            "Open /Applications/DisableMainDisplay.app (Xcode build symlink), then enable Open at Login."
        }
      } else {
        statusDetail = "Will not start at login."
      }
    @unknown default:
      isEnabled = false
      statusDetail = "Login item status unknown."
    }
  }

  private func enable() {
    do {
      try SMAppService.mainApp.register()
    } catch {
      statusDetail = error.localizedDescription
      refresh()
      return
    }
    refresh()
  }

  private func disable() {
    do {
      try SMAppService.mainApp.unregister()
    } catch {
      statusDetail = error.localizedDescription
      refresh()
      return
    }
    refresh()
  }
}
