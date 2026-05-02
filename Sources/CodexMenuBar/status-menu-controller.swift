import AppKit
import Observation
import SwiftUI

private enum StatusMenuLayout {
  static let popoverWidth: CGFloat = 480
  static let compactHeight: CGFloat = 238
  static let activeMinHeight: CGFloat = 390
  static let activeMaxHeight: CGFloat = 548
  static let activeBaseHeight: CGFloat = 150
  static let activeRowHeight: CGFloat = 96
  static let activeExpandedRowExtra: CGFloat = 120
  static let activeRateLimitHeight: CGFloat = 34
  static let outerPadding: CGFloat = 12
  static let contentWidth: CGFloat = popoverWidth - (outerPadding * 2)
  static let activeListMaxHeight: CGFloat = 388
  static let headerActionButtonSize: CGFloat = 26
}

@MainActor
final class StatusMenuController: NSObject, NSPopoverDelegate {
  enum UITestSurface: String {
    case popover
    case contextMenu = "context-menu"
  }

  private enum PopoverLayoutProfile: Equatable {
    case compact
    case active(height: CGFloat)

    init(for model: MenuBarViewModel) {
      let rows = model.endpointRows
      guard !rows.isEmpty else {
        self = .compact
        return
      }

      let expandedCount = rows.filter { model.expandedEndpointIds.contains($0.endpointId) }.count
      let listHeight = min(
        StatusMenuLayout.activeListMaxHeight,
        CGFloat(rows.count) * StatusMenuLayout.activeRowHeight
          + CGFloat(expandedCount) * StatusMenuLayout.activeExpandedRowExtra
      )
      let rateLimitHeight =
        model.activeRateLimitInfo == nil ? 0 : StatusMenuLayout.activeRateLimitHeight
      let height = min(
        StatusMenuLayout.activeMaxHeight,
        max(
          StatusMenuLayout.activeMinHeight,
          StatusMenuLayout.activeBaseHeight + listHeight + rateLimitHeight)
      )
      self = .active(height: height)
    }

    var height: CGFloat {
      switch self {
      case .compact:
        return StatusMenuLayout.compactHeight
      case .active(let height):
        return height
      }
    }
  }

  var ReconnectHandler: (() -> Void)?
  var QuickStartHandler: (() -> Void)?
  var SettingsHandler: (() -> Void)?
  var StatusCenterHandler: (() -> Void)?
  var OpenTerminalHandler: ((String) -> Void)?
  var QuitHandler: (() -> Void)?
  var PopoverVisibilityChanged: ((Bool) -> Void)?

  private let model: MenuBarViewModel
  private let statusItem: NSStatusItem
  private let statusIcon: NSImage?
  private let contextMenu: NSMenu
  private let popover: NSPopover
  private let uiTestStatusItemTitle: String?
  private var popoverLayoutProfile: PopoverLayoutProfile?
  private var popoverDismissMonitors: [Any] = []
  private var appResignObserver: NSObjectProtocol?
  private var workspaceActivationObserver: NSObjectProtocol?

  init(model: MenuBarViewModel) {
    self.model = model
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusIcon = Self.LoadStatusIcon()
    contextMenu = NSMenu(title: "CodexMenuBar")
    popover = NSPopover()
    uiTestStatusItemTitle = Self.LoadUITestStatusItemTitle()
    super.init()

    popover.behavior = .transient
    popover.animates = true
    popover.delegate = self
    popover.contentSize = NSSize(
      width: StatusMenuLayout.popoverWidth,
      height: StatusMenuLayout.compactHeight
    )
    popover.contentViewController = NSHostingController(
      rootView: StatusDropdownView(
        model: model,
        onReconnectAll: { [weak self] in self?.ReconnectHandler?() },
        onQuickStart: { [weak self] in self?.QuickStartHandler?() },
        onOpenSettings: { [weak self] in
          self?.ClosePopover()
          self?.SettingsHandler?()
        },
        onOpenStatusCenter: { [weak self] in
          self?.ClosePopover()
          self?.StatusCenterHandler?()
        },
        onOpenTerminal: { [weak self] workingDirectory in
          self?.OpenTerminalHandler?(workingDirectory)
        },
        onQuit: { [weak self] in self?.QuitHandler?() }
      )
      .fixedSize(horizontal: false, vertical: true)
    )

    if let button = statusItem.button {
      button.title = ""
      button.image = statusIcon
      button.imagePosition = .imageLeading
      button.toolTip = "CodexMenuBar"
      button.target = self
      button.action = #selector(OnStatusItemPressed)
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    ConfigureContextMenu()
    UpdateButton()
    UpdatePopoverSize()
    ObserveModel()
  }

  @objc
  private func OnStatusItemPressed() {
    guard let button = statusItem.button else {
      return
    }

    if IsSecondaryClick(NSApp.currentEvent) {
      ShowContextMenu(using: button)
      return
    }

    if popover.isShown {
      ClosePopover()
    } else {
      ShowPopover(using: button)
    }
  }

  func PresentUITestSurface(_ surface: UITestSurface) {
    guard let button = statusItem.button else {
      return
    }

    switch surface {
    case .popover:
      ShowPopover(using: button)
    case .contextMenu:
      ShowContextMenu(using: button)
    }
  }

  private func ConfigureContextMenu() {
    let reconnectItem = NSMenuItem(
      title: "Reconnect codexd",
      action: #selector(OnContextReconnect),
      keyEquivalent: ""
    )
    reconnectItem.target = self

    let quickStartItem = NSMenuItem(
      title: "Quick Start",
      action: #selector(OnContextQuickStart),
      keyEquivalent: ""
    )
    quickStartItem.target = self

    let settingsItem = NSMenuItem(
      title: "Settings...",
      action: #selector(OnContextSettings),
      keyEquivalent: ""
    )
    settingsItem.target = self

    let statusCenterItem = NSMenuItem(
      title: "Status Center...",
      action: #selector(OnContextStatusCenter),
      keyEquivalent: ""
    )
    statusCenterItem.target = self

    let quitItem = NSMenuItem(
      title: "Quit CodexMenuBar",
      action: #selector(OnContextQuit),
      keyEquivalent: ""
    )
    quitItem.target = self

    contextMenu.items = [
      reconnectItem,
      quickStartItem,
      statusCenterItem,
      settingsItem,
      .separator(),
      quitItem,
    ]
  }

  private func IsSecondaryClick(_ event: NSEvent?) -> Bool {
    guard let event else {
      return false
    }

    switch event.type {
    case .rightMouseUp:
      return true
    case .leftMouseUp:
      return event.modifierFlags.contains(.control)
    default:
      return false
    }
  }

  private func ClosePopover() {
    guard popover.isShown else {
      return
    }

    popover.performClose(nil)
  }

  private func StartPopoverDismissMonitoring() {
    guard popoverDismissMonitors.isEmpty else {
      return
    }

    let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

    if let localMonitor = NSEvent.addLocalMonitorForEvents(
      matching: eventMask,
      handler: {
        [weak self] event in
        let windowNumber = event.windowNumber
        let locationX = event.locationInWindow.x
        let locationY = event.locationInWindow.y

        Task { @MainActor [weak self] in
          self?.ClosePopoverIfClickIsOutside(
            windowNumber: windowNumber,
            locationInWindow: NSPoint(x: locationX, y: locationY)
          )
        }

        return event
      })
    {
      popoverDismissMonitors.append(localMonitor)
    }

    if let globalMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: eventMask,
      handler: {
        [weak self] _ in
        Task { @MainActor [weak self] in
          self?.ClosePopover()
        }
      })
    {
      popoverDismissMonitors.append(globalMonitor)
    }

    appResignObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification,
      object: NSApp,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.ClosePopover()
      }
    }

    workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      let activatedApplication =
        notification.userInfo?[NSWorkspace.applicationUserInfoKey]
        as? NSRunningApplication
      let isCurrentApplication =
        activatedApplication?.processIdentifier == NSRunningApplication.current.processIdentifier

      guard !isCurrentApplication else {
        return
      }

      Task { @MainActor [weak self] in
        self?.ClosePopover()
      }
    }
  }

  private func StopPopoverDismissMonitoring() {
    for monitor in popoverDismissMonitors {
      NSEvent.removeMonitor(monitor)
    }
    popoverDismissMonitors.removeAll()

    if let appResignObserver {
      NotificationCenter.default.removeObserver(appResignObserver)
      self.appResignObserver = nil
    }

    if let workspaceActivationObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
      self.workspaceActivationObserver = nil
    }
  }

  private func ClosePopoverIfClickIsOutside(
    windowNumber: Int,
    locationInWindow: NSPoint
  ) {
    guard popover.isShown else {
      return
    }

    if let popoverWindow = popover.contentViewController?.view.window,
      popoverWindow.windowNumber == windowNumber
    {
      return
    }

    if IsStatusButtonClick(windowNumber: windowNumber, locationInWindow: locationInWindow) {
      return
    }

    ClosePopover()
  }

  private func IsStatusButtonClick(windowNumber: Int, locationInWindow: NSPoint) -> Bool {
    guard let button = statusItem.button,
      let buttonWindow = button.window,
      buttonWindow.windowNumber == windowNumber
    else {
      return false
    }

    let locationInButton = button.convert(locationInWindow, from: nil)
    return button.bounds.contains(locationInButton)
  }

  private func ShowContextMenu(using button: NSStatusBarButton) {
    ClosePopover()
    statusItem.menu = contextMenu
    button.performClick(nil)
    statusItem.menu = nil
  }

  private func ShowPopover(using button: NSStatusBarButton) {
    model.SyncSectionDisclosureState()
    UpdatePopoverSize(force: true)
    let anchorRect = NSRect(
      x: button.bounds.midX - 1,
      y: button.bounds.maxY - 1,
      width: 2,
      height: 1
    )
    popover.show(relativeTo: anchorRect, of: button, preferredEdge: .minY)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc
  private func OnContextReconnect() {
    ReconnectHandler?()
  }

  @objc
  private func OnContextQuickStart() {
    QuickStartHandler?()
  }

  @objc
  private func OnContextSettings() {
    SettingsHandler?()
  }

  @objc
  private func OnContextStatusCenter() {
    StatusCenterHandler?()
  }

  @objc
  private func OnContextQuit() {
    QuitHandler?()
  }

  func popoverDidShow(_ notification: Notification) {
    _ = notification
    StartPopoverDismissMonitoring()
    PopoverVisibilityChanged?(true)
  }

  func popoverDidClose(_ notification: Notification) {
    _ = notification
    StopPopoverDismissMonitoring()
    PopoverVisibilityChanged?(false)
    model.ClearExpandedState()
  }

  private func ObserveModel() {
    withObservationTracking {
      _ = model.connectionState
      _ = model.runningCount
      _ = model.endpointRows.count
      _ = model.expandedEndpointIds.count
      _ = model.activeRateLimitInfo
      _ = model.lowRateLimitWarningText
      _ = model.codexdDiagnostics
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.UpdateButton()
        self?.UpdatePopoverSize()
        self?.ObserveModel()
      }
    }
  }

  private func UpdateButton() {
    guard let button = statusItem.button else { return }

    if let uiTestStatusItemTitle {
      if let statusIcon {
        button.image = statusIcon
        button.imagePosition = .imageLeading
      }
      button.title = uiTestStatusItemTitle
      return
    }

    if let statusIcon {
      button.image = statusIcon
      button.imagePosition = .imageLeading
      switch model.connectionState {
      case .connected:
        button.title = model.runningCount > 0 ? "\(model.runningCount)" : ""
      case .connecting, .reconnecting:
        button.title = "..."
      case .failed:
        button.title = "!"
      case .disconnected:
        button.title = ""
      }
      return
    }

    switch model.connectionState {
    case .connected:
      button.title = model.runningCount > 0 ? "◉\(model.runningCount)" : "◎"
    case .connecting, .reconnecting:
      button.title = "◌"
    case .failed:
      button.title = "⚠︎"
    case .disconnected:
      button.title = "○"
    }
  }

  private func UpdatePopoverSize(force: Bool = false) {
    let nextProfile = PopoverLayoutProfile(for: model)
    guard force || nextProfile != popoverLayoutProfile || !popover.isShown else {
      return
    }

    popoverLayoutProfile = nextProfile
    popover.contentSize = NSSize(
      width: StatusMenuLayout.popoverWidth,
      height: nextProfile.height
    )
  }

  private static func LoadStatusIcon() -> NSImage? {
    #if SWIFT_PACKAGE
      let bundle = Bundle.module
    #else
      let bundle = Bundle.main
    #endif
    let iconCandidates: [(name: String, subdirectory: String?)] = [
      ("codex", "svgs"),
      ("codex", "Resources/svgs"),
      ("codex", nil),
      ("codex-app", "svgs"),
      ("codex-app", "Resources/svgs"),
      ("codex-app", nil),
    ]
    for iconCandidate in iconCandidates {
      guard
        let url = bundle.url(
          forResource: iconCandidate.name,
          withExtension: "svg",
          subdirectory: iconCandidate.subdirectory
        ),
        let image = NSImage(contentsOf: url)
      else { continue }
      image.isTemplate = true
      image.size = NSSize(width: 18, height: 18)
      return image
    }
    return nil
  }

  private static func LoadUITestStatusItemTitle() -> String? {
    guard ProcessInfo.processInfo.arguments.contains("--uitest") else {
      return nil
    }

    let value = ProcessInfo.processInfo.environment["CODEXMENUBAR_UI_TEST_STATUS_TITLE"]?
      .trimmingCharacters(
        in: .whitespacesAndNewlines)
    if let value, !value.isEmpty {
      return value
    }
    return "CodexUITest"
  }
}

private struct StatusDropdownView: View {
  @Bindable var model: MenuBarViewModel

  let onReconnectAll: () -> Void
  let onQuickStart: () -> Void
  let onOpenSettings: () -> Void
  let onOpenStatusCenter: () -> Void
  let onOpenTerminal: (String) -> Void
  let onQuit: () -> Void

  var body: some View {
    let _ = model.viewRefreshToken
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 8) {
        Text(model.headerTitle)
          .font(.headline)
          .lineLimit(1)
          .accessibilityIdentifier("status.headerTitle")

        Spacer(minLength: 2)

        if let warningText = model.lowRateLimitWarningText {
          Label(warningText, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .lineLimit(1)
        }

        StatusDropdownHeaderActions(
          onReconnectAll: onReconnectAll,
          onOpenStatusCenter: onOpenStatusCenter,
          onOpenSettings: onOpenSettings,
          onQuit: onQuit
        )
      }

      Divider()

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Image(systemName: "server.rack")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(model.daemonSummaryText)
            .font(.caption)
            .lineLimit(1)
            .accessibilityIdentifier("status.daemonSummary")
          Spacer(minLength: 4)
        }

        Text("Socket: \(model.codexdDiagnostics.shortSocketPath)")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .accessibilityIdentifier("status.daemonSocket")
      }

      if model.endpointRows.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text("No active Codex sessions")
            .font(.subheadline)
            .foregroundStyle(.secondary)

          if model.connectionState == .connected || model.connectionState == .connecting {
            Text("Run codex in a terminal to start a session")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Button(action: onQuickStart) {
            Label("Quick Start", systemImage: "play.fill")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .accessibilityIdentifier("status.quickStart")
        }
      } else {
        ScrollView {
          LazyVStack(spacing: 8) {
            ForEach(model.endpointRows, id: \.endpointId) { endpointRow in
              TurnMenuRowView(
                endpointRow: endpointRow,
                now: model.now,
                isExpanded: model.expandedEndpointIds.contains(endpointRow.endpointId),
                expandedRunKeys: model.expandedRunKeysByEndpoint[endpointRow.endpointId] ?? [],
                onToggle: { model.ToggleEndpoint(endpointRow.endpointId) },
                onToggleHistoryRun: { runKey in
                  model.ToggleRun(endpointId: endpointRow.endpointId, runKey: runKey)
                },
                isFilesExpanded: model.IsSectionExpanded(
                  endpointId: endpointRow.endpointId, section: .files),
                isCommandsExpanded: model.IsSectionExpanded(
                  endpointId: endpointRow.endpointId, section: .commands),
                isPastRunsExpanded: model.IsSectionExpanded(
                  endpointId: endpointRow.endpointId, section: .pastRuns),
                onToggleFiles: {
                  model.ToggleSection(endpointId: endpointRow.endpointId, section: .files)
                },
                onToggleCommands: {
                  model.ToggleSection(endpointId: endpointRow.endpointId, section: .commands)
                },
                onTogglePastRuns: {
                  model.ToggleSection(endpointId: endpointRow.endpointId, section: .pastRuns)
                },
                onOpenInTerminal: { cwd in onOpenTerminal(cwd) }
              )
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 6)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: StatusMenuLayout.activeListMaxHeight)
      }

      if let rateLimits = model.activeRateLimitInfo,
        let remaining = rateLimits.remaining,
        let limit = rateLimits.limit
      {
        Divider()

        Text(RateLimitText(rateLimits: rateLimits, remaining: remaining, limit: limit))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

    }
    .padding(StatusMenuLayout.outerPadding)
    .frame(width: StatusMenuLayout.popoverWidth, alignment: .topLeading)
  }

  private func RateLimitText(rateLimits: RateLimitInfo, remaining: Int, limit: Int) -> String {
    var text = "Rate: \(remaining)/\(limit) remaining"

    if let resetsAt = rateLimits.resetsAt {
      let seconds = max(0, Int(resetsAt.timeIntervalSince(model.now)))
      if seconds > 0 {
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes > 0 {
          text += ", resets in \(minutes)m \(secs)s"
        } else {
          text += ", resets in \(secs)s"
        }
      }
    }

    return text
  }
}

private struct StatusDropdownHeaderActions: View {
  let onReconnectAll: () -> Void
  let onOpenStatusCenter: () -> Void
  let onOpenSettings: () -> Void
  let onQuit: () -> Void

  var body: some View {
    HStack(spacing: 4) {
      StatusDropdownHeaderButton(
        title: "Reconnect codexd",
        systemImage: "arrow.clockwise",
        accessibilityIdentifier: "status.reconnect",
        action: onReconnectAll
      )
      StatusDropdownHeaderButton(
        title: "Status Center",
        systemImage: "rectangle.3.group",
        accessibilityIdentifier: "status.statusCenter",
        action: onOpenStatusCenter
      )
      StatusDropdownHeaderButton(
        title: "Settings",
        systemImage: "gearshape",
        accessibilityIdentifier: "status.settings",
        action: onOpenSettings
      )
      StatusDropdownHeaderButton(
        title: "Quit CodexMenuBar",
        systemImage: "power",
        accessibilityIdentifier: "status.quit",
        action: onQuit
      )
    }
  }
}

private struct StatusDropdownHeaderButton: View {
  let title: String
  let systemImage: String
  let accessibilityIdentifier: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 12, weight: .semibold))
        .frame(
          width: StatusMenuLayout.headerActionButtonSize,
          height: StatusMenuLayout.headerActionButtonSize
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .controlSize(.small)
    .help(title)
    .accessibilityLabel(title)
    .accessibilityIdentifier(accessibilityIdentifier)
  }
}
