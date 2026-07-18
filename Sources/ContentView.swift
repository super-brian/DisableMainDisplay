import AppKit
import SwiftUI

struct ContentView: View {
  @ObservedObject var displayManager: DisplayManager
  @ObservedObject var loginItemManager: LoginItemManager

  private var controlsDisabled: Bool {
    !displayManager.isAvailable || displayManager.isBusy
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      statusBar

      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          Picker(selection: $displayManager.displayMode) {
            labeledMode(
              "Keep main display off",
              "Even when no external is connected."
            ).tag(0)

            labeledMode(
              "Only while external is connected",
              "Turns back on when unplugged."
            ).tag(1)

            labeledMode(
              "Manual only",
              "No automatic changes."
            ).tag(2)
          } label: {
            EmptyView()
          }
          .pickerStyle(.radioGroup)
          .disabled(controlsDisabled)

          HStack(spacing: 8) {
            Text("Built-in")
              .font(.caption)
              .foregroundColor(.secondary)

            Spacer(minLength: 8)

            Button("Disable") {
              displayManager.enterCustomMode()
              displayManager.disableBuiltInDisplay()
            }
            .disabled(
              displayManager.isBuiltInDisplayDisabled || controlsDisabled
            )

            Button("Enable") {
              displayManager.enterCustomMode()
              displayManager.enableBuiltInDisplay()
            }
            .disabled(
              !displayManager.isBuiltInDisplayDisabled || controlsDisabled
            )
          }
          .controlSize(.regular)
          .padding(.top, 2)

          Text("Disable / Enable switches mode to Manual only.")
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
      } label: {
        Text("Mode")
      }

      VStack(alignment: .leading, spacing: 4) {
        Toggle(
          "Open at Login",
          isOn: Binding(
            get: { loginItemManager.isDesired },
            set: { loginItemManager.setEnabled($0) }
          )
        )

        if !loginItemManager.statusDetail.isEmpty {
          Text(loginItemManager.statusDetail)
            .font(.caption2)
            .foregroundColor(loginItemManager.isEnabled ? .secondary : .orange)
            .fixedSize(horizontal: false, vertical: true)
        }

        if !displayManager.statusMessage.isEmpty {
          Text(displayManager.statusMessage)
            .font(.caption)
            .foregroundColor(statusColor)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      HStack {
        Spacer(minLength: 0)
        Button("Quit") {
          NSApp.terminate(nil)
        }
      }
    }
    .padding(16)
    .frame(width: 400, height: 360)
    .onChange(of: displayManager.displayMode) { newMode in
      displayManager.applySelectedModePolicy(mode: newMode)
    }
    .onAppear {
      loginItemManager.refresh()
    }
  }

  private var statusBar: some View {
    HStack(alignment: .center, spacing: 8) {
      Circle()
        .fill(stateDotColor)
        .frame(width: 8, height: 8)

      Text("Built-in")
        .font(.headline)

      Text(displayManager.mainDisplayStateLabel)
        .font(.headline)
        .foregroundColor(.secondary)

      if displayManager.isBusy {
        ProgressView()
          .controlSize(.small)
      }

      Spacer(minLength: 8)

      Text(displayManager.connectionSummary)
        .font(.caption)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.trailing)
    }
  }

  private func labeledMode(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(title)
      Text(subtitle)
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding(.bottom, 2)
  }

  private var stateDotColor: Color {
    if !displayManager.isAvailable { return .red }
    if displayManager.isBusy { return .orange }
    return displayManager.isBuiltInDisplayDisabled ? .green : .secondary
  }

  private var statusColor: Color {
    displayManager.isAvailable ? .secondary : .red
  }
}
