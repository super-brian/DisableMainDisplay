import SwiftUI

struct ContentView: View {
  @ObservedObject var displayManager: DisplayManager

  var body: some View {
    VStack(spacing: 16) {
      Button("Disable Main Display") {
        displayManager.enterCustomMode()
        displayManager.disableBuiltInDisplay()
      }
      .disabled(displayManager.isBuiltInDisplayDisabled || !displayManager.isAvailable)
      .controlSize(.large)

      Button("Enable Main Display") {
        displayManager.enterCustomMode()
        displayManager.enableBuiltInDisplay()
      }
      .disabled(!displayManager.isBuiltInDisplayDisabled || !displayManager.isAvailable)
      .controlSize(.large)

      Picker("", selection: $displayManager.displayMode) {
        Text("Keep main display off").tag(0)
        Text("Disable only while external display is connected").tag(1)
        Text("Custom Mode").tag(2)
      }
      .pickerStyle(.radioGroup)
      .labelsHidden()

      if !displayManager.statusMessage.isEmpty {
        Text(displayManager.statusMessage)
          .font(.caption)
          .foregroundColor(displayManager.isAvailable ? .secondary : .red)
      }
    }
    .padding(30)
    .frame(width: 380, height: 250)
  }
}
