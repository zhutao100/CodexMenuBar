import Foundation
import Observation

@Observable
final class TurnStore {
  private var turnsByKey: [String: ActiveTurn] = [:]
  private var completedRunsByEndpoint: [String: [CompletedRun]] = [:]
  private var metadataByEndpoint: [String: EndpointMetadata] = [:]
  private(set) var activeEndpointIds: [String] = []
  private let completionRetentionSeconds: TimeInterval = 10
  private let maxCompletedRunsPerEndpoint = 50

  private func LocalTurnKey(
    endpointId: String,
    turnKey: String?,
    threadId: String?,
    turnId: String
  ) -> String {
    if let turnKey = NonEmptyString(turnKey) {
      return "\(endpointId):\(turnKey)"
    }
    if let threadId = NonEmptyString(threadId) {
      return "\(endpointId):\(threadId):\(turnId)"
    }
    return "\(endpointId):\(turnId)"
  }

  private func ResolveLocalTurnKey(
    endpointId: String,
    turnKey: String?,
    threadId: String?,
    turnId: String
  ) -> String {
    let candidates = [
      NonEmptyString(turnKey).map { "\(endpointId):\($0)" },
      NonEmptyString(threadId).map { "\(endpointId):\($0):\(turnId)" },
      "\(endpointId):\(turnId)",
    ].compactMap { $0 }

    if let existing = candidates.first(where: { turnsByKey[$0] != nil }) {
      return existing
    }

    let requestedTurnKey = NonEmptyString(turnKey)
    let requestedThreadId = NonEmptyString(threadId)
    let matchingKeys = turnsByKey.compactMap { key, turn -> String? in
      guard turn.endpointId == endpointId, turn.turnId == turnId else {
        return nil
      }
      if let requestedTurnKey {
        if turn.turnKey == requestedTurnKey {
          return key
        }
        if let requestedThreadId {
          return turn.threadId == requestedThreadId ? key : nil
        }
        return nil
      }
      if let requestedThreadId, turn.threadId == requestedThreadId {
        return key
      }
      return key
    }
    if matchingKeys.count == 1, let onlyMatch = matchingKeys.first {
      return onlyMatch
    }

    return LocalTurnKey(
      endpointId: endpointId, turnKey: turnKey, threadId: threadId, turnId: turnId)
  }

  private func SeedTokenUsageSamplesIfNeeded(
    into turn: ActiveTurn,
    endpointId: String,
    turnKey: String?,
    threadId: String?,
    turnId: String
  ) {
    // codexd snapshots replay already-active turns. Only seed a newly-created
    // local turn; existing turns receive token updates through UpdateTokenUsage.
    guard turn.tokenUsageSamples.isEmpty else {
      return
    }

    guard let metadata = metadataByEndpoint[endpointId],
      MetadataMatchesTurn(metadata, turnKey: turnKey, threadId: threadId, turnId: turnId)
    else {
      return
    }

    turn.UpdateTokenUsage(
      total: metadata.tokenUsageTotal,
      last: metadata.tokenUsageLast,
      at: Date(),
      recordSample: false
    )
    for sample in metadata.tokenUsageSamples {
      turn.UpdateTokenUsage(total: nil, last: sample.usage, at: sample.observedAt)
    }
  }

  private func ApplyTurnIdentity(
    to metadata: inout EndpointMetadata,
    turnKey: String?,
    threadId: String?,
    turnId: String
  ) {
    let changedTurn =
      metadata.turnId != nil
      && (metadata.turnId != turnId
        || (turnKey != nil && metadata.turnKey != nil && metadata.turnKey != turnKey)
        || (threadId != nil && metadata.threadId != nil && metadata.threadId != threadId))
    if changedTurn {
      metadata.promptPreview = nil
      metadata.model = nil
      metadata.modelProvider = nil
      metadata.thinkingLevel = nil
      metadata.cwd = nil
      metadata.sessionSource = nil
      metadata.threadId = nil
      metadata.turnKey = nil
      metadata.scope = nil
      metadata.taskKind = nil
      metadata.subAgentSource = nil
      metadata.parentTurnId = nil
      metadata.threadName = nil
      metadata.tokenUsageTotal = nil
      metadata.tokenUsageLast = nil
      metadata.tokenUsageSamples.removeAll()
    }
    if let turnKey {
      metadata.turnKey = turnKey
    }
    if let threadId {
      metadata.threadId = threadId
    }
    metadata.turnId = turnId
  }

  private func MetadataMatchesTurn(
    _ metadata: EndpointMetadata,
    turnKey: String?,
    threadId: String?,
    turnId: String
  ) -> Bool {
    guard metadata.turnId == turnId else {
      return false
    }
    if let turnKey = NonEmptyString(turnKey), let metadataTurnKey = metadata.turnKey {
      return turnKey == metadataTurnKey
    }
    if let threadId = NonEmptyString(threadId), let metadataThreadId = metadata.threadId {
      return threadId == metadataThreadId
    }
    return true
  }

  private func ThreadIdFromTurnKey(_ turnKey: String?) -> String? {
    guard let turnKey = NonEmptyString(turnKey),
      let separator = turnKey.lastIndex(of: ":"),
      separator > turnKey.startIndex
    else {
      return nil
    }
    return String(turnKey[..<separator])
  }

  private func SessionThreadUsageKey(
    threadId: String?,
    turnKey: String?,
    turnId: String?
  ) -> String? {
    if let threadId = NonEmptyString(threadId) ?? ThreadIdFromTurnKey(turnKey) {
      return "thread:\(threadId)"
    }
    if let turnKey = NonEmptyString(turnKey) {
      return "turnKey:\(turnKey)"
    }
    if let turnId = NonEmptyString(turnId) {
      return "turn:\(turnId)"
    }
    return nil
  }

  private func RecordSessionTokenUsage(
    _ usage: TokenUsageInfo,
    in metadata: inout EndpointMetadata,
    threadId: String?,
    turnKey: String?,
    turnId: String?,
    observedAt: Date
  ) {
    guard usage.totalTokens > 0,
      let key = SessionThreadUsageKey(threadId: threadId, turnKey: turnKey, turnId: turnId)
    else {
      return
    }

    metadata.sessionTokenUsageByThread[key] = TokenUsageSample(usage: usage, observedAt: observedAt)

    if key.hasPrefix("thread:") {
      if let turnKey = NonEmptyString(turnKey) {
        metadata.sessionTokenUsageByThread.removeValue(forKey: "turnKey:\(turnKey)")
      }
      if let turnId = NonEmptyString(turnId) {
        metadata.sessionTokenUsageByThread.removeValue(forKey: "turn:\(turnId)")
      }
    }
  }

  private func ThreadTokenUsageBaseline(
    in metadata: EndpointMetadata?,
    threadId: String?,
    turnKey: String?
  ) -> TokenUsageInfo? {
    guard let metadata,
      let key = SessionThreadUsageKey(threadId: threadId, turnKey: turnKey, turnId: nil),
      let usage = metadata.sessionTokenUsageByThread[key]?.usage,
      usage.isTurnRoundUsage
    else {
      return nil
    }
    return usage
  }

  private func SessionTokenUsage(from metadata: EndpointMetadata?) -> SessionTokenUsageSummary? {
    guard let metadata else {
      return nil
    }

    var usage = TokenUsageInfo()
    for sample in metadata.sessionTokenUsageByThread.values {
      usage.inputTokens += sample.usage.inputTokens
      usage.cachedInputTokens += sample.usage.cachedInputTokens
      usage.outputTokens += sample.usage.outputTokens
      usage.reasoningTokens += sample.usage.reasoningTokens
      usage.totalTokens += sample.usage.totalTokens
    }

    guard usage.totalTokens > 0 else {
      return nil
    }

    return SessionTokenUsageSummary(
      usage: usage,
      threadCount: metadata.sessionTokenUsageByThread.count
    )
  }

  private func CompletedTurnTokenUsageTotal(
    cumulative: TokenUsageInfo?,
    baseline: TokenUsageInfo?,
    samples: [TokenUsageSample],
    fallback: TokenUsageInfo?
  ) -> TokenUsageInfo? {
    if let cumulative, cumulative.isTurnRoundUsage {
      if let baseline {
        let turnScoped = cumulative.subtracting(baseline)
        if turnScoped.isTurnRoundUsage {
          return turnScoped
        }
      } else {
        return cumulative
      }
    }

    let roundUsages = samples.map(\.usage).filter(\.isTurnRoundUsage)
    if roundUsages.isEmpty {
      guard let fallback, fallback.isTurnRoundUsage else {
        return nil
      }
      return fallback
    }

    var total = TokenUsageInfo()
    for usage in roundUsages {
      total.inputTokens += usage.inputTokens
      total.cachedInputTokens += usage.cachedInputTokens
      total.outputTokens += usage.outputTokens
      total.reasoningTokens += usage.reasoningTokens
      total.totalTokens += usage.totalTokens
      total.contextWindow = usage.contextWindow ?? total.contextWindow
    }
    guard total.totalTokens > 0 else {
      return nil
    }
    if let fallback, fallback.isTurnRoundUsage, fallback.totalTokens > total.totalTokens {
      return fallback
    }
    return total
  }

  func UpdateRuntimeMetadata(endpointId: String, cwd: String?, sessionSource: String?) {
    var metadata = metadataByEndpoint[endpointId] ?? EndpointMetadata()
    if let cwd { metadata.cwd = cwd }
    if let sessionSource { metadata.sessionSource = sessionSource }
    metadataByEndpoint[endpointId] = metadata
  }

  func UpsertTurnStarted(
    endpointId: String,
    threadId: String?,
    turnId: String,
    turnKey: String? = nil,
    tokenUsageCumulativeBaseline: TokenUsageInfo? = nil,
    at now: Date
  ) {
    let key = ResolveLocalTurnKey(
      endpointId: endpointId, turnKey: turnKey, threadId: threadId, turnId: turnId)
    if let existing = turnsByKey[key] {
      existing.ApplyStatus(.inProgress, at: now)
      existing.UpdateThreadId(threadId)
      existing.UpdateTurnKey(turnKey)
      let baseline =
        tokenUsageCumulativeBaseline
        ?? ThreadTokenUsageBaseline(
          in: metadataByEndpoint[endpointId], threadId: threadId, turnKey: turnKey)
      existing.SetTokenUsageCumulativeBaselineIfMissing(
        baseline)
      SeedTokenUsageSamplesIfNeeded(
        into: existing, endpointId: endpointId, turnKey: turnKey, threadId: threadId, turnId: turnId
      )
      UpdateTurnMetadata(
        endpointId: endpointId, threadId: threadId, turnId: turnId, turnKey: turnKey, turn: nil,
        at: now)
      return
    }
    let baseline =
      tokenUsageCumulativeBaseline
      ?? ThreadTokenUsageBaseline(
        in: metadataByEndpoint[endpointId], threadId: threadId, turnKey: turnKey)
    let turn = ActiveTurn(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      turnKey: turnKey,
      startedAt: now,
      tokenUsageCumulativeBaseline: baseline
    )
    SeedTokenUsageSamplesIfNeeded(
      into: turn, endpointId: endpointId, turnKey: turnKey, threadId: threadId, turnId: turnId)
    turnsByKey[key] = turn
    UpdateTurnMetadata(
      endpointId: endpointId, threadId: threadId, turnId: turnId, turnKey: turnKey, turn: nil,
      at: now)
  }

  @discardableResult
  func MarkTurnCompleted(
    endpointId: String,
    threadId: String?,
    turnId: String,
    turnKey: String? = nil,
    status: TurnExecutionStatus,
    at now: Date
  ) -> Bool {
    let key = ResolveLocalTurnKey(
      endpointId: endpointId, turnKey: turnKey, threadId: threadId, turnId: turnId)
    if let existing = turnsByKey[key] {
      if existing.status != .inProgress,
        CompletedRunAlreadyArchived(
          endpointId: endpointId, turnKey: turnKey, threadId: threadId, turnId: turnId)
      {
        return false
      }
      existing.ApplyStatus(status, at: now)
      existing.UpdateThreadId(threadId)
      existing.UpdateTurnKey(turnKey)
      let archived = ArchiveCompletedTurnIfNeeded(existing)
      if archived {
        UpdateTurnMetadata(
          endpointId: endpointId, threadId: threadId, turnId: turnId, turnKey: turnKey, turn: nil,
          at: now)
      }
      return archived
    }
    if CompletedRunAlreadyArchived(
      endpointId: endpointId, turnKey: turnKey, threadId: threadId, turnId: turnId)
    {
      return false
    }
    if HasConflictingActiveTurnIdentity(
      endpointId: endpointId, turnKey: turnKey, threadId: threadId, turnId: turnId)
    {
      return false
    }
    let turn = ActiveTurn(
      endpointId: endpointId, threadId: threadId, turnId: turnId, turnKey: turnKey, startedAt: now)
    turn.ApplyStatus(status, at: now)
    turnsByKey[key] = turn
    let archived = ArchiveCompletedTurnIfNeeded(turn)
    if archived {
      UpdateTurnMetadata(
        endpointId: endpointId, threadId: threadId, turnId: turnId, turnKey: turnKey, turn: nil,
        at: now)
    } else {
      turnsByKey.removeValue(forKey: key)
    }
    return archived
  }

  func MarkTurnCompletedIfPresent(
    endpointId: String,
    threadId: String?,
    turnId: String,
    turnKey: String? = nil,
    status: TurnExecutionStatus,
    at now: Date
  ) {
    let key = ResolveLocalTurnKey(
      endpointId: endpointId, turnKey: turnKey, threadId: threadId, turnId: turnId)
    guard let existing = turnsByKey[key] else {
      return
    }
    existing.ApplyStatus(status, at: now)
    existing.UpdateThreadId(threadId)
    existing.UpdateTurnKey(turnKey)
    ArchiveCompletedTurnIfNeeded(existing)
    UpdateTurnMetadata(
      endpointId: endpointId, threadId: threadId, turnId: turnId, turnKey: turnKey, turn: nil,
      at: now)
  }

  func RecordProgress(
    endpointId: String,
    threadId: String?,
    turnId: String,
    turnKey: String? = nil,
    category: ProgressCategory,
    state: ProgressState,
    label: String?,
    at now: Date
  ) {
    let key = ResolveLocalTurnKey(
      endpointId: endpointId, turnKey: turnKey, threadId: threadId, turnId: turnId)
    let turn = turnsByKey[key]
    if turn == nil && state == .completed {
      var metadata = metadataByEndpoint[endpointId] ?? EndpointMetadata()
      ApplyTurnIdentity(to: &metadata, turnKey: turnKey, threadId: threadId, turnId: turnId)
      metadata.lastTraceCategory = category
      if let label, !label.isEmpty {
        metadata.lastTraceLabel = label
      }
      metadata.lastEventAt = now
      metadataByEndpoint[endpointId] = metadata
      return
    }

    let activeTurn =
      turn
      ?? ActiveTurn(
        endpointId: endpointId, threadId: threadId, turnId: turnId, turnKey: turnKey, startedAt: now
      )
    if turn == nil {
      SeedTokenUsageSamplesIfNeeded(
        into: activeTurn, endpointId: endpointId, turnKey: turnKey, threadId: threadId,
        turnId: turnId)
    }
    turnsByKey[key] = activeTurn
    activeTurn.UpdateThreadId(threadId)
    activeTurn.UpdateTurnKey(turnKey)
    activeTurn.ApplyProgress(category: category, state: state, label: label, at: now)

    var metadata = metadataByEndpoint[endpointId] ?? EndpointMetadata()
    ApplyTurnIdentity(to: &metadata, turnKey: turnKey, threadId: threadId, turnId: turnId)
    metadata.lastTraceCategory = category
    if let label, !label.isEmpty {
      metadata.lastTraceLabel = label
    }
    metadata.lastEventAt = now
    metadataByEndpoint[endpointId] = metadata
  }

  func ApplyThreadSnapshot(endpointId: String, thread: [String: Any], at now: Date) {
    var metadata = metadataByEndpoint[endpointId] ?? EndpointMetadata()
    metadata.threadId = NonEmptyString(thread["id"]) ?? metadata.threadId
    metadata.chatTitle = NonEmptyString(thread["title"]) ?? metadata.chatTitle
    metadata.cwd = NonEmptyString(thread["cwd"]) ?? metadata.cwd
    metadata.model = ExtractModelIdentifier(from: thread) ?? metadata.model
    metadata.modelProvider = ExtractModelProvider(from: thread) ?? metadata.modelProvider
    metadata.thinkingLevel = ExtractThinkingLevel(from: thread) ?? metadata.thinkingLevel

    if let fallbackPreview = NonEmptyString(thread["preview"]) {
      metadata.promptPreview = fallbackPreview
    }

    if let turns = thread["turns"] as? [[String: Any]] {
      metadata.chatTurnCount = turns.count
      if let latestTurn = turns.last {
        if let turnId = NonEmptyString(latestTurn["id"]) {
          let turnKey = ExtractTurnKey(from: latestTurn)
          ApplyTurnIdentity(
            to: &metadata, turnKey: turnKey, threadId: metadata.threadId, turnId: turnId)
        }
        metadata.model = ExtractModelIdentifier(from: latestTurn) ?? metadata.model
        metadata.modelProvider = ExtractModelProvider(from: latestTurn) ?? metadata.modelProvider
        metadata.thinkingLevel = ExtractThinkingLevel(from: latestTurn) ?? metadata.thinkingLevel
        ApplyRuntimeContextFields(from: latestTurn, to: &metadata)
        if let threadId = metadata.threadId,
          let turnId = metadata.turnId
        {
          let key = ResolveLocalTurnKey(
            endpointId: endpointId,
            turnKey: metadata.turnKey,
            threadId: threadId,
            turnId: turnId
          )
          turnsByKey[key]?.UpdateThreadId(threadId)
          turnsByKey[key]?.UpdateTurnKey(metadata.turnKey)
        }
        if let promptPreview = ExtractPromptPreview(from: latestTurn) {
          metadata.promptPreview = promptPreview
        }
        if let cwd = ExtractLatestCwd(from: latestTurn) {
          metadata.cwd = cwd
        }
      }
    }
    metadata.lastEventAt = now
    metadataByEndpoint[endpointId] = metadata
  }

  func UpdateTurnMetadata(
    endpointId: String,
    threadId: String?,
    turnId: String,
    turnKey: String? = nil,
    turn: [String: Any]?,
    at now: Date
  ) {
    var metadata = metadataByEndpoint[endpointId] ?? EndpointMetadata()
    ApplyTurnIdentity(to: &metadata, turnKey: turnKey, threadId: threadId, turnId: turnId)
    let localKey = ResolveLocalTurnKey(
      endpointId: endpointId, turnKey: turnKey, threadId: threadId, turnId: turnId)
    let activeTurn = turnsByKey[localKey]
    activeTurn?.UpdateThreadId(threadId)
    activeTurn?.UpdateTurnKey(turnKey)
    if let turn {
      let promptPreview = ExtractPromptPreview(from: turn)
      if let promptPreview {
        metadata.promptPreview = promptPreview
      }

      let model = ExtractModelIdentifier(from: turn)
      let modelProvider = ExtractModelProvider(from: turn)
      let thinkingLevel = ExtractThinkingLevel(from: turn)
      let cwd = NonEmptyString(turn["cwd"])
      let sessionSource = NonEmptyString(turn["sessionSource"])

      metadata.model = model ?? metadata.model
      metadata.modelProvider = modelProvider ?? metadata.modelProvider
      metadata.thinkingLevel = thinkingLevel ?? metadata.thinkingLevel
      metadata.cwd = cwd ?? metadata.cwd
      metadata.sessionSource = sessionSource ?? metadata.sessionSource
      ApplyRuntimeContextFields(from: turn, to: &metadata)
      activeTurn?.UpdateMetadata(
        promptPreview: promptPreview,
        model: model,
        modelProvider: modelProvider,
        thinkingLevel: thinkingLevel,
        cwd: cwd,
        sessionSource: sessionSource,
        scope: NonEmptyString(turn["scope"]),
        taskKind: NonEmptyString(turn["taskKind"]) ?? NonEmptyString(turn["task_kind"]),
        subAgentSource: NonEmptyString(turn["subAgentSource"])
          ?? NonEmptyString(turn["sub_agent_source"]),
        parentTurnId: NonEmptyString(turn["parentTurnId"])
          ?? NonEmptyString(turn["parent_turn_id"]),
        threadName: NonEmptyString(turn["threadName"]) ?? NonEmptyString(turn["thread_name"])
      )
      UpdateCompletedRunMetadata(
        endpointId: endpointId,
        threadId: threadId,
        turnId: turnId,
        turnKey: turnKey,
        promptPreview: promptPreview,
        model: model,
        modelProvider: modelProvider,
        thinkingLevel: thinkingLevel,
        scope: NonEmptyString(turn["scope"]),
        taskKind: NonEmptyString(turn["taskKind"]) ?? NonEmptyString(turn["task_kind"]),
        sessionSource: sessionSource,
        subAgentSource: NonEmptyString(turn["subAgentSource"])
          ?? NonEmptyString(turn["sub_agent_source"]),
        parentTurnId: NonEmptyString(turn["parentTurnId"])
          ?? NonEmptyString(turn["parent_turn_id"]),
        threadName: NonEmptyString(turn["threadName"]) ?? NonEmptyString(turn["thread_name"])
      )
    }
    metadata.lastEventAt = now
    metadataByEndpoint[endpointId] = metadata
  }

  func ApplyItemMetadata(
    endpointId: String,
    threadId: String?,
    turnId: String,
    turnKey: String? = nil,
    item: [String: Any],
    at now: Date
  ) {
    var metadata = metadataByEndpoint[endpointId] ?? EndpointMetadata()
    ApplyTurnIdentity(to: &metadata, turnKey: turnKey, threadId: threadId, turnId: turnId)
    let key = ResolveLocalTurnKey(
      endpointId: endpointId, turnKey: turnKey, threadId: threadId, turnId: turnId)
    let activeTurn = turnsByKey[key]

    let itemType = CanonicalItemType(item["type"])

    if itemType == "usermessage" {
      let pseudoTurn: [String: Any] = [
        "items": [item]
      ]
      if let promptPreview = ExtractPromptPreview(from: pseudoTurn) {
        metadata.promptPreview = promptPreview
        activeTurn?.UpdateMetadata(promptPreview: promptPreview)
        UpdateCompletedRunMetadata(
          endpointId: endpointId,
          threadId: threadId,
          turnId: turnId,
          turnKey: turnKey,
          promptPreview: promptPreview
        )
      }
    }

    if itemType == "commandexecution" {
      if let cwd = NonEmptyString(item["cwd"]) {
        metadata.cwd = cwd
        activeTurn?.UpdateMetadata(cwd: cwd)
      }
    }

    metadata.lastEventAt = now
    metadataByEndpoint[endpointId] = metadata
  }

  private func UpdateCompletedRunMetadata(
    endpointId: String,
    threadId: String?,
    turnId: String,
    turnKey: String? = nil,
    promptPreview: String? = nil,
    model: String? = nil,
    modelProvider: String? = nil,
    thinkingLevel: String? = nil,
    scope: String? = nil,
    taskKind: String? = nil,
    sessionSource: String? = nil,
    subAgentSource: String? = nil,
    parentTurnId: String? = nil,
    threadName: String? = nil
  ) {
    guard var runs = completedRunsByEndpoint[endpointId],
      let index = runs.firstIndex(where: { run in
        RunMatchesTurn(run, turnKey: turnKey, threadId: threadId, turnId: turnId)
      })
    else {
      return
    }

    let run = runs[index]
    runs[index] = CompletedRun(
      endpointId: run.endpointId,
      threadId: run.threadId,
      turnId: run.turnId,
      turnKey: run.turnKey,
      startedAt: run.startedAt,
      endedAt: run.endedAt,
      status: run.status,
      latestLabel: run.latestLabel,
      promptPreview: promptPreview ?? run.promptPreview,
      model: model ?? run.model,
      modelProvider: modelProvider ?? run.modelProvider,
      thinkingLevel: thinkingLevel ?? run.thinkingLevel,
      scope: scope ?? run.scope,
      taskKind: taskKind ?? run.taskKind,
      sessionSource: sessionSource ?? run.sessionSource,
      subAgentSource: subAgentSource ?? run.subAgentSource,
      parentTurnId: parentTurnId ?? run.parentTurnId,
      threadName: threadName ?? run.threadName,
      tokenUsage: run.tokenUsage,
      tokenUsageTotal: run.tokenUsageTotal,
      tokenUsageCumulativeBaseline: run.tokenUsageCumulativeBaseline,
      tokenUsageSamples: run.tokenUsageSamples,
      fileChanges: run.fileChanges,
      commands: run.commands,
      traceHistory: run.traceHistory
    )
    completedRunsByEndpoint[endpointId] = runs
  }

  func UpdateTokenUsage(
    endpointId: String,
    threadId: String?,
    turnId: String?,
    turnKey: String? = nil,
    tokenUsageTotal: TokenUsageInfo?,
    tokenUsageLast: TokenUsageInfo?,
    observedAt: Date = Date()
  ) {
    var metadata = metadataByEndpoint[endpointId] ?? EndpointMetadata()
    let resolvedTurnId =
      turnId
      ?? ResolveKnownTurnId(endpointId: endpointId, turnKey: turnKey, threadId: threadId)
    let resolvedThreadId =
      NonEmptyString(threadId)
      ?? resolvedTurnId.flatMap {
        ResolveThreadId(endpointId: endpointId, turnId: $0, turnKey: turnKey)
      }
      ?? ThreadIdFromTurnKey(turnKey)
    if let resolvedTurnId {
      ApplyTurnIdentity(
        to: &metadata, turnKey: turnKey, threadId: resolvedThreadId, turnId: resolvedTurnId)
    } else if let resolvedThreadId {
      metadata.threadId = resolvedThreadId
    }
    if let tokenUsageTotal {
      metadata.tokenUsageTotal = tokenUsageTotal
      RecordSessionTokenUsage(
        tokenUsageTotal,
        in: &metadata,
        threadId: resolvedThreadId,
        turnKey: turnKey,
        turnId: resolvedTurnId ?? turnId,
        observedAt: observedAt
      )
    }
    if let tokenUsageLast {
      metadata.tokenUsageLast = tokenUsageLast
    }

    guard let resolvedTurnId else {
      metadataByEndpoint[endpointId] = metadata
      return
    }

    let runTokenUsage = tokenUsageLast ?? tokenUsageTotal
    if let runTokenUsage {
      AppendTokenUsageRoundSample(runTokenUsage, at: observedAt, to: &metadata.tokenUsageSamples)
      let key = ResolveLocalTurnKey(
        endpointId: endpointId, turnKey: turnKey, threadId: resolvedThreadId, turnId: resolvedTurnId
      )
      turnsByKey[key]?.UpdateThreadId(resolvedThreadId)
      turnsByKey[key]?.UpdateTokenUsage(
        total: tokenUsageTotal, last: tokenUsageLast, at: observedAt)
    }
    metadataByEndpoint[endpointId] = metadata

    guard var runs = completedRunsByEndpoint[endpointId] else {
      return
    }

    guard
      let index = runs.firstIndex(where: { run in
        RunMatchesTurn(run, turnKey: turnKey, threadId: resolvedThreadId, turnId: resolvedTurnId)
      })
    else {
      return
    }

    let run = runs[index]
    guard let runTokenUsage else {
      return
    }
    var runTokenUsageSamples = run.tokenUsageSamples
    AppendTokenUsageRoundSample(runTokenUsage, at: observedAt, to: &runTokenUsageSamples)
    let updatedRunTokenUsage = runTokenUsage.isTurnRoundUsage ? runTokenUsage : run.tokenUsage
    let updatedRunTokenUsageTotal = CompletedTurnTokenUsageTotal(
      cumulative: tokenUsageTotal,
      baseline: run.tokenUsageCumulativeBaseline,
      samples: runTokenUsageSamples,
      fallback: updatedRunTokenUsage ?? run.tokenUsageTotal
    )
    runs[index] = CompletedRun(
      endpointId: run.endpointId,
      threadId: run.threadId,
      turnId: run.turnId,
      turnKey: run.turnKey,
      startedAt: run.startedAt,
      endedAt: run.endedAt,
      status: run.status,
      latestLabel: run.latestLabel,
      promptPreview: run.promptPreview,
      model: run.model,
      modelProvider: run.modelProvider,
      thinkingLevel: run.thinkingLevel,
      scope: run.scope,
      taskKind: run.taskKind,
      sessionSource: run.sessionSource,
      subAgentSource: run.subAgentSource,
      parentTurnId: run.parentTurnId,
      threadName: run.threadName,
      tokenUsage: updatedRunTokenUsage,
      tokenUsageTotal: updatedRunTokenUsageTotal,
      tokenUsageCumulativeBaseline: run.tokenUsageCumulativeBaseline,
      tokenUsageSamples: runTokenUsageSamples,
      fileChanges: run.fileChanges,
      commands: run.commands,
      traceHistory: run.traceHistory
    )
    completedRunsByEndpoint[endpointId] = runs
  }

  func RecordError(endpointId: String, error: ErrorInfo) {
    var metadata = metadataByEndpoint[endpointId] ?? EndpointMetadata()
    metadata.latestError = error
    metadataByEndpoint[endpointId] = metadata
  }

  func ClearError(endpointId: String) {
    guard var metadata = metadataByEndpoint[endpointId] else { return }
    metadata.latestError = nil
    metadataByEndpoint[endpointId] = metadata
  }

  func UpdateGitInfo(endpointId: String, gitInfo: GitInfo) {
    var metadata = metadataByEndpoint[endpointId] ?? EndpointMetadata()
    metadata.gitInfo = gitInfo
    metadataByEndpoint[endpointId] = metadata
  }

  func UpdateRateLimits(rateLimits: RateLimitInfo) {
    for endpointId in metadataByEndpoint.keys {
      metadataByEndpoint[endpointId]?.rateLimits = rateLimits
    }
    globalRateLimits = rateLimits
  }

  func UpdateSessionSource(endpointId: String, source: String) {
    var metadata = metadataByEndpoint[endpointId] ?? EndpointMetadata()
    metadata.sessionSource = source
    metadataByEndpoint[endpointId] = metadata
  }

  func UpdatePlan(
    endpointId: String,
    turnId: String,
    turnKey: String? = nil,
    threadId: String? = nil,
    steps: [PlanStepInfo],
    explanation: String?
  ) {
    let key = ResolveLocalTurnKey(
      endpointId: endpointId, turnKey: turnKey, threadId: threadId, turnId: turnId)
    turnsByKey[key]?.UpdatePlan(steps: steps, explanation: explanation)
  }

  func RecordFileChange(
    endpointId: String,
    turnId: String,
    turnKey: String? = nil,
    threadId: String? = nil,
    change: FileChangeSummary
  ) {
    let key = ResolveLocalTurnKey(
      endpointId: endpointId, turnKey: turnKey, threadId: threadId, turnId: turnId)
    turnsByKey[key]?.UpsertFileChange(change)
  }

  func RecordCommand(
    endpointId: String,
    turnId: String,
    turnKey: String? = nil,
    threadId: String? = nil,
    command: CommandSummary
  ) {
    let key = ResolveLocalTurnKey(
      endpointId: endpointId, turnKey: turnKey, threadId: threadId, turnId: turnId)
    turnsByKey[key]?.UpsertCommand(command)
  }

  var globalRateLimits: RateLimitInfo?

  func ReconcileSnapshotActiveTurns(endpointId: String, activeTurnKeys: [String], at now: Date) {
    let activeSet = Set(activeTurnKeys)
    for turn in turnsByKey.values {
      guard turn.endpointId == endpointId else {
        continue
      }
      guard turn.status == .inProgress else {
        continue
      }
      let key = LocalTurnKey(
        endpointId: endpointId, turnKey: turn.turnKey, threadId: turn.threadId, turnId: turn.turnId)
      let legacyKey = "\(endpointId):\(turn.turnId)"
      let threadKey = turn.threadId.map { "\(endpointId):\($0):\(turn.turnId)" }
      let isActive =
        activeSet.contains(key) || activeSet.contains(legacyKey)
        || threadKey.map(activeSet.contains) == true
      if isActive { continue }
      turn.ApplyStatus(.completed, at: now)
      ArchiveCompletedTurnIfNeeded(turn)
    }
  }

  func ResolveThreadId(endpointId: String, turnId: String, turnKey: String? = nil) -> String? {
    let key = ResolveLocalTurnKey(
      endpointId: endpointId,
      turnKey: turnKey,
      threadId: nil,
      turnId: turnId
    )
    return turnsByKey[key]?.threadId ?? metadataByEndpoint[endpointId]?.threadId
  }

  func ResolveActiveThreadId(endpointId: String, turnId: String, turnKey: String? = nil) -> String?
  {
    if let turnKey = NonEmptyString(turnKey) {
      return turnsByKey["\(endpointId):\(turnKey)"]?.threadId
    }

    let legacyKey = "\(endpointId):\(turnId)"
    if let threadId = turnsByKey[legacyKey]?.threadId {
      return threadId
    }

    let matchingTurns = turnsByKey.values.filter { turn in
      turn.endpointId == endpointId && turn.turnId == turnId
    }
    guard matchingTurns.count == 1 else {
      return nil
    }
    return matchingTurns.first?.threadId
  }

  func ResolveKnownTurnId(endpointId: String, turnKey: String?, threadId: String?) -> String? {
    if let turnKey = NonEmptyString(turnKey),
      let directTurn = turnsByKey["\(endpointId):\(turnKey)"]
    {
      return directTurn.turnId
    }

    let activeMatches = Set(
      turnsByKey.values.compactMap { turn -> String? in
        guard turn.endpointId == endpointId else {
          return nil
        }
        if let turnKey = NonEmptyString(turnKey) {
          return turn.turnKey == turnKey ? turn.turnId : nil
        }
        if let threadId = NonEmptyString(threadId) {
          return turn.threadId == threadId ? turn.turnId : nil
        }
        return nil
      })
    if activeMatches.count == 1 {
      return activeMatches.first
    }

    let completedMatches =
      Set(
        completedRunsByEndpoint[endpointId]?.compactMap { run -> String? in
          if let turnKey = NonEmptyString(turnKey) {
            return run.turnKey == turnKey ? run.turnId : nil
          }
          if let threadId = NonEmptyString(threadId) {
            return run.threadId == threadId ? run.turnId : nil
          }
          return nil
        } ?? [])
    if completedMatches.count == 1 {
      return completedMatches.first
    }
    return nil
  }

  func Tick(now: Date) {
    let expiredKeys = turnsByKey.compactMap { key, turn -> String? in
      guard let endedAt = turn.endedAt else {
        return nil
      }
      if now.timeIntervalSince(endedAt) >= completionRetentionSeconds {
        return key
      }
      return nil
    }
    for key in expiredKeys {
      turnsByKey.removeValue(forKey: key)
    }
  }

  func Snapshot() -> [ActiveTurn] {
    turnsByKey.values.sorted { lhs, rhs in
      if lhs.status == .inProgress && rhs.status != .inProgress {
        return true
      }
      if lhs.status != .inProgress && rhs.status == .inProgress {
        return false
      }
      if lhs.startedAt != rhs.startedAt {
        return lhs.startedAt > rhs.startedAt
      }
      let lhsThreadId = lhs.threadId ?? ""
      let rhsThreadId = rhs.threadId ?? ""
      if lhsThreadId != rhsThreadId {
        return lhsThreadId < rhsThreadId
      }
      if lhs.endpointId != rhs.endpointId {
        return lhs.endpointId < rhs.endpointId
      }
      return lhs.turnId < rhs.turnId
    }
  }

  func RunningTurnCount() -> Int {
    turnsByKey.values.filter { $0.status == .inProgress }.count
  }

  func EndpointRows(activeEndpointIds: [String]) -> [EndpointRow] {
    var endpointIds = Set(activeEndpointIds)
    var activeTurnByEndpoint: [String: ActiveTurn] = [:]

    for turn in turnsByKey.values where turn.status == .inProgress {
      endpointIds.insert(turn.endpointId)

      if let existing = activeTurnByEndpoint[turn.endpointId] {
        if turn.startedAt != existing.startedAt {
          if turn.startedAt > existing.startedAt {
            activeTurnByEndpoint[turn.endpointId] = turn
          }
          continue
        }

        let turnThreadId = turn.threadId ?? ""
        let existingThreadId = existing.threadId ?? ""
        if turnThreadId != existingThreadId {
          if turnThreadId < existingThreadId {
            activeTurnByEndpoint[turn.endpointId] = turn
          }
          continue
        }

        if turn.turnId < existing.turnId {
          activeTurnByEndpoint[turn.endpointId] = turn
        }
      } else {
        activeTurnByEndpoint[turn.endpointId] = turn
      }
    }

    let sortedEndpointIds = endpointIds.sorted()
    return sortedEndpointIds.map { endpointId in
      let activeTurn = activeTurnByEndpoint[endpointId]
      let metadata = metadataByEndpoint[endpointId]
      let isActive = activeTurn != nil
      let promptPreview =
        isActive ? activeTurn?.promptPreview ?? metadata?.promptPreview : metadata?.promptPreview
      let cwd = isActive ? activeTurn?.cwd ?? metadata?.cwd : metadata?.cwd
      let model = isActive ? activeTurn?.model ?? metadata?.model : metadata?.model
      let modelProvider =
        isActive ? activeTurn?.modelProvider ?? metadata?.modelProvider : metadata?.modelProvider
      let thinkingLevel =
        isActive ? activeTurn?.thinkingLevel ?? metadata?.thinkingLevel : metadata?.thinkingLevel
      let sessionSource =
        isActive ? activeTurn?.sessionSource ?? metadata?.sessionSource : metadata?.sessionSource
      let tokenUsageTotal = isActive ? activeTurn?.tokenUsageTotal : metadata?.tokenUsageTotal
      let tokenUsageLast = isActive ? activeTurn?.tokenUsageLast : metadata?.tokenUsageLast
      let tokenUsageSamples =
        isActive ? activeTurn?.tokenUsageSamples ?? [] : metadata?.tokenUsageSamples ?? []
      return EndpointRow(
        endpointId: endpointId,
        activeTurn: activeTurn,
        recentRuns: completedRunsByEndpoint[endpointId] ?? [],
        chatTitle: metadata?.chatTitle,
        promptPreview: promptPreview,
        chatTurnCount: metadata?.chatTurnCount,
        cwd: cwd,
        model: model,
        modelProvider: modelProvider,
        thinkingLevel: thinkingLevel,
        threadId: activeTurn?.threadId ?? metadata?.threadId,
        turnId: activeTurn?.turnId ?? metadata?.turnId,
        turnKey: activeTurn?.turnKey ?? metadata?.turnKey,
        scope: activeTurn?.scope ?? metadata?.scope,
        taskKind: activeTurn?.taskKind ?? metadata?.taskKind,
        subAgentSource: activeTurn?.subAgentSource ?? metadata?.subAgentSource,
        parentTurnId: activeTurn?.parentTurnId ?? metadata?.parentTurnId,
        threadName: activeTurn?.threadName ?? metadata?.threadName,
        lastTraceCategory: metadata?.lastTraceCategory,
        lastTraceLabel: activeTurn?.latestLabel ?? metadata?.lastTraceLabel,
        lastEventAt: metadata?.lastEventAt,
        tokenUsageTotal: tokenUsageTotal,
        tokenUsageLast: tokenUsageLast,
        tokenUsageSamples: tokenUsageSamples,
        sessionTokenUsage: SessionTokenUsage(from: metadata),
        latestError: metadata?.latestError,
        fileChanges: activeTurn?.fileChanges ?? [],
        commands: activeTurn?.commands ?? [],
        planSteps: activeTurn?.planSteps ?? [],
        planExplanation: activeTurn?.planExplanation,
        gitInfo: metadata?.gitInfo,
        rateLimits: metadata?.rateLimits ?? globalRateLimits,
        sessionSource: sessionSource
      )
    }
  }

  func SetActiveEndpointIds(_ endpointIds: [String]) {
    activeEndpointIds = endpointIds
  }

  var EndpointRows: [EndpointRow] {
    EndpointRows(activeEndpointIds: activeEndpointIds)
  }

  @discardableResult
  private func ArchiveCompletedTurnIfNeeded(_ turn: ActiveTurn) -> Bool {
    guard turn.status != .inProgress, let endedAt = turn.endedAt else {
      return false
    }

    if CompletedRunAlreadyArchived(
      endpointId: turn.endpointId,
      turnKey: turn.turnKey,
      threadId: turn.threadId,
      turnId: turn.turnId)
    {
      return false
    }

    var runs = completedRunsByEndpoint[turn.endpointId] ?? []
    let metadata = metadataByEndpoint[turn.endpointId]
    let metadataMatchesTurn =
      metadata.map {
        MetadataMatchesTurn($0, turnKey: turn.turnKey, threadId: turn.threadId, turnId: turn.turnId)
      } == true
    let metadataTokenSamples = metadataMatchesTurn ? metadata?.tokenUsageSamples ?? [] : []
    let tokenUsageSamples =
      turn.tokenUsageSamples.isEmpty ? metadataTokenSamples : turn.tokenUsageSamples
    let tokenUsage =
      tokenUsageSamples.last?.usage ?? turn.tokenUsageLast ?? metadata?.tokenUsageLast
    let tokenUsageTotal = CompletedTurnTokenUsageTotal(
      cumulative: turn.tokenUsageTotal ?? (metadataMatchesTurn ? metadata?.tokenUsageTotal : nil),
      baseline: turn.tokenUsageCumulativeBaseline,
      samples: tokenUsageSamples,
      fallback: tokenUsage
    )
    runs.insert(
      CompletedRun(
        endpointId: turn.endpointId,
        threadId: turn.threadId,
        turnId: turn.turnId,
        turnKey: turn.turnKey,
        startedAt: turn.startedAt,
        endedAt: endedAt,
        status: turn.status,
        latestLabel: turn.latestLabel,
        promptPreview: turn.promptPreview ?? metadata?.promptPreview,
        model: turn.model ?? metadata?.model,
        modelProvider: turn.modelProvider ?? metadata?.modelProvider,
        thinkingLevel: turn.thinkingLevel ?? metadata?.thinkingLevel,
        scope: turn.scope ?? metadata?.scope,
        taskKind: turn.taskKind ?? metadata?.taskKind,
        sessionSource: turn.sessionSource ?? metadata?.sessionSource,
        subAgentSource: turn.subAgentSource ?? metadata?.subAgentSource,
        parentTurnId: turn.parentTurnId ?? metadata?.parentTurnId,
        threadName: turn.threadName ?? metadata?.threadName,
        tokenUsage: tokenUsage?.isTurnRoundUsage == true ? tokenUsage : nil,
        tokenUsageTotal: tokenUsageTotal,
        tokenUsageCumulativeBaseline: turn.tokenUsageCumulativeBaseline,
        tokenUsageSamples: tokenUsageSamples,
        fileChanges: turn.fileChanges,
        commands: turn.commands,
        traceHistory: turn.traceHistory
      ),
      at: 0
    )

    if runs.count > maxCompletedRunsPerEndpoint {
      runs.removeLast(runs.count - maxCompletedRunsPerEndpoint)
    }
    completedRunsByEndpoint[turn.endpointId] = runs
    return true
  }

  private func CompletedRunAlreadyArchived(
    endpointId: String,
    turnKey: String?,
    threadId: String?,
    turnId: String
  ) -> Bool {
    completedRunsByEndpoint[endpointId]?.contains {
      RunMatchesTurn($0, turnKey: turnKey, threadId: threadId, turnId: turnId)
    } == true
  }

  private func HasConflictingActiveTurnIdentity(
    endpointId: String,
    turnKey: String?,
    threadId: String?,
    turnId: String
  ) -> Bool {
    guard let requestedTurnKey = NonEmptyString(turnKey) else {
      return false
    }

    let requestedThreadId = NonEmptyString(threadId)
    return turnsByKey.values.contains { turn in
      guard turn.endpointId == endpointId, turn.turnId == turnId else {
        return false
      }
      if turn.turnKey == requestedTurnKey {
        return false
      }
      if let requestedThreadId, turn.threadId == requestedThreadId {
        return false
      }
      return true
    }
  }

  private func ExtractPromptPreview(from turn: [String: Any]) -> String? {
    if let promptPreview =
      NonEmptyString(turn["promptPreview"]) ?? NonEmptyString(turn["prompt_preview"])
      ?? NonEmptyString(turn["prompt"])
    {
      return promptPreview
    }

    guard let items = turn["items"] as? [[String: Any]] else {
      return nil
    }

    for item in items.reversed() {
      guard CanonicalItemType(item["type"]) == "usermessage" else {
        continue
      }

      if let preview = ExtractContentPreview(item["content"]) {
        return preview
      }
    }

    return nil
  }

  private func ExtractContentPreview(_ content: Any?) -> String? {
    if let value = NonEmptyString(content) {
      return value
    }

    if let dict = content as? [String: Any], let value = NonEmptyString(dict["text"]) {
      return value
    }

    guard let items = content as? [Any] else {
      return nil
    }

    let textParts = items.compactMap { item -> String? in
      if let text = NonEmptyString(item) {
        return text
      }

      if let dict = item as? [String: Any] {
        return NonEmptyString(dict["text"])
      }

      return nil
    }
    let combined = textParts.joined(separator: " ").trimmingCharacters(
      in: .whitespacesAndNewlines)
    return combined.isEmpty ? nil : combined
  }

  private func RunMatchesTurn(
    _ run: CompletedRun,
    turnKey: String?,
    threadId: String?,
    turnId: String
  ) -> Bool {
    guard run.turnId == turnId else {
      return false
    }

    if let turnKey = NonEmptyString(turnKey), let runTurnKey = NonEmptyString(run.turnKey) {
      if turnKey == runTurnKey {
        return true
      }
      if let threadId = NonEmptyString(threadId), let runThreadId = NonEmptyString(run.threadId) {
        return threadId == runThreadId
      }
      return IsPostTurnReviewRun(run)
    }
    if let threadId = NonEmptyString(threadId), let runThreadId = run.threadId {
      return threadId == runThreadId
    }
    return true
  }

  private func IsPostTurnReviewRun(_ run: CompletedRun) -> Bool {
    IsPostTurnReviewTaskKind(run.taskKind) || IsPostTurnReviewTurnId(run.turnId)
  }

  private func IsPostTurnReviewTaskKind(_ value: String?) -> Bool {
    NonEmptyString(value)?.lowercased() == "post_turn_completion_review"
  }

  private func IsPostTurnReviewTurnId(_ turnId: String) -> Bool {
    turnId.hasPrefix("post-turn-review")
  }

  private func ExtractTurnKey(from payload: [String: Any]) -> String? {
    NonEmptyString(payload["key"]) ?? NonEmptyString(payload["turnKey"])
      ?? NonEmptyString(payload["turn_key"])
  }

  private func ApplyRuntimeContextFields(
    from payload: [String: Any],
    to metadata: inout EndpointMetadata
  ) {
    metadata.turnKey = ExtractTurnKey(from: payload) ?? metadata.turnKey
    metadata.scope = NonEmptyString(payload["scope"]) ?? metadata.scope
    metadata.taskKind =
      NonEmptyString(payload["taskKind"]) ?? NonEmptyString(payload["task_kind"])
      ?? metadata.taskKind
    metadata.sessionSource =
      NonEmptyString(payload["sessionSource"]) ?? NonEmptyString(payload["session_source"])
      ?? metadata.sessionSource
    metadata.subAgentSource =
      NonEmptyString(payload["subAgentSource"]) ?? NonEmptyString(payload["sub_agent_source"])
      ?? metadata.subAgentSource
    metadata.parentTurnId =
      NonEmptyString(payload["parentTurnId"]) ?? NonEmptyString(payload["parent_turn_id"])
      ?? metadata.parentTurnId
    metadata.threadName =
      NonEmptyString(payload["threadName"]) ?? NonEmptyString(payload["thread_name"])
      ?? metadata.threadName
  }

  private func ExtractLatestCwd(from turn: [String: Any]) -> String? {
    guard let items = turn["items"] as? [[String: Any]] else {
      return nil
    }

    for item in items.reversed() {
      guard CanonicalItemType(item["type"]) == "commandexecution" else {
        continue
      }
      if let cwd = NonEmptyString(item["cwd"]) {
        return cwd
      }
    }

    return nil
  }

  private func NonEmptyString(_ value: Any?) -> String? {
    guard let value = value as? String else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func CanonicalItemType(_ value: Any?) -> String? {
    guard let value = NonEmptyString(value) else {
      return nil
    }
    return
      value
      .replacingOccurrences(of: "_", with: "")
      .lowercased()
  }

  private func ExtractModelIdentifier(from payload: [String: Any]) -> String? {
    let directKeys = ["model", "modelSlug", "model_slug", "modelName", "model_name"]
    for key in directKeys {
      if let value = NonEmptyString(payload[key]) {
        return value
      }
    }

    if let model = payload["model"] as? [String: Any] {
      if let value = NonEmptyString(model["slug"]) ?? NonEmptyString(model["name"])
        ?? NonEmptyString(model["id"])
      {
        return value
      }
    }

    if let modelInfo = payload["modelInfo"] as? [String: Any] {
      if let value = NonEmptyString(modelInfo["slug"]) ?? NonEmptyString(modelInfo["name"])
        ?? NonEmptyString(modelInfo["id"])
      {
        return value
      }
    }

    return nil
  }

  private func ExtractModelProvider(from payload: [String: Any]) -> String? {
    let directKeys = ["modelProvider", "model_provider", "provider", "modelVendor", "model_vendor"]
    for key in directKeys {
      if let value = NonEmptyString(payload[key]) {
        return value
      }
    }

    if let model = payload["model"] as? [String: Any] {
      if let value = NonEmptyString(model["provider"]) ?? NonEmptyString(model["vendor"]) {
        return value
      }
    }

    if let modelInfo = payload["modelInfo"] as? [String: Any] {
      if let value = NonEmptyString(modelInfo["provider"]) ?? NonEmptyString(modelInfo["vendor"]) {
        return value
      }
    }

    return nil
  }

  private func ExtractThinkingLevel(from payload: [String: Any]) -> String? {
    let directKeys = [
      "thinkingLevel",
      "thinking_level",
      "reasoningEffort",
      "reasoning_effort",
      "effort",
    ]
    for key in directKeys {
      if let value = NonEmptyString(payload[key]) {
        return value
      }
    }

    if let reasoning = payload["reasoning"] as? [String: Any] {
      if let value = NonEmptyString(reasoning["effort"]) {
        return value
      }
    }

    if let model = payload["model"] as? [String: Any] {
      if let value = NonEmptyString(model["reasoningEffort"])
        ?? NonEmptyString(model["reasoning_effort"])
        ?? NonEmptyString(model["effort"])
      {
        return value
      }
    }

    if let modelInfo = payload["modelInfo"] as? [String: Any] {
      if let value = NonEmptyString(modelInfo["reasoningEffort"])
        ?? NonEmptyString(modelInfo["reasoning_effort"])
        ?? NonEmptyString(modelInfo["effort"])
      {
        return value
      }
    }

    return nil
  }
}
