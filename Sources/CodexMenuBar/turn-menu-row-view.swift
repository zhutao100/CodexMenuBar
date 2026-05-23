import AppKit
import Foundation
import SwiftUI

private enum RuntimeHistoryPageSize {
  static let planSteps = 6
  static let files = 8
  static let commands = 5
  static let runs = 5
}

private struct RuntimeHistoryPage<Item> {
  let items: [Item]
  let page: Int
  let pageSize: Int

  var visibleItems: [Item] {
    let range = range
    guard !range.isEmpty else {
      return []
    }
    return Array(items[range])
  }

  var positionText: String {
    let range = range
    guard !range.isEmpty else {
      return "0 of 0"
    }
    return "\(range.lowerBound + 1)-\(range.upperBound) of \(items.count)"
  }

  var canShowNewer: Bool {
    clampedPage > 0
  }

  var canShowOlder: Bool {
    clampedPage < maxPage
  }

  var newerPage: Int {
    max(0, clampedPage - 1)
  }

  var olderPage: Int {
    min(maxPage, clampedPage + 1)
  }

  private var range: Range<Int> {
    guard items.count > 0, pageSize > 0 else {
      return 0..<0
    }

    let end = items.count - (clampedPage * pageSize)
    let start = max(0, end - pageSize)
    return start..<end
  }

  private var clampedPage: Int {
    min(max(0, page), maxPage)
  }

  private var maxPage: Int {
    guard items.count > 0, pageSize > 0 else {
      return 0
    }
    return (items.count - 1) / pageSize
  }
}

private func IsDelegateTurn(
  scope: String?,
  sessionSource: String?,
  subAgentSource: String?
) -> Bool {
  let normalizedScope = NormalizeIdentifier(scope)
  let normalizedSessionSource = NormalizeIdentifier(sessionSource)
  return normalizedScope == "delegate" || normalizedSessionSource.hasPrefix("subagent")
    || NormalizeIdentifier(subAgentSource).isEmpty == false
}

private func RuntimeTurnKindLabel(
  scope: String?,
  taskKind: String?,
  sessionSource: String?,
  subAgentSource: String?
) -> String {
  if IsDelegateTurn(scope: scope, sessionSource: sessionSource, subAgentSource: subAgentSource) {
    let normalizedTaskKind = NormalizeIdentifier(taskKind)
    if normalizedTaskKind == "post_turn_completion_review" {
      return "Post-turn review"
    }
    if NormalizeIdentifier(subAgentSource) == "review" {
      return "Review delegate"
    }
    if !normalizedTaskKind.isEmpty {
      return "\(HumanizeIdentifier(normalizedTaskKind)) delegate"
    }
    return "Delegate turn"
  }
  return "Regular turn"
}

private func RuntimeTurnKindNoun(
  scope: String?,
  taskKind: String?,
  sessionSource: String?,
  subAgentSource: String?
) -> String {
  let label = RuntimeTurnKindLabel(
    scope: scope,
    taskKind: taskKind,
    sessionSource: sessionSource,
    subAgentSource: subAgentSource
  )
  switch label {
  case "Regular turn", "Delegate turn":
    return label.lowercased()
  default:
    return label.lowercased()
  }
}

private func ParentTurnDetailLabel(taskKind: String?) -> String {
  NormalizeIdentifier(taskKind) == "post_turn_completion_review" ? "Reviewed turn" : "Parent"
}

private func NormalizeIdentifier(_ value: String?) -> String {
  guard let value else {
    return ""
  }
  return value.trimmingCharacters(in: .whitespacesAndNewlines)
    .replacingOccurrences(of: "-", with: "_")
    .lowercased()
}

private func HumanizeIdentifier(_ value: String) -> String {
  value.split(separator: "_")
    .filter { !$0.isEmpty }
    .map { part in
      part.prefix(1).uppercased() + part.dropFirst()
    }
    .joined(separator: " ")
}

struct TurnMenuRowView: View {
  let endpointRow: EndpointRow
  let now: Date
  let isExpanded: Bool
  let expandedRunKeys: Set<String>
  let onToggle: () -> Void
  let onToggleHistoryRun: (String) -> Void
  let isFilesExpanded: Bool
  let isCommandsExpanded: Bool
  let isPastRunsExpanded: Bool
  let onToggleFiles: () -> Void
  let onToggleCommands: () -> Void
  let onTogglePastRuns: () -> Void
  let onOpenInTerminal: (String) -> Void

  @State private var selectedTokenHistoryIndex = 0
  @State private var planHistoryPage = 0
  @State private var fileHistoryPage = 0
  @State private var commandHistoryPage = 0
  @State private var runHistoryPage = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button(action: onToggle) {
        HStack(alignment: .center, spacing: 6) {
          Circle()
            .fill(StatusDotColor(activeTurn?.status ?? .completed))
            .frame(width: 8, height: 8)

          Text(NameText())
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)

          Text(TurnKindLabel())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(TurnKindForeground())
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
              TurnKindForeground().opacity(0.12),
              in: Capsule(style: .continuous)
            )
            .lineLimit(1)
            .accessibilityIdentifier("turn.kind.\(endpointRow.endpointId)")

          Spacer(minLength: 8)

          Text(ElapsedText())
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)

          Text(isExpanded ? "▾" : "▸")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("turn.row.\(endpointRow.endpointId)")

      if activeTurn != nil {
        Text(TimelineSummaryText())
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(1)

        TimelineBarView(segments: activeTurn?.TimelineSegments(now: now) ?? [])
          .frame(maxWidth: .infinity)
          .frame(height: 8)

        if let modelSummary = ModelSummary() {
          Text(modelSummary)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
      } else {
        if isExpanded, let cwd = endpointRow.cwd {
          Text(cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
        }

        Text(endpointRow.lastTraceLabel ?? "No active run")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      if isExpanded {
        ExpandedBody
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(
      Color(nsColor: NSColor.controlBackgroundColor).opacity(0.78),
      in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color(nsColor: NSColor.separatorColor).opacity(0.2), lineWidth: 0.5)
    )
    .overlay {
      if !isExpanded {
        Rectangle()
          .fill(.clear)
          .contentShape(Rectangle())
          .onTapGesture {
            onToggle()
          }
      }
    }
    .onChange(of: endpointRow.endpointId) { _, _ in
      ResetHistorySelections()
    }
    .onChange(of: endpointRow.turnId ?? "") { _, _ in
      ResetHistorySelections()
    }
    .onChange(of: endpointRow.turnKey ?? "") { _, _ in
      ResetHistorySelections()
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isExpanded)
  }

  @ViewBuilder
  private var ExpandedBody: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let prompt = PromptDisplayText() {
        SectionCard {
          HStack(spacing: 6) {
            Label("Prompt", systemImage: "text.bubble.fill")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            Button(action: { CopyToClipboard(prompt) }) {
              Image(systemName: "doc.on.doc")
                .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy prompt")
            .help("Copy prompt")
          }
        } content: {
          Text(prompt)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }

      if HasGitOrModelInfo() {
        Label(GitModelLine(), systemImage: "folder.fill")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      if let turnDetails = TurnDetailsLine() {
        SectionCard {
          Label("Turn Details", systemImage: "info.circle.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
        } content: {
          Text(turnDetails)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary)
            .lineLimit(3)
            .textSelection(.enabled)
            .accessibilityIdentifier("turn.details.\(endpointRow.endpointId)")
        }
      }

      let tokenHistoryEntries = TokenUsageHistoryEntries()
      if !tokenHistoryEntries.isEmpty {
        TokenUsageHistoryCard(
          endpointId: endpointRow.endpointId,
          entries: tokenHistoryEntries,
          selectedIndex: $selectedTokenHistoryIndex
        )
      }

      if let usage = SessionTokenUsage() {
        SectionCard {
          Label(SessionTokenTitle(usage: usage), systemImage: "chart.pie.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
        } content: {
          VStack(alignment: .leading, spacing: 4) {
            TokenUsageBarView(usage: usage)
              .frame(maxWidth: .infinity)
              .frame(height: 12)

            Text(TokenUsageDetailText(usage))
              .font(.system(size: 10, design: .monospaced))
              .foregroundStyle(.tertiary)
              .lineLimit(1)
          }
        }
      }

      if let latestError = endpointRow.latestError {
        SectionCard {
          HStack(spacing: 6) {
            Label("Error", systemImage: "exclamationmark.circle.fill")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.red)

            Spacer(minLength: 4)

            Button(action: { CopyToClipboard(ErrorCopyText(latestError)) }) {
              Image(systemName: "doc.on.doc")
                .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy error")
            .help("Copy error")
          }
        } content: {
          VStack(alignment: .leading, spacing: 2) {
            Text(
              latestError.willRetry ? "\(latestError.message) (retrying...)" : latestError.message
            )
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.red)
            .lineLimit(2)

            if let details = latestError.details, !details.isEmpty {
              Text(details)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            }
          }
        }
      }

      if !endpointRow.planSteps.isEmpty {
        let planPage = PlanHistoryPage()
        SectionCard {
          Label(PlanTitle(), systemImage: "checklist")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
        } content: {
          VStack(alignment: .leading, spacing: 4) {
            if endpointRow.planSteps.count > RuntimeHistoryPageSize.planSteps {
              HistoryPagerControls(
                endpointId: endpointRow.endpointId,
                namespace: "plan",
                label: "plan history",
                positionText: planPage.positionText,
                canShowNewer: planPage.canShowNewer,
                canShowOlder: planPage.canShowOlder,
                onShowNewer: ShowNewerPlanSteps,
                onShowOlder: ShowOlderPlanSteps
              )
            }

            ForEach(Array(planPage.visibleItems.enumerated()), id: \.offset) { _, step in
              Text("\(PlanIcon(step.status))  \(Truncate(step.description, limit: 52))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("turn.planHistory.step.\(endpointRow.endpointId)")
            }
          }
        }
      }

      if !VisibleFileChanges().isEmpty {
        let filePage = FileHistoryPage()
        AccordionSectionCard(
          title: "Files (\(VisibleFileChanges().count))",
          systemImage: "doc.text.fill",
          isExpanded: isFilesExpanded,
          onToggle: onToggleFiles
        ) {
          VStack(alignment: .leading, spacing: 4) {
            if VisibleFileChanges().count > RuntimeHistoryPageSize.files {
              HistoryPagerControls(
                endpointId: endpointRow.endpointId,
                namespace: "files",
                label: "file history",
                positionText: filePage.positionText,
                canShowNewer: filePage.canShowNewer,
                canShowOlder: filePage.canShowOlder,
                onShowNewer: ShowNewerFiles,
                onShowOlder: ShowOlderFiles
              )
            }

            ForEach(filePage.visibleItems, id: \.path) { change in
              let filename = (change.path as NSString).lastPathComponent
              let dir = (change.path as NSString).deletingLastPathComponent
              let shortDir = dir.isEmpty ? "" : "\(dir)/"
              Text("\(change.kind.label)  \(shortDir)\(filename)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
        }
      }

      if !VisibleCommands().isEmpty {
        let commandPage = CommandHistoryPage()
        AccordionSectionCard(
          title: "Commands / Tools Run (\(VisibleCommands().count))",
          systemImage: "terminal.fill",
          isExpanded: isCommandsExpanded,
          onToggle: onToggleCommands
        ) {
          VStack(alignment: .leading, spacing: 4) {
            if VisibleCommands().count > RuntimeHistoryPageSize.commands {
              HistoryPagerControls(
                endpointId: endpointRow.endpointId,
                namespace: "commands",
                label: "command history",
                positionText: commandPage.positionText,
                canShowNewer: commandPage.canShowNewer,
                canShowOlder: commandPage.canShowOlder,
                onShowNewer: ShowNewerCommands,
                onShowOlder: ShowOlderCommands
              )
            }

            ForEach(commandPage.visibleItems, id: \.command) { command in
              Text(CommandLine(command: command))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
        }
      }

      if !endpointRow.recentRuns.isEmpty {
        let runPage = RunHistoryPage()
        AccordionSectionCard(
          title: "Completed Turns (\(endpointRow.recentRuns.count))",
          systemImage: "clock.arrow.circlepath",
          isExpanded: isPastRunsExpanded,
          onToggle: onTogglePastRuns
        ) {
          VStack(spacing: 4) {
            if endpointRow.recentRuns.count > RuntimeHistoryPageSize.runs {
              HistoryPagerControls(
                endpointId: endpointRow.endpointId,
                namespace: "runs",
                label: "past run history",
                positionText: runPage.positionText,
                canShowNewer: runPage.canShowNewer,
                canShowOlder: runPage.canShowOlder,
                onShowNewer: ShowNewerRuns,
                onShowOlder: ShowOlderRuns
              )
            }

            ForEach(runPage.visibleItems, id: \.runKey) { run in
              RunHistoryRowView(
                run: run,
                fallbackModel: endpointRow.model,
                fallbackModelProvider: endpointRow.modelProvider,
                fallbackThinkingLevel: endpointRow.thinkingLevel,
                isLastRun: run.turnId == endpointRow.recentRuns.first?.turnId,
                isExpanded: expandedRunKeys.contains(run.runKey),
                onToggle: { onToggleHistoryRun(run.runKey) }
              )
            }
          }
        }
      }

      Divider()

      HStack(spacing: 8) {
        if let cwd = endpointRow.cwd {
          Button("Open in Finder") {
            NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
          }

          Button("Open in Terminal") {
            onOpenInTerminal(cwd)
          }
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
    .padding(.top, 2)
  }

  private var activeTurn: ActiveTurn? {
    endpointRow.activeTurn
  }

  private func NameText() -> String {
    let hasCwd = endpointRow.cwd != nil
    let hasTitle = endpointRow.chatTitle != nil && !(endpointRow.chatTitle?.isEmpty ?? true)
    if hasCwd || hasTitle {
      return "\(endpointRow.displayName) (\(endpointRow.shortId))"
    }
    return endpointRow.displayName
  }

  private func ElapsedText() -> String {
    guard let activeTurn else {
      return "Idle"
    }
    return "\(StatusLabel(activeTurn.status)) \(activeTurn.ElapsedString(now: now))"
  }

  private func TimelineSummaryText() -> String {
    var summaryParts: [String] = []
    if let traceLabel = endpointRow.lastTraceLabel ?? activeTurn?.latestLabel {
      summaryParts.append(traceLabel)
    }

    if endpointRow.fileChanges.count > 0 {
      let fileCount = endpointRow.fileChanges.count
      summaryParts.append("\(fileCount) file\(fileCount == 1 ? "" : "s")")
    }

    if endpointRow.commands.count > 0 {
      let commandCount = endpointRow.commands.count
      summaryParts.append("\(commandCount) cmd\(commandCount == 1 ? "" : "s")")
    }

    return summaryParts.isEmpty ? "Working..." : summaryParts.joined(separator: " · ")
  }

  private func PromptDisplayText() -> String? {
    guard endpointRow.activeTurn != nil else { return nil }
    if let promptPreview = endpointRow.promptPreview, !promptPreview.isEmpty {
      return promptPreview
    }
    return "waiting for first user message"
  }

  private func EffectiveLastTurnTokenUsage() -> TokenUsageInfo? {
    guard let usage = endpointRow.tokenUsageLast, usage.isTurnRoundUsage else { return nil }
    return usage
  }

  private func EffectiveTokenUsageSamples() -> [TokenUsageSample] {
    let samples = endpointRow.tokenUsageSamples.filter { $0.usage.isTurnRoundUsage }
    if !samples.isEmpty {
      return samples
    }

    guard let usage = EffectiveLastTurnTokenUsage() else {
      return []
    }
    return [TokenUsageSample(usage: usage, observedAt: endpointRow.lastEventAt ?? now)]
  }

  private func SessionTokenUsage() -> TokenUsageInfo? {
    guard let usage = endpointRow.tokenUsageTotal, usage.totalTokens > 0 else { return nil }
    return usage
  }

  private func TokenUsageHistoryEntries() -> [TokenUsageHistoryEntry] {
    var entries: [TokenUsageHistoryEntry] = []
    var seenTurnIds: Set<String> = []

    let effectiveSamples = EffectiveTokenUsageSamples()
    if !effectiveSamples.isEmpty {
      let turnId = activeTurn?.turnId ?? endpointRow.turnId ?? "latest"
      seenTurnIds.insert(TurnIdentity(threadId: endpointRow.threadId, turnId: turnId))
      let titlePrefix = activeTurn == nil ? "Latest" : "Current"

      let newestFirstSamples = Array(effectiveSamples.enumerated().reversed())
      for (index, sample) in newestFirstSamples {
        entries.append(
          TokenUsageHistoryEntry(
            id: "latest:\(endpointRow.endpointId):\(turnId):\(index)",
            title: "\(titlePrefix) \(TurnKindNoun())",
            subtitle: TokenUsageHistoryPrimarySubtitle(
              sampleIndex: index,
              sampleCount: effectiveSamples.count,
              observedAt: sample.observedAt
            ),
            usage: sample.usage
          )
        )
      }
    } else if let usage = EffectiveLastTurnTokenUsage() {
      let turnId = activeTurn?.turnId ?? endpointRow.turnId ?? "latest"
      seenTurnIds.insert(TurnIdentity(threadId: endpointRow.threadId, turnId: turnId))
      let titlePrefix = activeTurn == nil ? "Latest" : "Current"
      entries.append(
        TokenUsageHistoryEntry(
          id: "latest:\(endpointRow.endpointId):\(turnId)",
          title: "\(titlePrefix) \(TurnKindNoun())",
          subtitle: TokenUsageHistoryPrimarySubtitle(
            sampleIndex: nil,
            sampleCount: 0,
            observedAt: endpointRow.lastEventAt
          ),
          usage: usage
        )
      )
    } else if activeTurn != nil {
      return entries
    }

    for (index, run) in endpointRow.recentRuns.enumerated() {
      let runSamples = RunTokenUsageSamples(run)
      guard !runSamples.isEmpty else {
        continue
      }

      let turnIdentity = TurnIdentity(threadId: run.threadId, turnId: run.turnId)
      guard !seenTurnIds.contains(turnIdentity) else {
        continue
      }
      seenTurnIds.insert(turnIdentity)

      let newestFirstSamples = Array(runSamples.enumerated().reversed())
      for (sampleIndex, sample) in newestFirstSamples {
        entries.append(
          TokenUsageHistoryEntry(
            id: "run:\(run.runKey):\(sampleIndex)",
            title: index == 0
              ? "Latest completed \(TurnKindNoun(run: run))"
              : "Earlier \(TurnKindNoun(run: run))",
            subtitle: RunTokenUsageSubtitle(
              run: run,
              sampleIndex: sampleIndex,
              sampleCount: runSamples.count,
              observedAt: sample.observedAt
            ),
            usage: sample.usage
          )
        )
      }
    }

    return entries
  }

  private func TokenUsageHistoryPrimarySubtitle(
    sampleIndex: Int?,
    sampleCount: Int,
    observedAt: Date?
  ) -> String {
    var values: [String] = []
    if let sampleIndex, sampleCount > 1 {
      values.append("Round \(sampleIndex + 1) of \(sampleCount)")
    }
    if activeTurn != nil {
      values.append("Active now")
    } else if endpointRow.turnId != nil {
      values.append("Latest reported usage")
    }
    if let chatTurnCount = endpointRow.chatTurnCount, chatTurnCount > 0 {
      values.append("\(chatTurnCount) chat turn\(chatTurnCount == 1 ? "" : "s")")
    }
    if let observedAt {
      values.append("Updated \(FormatClockTime(observedAt))")
    }
    if values.isEmpty {
      return "Most recent reported turn"
    }
    return values.joined(separator: " · ")
  }

  private func RunTokenUsageSamples(_ run: CompletedRun) -> [TokenUsageSample] {
    let samples = run.tokenUsageSamples.filter { $0.usage.isTurnRoundUsage }
    if !samples.isEmpty {
      return samples
    }
    guard let usage = run.tokenUsage, usage.isTurnRoundUsage else {
      return []
    }
    return [TokenUsageSample(usage: usage, observedAt: run.endedAt)]
  }

  private func RunTokenUsageSubtitle(
    run: CompletedRun,
    sampleIndex: Int,
    sampleCount: Int,
    observedAt: Date
  ) -> String {
    var values = [RunStatusText(run.status), run.ElapsedString(), run.RanAtString()]
    if sampleCount > 1 {
      values.insert("Round \(sampleIndex + 1) of \(sampleCount)", at: 1)
    }
    values.append("Updated \(FormatClockTime(observedAt))")
    return values.joined(separator: " · ")
  }

  private func TurnIdentity(threadId: String?, turnId: String) -> String {
    "\(threadId ?? "no-thread"):\(turnId)"
  }

  private func RunStatusText(_ status: TurnExecutionStatus) -> String {
    switch status {
    case .inProgress: return "Working"
    case .completed: return "Completed"
    case .interrupted: return "Interrupted"
    case .failed: return "Failed"
    }
  }

  private func HasGitOrModelInfo() -> Bool {
    endpointRow.activeTurn != nil && (endpointRow.gitInfo?.branch != nil || ModelSummary() != nil)
  }

  private func GitModelLine() -> String {
    var values: [String] = []

    if let branch = endpointRow.gitInfo?.branch {
      var value = branch
      if let sha = endpointRow.gitInfo?.sha {
        value += " · \(String(sha.prefix(7)))"
      }
      values.append(value)
    }

    if let modelSummary = ModelSummary() {
      values.append(modelSummary)
    }

    return values.joined(separator: "   ")
  }

  private func ModelSummary() -> String? {
    guard endpointRow.activeTurn != nil else { return nil }
    let model = endpointRow.model?.trimmingCharacters(in: .whitespacesAndNewlines)
    let thinking = ThinkingLabel(endpointRow.thinkingLevel)
    if let model, !model.isEmpty {
      if let thinking {
        return "Model: \(model) · Thinking: \(thinking)"
      }
      return "Model: \(model)"
    }
    if let thinking {
      return "Thinking: \(thinking)"
    }
    return nil
  }

  private func TurnKindLabel() -> String {
    RuntimeTurnKindLabel(
      scope: endpointRow.scope,
      taskKind: endpointRow.taskKind,
      sessionSource: endpointRow.sessionSource,
      subAgentSource: endpointRow.subAgentSource
    )
  }

  private func TurnKindNoun() -> String {
    RuntimeTurnKindNoun(
      scope: endpointRow.scope,
      taskKind: endpointRow.taskKind,
      sessionSource: endpointRow.sessionSource,
      subAgentSource: endpointRow.subAgentSource
    )
  }

  private func TurnKindNoun(run: CompletedRun) -> String {
    RuntimeTurnKindNoun(
      scope: run.scope,
      taskKind: run.taskKind,
      sessionSource: run.sessionSource,
      subAgentSource: run.subAgentSource
    )
  }

  private func TurnKindForeground() -> Color {
    IsDelegateTurn(
      scope: endpointRow.scope,
      sessionSource: endpointRow.sessionSource,
      subAgentSource: endpointRow.subAgentSource
    ) ? .purple : Color(nsColor: .secondaryLabelColor)
  }

  private func TurnDetailsLine() -> String? {
    var values = [TurnKindLabel()]
    if let threadName = NonEmpty(endpointRow.threadName) {
      values.append("Name: \(threadName)")
    }
    if let turnId = NonEmpty(endpointRow.turnId) {
      values.append("Turn: \(turnId)")
    }
    if let threadId = NonEmpty(endpointRow.threadId) {
      values.append("Thread: \(threadId)")
    }
    if let parentTurnId = NonEmpty(endpointRow.parentTurnId) {
      values.append("\(ParentTurnDetailLabel(taskKind: endpointRow.taskKind)): \(parentTurnId)")
    }
    guard values.count > 1 || endpointRow.activeTurn != nil else {
      return nil
    }
    return values.joined(separator: " · ")
  }

  private func NonEmpty(_ value: String?) -> String? {
    guard let value else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func ThinkingLabel(_ value: String?) -> String? {
    guard let value else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return nil
    }
    return trimmed.replacingOccurrences(of: "_", with: "-")
  }

  private func SessionTokenTitle(usage: TokenUsageInfo) -> String {
    "Session Token Usage - \(FormatTokenCount(usage.totalTokens))"
  }

  private func PlanTitle() -> String {
    let completed = endpointRow.planSteps.filter { $0.status == .completed }.count
    return "Plan (\(completed)/\(endpointRow.planSteps.count))"
  }

  private func PlanIcon(_ status: PlanStepStatus) -> String {
    switch status {
    case .completed: return "✓"
    case .inProgress: return "●"
    case .pending: return "○"
    }
  }

  private func PlanHistoryPage() -> RuntimeHistoryPage<PlanStepInfo> {
    RuntimeHistoryPage(
      items: endpointRow.planSteps, page: planHistoryPage,
      pageSize: RuntimeHistoryPageSize.planSteps)
  }

  private func ShowNewerPlanSteps() {
    planHistoryPage = PlanHistoryPage().newerPage
  }

  private func ShowOlderPlanSteps() {
    planHistoryPage = PlanHistoryPage().olderPage
  }

  private func VisibleFileChanges() -> [FileChangeSummary] {
    guard endpointRow.activeTurn != nil else {
      return []
    }

    if !endpointRow.fileChanges.isEmpty {
      return endpointRow.fileChanges
    }

    return []
  }

  private func FileHistoryPage() -> RuntimeHistoryPage<FileChangeSummary> {
    RuntimeHistoryPage(
      items: VisibleFileChanges(), page: fileHistoryPage, pageSize: RuntimeHistoryPageSize.files)
  }

  private func ShowNewerFiles() {
    fileHistoryPage = FileHistoryPage().newerPage
  }

  private func ShowOlderFiles() {
    fileHistoryPage = FileHistoryPage().olderPage
  }

  private func VisibleCommands() -> [CommandSummary] {
    guard endpointRow.activeTurn != nil else {
      return []
    }

    if !endpointRow.commands.isEmpty {
      return endpointRow.commands
    }

    return []
  }

  private func CommandHistoryPage() -> RuntimeHistoryPage<CommandSummary> {
    RuntimeHistoryPage(
      items: VisibleCommands(), page: commandHistoryPage, pageSize: RuntimeHistoryPageSize.commands)
  }

  private func ShowNewerCommands() {
    commandHistoryPage = CommandHistoryPage().newerPage
  }

  private func ShowOlderCommands() {
    commandHistoryPage = CommandHistoryPage().olderPage
  }

  private func RunHistoryPage() -> RuntimeHistoryPage<CompletedRun> {
    RuntimeHistoryPage(
      items: endpointRow.recentRuns, page: runHistoryPage, pageSize: RuntimeHistoryPageSize.runs)
  }

  private func ShowNewerRuns() {
    runHistoryPage = RunHistoryPage().newerPage
  }

  private func ShowOlderRuns() {
    runHistoryPage = RunHistoryPage().olderPage
  }

  private func ResetHistorySelections() {
    selectedTokenHistoryIndex = 0
    planHistoryPage = 0
    fileHistoryPage = 0
    commandHistoryPage = 0
    runHistoryPage = 0
  }

  private func ErrorCopyText(_ error: ErrorInfo) -> String {
    var lines = [error.message]

    if let details = error.details, !details.isEmpty {
      lines.append(details)
    }

    if error.willRetry {
      lines.append("retrying...")
    }

    return lines.joined(separator: "\n")
  }

  @MainActor
  private func CopyToClipboard(_ value: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(value, forType: .string)
  }

  private func CommandLine(command: CommandSummary) -> String {
    var metadata: [String] = []

    if let exitCode = command.exitCode {
      metadata.append("exit \(exitCode)")
    }

    if let ms = command.durationMs {
      metadata.append(String(format: "%.1fs", Double(ms) / 1000.0))
    }

    let suffix = metadata.isEmpty ? "" : "  \(metadata.joined(separator: "  "))"
    return "• \(Truncate(command.command, limit: 38))\(suffix)"
  }

  private func StatusLabel(_ status: TurnExecutionStatus) -> String {
    switch status {
    case .inProgress: return "Working"
    case .completed: return "Done"
    case .interrupted: return "Interrupted"
    case .failed: return "Failed"
    }
  }

  private func StatusDotColor(_ status: TurnExecutionStatus) -> Color {
    switch status {
    case .inProgress: return .green
    case .completed: return Color(nsColor: .systemGray)
    case .interrupted: return .orange
    case .failed: return .red
    }
  }

  private func Truncate(_ value: String, limit: Int) -> String {
    if value.count <= limit { return value }
    return "\(value.prefix(max(0, limit - 1)))…"
  }
}

private struct TokenUsageHistoryEntry: Identifiable, Equatable {
  let id: String
  let title: String
  let subtitle: String
  let usage: TokenUsageInfo
}

private struct TokenUsageHistoryCard: View {
  let endpointId: String
  let entries: [TokenUsageHistoryEntry]
  @Binding var selectedIndex: Int

  var body: some View {
    if let entry = SelectedEntry {
      SectionCard {
        HStack(spacing: 6) {
          Label("Turn Token Usage", systemImage: "chart.bar.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)

          Spacer(minLength: 4)

          if entries.count > 1 {
            Text("\(ClampedSelectedIndex + 1) of \(entries.count)")
              .font(.system(size: 9, weight: .medium, design: .monospaced))
              .foregroundStyle(.tertiary)
              .accessibilityLabel("\(ClampedSelectedIndex + 1) of \(entries.count)")
              .accessibilityIdentifier("turn.tokenUsageHistory.position.\(endpointId)")

            Button(action: ShowLatestEntry) {
              Text("Latest")
                .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(ClampedSelectedIndex == 0)
            .help("Back to latest turn token usage")
            .accessibilityLabel("Back to latest turn token usage")
            .accessibilityIdentifier("turn.tokenUsageHistory.latest.\(endpointId)")

            Button(action: ShowNewerEntry) {
              Image(systemName: "chevron.left")
                .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(ClampedSelectedIndex == 0)
            .help("Show newer turn token usage")
            .accessibilityLabel("Show newer turn token usage")
            .accessibilityIdentifier("turn.tokenUsageHistory.newer.\(endpointId)")

            Button(action: ShowEarlierEntry) {
              Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(ClampedSelectedIndex >= entries.count - 1)
            .help("Show earlier turn token usage")
            .accessibilityLabel("Show earlier turn token usage")
            .accessibilityIdentifier("turn.tokenUsageHistory.earlier.\(endpointId)")
          }
        }
      } content: {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(entry.title)
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .accessibilityIdentifier("turn.tokenUsageHistory.title.\(endpointId)")

            Spacer(minLength: 4)

            Text(FormatTokenCount(entry.usage.totalTokens))
              .font(.system(size: 10, weight: .medium, design: .monospaced))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }

          Text(entry.subtitle)
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .accessibilityIdentifier("turn.tokenUsageHistory.subtitle.\(endpointId)")

          TokenUsageBarView(usage: entry.usage)
            .frame(maxWidth: .infinity)
            .frame(height: 12)

          Text(TokenUsageDetailText(entry.usage))
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .accessibilityIdentifier("turn.tokenUsageHistory.detail.\(endpointId)")
        }
      }
      .onAppear(perform: ClampSelection)
      .onChange(of: entries.count) { _, _ in
        ClampSelection()
      }
    }
  }

  private var SelectedEntry: TokenUsageHistoryEntry? {
    guard !entries.isEmpty else {
      return nil
    }
    return entries[ClampedSelectedIndex]
  }

  private var ClampedSelectedIndex: Int {
    guard !entries.isEmpty else {
      return 0
    }
    return min(max(0, selectedIndex), entries.count - 1)
  }

  private func ClampSelection() {
    selectedIndex = ClampedSelectedIndex
  }

  private func ShowLatestEntry() {
    selectedIndex = 0
  }

  private func ShowNewerEntry() {
    selectedIndex = max(0, ClampedSelectedIndex - 1)
  }

  private func ShowEarlierEntry() {
    selectedIndex = min(entries.count - 1, ClampedSelectedIndex + 1)
  }
}

private struct RunHistoryRowView: View {
  let run: CompletedRun
  let fallbackModel: String?
  let fallbackModelProvider: String?
  let fallbackThinkingLevel: String?
  let isLastRun: Bool
  let isExpanded: Bool
  let onToggle: () -> Void

  @State private var fileHistoryPage = 0
  @State private var commandHistoryPage = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Button(action: onToggle) {
        HStack(spacing: 6) {
          Circle()
            .fill(StatusColor(run.status))
            .frame(width: 6, height: 6)

          Text(TitleText())
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)

          Spacer(minLength: 4)

          Text(isExpanded ? "▾" : "▸")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if let usage = run.tokenUsage, usage.totalTokens > 0 {
        TokenUsageBarView(usage: usage)
          .frame(maxWidth: .infinity)
          .frame(height: 7)
      }

      if let modelLine = ModelLine() {
        Text(modelLine)
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }

      if isExpanded {
        VStack(alignment: .leading, spacing: 4) {
          Text("Prompt: \(run.promptPreview ?? "Prompt unavailable")")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(2)

          if let turnDetails = TurnDetailsLine() {
            Text(turnDetails)
              .font(.system(size: 10, design: .monospaced))
              .foregroundStyle(.tertiary)
              .lineLimit(3)
              .textSelection(.enabled)
              .accessibilityIdentifier("turn.completedRun.details.\(run.runKey)")
          }

          TimelineBarView(segments: run.TimelineSegments())
            .frame(maxWidth: .infinity)
            .frame(height: 8)

          if !run.fileChanges.isEmpty {
            let filePage = FileHistoryPage()
            VStack(alignment: .leading, spacing: 2) {
              Text("Files touched:")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)

              if run.fileChanges.count > RuntimeHistoryPageSize.files {
                HistoryPagerControls(
                  endpointId: run.runKey,
                  namespace: "runFiles",
                  label: "run file history",
                  positionText: filePage.positionText,
                  canShowNewer: filePage.canShowNewer,
                  canShowOlder: filePage.canShowOlder,
                  onShowNewer: ShowNewerFiles,
                  onShowOlder: ShowOlderFiles
                )
              }

              ForEach(filePage.visibleItems, id: \.path) { change in
                Text("\(change.kind.label)  \((change.path as NSString).lastPathComponent)")
                  .font(.system(size: 10))
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            }
          }

          if !run.commands.isEmpty {
            let commandPage = CommandHistoryPage()
            VStack(alignment: .leading, spacing: 2) {
              Text("Commands:")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)

              if run.commands.count > RuntimeHistoryPageSize.commands {
                HistoryPagerControls(
                  endpointId: run.runKey,
                  namespace: "runCommands",
                  label: "run command history",
                  positionText: commandPage.positionText,
                  canShowNewer: commandPage.canShowNewer,
                  canShowOlder: commandPage.canShowOlder,
                  onShowNewer: ShowNewerCommands,
                  onShowOlder: ShowOlderCommands
                )
              }

              ForEach(commandPage.visibleItems, id: \.command) { command in
                Text("• \(command.command)")
                  .font(.system(size: 10))
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            }
          }

          if let usage = run.tokenUsage, usage.totalTokens > 0 {
            TokenUsageBarView(usage: usage)
              .frame(maxWidth: .infinity)
              .frame(height: 10)

            Text(TokenUsageDetailText(usage))
              .font(.system(size: 10, design: .monospaced))
              .foregroundStyle(.tertiary)
              .lineLimit(1)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 6)
    .padding(.vertical, 4)
    .background(
      Color(nsColor: NSColor.controlBackgroundColor).opacity(0.62),
      in: RoundedRectangle(cornerRadius: 4, style: .continuous)
    )
    .overlay {
      if !isExpanded {
        Rectangle()
          .fill(.clear)
          .contentShape(Rectangle())
          .onTapGesture {
            onToggle()
          }
      }
    }
    .onChange(of: run.runKey) { _, _ in
      fileHistoryPage = 0
      commandHistoryPage = 0
    }
  }

  private func TitleText() -> String {
    let suffix = isLastRun ? " · latest" : ""
    return
      "\(RunKindLabel()) · \(StatusText(run.status)) · \(run.ElapsedString()) · \(run.RanAtString())\(suffix)"
  }

  private func RunKindLabel() -> String {
    RuntimeTurnKindLabel(
      scope: run.scope,
      taskKind: run.taskKind,
      sessionSource: run.sessionSource,
      subAgentSource: run.subAgentSource
    )
  }

  private func TurnDetailsLine() -> String? {
    var values = [RunKindLabel()]
    if let threadName = NonEmpty(run.threadName) {
      values.append("Name: \(threadName)")
    }
    values.append("Turn: \(run.turnId)")
    if let threadId = NonEmpty(run.threadId) {
      values.append("Thread: \(threadId)")
    }
    if let parentTurnId = NonEmpty(run.parentTurnId) {
      values.append("\(ParentTurnDetailLabel(taskKind: run.taskKind)): \(parentTurnId)")
    }
    return values.joined(separator: " · ")
  }

  private func FileHistoryPage() -> RuntimeHistoryPage<FileChangeSummary> {
    RuntimeHistoryPage(
      items: run.fileChanges, page: fileHistoryPage, pageSize: RuntimeHistoryPageSize.files)
  }

  private func ShowNewerFiles() {
    fileHistoryPage = FileHistoryPage().newerPage
  }

  private func ShowOlderFiles() {
    fileHistoryPage = FileHistoryPage().olderPage
  }

  private func CommandHistoryPage() -> RuntimeHistoryPage<CommandSummary> {
    RuntimeHistoryPage(
      items: run.commands, page: commandHistoryPage, pageSize: RuntimeHistoryPageSize.commands)
  }

  private func ShowNewerCommands() {
    commandHistoryPage = CommandHistoryPage().newerPage
  }

  private func ShowOlderCommands() {
    commandHistoryPage = CommandHistoryPage().olderPage
  }

  private func StatusText(_ status: TurnExecutionStatus) -> String {
    switch status {
    case .inProgress: return "Working"
    case .completed: return "Completed"
    case .interrupted: return "Interrupted"
    case .failed: return "Failed"
    }
  }

  private func StatusColor(_ status: TurnExecutionStatus) -> Color {
    switch status {
    case .inProgress: return .green
    case .completed: return Color(nsColor: .systemGray)
    case .interrupted: return .orange
    case .failed: return .red
    }
  }

  private func ModelLine() -> String? {
    let model = NonEmpty(run.model) ?? NonEmpty(fallbackModel)
    let provider = NonEmpty(run.modelProvider) ?? NonEmpty(fallbackModelProvider)
    let thinkingLevel = ThinkingLabel(run.thinkingLevel) ?? ThinkingLabel(fallbackThinkingLevel)

    var details: [String] = []
    if let provider {
      details.append(provider)
    }
    if let thinkingLevel {
      details.append("Thinking: \(thinkingLevel)")
    }

    if let model {
      if details.isEmpty {
        return "Model: \(model)"
      }
      return "Model: \(model) (\(details.joined(separator: ", ")))"
    }

    if let thinkingLevel {
      return "Thinking: \(thinkingLevel)"
    }

    if let provider {
      return "Model Provider: \(provider)"
    }

    return nil
  }

  private func NonEmpty(_ value: String?) -> String? {
    guard let value else {
      return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func ThinkingLabel(_ value: String?) -> String? {
    guard let value else {
      return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return nil
    }

    return trimmed.replacingOccurrences(of: "_", with: "-")
  }
}

private struct SectionCard<Header: View, Content: View>: View {
  @ViewBuilder let header: Header
  @ViewBuilder let content: Content

  init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
    self.header = header()
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      header
      content
    }
    .padding(6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(nsColor: NSColor.controlBackgroundColor).opacity(0.62),
      in: RoundedRectangle(cornerRadius: 6, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .stroke(Color(nsColor: NSColor.separatorColor).opacity(0.3), lineWidth: 0.5)
    )
  }
}

private struct AccordionSectionCard<Content: View>: View {
  let title: String
  let systemImage: String
  let isExpanded: Bool
  let onToggle: () -> Void
  @ViewBuilder let content: Content

  var body: some View {
    SectionCard {
      Button(action: onToggle) {
        HStack(spacing: 6) {
          Label(title, systemImage: systemImage)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)

          Spacer(minLength: 4)

          Text(isExpanded ? "▾" : "▸")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
        }
      }
      .buttonStyle(.plain)
    } content: {
      if isExpanded {
        content
      }
    }
  }
}

private struct HistoryPagerControls: View {
  let endpointId: String
  let namespace: String
  let label: String
  let positionText: String
  let canShowNewer: Bool
  let canShowOlder: Bool
  let onShowNewer: () -> Void
  let onShowOlder: () -> Void

  var body: some View {
    HStack(spacing: 6) {
      Text(positionText)
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .accessibilityLabel(positionText)
        .accessibilityIdentifier("turn.\(namespace)History.position.\(endpointId)")

      Spacer(minLength: 4)

      Button(action: onShowNewer) {
        Image(systemName: "chevron.left")
          .font(.system(size: 9, weight: .semibold))
      }
      .buttonStyle(.plain)
      .disabled(!canShowNewer)
      .help("Show newer \(label)")
      .accessibilityLabel("Show newer \(label)")
      .accessibilityIdentifier("turn.\(namespace)History.newer.\(endpointId)")

      Button(action: onShowOlder) {
        Image(systemName: "chevron.right")
          .font(.system(size: 9, weight: .semibold))
      }
      .buttonStyle(.plain)
      .disabled(!canShowOlder)
      .help("Show older \(label)")
      .accessibilityLabel("Show older \(label)")
      .accessibilityIdentifier("turn.\(namespace)History.older.\(endpointId)")
    }
  }
}

private struct TimelineBarView: View {
  let segments: [TimelineSegment]

  @State private var hoveredIndex: Int?

  var body: some View {
    GeometryReader { geometry in
      let filtered = segments.filter { $0.duration > 0 }
      let totalDuration = filtered.reduce(0.0) { $0 + $1.duration }
      let segmentCount = max(1, filtered.count)

      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(Color(nsColor: NSColor.controlBackgroundColor).opacity(0.8))

        HStack(spacing: 0) {
          ForEach(Array(filtered.enumerated()), id: \.offset) { index, segment in
            let width = SegmentWidth(
              availableWidth: geometry.size.width,
              segmentDuration: segment.duration,
              totalDuration: totalDuration,
              segmentCount: segmentCount
            )

            Rectangle()
              .fill(SegmentFillColor(segment.kind))
              .frame(width: width)
              .overlay(alignment: .trailing) {
                if index < filtered.count - 1 {
                  Rectangle()
                    .fill(Color(nsColor: NSColor.separatorColor).opacity(0.4))
                    .frame(width: 0.5)
                }
              }
              .onHover { hovering in
                hoveredIndex = hovering ? index : nil
              }
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
      }
      .overlay(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .stroke(Color(nsColor: NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
      )
      .overlay(alignment: .leading) {
        if let hoveredIndex,
          hoveredIndex < filtered.count
        {
          let xOffset = HoverOffset(
            availableWidth: geometry.size.width,
            segments: filtered,
            index: hoveredIndex,
            totalDuration: totalDuration,
            segmentCount: segmentCount
          )
          let width = SegmentWidth(
            availableWidth: geometry.size.width,
            segmentDuration: filtered[hoveredIndex].duration,
            totalDuration: totalDuration,
            segmentCount: segmentCount
          )

          RoundedRectangle(cornerRadius: 2, style: .continuous)
            .stroke(Color.primary.opacity(0.4), lineWidth: 1)
            .frame(width: max(0, width - 1), height: max(0, geometry.size.height - 1))
            .offset(x: xOffset + 0.5, y: 0)
        }
      }
      .overlay(alignment: .topLeading) {
        if let hoveredIndex,
          hoveredIndex < filtered.count
        {
          let xOffset = HoverOffset(
            availableWidth: geometry.size.width,
            segments: filtered,
            index: hoveredIndex,
            totalDuration: totalDuration,
            segmentCount: segmentCount
          )
          let width = SegmentWidth(
            availableWidth: geometry.size.width,
            segmentDuration: filtered[hoveredIndex].duration,
            totalDuration: totalDuration,
            segmentCount: segmentCount
          )
          let tooltipMaxWidth = max(120, min(geometry.size.width - 8, 260))
          let tooltipX = max(
            0,
            min(
              xOffset + (width / 2) - (tooltipMaxWidth / 2), geometry.size.width - tooltipMaxWidth))

          Text(SegmentTooltipText(segment: filtered[hoveredIndex]))
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(width: tooltipMaxWidth, alignment: .leading)
            .background(
              Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 4)
            )
            .overlay(
              RoundedRectangle(cornerRadius: 4)
                .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
            .offset(x: tooltipX, y: -18)
            .allowsHitTesting(false)
            .zIndex(2)
        }
      }
    }
  }

  private func SegmentWidth(
    availableWidth: CGFloat,
    segmentDuration: TimeInterval,
    totalDuration: TimeInterval,
    segmentCount: Int
  ) -> CGFloat {
    guard availableWidth > 0 else { return 0 }

    if totalDuration <= 0 {
      return availableWidth / CGFloat(segmentCount)
    }

    return availableWidth * CGFloat(segmentDuration / totalDuration)
  }

  private func HoverOffset(
    availableWidth: CGFloat,
    segments: [TimelineSegment],
    index: Int,
    totalDuration: TimeInterval,
    segmentCount: Int
  ) -> CGFloat {
    guard index > 0 else { return 0 }

    return segments.prefix(index).reduce(0) { total, segment in
      total
        + SegmentWidth(
          availableWidth: availableWidth,
          segmentDuration: segment.duration,
          totalDuration: totalDuration,
          segmentCount: segmentCount)
    }
  }
}

private struct TokenUsageBarView: View {
  let usage: TokenUsageInfo

  @State private var hoveredIndex: Int?

  var body: some View {
    GeometryReader { geometry in
      let segments = BuildUsageSegments(usage)
      let total = segments.reduce(0.0) { $0 + $1.count }
      let maxFraction =
        usage.contextWindow.map { contextWindow in
          contextWindow > 0
            ? CGFloat(min(1.0, Double(usage.totalTokens) / Double(contextWindow)))
            : CGFloat(1.0)
        } ?? 1.0
      let availableWidth = geometry.size.width * maxFraction

      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(Color(nsColor: NSColor.controlBackgroundColor).opacity(0.8))

        HStack(spacing: 0) {
          ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
            let width =
              total > 0
              ? availableWidth * CGFloat(segment.count / total)
              : 0

            Rectangle()
              .fill(segment.color)
              .frame(width: width)
              .onHover { hovering in
                hoveredIndex = hovering ? index : nil
              }
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
      }
      .overlay(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .stroke(Color(nsColor: NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
      )
      .overlay(alignment: .topLeading) {
        if let hoveredIndex,
          hoveredIndex < segments.count
        {
          let xOffset = TokenHoverOffset(
            availableWidth: availableWidth,
            segments: segments,
            index: hoveredIndex,
            total: total
          )
          let width = TokenSegmentWidth(
            availableWidth: availableWidth,
            segmentCount: segments[hoveredIndex].count,
            total: total
          )
          let tooltipMaxWidth = max(100, min(geometry.size.width - 8, 220))
          let tooltipX = max(
            0,
            min(
              xOffset + (width / 2) - (tooltipMaxWidth / 2), geometry.size.width - tooltipMaxWidth))

          Text(TokenSegmentTooltip(segment: segments[hoveredIndex], total: total))
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(width: tooltipMaxWidth, alignment: .leading)
            .background(
              Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 4)
            )
            .overlay(
              RoundedRectangle(cornerRadius: 4)
                .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
            .offset(x: tooltipX, y: -18)
            .allowsHitTesting(false)
            .zIndex(2)
        }
      }
    }
  }

  private func TokenSegmentTooltip(
    segment: (label: String, count: Double, color: Color),
    total: Double
  ) -> String {
    let countText = FormatTokenCount(Int(segment.count))
    guard total > 0 else {
      return "\(segment.label): \(countText)"
    }
    let fraction = Int((segment.count / total * 100).rounded())
    return "\(segment.label): \(countText) (\(fraction)%)"
  }

  private func BuildUsageSegments(_ usage: TokenUsageInfo) -> [(
    label: String, count: Double, color: Color
  )] {
    var segments: [(String, Double, Color)] = []

    let cached = usage.cachedInputTokens
    let freshInput = max(0, usage.inputTokens - cached)

    if cached > 0 {
      segments.append(("Cached Input", Double(cached), Color(nsColor: .systemGray).opacity(0.5)))
    }

    if freshInput > 0 {
      segments.append(("Input", Double(freshInput), Color.accentColor.opacity(0.45)))
    }

    if usage.reasoningTokens > 0 {
      segments.append(
        ("Reasoning", Double(usage.reasoningTokens), Color(nsColor: .systemPink).opacity(0.55)))
    }

    let regularOutput = max(0, usage.outputTokens - usage.reasoningTokens)
    if regularOutput > 0 {
      segments.append(("Output", Double(regularOutput), Color(nsColor: .systemGreen).opacity(0.55)))
    }

    return segments
  }

  private func TokenSegmentWidth(
    availableWidth: CGFloat,
    segmentCount: Double,
    total: Double
  ) -> CGFloat {
    guard total > 0 else {
      return 0
    }

    return availableWidth * CGFloat(segmentCount / total)
  }

  private func TokenHoverOffset(
    availableWidth: CGFloat,
    segments: [(label: String, count: Double, color: Color)],
    index: Int,
    total: Double
  ) -> CGFloat {
    guard index > 0 else {
      return 0
    }

    return segments.prefix(index).reduce(0) { value, segment in
      value
        + TokenSegmentWidth(
          availableWidth: availableWidth, segmentCount: segment.count, total: total)
    }
  }
}

private let durationFormatter: DateComponentsFormatter = {
  let formatter = DateComponentsFormatter()
  formatter.allowedUnits = [.hour, .minute, .second]
  formatter.unitsStyle = .abbreviated
  formatter.maximumUnitCount = 2
  formatter.zeroFormattingBehavior = [.dropLeading]
  return formatter
}()

private let clockTimeFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.timeStyle = .medium
  formatter.dateStyle = .none
  return formatter
}()

private func TokenUsageDetailText(_ usage: TokenUsageInfo) -> String {
  var values = ["In: \(FormatTokenCount(usage.inputTokens))"]
  if usage.cachedInputTokens > 0 {
    values[0] += " (\(FormatTokenCount(usage.cachedInputTokens)) cached)"
  }
  values.append("Out: \(FormatTokenCount(usage.outputTokens))")
  if usage.reasoningTokens > 0 {
    values.append("Reasoning: \(FormatTokenCount(usage.reasoningTokens))")
  }
  return values.joined(separator: " · ")
}

private func SegmentTooltipText(segment: TimelineSegment) -> String {
  let category = SegmentKindLabel(segment.kind)
  let duration = FormatDuration(segment.duration)
  let start = FormatClockTime(segment.startedAt)
  let end = FormatClockTime(segment.endedAt)

  if let label = segment.label, !label.isEmpty {
    return "\(category) · \(duration) · \(start)-\(end) · \(label)"
  }
  return "\(category) · \(duration) · \(start)-\(end)"
}

private func SegmentFillColor(_ kind: TimelineSegmentKind) -> Color {
  switch kind {
  case .category(let category):
    switch category {
    case .tool: return Color(nsColor: .systemIndigo).opacity(0.85)
    case .edit: return Color(nsColor: .systemPurple).opacity(0.85)
    case .waiting: return Color(nsColor: .systemRed).opacity(0.85)
    case .network: return Color(nsColor: .systemBlue).opacity(0.85)
    case .prefill: return Color(nsColor: .systemOrange).opacity(0.85)
    case .reasoning: return Color(nsColor: .systemPink).opacity(0.85)
    case .gen: return Color(nsColor: .systemGreen).opacity(0.85)
    }
  case .idle:
    return Color(nsColor: .systemGray).opacity(0.3)
  }
}

private func SegmentKindLabel(_ kind: TimelineSegmentKind) -> String {
  switch kind {
  case .category(let category):
    switch category {
    case .tool: return "Tool"
    case .edit: return "Edit"
    case .waiting: return "Waiting"
    case .network: return "Network"
    case .prefill: return "Prefill"
    case .reasoning: return "Reasoning"
    case .gen: return "Generation"
    }
  case .idle:
    return "Idle"
  }
}

private func FormatClockTime(_ date: Date) -> String {
  clockTimeFormatter.string(from: date)
}

private func FormatDuration(_ duration: TimeInterval) -> String {
  if duration <= 0 {
    return "0s"
  }
  return durationFormatter.string(from: duration) ?? "0s"
}
