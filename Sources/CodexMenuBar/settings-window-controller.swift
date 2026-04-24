import AppKit
import Observation
import SwiftUI

private enum SettingsWindowLayout {
  static let initialSize = NSSize(width: 560, height: 480)
  static let minSize = NSSize(width: 520, height: 360)
  static let maxContentWidth: CGFloat = 760
}

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
    window.setContentSize(SettingsWindowLayout.initialSize)
    window.contentMinSize = SettingsWindowLayout.minSize
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
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
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack(spacing: 10) {
            Image(systemName: model.connectionStateSymbol)
              .imageScale(.large)
              .foregroundStyle(ConnectionStateColor())
            Text(model.connectionStateTitle)
              .font(.headline)
              .foregroundStyle(.primary)
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("settings.connectionStatus")

          SettingsSection(title: "codexd Socket") {
            VStack(alignment: .leading, spacing: 10) {
              TextField(
                "Optional socket path override for this app session",
                text: $model.sessionSocketPathOverride
              )
              .textFieldStyle(.roundedBorder)
              .font(.system(.body, design: .monospaced))
              .accessibilityIdentifier("settings.socketOverride")

              HStack(spacing: 8) {
                Button("Apply & Reconnect") {
                  onApplySocketOverride(model.sessionSocketPathOverride)
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("settings.applySocketOverride")

                Button("Use Launch Default") {
                  model.sessionSocketPathOverride = ""
                  onApplySocketOverride(nil)
                }
                .accessibilityIdentifier("settings.useLaunchDefault")
              }

              VStack(alignment: .leading, spacing: 4) {
                Text("Effective socket path")
                  .font(.caption)
                  .foregroundStyle(.primary)

                Text(model.effectiveConfiguration.resolvedSocketPath)
                  .font(.system(.body, design: .monospaced))
                  .lineLimit(2)
                  .truncationMode(.middle)
                  .textSelection(.enabled)
                  .help(model.effectiveConfiguration.resolvedSocketPath)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .accessibilityIdentifier("settings.effectiveSocketPath")

                Text(model.effectiveConfiguration.source.description)
                  .font(.caption)
                  .foregroundStyle(.primary)
              }

              Text(
                "Launch defaults still honor CODEXD_SOCKET_PATH and CODEX_HOME. The field above only overrides the socket for this running app."
              )
              .font(.caption)
              .foregroundStyle(.primary)
              .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }

          SettingsSection(title: "Troubleshooting") {
            VStack(alignment: .leading, spacing: 8) {
              Text(
                "If the status item is hidden on macOS 26, enable CodexMenuBar in System Settings → Menu Bar."
              )
              .fixedSize(horizontal: false, vertical: true)

              Text(
                "Use Quick Start to open a terminal and launch `codex`, or reconnect after codexd is already running."
              )
              .font(.caption)
              .foregroundStyle(.primary)
              .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(16)
        .frame(maxWidth: SettingsWindowLayout.maxContentWidth, alignment: .topLeading)
      }

      Divider()

      HStack(spacing: 8) {
        Button("Reconnect codexd", action: onReconnect)
          .accessibilityIdentifier("settings.reconnect")
        Button("Quick Start", action: onQuickStart)
          .accessibilityIdentifier("settings.quickStart")
        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(maxWidth: SettingsWindowLayout.maxContentWidth, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("CodexMenuBar settings")
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

private struct SettingsSection<Content: View>: View {
  let title: String
  let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.headline)

      content
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
        .accessibilityHidden(true)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        .accessibilityHidden(true)
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel(title)
  }
}
