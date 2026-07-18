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
  @Published var isBusy = false
  @Published var hasExternalDisplayConnected = false
  @Published var statusMessage: String = ""
  // 0 = keep main display off always, 1 = only while external display is connected, 2 = custom/manual mode
  // Default to external-only when unset.
  @Published var displayMode: Int = UserDefaults.standard.object(forKey: "displayMode") as? Int ?? 1
  {
    didSet { UserDefaults.standard.set(displayMode, forKey: "displayMode") }
  }

  var autoDisable: Bool { displayMode == 0 || (displayMode == 1 && checkExternalDisplay()) }
  var autoEnable: Bool { displayMode == 1 }

  var mainDisplayStateLabel: String {
    if !isAvailable { return "Unavailable" }
    if isBusy { return "Updating…" }
    return isBuiltInDisplayDisabled ? "Off" : "On"
  }

  var connectionSummary: String {
    if !isAvailable {
      return "No built-in display detected."
    }
    return hasExternalDisplayConnected
      ? "External display connected."
      : "No external display connected."
  }

  private var builtInDisplayID: CGDirectDisplayID?
  private var savedBrightness: Float = 1.0
  /// If disable/enable is requested while another operation is in flight, run it next.
  private var pendingDisable = false
  private var pendingEnable = false
  private var pendingCompletions: [() -> Void] = []

  /// Called when the built-in display appears (e.g. lid opened)
  var onBuiltInDisplayAppeared: (() -> Void)?

  func enterCustomMode() {
    displayMode = 2
  }

  func enterExternalDisplayOnlyMode() {
    displayMode = 1
    UserDefaults.standard.set(displayMode, forKey: "displayMode")
  }

  /// Applies the policy for a mode the user just selected in the UI.
  func applySelectedModePolicy(mode: Int) {
    guard isAvailable, !isBusy else { return }

    refreshConnectionStatus()

    switch mode {
    case 0:
      if !isBuiltInDisplayDisabled {
        disableBuiltInDisplay()
      } else {
        statusMessage = "Keeping main display off"
      }
    case 1:
      applyExternalOnlyState()
    case 2:
      // Manual only — leave current display state alone.
      break
    default:
      break
    }
  }

  func applyExternalDisplayOnlyPolicy(completion: (() -> Void)? = nil) {
    enterExternalDisplayOnlyMode()

    guard isAvailable else {
      completion?()
      return
    }

    refreshConnectionStatus()

    if checkExternalDisplay() {
      if !isBuiltInDisplayDisabled {
        disableBuiltInDisplay(completion: completion)
      } else {
        completion?()
      }
      return
    }

    if isBuiltInDisplayDisabled {
      enableBuiltInDisplay(completion: completion)
    } else {
      completion?()
    }
  }

  private func applyExternalOnlyState() {
    if checkExternalDisplay() {
      if !isBuiltInDisplayDisabled {
        disableBuiltInDisplay()
      } else {
        statusMessage = "Main display stays off while external is connected"
      }
    } else if isBuiltInDisplayDisabled {
      enableBuiltInDisplay()
    } else {
      statusMessage = "No external display — main display left on"
    }
  }

  func refreshConnectionStatus() {
    hasExternalDisplayConnected = checkExternalDisplay()
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

    refreshConnectionStatus()
    startMonitoringDisplayChanges()

    // After reboot, externals often appear a few seconds after login — retry the saved policy.
    if isAvailable {
      startLaunchPolicyWithRetries()
    }
  }

  /// Launch / login: re-apply the saved automatic mode as displays settle.
  func startLaunchPolicyWithRetries() {
    let delays: [TimeInterval] = [0.5, 2.0, 5.0, 10.0]
    for delay in delays {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        self?.reapplyAutomaticPolicyIfNeeded()
      }
    }
  }

  /// Re-applies mode 0/1 without changing the selected mode (used after login / hotplug).
  func reapplyAutomaticPolicyIfNeeded() {
    guard isAvailable, !isBusy else { return }
    refreshConnectionStatus()

    switch displayMode {
    case 0:
      if !isBuiltInDisplayDisabled {
        disableBuiltInDisplay()
      }
    case 1:
      applyExternalOnlyState()
    default:
      break
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

  private func restoreSavedBrightness(for displayID: CGDirectDisplayID) {
    let target = savedBrightness > 0 ? savedBrightness : Float(1.0)
    _ = setBrightness(target, for: displayID)
  }

  private func finishBusyAndFlushPending() {
    isBusy = false

    if pendingDisable {
      pendingDisable = false
      pendingEnable = false
      disableBuiltInDisplay()
      return
    }

    if pendingEnable {
      pendingEnable = false
      enableBuiltInDisplay()
      return
    }

    let completions = pendingCompletions
    pendingCompletions.removeAll()
    for completion in completions {
      completion()
    }
  }

  private func enqueueCompletion(_ completion: (() -> Void)?) {
    if let completion {
      pendingCompletions.append(completion)
    }
  }

  private func flushCompletionsOnly() {
    let completions = pendingCompletions
    pendingCompletions.removeAll()
    for completion in completions {
      completion()
    }
  }

  private func setBrightness(_ value: Float, for displayID: CGDirectDisplayID) -> Bool {
    if let setBrightness = displayServicesSetBrightness {
      return setBrightness(displayID, value) == 0
    }
    return false
  }

  func disableBuiltInDisplay(completion: (() -> Void)? = nil) {
    enqueueCompletion(completion)

    guard !isBusy else {
      pendingDisable = true
      pendingEnable = false
      return
    }

    guard let builtIn = builtInDisplayID else {
      statusMessage = "Cannot disable: no built-in display"
      flushCompletionsOnly()
      return
    }

    isBusy = true
    pendingDisable = false
    refreshConnectionStatus()

    guard let external = findExternalDisplayID() else {
      // No external display — just set brightness to 0
      if let getBrightness = displayServicesGetBrightness {
        var currentBrightness: Float = 1.0
        if getBrightness(builtIn, &currentBrightness) == 0 && currentBrightness > 0 {
          savedBrightness = currentBrightness
        }
      }
      let ok = setBrightness(0.0, for: builtIn)
      isBuiltInDisplayDisabled = ok
      statusMessage =
        ok
        ? "Built-in display dimmed (no external for mirroring)"
        : "Cannot disable: brightness API unavailable"
      finishBusyAndFlushPending()
      return
    }

    // Save current brightness BEFORE any display changes
    if let getBrightness = displayServicesGetBrightness {
      var currentBrightness: Float = 1.0
      if getBrightness(builtIn, &currentBrightness) == 0 && currentBrightness > 0 {
        savedBrightness = currentBrightness
      }
    }

    // Step 1: Set brightness to 0 BEFORE mirroring (while display is still independently accessible)
    let brightnessOK = setBrightness(0.0, for: builtIn)

    // Save the external display's current mode so we can restore it after mirroring
    let savedExternalMode = CGDisplayCopyDisplayMode(external)

    // Defer mirroring so AppKit finishes processing the button click
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self = self else { return }

      // Step 2: Mirror the built-in onto the external (removes built-in from desktop)
      var config: CGDisplayConfigRef?
      guard CGBeginDisplayConfiguration(&config) == .success else {
        self.restoreSavedBrightness(for: builtIn)
        self.isBuiltInDisplayDisabled = false
        self.statusMessage = "Failed to begin display config"
        self.finishBusyAndFlushPending()
        return
      }
      CGConfigureDisplayMirrorOfDisplay(config, builtIn, external)
      guard CGCompleteDisplayConfiguration(config, .forSession) == .success else {
        self.restoreSavedBrightness(for: builtIn)
        self.isBuiltInDisplayDisabled = false
        self.statusMessage = "Failed to set up mirroring"
        self.finishBusyAndFlushPending()
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

      self.refreshConnectionStatus()
      self.isBuiltInDisplayDisabled = true
      if brightnessOK {
        self.statusMessage = "Built-in display disabled"
      } else {
        self.statusMessage = "Mirrored (brightness API unavailable)"
      }
      self.finishBusyAndFlushPending()
    }
  }

  func enableBuiltInDisplay(completion: (() -> Void)? = nil) {
    enqueueCompletion(completion)

    guard !isBusy else {
      pendingEnable = true
      pendingDisable = false
      return
    }

    guard let builtIn = builtInDisplayID else {
      statusMessage = "Cannot enable: no built-in display"
      flushCompletionsOnly()
      return
    }

    isBusy = true
    pendingEnable = false

    // Step 1: Remove mirroring — restore built-in as an independent display
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success else {
      statusMessage = "Failed to begin display config"
      finishBusyAndFlushPending()
      return
    }
    CGConfigureDisplayMirrorOfDisplay(config, builtIn, kCGNullDirectDisplay)
    guard CGCompleteDisplayConfiguration(config, .forSession) == .success else {
      statusMessage = "Failed to remove mirroring"
      finishBusyAndFlushPending()
      return
    }

    // Step 2: Restore brightness
    restoreSavedBrightness(for: builtIn)

    refreshConnectionStatus()
    isBuiltInDisplayDisabled = false
    statusMessage = "Built-in display enabled"
    finishBusyAndFlushPending()
  }

  fileprivate func handleDisplayReconfiguration(
    display: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags
  ) {
    // Built-in display appeared (e.g. lid opened)
    if flags.contains(.addFlag) && CGDisplayIsBuiltin(display) != 0 {
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.builtInDisplayID = display
        self.isAvailable = true
        self.refreshConnectionStatus()
        if self.statusMessage == "No built-in display found" {
          self.statusMessage = ""
        }
        self.onBuiltInDisplayAppeared?()
        // Auto-disable if enabled (queues if an operation is already in flight)
        if self.autoDisable {
          self.disableBuiltInDisplay()
        }
      }
      return
    }

    // External display added — re-apply disable (macOS may have broken mirroring during reconfiguration)
    if flags.contains(.addFlag) && CGDisplayIsBuiltin(display) == 0 {
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.refreshConnectionStatus()
        if self.autoDisable && self.isAvailable {
          // Re-apply mirror+brightness (queues if an operation is already in flight)
          self.disableBuiltInDisplay()
        }
      }
      return
    }

    // External display removed while built-in is disabled
    if flags.contains(.removeFlag) {
      let wasDisabled = isBuiltInDisplayDisabled
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        guard let self = self else { return }
        self.refreshConnectionStatus()
        guard wasDisabled || self.isBuiltInDisplayDisabled else { return }
        if self.checkExternalDisplay() {
          // Mirror target may have been removed — re-apply to a remaining external
          self.disableBuiltInDisplay()
        } else if self.autoEnable {
          self.enableBuiltInDisplay()
          self.statusMessage = "Built-in display re-enabled (no external display)"
        } else if self.displayMode == 0 {
          // "Always" mode — keep brightness at 0 even without external
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
