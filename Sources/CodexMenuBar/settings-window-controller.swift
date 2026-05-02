import AppKit
import Observation
import SwiftUI

private enum SettingsWindowLayout {
  static let initialSize = NSSize(width: 640, height: 520)
  static let minSize = NSSize(width: 560, height: 420)
  static let maxContentWidth: CGFloat = 720
}

@MainActor
@Observable
final class SettingsViewModel {
  @ObservationIgnored private let loginItemManager: LoginItemManaging

  var sessionSocketPathOverride: String = ""
  var connectionState: AppServerConnectionState = .disconnected
  var launchAtLoginStatus: LoginItemStatus = .notRegistered
  var launchAtLoginError: String?

  init(loginItemManager: LoginItemManaging = ServiceManagementLoginItemManager()) {
    self.loginItemManager = loginItemManager
    RefreshLaunchAtLoginStatus()
  }

  var effectiveConfiguration: CodexdSocketConfiguration {
    CodexdSocketConfiguration.Resolve(sessionOverride: sessionSocketPathOverride)
  }

  var isLaunchAtLoginRequested: Bool {
    switch launchAtLoginStatus {
    case .enabled, .requiresApproval:
      return true
    case .notRegistered, .notFound:
      return false
    }
  }

  var launchAtLoginStatusTitle: String {
    if let launchAtLoginError {
      return launchAtLoginError
    }

    switch launchAtLoginStatus {
    case .enabled:
      return "CodexMenuBar will open when you log in."
    case .requiresApproval:
      return "Approve CodexMenuBar in System Settings to finish enabling launch at login."
    case .notRegistered:
      return "CodexMenuBar will not open automatically at login."
    case .notFound:
      return
        "macOS could not find this app as a login item. Install and sign the app bundle, then try again."
    }
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

  func RefreshLaunchAtLoginStatus() {
    launchAtLoginStatus = loginItemManager.Status
  }

  func SetLaunchAtLoginEnabled(_ isEnabled: Bool) {
    do {
      try loginItemManager.SetEnabled(isEnabled)
      launchAtLoginError = nil
    } catch {
      launchAtLoginError = "Could not update launch at login: \(error.localizedDescription)"
    }

    RefreshLaunchAtLoginStatus()
  }

  func OpenLoginItemsSettings() {
    loginItemManager.OpenSystemSettingsLoginItems()
  }
}

@MainActor
final class SettingsWindowController: NSWindowController {
  private let model: SettingsViewModel

  init(
    model: SettingsViewModel,
    onApplySocketOverride: @escaping (String?) -> Void,
    onReconnect: @escaping () -> Void,
    onQuickStart: @escaping () -> Void
  ) {
    self.model = model
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
    model.RefreshLaunchAtLoginStatus()
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
      Header

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          SettingsGroup(title: "codexd Socket", systemImage: "server.rack") {
            VStack(alignment: .leading, spacing: 10) {
              Text("Session override")
                .font(.subheadline.weight(.medium))

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
                .buttonStyle(.borderedProminent)
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
                  .font(.subheadline.weight(.medium))

                Text(model.effectiveConfiguration.resolvedSocketPath)
                  .font(.system(.callout, design: .monospaced))
                  .lineLimit(2)
                  .truncationMode(.middle)
                  .textSelection(.enabled)
                  .help(model.effectiveConfiguration.resolvedSocketPath)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(8)
                  .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                      .fill(Color(nsColor: .textBackgroundColor))
                  )
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

          ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
              StartupSettings
              TroubleshootingSettings
            }

            VStack(alignment: .leading, spacing: 16) {
              StartupSettings
              TroubleshootingSettings
            }
          }
        }
        .padding(20)
        .frame(maxWidth: SettingsWindowLayout.maxContentWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
      }

      Divider()

      Footer
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
    .accessibilityElement(children: .contain)
    .accessibilityLabel("CodexMenuBar settings")
  }

  private var StartupSettings: some View {
    SettingsGroup(title: "Startup", systemImage: "power.circle") {
      VStack(alignment: .leading, spacing: 8) {
        Toggle(
          "Open CodexMenuBar at login",
          isOn: Binding(
            get: { model.isLaunchAtLoginRequested },
            set: { model.SetLaunchAtLoginEnabled($0) }
          )
        )
        .accessibilityIdentifier("settings.launchAtLogin")

        Text(model.launchAtLoginStatusTitle)
          .font(.caption)
          .foregroundStyle(model.launchAtLoginError == nil ? Color.primary : Color.red)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("settings.launchAtLoginStatus")

        if model.launchAtLoginStatus == .requiresApproval {
          Button("Open Login Items Settings") {
            model.OpenLoginItemsSettings()
          }
          .accessibilityIdentifier("settings.openLoginItems")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private var TroubleshootingSettings: some View {
    SettingsGroup(title: "Troubleshooting", systemImage: "wrench.and.screwdriver") {
      DisclosureGroup {
        Text(
          "If the status item is hidden on macOS 26, enable CodexMenuBar in System Settings -> Menu Bar."
        )
        .font(.callout)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
      } label: {
        Label("Menu Bar visibility", systemImage: "menubar.rectangle")
          .font(.subheadline.weight(.medium))
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private var Header: some View {
    HStack(spacing: 14) {
      Image(systemName: "command.circle.fill")
        .font(.system(size: 34))
        .foregroundStyle(Color.accentColor)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text("CodexMenuBar")
          .font(.title3.weight(.semibold))
        Text("Menu bar connection, startup, and recovery settings.")
          .font(.callout)
          .foregroundStyle(.primary)
      }

      Spacer(minLength: 12)

      HStack(spacing: 5) {
        Image(systemName: model.connectionStateSymbol)
          .foregroundStyle(ConnectionStateColor())
        Text(model.connectionStateTitle)
          .foregroundStyle(.primary)
      }
      .font(.caption.weight(.medium))
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(
        Capsule(style: .continuous)
          .fill(ConnectionStateColor().opacity(0.12))
      )
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("settings.connectionStatus")
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
  }

  private var Footer: some View {
    HStack(spacing: 8) {
      Button("Reconnect codexd", action: onReconnect)
        .accessibilityIdentifier("settings.reconnect")
      Button("Quick Start", action: onQuickStart)
        .accessibilityIdentifier("settings.quickStart")
      Spacer()
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .frame(maxWidth: SettingsWindowLayout.maxContentWidth, alignment: .leading)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
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

private struct SettingsGroup<Content: View>: View {
  let title: String
  let systemImage: String
  let content: Content

  init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.systemImage = systemImage
    self.content = content()
  }

  var body: some View {
    GroupBox {
      content
        .padding(.top, 4)
    } label: {
      Label(title, systemImage: systemImage)
        .font(.headline)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(title)
  }
}
