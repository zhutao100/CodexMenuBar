import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsViewModel {
  var sessionSocketPathOverride: String = ""
  var connectionState: AppServerConnectionState = .disconnected

  var effectiveConfiguration: CodexdSocketConfiguration {
    CodexdSocketConfiguration.Resolve(sessionOverride: sessionSocketPathOverride)
  }

  var connectionStateTitle: String {
    switch connectionState {
    case .connected:
      return "Connected to codexd"
    case .connecting:
      return "Connecting to codexd"
    case .reconnecting:
      return "Reconnecting to codexd"
    case .failed(let message):
      return "Connection error: \(message)"
    case .disconnected:
      return "Disconnected from codexd"
    }
  }

  var connectionStateSymbol: String {
    switch connectionState {
    case .connected:
      return "checkmark.circle.fill"
    case .connecting, .reconnecting:
      return "arrow.triangle.2.circlepath.circle.fill"
    case .failed:
      return "exclamationmark.triangle.fill"
    case .disconnected:
      return "circle.dashed"
    }
  }
}

@MainActor
final class SettingsWindowController: NSWindowController {
  init(
    model: SettingsViewModel,
    onApplySocketOverride: @escaping (String?) -> Void,
    onReconnect: @escaping () -> Void,
    onQuickStart: @escaping () -> Void
  ) {
    let contentView = SettingsView(
      model: model,
      onApplySocketOverride: onApplySocketOverride,
      onReconnect: onReconnect,
      onQuickStart: onQuickStart
    )
    let hostingController = NSHostingController(rootView: contentView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "CodexMenuBar Settings"
    window.setContentSize(NSSize(width: 540, height: 360))
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.isReleasedWhenClosed = false
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func Show() {
    showWindow(nil)
    window?.center()
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}

private struct SettingsView: View {
  @Bindable var model: SettingsViewModel

  let onApplySocketOverride: (String?) -> Void
  let onReconnect: () -> Void
  let onQuickStart: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label(model.connectionStateTitle, systemImage: model.connectionStateSymbol)
        .foregroundStyle(ConnectionStateColor())

      GroupBox("codexd Socket") {
        VStack(alignment: .leading, spacing: 10) {
          TextField(
            "Optional socket path override for this app session",
            text: $model.sessionSocketPathOverride
          )
          .textFieldStyle(.roundedBorder)
          .font(.system(.body, design: .monospaced))

          HStack(spacing: 8) {
            Button("Apply & Reconnect") {
              onApplySocketOverride(model.sessionSocketPathOverride)
            }
            .keyboardShortcut(.defaultAction)

            Button("Use Launch Default") {
              model.sessionSocketPathOverride = ""
              onApplySocketOverride(nil)
            }
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Effective socket path")
              .font(.caption)
              .foregroundStyle(.secondary)

            Text(model.effectiveConfiguration.resolvedSocketPath)
              .font(.system(.body, design: .monospaced))
              .textSelection(.enabled)

            Text(model.effectiveConfiguration.source.description)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Text(
            "Launch defaults still honor CODEXD_SOCKET_PATH and CODEX_HOME. The field above only overrides the socket for this running app."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      GroupBox("Troubleshooting") {
        VStack(alignment: .leading, spacing: 8) {
          Text(
            "If the status item is hidden on macOS 26, enable CodexMenuBar in System Settings → Menu Bar."
          )
          .fixedSize(horizontal: false, vertical: true)

          Text(
            "Use Quick Start to open a terminal and launch `codex`, or reconnect after codexd is already running."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      HStack(spacing: 8) {
        Button("Reconnect codexd", action: onReconnect)
        Button("Quick Start", action: onQuickStart)
        Spacer()
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func ConnectionStateColor() -> Color {
    switch model.connectionState {
    case .connected:
      return .green
    case .connecting, .reconnecting:
      return .orange
    case .failed:
      return .red
    case .disconnected:
      return .secondary
    }
  }
}
