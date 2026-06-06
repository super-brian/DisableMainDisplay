import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics

// DisplayServices private framework — works on modern macOS including Apple Silicon
private typealias DisplayServicesSetBrightnessFunc =
  @convention(c) (CGDirectDisplayID, Float) -> Int32
private typealias DisplayServicesGetBrightnessFunc =
  @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

private let displayServicesSetBrightness: DisplayServicesSetBrightnessFunc? = {
  guard
    let handle = dlopen(
      "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
  else { return nil }
  guard let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
  return unsafeBitCast(sym, to: DisplayServicesSetBrightnessFunc.self)
}()

private let displayServicesGetBrightness: DisplayServicesGetBrightnessFunc? = {
  guard
    let handle = dlopen(
      "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
  else { return nil }
  guard let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
  return unsafeBitCast(sym, to: DisplayServicesGetBrightnessFunc.self)
}()

class DisplayManager: ObservableObject {
  @Published var isBuiltInDisplayDisabled = false
  @Published var isAvailable = true
  @Published var statusMessage: String = ""
  // 0 = keep main display off always, 1 = only while external display is connected, 2 = custom/manual mode
  @Published var displayMode: Int = UserDefaults.standard.object(forKey: "displayMode") as? Int ?? 0
  {
    didSet { UserDefaults.standard.set(displayMode, forKey: "displayMode") }
  }

  var autoDisable: Bool { displayMode == 0 || displayMode == 1 }
  var autoEnable: Bool { displayMode == 1 }

  func enterCustomMode() {
    displayMode = 2
  }

  func checkExternalDisplay() -> Bool {
    var displayCount: UInt32 = 0
    var displays = [CGDirectDisplayID](repeating: 0, count: 16)
    CGGetOnlineDisplayList(16, &displays, &displayCount)

    for i in 0..<Int(displayCount) {
      if CGDisplayIsBuiltin(displays[i]) == 0 {
        return true
      }
    }
    return false
  }

  private var builtInDisplayID: CGDirectDisplayID?
  private var savedBrightness: Float = 1.0

  /// Called when the built-in display appears (e.g. lid opened)
  var onBuiltInDisplayAppeared: (() -> Void)?

  init() {
    builtInDisplayID = Self.findBuiltInDisplay()

    if builtInDisplayID == nil {
      statusMessage = "No built-in display found"
      isAvailable = false
    } else if let displayID = builtInDisplayID {
      // Save current brightness using DisplayServices
      var brightness: Float = 1.0
      if let getBrightness = displayServicesGetBrightness {
        if getBrightness(displayID, &brightness) == 0 {
          savedBrightness = brightness
        }
      }
    }

    startMonitoringDisplayChanges()

    // Auto-disable on launch if enabled
    if autoDisable && isAvailable {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.disableBuiltInDisplay()
      }
    }
  }

  deinit {
    CGDisplayRemoveReconfigurationCallback(
      displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
  }

  private func startMonitoringDisplayChanges() {
    CGDisplayRegisterReconfigurationCallback(
      displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
  }

  private func hasExternalDisplay() -> Bool {
    var displayCount: UInt32 = 0
    var displays = [CGDirectDisplayID](repeating: 0, count: 16)
    CGGetOnlineDisplayList(16, &displays, &displayCount)

    for i in 0..<Int(displayCount) {
      if CGDisplayIsBuiltin(displays[i]) == 0 {
        return true
      }
    }
    return false
  }

  private func findExternalDisplayID() -> CGDirectDisplayID? {
    var displayCount: UInt32 = 0
    var displays = [CGDirectDisplayID](repeating: 0, count: 16)
    CGGetOnlineDisplayList(16, &displays, &displayCount)

    for i in 0..<Int(displayCount) {
      if CGDisplayIsBuiltin(displays[i]) == 0 {
        return displays[i]
      }
    }
    return nil
  }

  private static func findBuiltInDisplay() -> CGDirectDisplayID? {
    var displayCount: UInt32 = 0
    var displays = [CGDirectDisplayID](repeating: 0, count: 16)
    CGGetOnlineDisplayList(16, &displays, &displayCount)

    for i in 0..<Int(displayCount) {
      if CGDisplayIsBuiltin(displays[i]) != 0 {
        return displays[i]
      }
    }
    return nil
  }

  private func setBrightness(_ value: Float, for displayID: CGDirectDisplayID) -> Bool {
    if let setBrightness = displayServicesSetBrightness {
      return setBrightness(displayID, value) == 0
    }
    return false
  }

  func disableBuiltInDisplay() {
    guard let builtIn = builtInDisplayID else {
      statusMessage = "Cannot disable: no built-in display"
      return
    }

    guard let external = findExternalDisplayID() else {
      // No external display — just set brightness to 0
      if let getBrightness = displayServicesGetBrightness {
        var currentBrightness: Float = 1.0
        if getBrightness(builtIn, &currentBrightness) == 0 && currentBrightness > 0 {
          savedBrightness = currentBrightness
        }
      }
      let ok = setBrightness(0.0, for: builtIn)
      isBuiltInDisplayDisabled = true
      statusMessage =
        ok
        ? "Built-in display dimmed (no external for mirroring)"
        : "Cannot disable: brightness API unavailable"
      return
    }

    // Save current brightness BEFORE any display changes
    if let getBrightness = displayServicesGetBrightness {
      var currentBrightness: Float = 1.0
      if getBrightness(builtIn, &currentBrightness) == 0 {
        savedBrightness = currentBrightness
      }
    }

    // Step 1: Set brightness to 0 BEFORE mirroring (while display is still independently accessible)
    let brightnessOK = setBrightness(0.0, for: builtIn)

    // Save the external display's current mode so we can restore it after mirroring
    let savedExternalMode = CGDisplayCopyDisplayMode(external)

    // Defer mirroring so AppKit finishes processing the button click
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      // Step 2: Mirror the built-in onto the external (removes built-in from desktop)
      var config: CGDisplayConfigRef?
      guard CGBeginDisplayConfiguration(&config) == .success else {
        self?.statusMessage = "Failed to begin display config"
        return
      }
      CGConfigureDisplayMirrorOfDisplay(config, builtIn, external)
      guard CGCompleteDisplayConfiguration(config, .forSession) == .success else {
        self?.statusMessage = "Failed to set up mirroring"
        return
      }

      // Step 3: Restore the external display's original mode (mirroring may have changed it)
      if let mode = savedExternalMode {
        var config2: CGDisplayConfigRef?
        if CGBeginDisplayConfiguration(&config2) == .success {
          CGConfigureDisplayWithDisplayMode(config2, external, mode, nil)
          CGCompleteDisplayConfiguration(config2, .forSession)
        }
      }

      self?.isBuiltInDisplayDisabled = true
      if brightnessOK {
        self?.statusMessage = "Built-in display disabled"
      } else {
        self?.statusMessage = "Mirrored (brightness API unavailable)"
      }
    }
  }

  func enableBuiltInDisplay() {
    guard let builtIn = builtInDisplayID else {
      statusMessage = "Cannot enable: no built-in display"
      return
    }

    // Step 1: Remove mirroring — restore built-in as an independent display
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success else {
      statusMessage = "Failed to begin display config"
      return
    }
    CGConfigureDisplayMirrorOfDisplay(config, builtIn, kCGNullDirectDisplay)
    guard CGCompleteDisplayConfiguration(config, .forSession) == .success else {
      statusMessage = "Failed to remove mirroring"
      return
    }

    // Step 2: Restore brightness
    let targetBrightness = savedBrightness > 0 ? savedBrightness : Float(1.0)
    _ = setBrightness(targetBrightness, for: builtIn)

    isBuiltInDisplayDisabled = false
    statusMessage = "Built-in display enabled"
  }

  fileprivate func handleDisplayReconfiguration(
    display: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags
  ) {
    // Built-in display appeared (e.g. lid opened)
    if flags.contains(.addFlag) && CGDisplayIsBuiltin(display) != 0 {
      DispatchQueue.main.async { [weak self] in
        self?.builtInDisplayID = display
        self?.isAvailable = true
        if self?.statusMessage == "No built-in display found" {
          self?.statusMessage = ""
        }
        self?.onBuiltInDisplayAppeared?()
        // Auto-disable if enabled
        if self?.autoDisable == true {
          self?.isBuiltInDisplayDisabled = false
          self?.disableBuiltInDisplay()
        }
      }
      return
    }

    // External display added — re-apply disable (macOS may have broken mirroring during reconfiguration)
    if flags.contains(.addFlag) && CGDisplayIsBuiltin(display) == 0 {
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        if self.autoDisable && self.isAvailable {
          // Reset flag so disableBuiltInDisplay re-applies mirror+brightness
          self.isBuiltInDisplayDisabled = false
          self.disableBuiltInDisplay()
        }
      }
      return
    }

    // External display removed while built-in is disabled
    if isBuiltInDisplayDisabled && flags.contains(.removeFlag) {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        guard let self = self else { return }
        if self.hasExternalDisplay() {
          // Mirror target may have been removed — re-apply to a remaining external
          self.isBuiltInDisplayDisabled = false
          self.disableBuiltInDisplay()
        } else if self.autoEnable {
          self.enableBuiltInDisplay()
          self.statusMessage = "Built-in display re-enabled (no external display)"
        } else {
          // "Always" mode — keep brightness at 0 even without external
          self.isBuiltInDisplayDisabled = false
          self.disableBuiltInDisplay()
        }
      }
    }
  }
}

private func displayReconfigurationCallback(
  _ display: CGDirectDisplayID,
  _ flags: CGDisplayChangeSummaryFlags,
  _ userInfo: UnsafeMutableRawPointer?
) {
  guard let userInfo = userInfo else { return }
  let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()
  manager.handleDisplayReconfiguration(display: display, flags: flags)
}
