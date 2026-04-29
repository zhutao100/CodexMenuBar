import AppKit
import SwiftUI

private enum StatusWindowLayout {
  static let width: CGFloat = 760
  static let height: CGFloat = 560
  static let minWidth: CGFloat = 640
  static let minHeight: CGFloat = 460
}

@MainActor
final class StatusWindowController: NSWindowController {
  init(model: MenuBarViewModel, onOpenTerminal: @escaping (String) -> Void) {
    let rootView = StatusCenterView(model: model, onOpenTerminal: onOpenTerminal)
    let hostingController = NSHostingController(rootView: rootView)

    let window = NSWindow(contentViewController: hostingController)
    window.title = "Codex Status Center"
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.setContentSize(
      NSSize(width: StatusWindowLayout.width, height: StatusWindowLayout.height))
    window.minSize = NSSize(
      width: StatusWindowLayout.minWidth, height: StatusWindowLayout.minHeight)
    window.isReleasedWhenClosed = false
    window.center()

    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func Show() {
    guard let window else {
      return
    }

    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

private struct StatusCenterView: View {
  @Bindable var model: MenuBarViewModel

  let onOpenTerminal: (String) -> Void

  @State private var selectedEndpointId: String?

  var body: some View {
    NavigationSplitView {
      VStack(alignment: .leading, spacing: 8) {
        Text("Runtimes")
          .font(.headline)
          .padding(.horizontal, 10)
          .padding(.top, 10)

        List(selection: $selectedEndpointId) {
          ForEach(model.endpointRows, id: \.endpointId) { row in
            StatusCenterRuntimeRow(row: row)
              .tag(row.endpointId)
          }
        }
        .accessibilityIdentifier("statusCenter.runtimeList")

        Divider()

        StatusCenterDaemonSummary(model: model)
          .padding(.horizontal, 10)
          .padding(.bottom, 10)
      }
      .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
    } detail: {
      DetailView
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(minWidth: StatusWindowLayout.minWidth, minHeight: StatusWindowLayout.minHeight)
    .onAppear {
      SelectDefaultEndpointIfNeeded()
    }
    .onChange(of: model.endpointRows.map(\.endpointId)) { _, _ in
      SelectDefaultEndpointIfNeeded()
    }
  }

  @ViewBuilder
  private var DetailView: some View {
    if let row = SelectedRow {
      ScrollView {
        TurnMenuRowView(
          endpointRow: row,
          now: model.now,
          isExpanded: true,
          expandedRunKeys: model.expandedRunKeysByEndpoint[row.endpointId] ?? [],
          onToggle: {},
          onToggleHistoryRun: { runKey in
            model.ToggleRun(endpointId: row.endpointId, runKey: runKey)
          },
          isFilesExpanded: true,
          isCommandsExpanded: true,
          isPastRunsExpanded: true,
          onToggleFiles: {},
          onToggleCommands: {},
          onTogglePastRuns: {},
          onOpenInTerminal: onOpenTerminal
        )
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .accessibilityIdentifier("statusCenter.detail")
    } else {
      ContentUnavailableView {
        Label("No Codex runtimes", systemImage: "server.rack")
      } description: {
        Text("Run codex in a terminal to populate the status center.")
      }
      .accessibilityIdentifier("statusCenter.empty")
    }
  }

  private var SelectedRow: EndpointRow? {
    let rows = model.endpointRows
    if let selectedEndpointId,
      let row = rows.first(where: { $0.endpointId == selectedEndpointId })
    {
      return row
    }
    return rows.first
  }

  private func SelectDefaultEndpointIfNeeded() {
    let rows = model.endpointRows
    if let selectedEndpointId,
      rows.contains(where: { $0.endpointId == selectedEndpointId })
    {
      return
    }
    selectedEndpointId = rows.first?.endpointId
  }
}

private struct StatusCenterRuntimeRow: View {
  let row: EndpointRow

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Circle()
          .fill(row.activeTurn == nil ? Color.secondary.opacity(0.5) : Color.green)
          .frame(width: 7, height: 7)
        Text(row.displayName)
          .font(.subheadline)
          .lineLimit(1)
      }

      Text(Subtitle)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .padding(.vertical, 3)
    .accessibilityIdentifier("statusCenter.runtime.\(row.endpointId)")
  }

  private var Subtitle: String {
    if let cwd = row.cwd {
      return cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
    if let sessionSource = row.sessionSource {
      return sessionSource
    }
    return row.shortId
  }
}

private struct StatusCenterDaemonSummary: View {
  @Bindable var model: MenuBarViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(model.daemonSummaryText)
        .font(.caption)
        .lineLimit(1)
        .accessibilityIdentifier("statusCenter.daemonSummary")

      Text(model.codexdDiagnostics.shortSocketPath)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }
}
