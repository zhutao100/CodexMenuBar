import Foundation
import XCTest

@testable import CodexMenuBar

final class TurnStoreHistoryTests: XCTestCase {
  func testArchivesTurnOnCompletion() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = start.addingTimeInterval(5)

    store.UpsertTurnStarted(endpointId: "ep-1", threadId: "thread-1", turnId: "turn-1", at: start)
    store.RecordProgress(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      category: .gen,
      state: .started,
      label: "Thinking",
      at: start.addingTimeInterval(1)
    )
    store.RecordProgress(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      category: .gen,
      state: .completed,
      label: "Done",
      at: start.addingTimeInterval(2)
    )
    store.RecordFileChange(
      endpointId: "ep-1",
      turnId: "turn-1",
      change: FileChangeSummary(path: "src/main.swift", kind: .update)
    )
    store.RecordCommand(
      endpointId: "ep-1",
      turnId: "turn-1",
      command: CommandSummary(
        command: "swift test",
        status: .completed,
        exitCode: 0,
        durationMs: 1200
      )
    )
    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      status: .completed,
      at: end
    )

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows[0].recentRuns.count, 1)
    XCTAssertEqual(rows[0].recentRuns[0].turnId, "turn-1")
    XCTAssertEqual(rows[0].recentRuns[0].status, .completed)
    XCTAssertEqual(rows[0].recentRuns[0].fileChanges.map(\.path), ["src/main.swift"])
    XCTAssertEqual(rows[0].recentRuns[0].commands.map(\.command), ["swift test"])
    XCTAssertFalse(rows[0].recentRuns[0].TimelineSegments().isEmpty)
  }

  func testArchivesTurnWhenSnapshotReconciliationCompletesIt() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let reconcile = start.addingTimeInterval(3)

    store.UpsertTurnStarted(endpointId: "ep-1", threadId: "thread-1", turnId: "turn-1", at: start)
    store.ReconcileSnapshotActiveTurns(endpointId: "ep-1", activeTurnKeys: [], at: reconcile)

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows[0].recentRuns.count, 1)
    XCTAssertEqual(rows[0].recentRuns[0].turnId, "turn-1")
    XCTAssertEqual(rows[0].recentRuns[0].status, .completed)
  }

  func testSnapshotReconciliationHonorsEndpointTurnKeys() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    store.UpsertTurnStarted(endpointId: "ep-1", threadId: "thread-1", turnId: "turn-1", at: start)
    store.ReconcileSnapshotActiveTurns(
      endpointId: "ep-1",
      activeTurnKeys: ["ep-1:turn-1"],
      at: start.addingTimeInterval(1)
    )

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows.count, 1)
    XCTAssertTrue(rows[0].recentRuns.isEmpty)
    XCTAssertEqual(rows[0].activeTurn?.turnId, "turn-1")
    XCTAssertEqual(rows[0].activeTurn?.status, .inProgress)
  }

  func testSnapshotReconciliationHonorsCodexdThreadTurnKeys() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    store.UpsertTurnStarted(endpointId: "ep-1", threadId: "thread-1", turnId: "turn-1", at: start)
    store.ReconcileSnapshotActiveTurns(
      endpointId: "ep-1",
      activeTurnKeys: ["ep-1:thread-1:turn-1"],
      at: start.addingTimeInterval(1)
    )

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows.count, 1)
    XCTAssertTrue(rows[0].recentRuns.isEmpty)
    XCTAssertEqual(rows[0].activeTurn?.turnId, "turn-1")
    XCTAssertEqual(rows[0].activeTurn?.status, .inProgress)
  }

  func testTokenUsageUpdateBackfillsArchivedRun() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    store.UpsertTurnStarted(endpointId: "ep-1", threadId: "thread-1", turnId: "turn-1", at: start)
    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      status: .completed,
      at: start.addingTimeInterval(1)
    )

    var usage = TokenUsageInfo()
    usage.totalTokens = 123
    usage.inputTokens = 77
    usage.outputTokens = 46

    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      tokenUsageTotal: nil,
      tokenUsageLast: usage
    )

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows[0].recentRuns.count, 1)
    XCTAssertEqual(rows[0].recentRuns[0].tokenUsage, usage)
  }

  func testTokenUsageUpdatesKeepPerTurnSampleHistory() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let second = start.addingTimeInterval(8)
    let third = start.addingTimeInterval(16)

    store.UpsertTurnStarted(endpointId: "ep-1", threadId: "thread-1", turnId: "turn-1", at: start)

    var firstUsage = TokenUsageInfo()
    firstUsage.totalTokens = 100
    firstUsage.inputTokens = 70
    firstUsage.outputTokens = 30
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      tokenUsageTotal: nil,
      tokenUsageLast: firstUsage,
      observedAt: second
    )

    var laterUsage = TokenUsageInfo()
    laterUsage.totalTokens = 160
    laterUsage.inputTokens = 100
    laterUsage.outputTokens = 60
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      tokenUsageTotal: nil,
      tokenUsageLast: laterUsage,
      observedAt: third
    )

    let activeRows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(activeRows[0].tokenUsageSamples.map(\.usage), [firstUsage, laterUsage])
    XCTAssertEqual(activeRows[0].tokenUsageSamples.map(\.observedAt), [second, third])

    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      status: .completed,
      at: third.addingTimeInterval(2)
    )

    let completedRows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(completedRows[0].recentRuns[0].tokenUsage, laterUsage)
    XCTAssertEqual(
      completedRows[0].recentRuns[0].tokenUsageSamples.map(\.usage),
      [
        firstUsage, laterUsage,
      ])
  }

  func testTokenUsageSampleHistorySkipsDuplicateConsecutiveUpdates() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    store.UpsertTurnStarted(endpointId: "ep-1", threadId: "thread-1", turnId: "turn-1", at: start)

    var usage = TokenUsageInfo()
    usage.totalTokens = 100
    usage.inputTokens = 70
    usage.outputTokens = 30

    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      tokenUsageTotal: nil,
      tokenUsageLast: usage,
      observedAt: start.addingTimeInterval(1)
    )
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      tokenUsageTotal: nil,
      tokenUsageLast: usage,
      observedAt: start.addingTimeInterval(2)
    )

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows[0].tokenUsageSamples.count, 1)
    XCTAssertEqual(rows[0].tokenUsageSamples[0].observedAt, start.addingTimeInterval(1))
  }

  func testRepeatedTurnStartedSnapshotsDoNotReplayTokenHistoryIntoActiveTurn() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    store.UpsertTurnStarted(endpointId: "ep-1", threadId: "thread-1", turnId: "turn-1", at: start)

    var firstUsage = TokenUsageInfo()
    firstUsage.totalTokens = 1_200
    firstUsage.inputTokens = 900
    firstUsage.outputTokens = 300
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      tokenUsageTotal: nil,
      tokenUsageLast: firstUsage,
      observedAt: start.addingTimeInterval(1)
    )

    var secondUsage = TokenUsageInfo()
    secondUsage.totalTokens = 1_700
    secondUsage.inputTokens = 1_100
    secondUsage.outputTokens = 600
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      tokenUsageTotal: nil,
      tokenUsageLast: secondUsage,
      observedAt: start.addingTimeInterval(2)
    )

    for index in 0..<5 {
      store.UpsertTurnStarted(
        endpointId: "ep-1",
        threadId: "thread-1",
        turnId: "turn-1",
        at: start.addingTimeInterval(3 + Double(index))
      )
    }

    var activeRows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(
      activeRows[0].activeTurn?.tokenUsageSamples.map(\.usage),
      [
        firstUsage, secondUsage,
      ])
    XCTAssertEqual(activeRows[0].tokenUsageSamples.map(\.usage), [firstUsage, secondUsage])

    var thirdUsage = TokenUsageInfo()
    thirdUsage.totalTokens = 2_300
    thirdUsage.inputTokens = 1_500
    thirdUsage.outputTokens = 800
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      tokenUsageTotal: nil,
      tokenUsageLast: thirdUsage,
      observedAt: start.addingTimeInterval(10)
    )
    store.UpsertTurnStarted(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      at: start.addingTimeInterval(11)
    )

    activeRows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(
      activeRows[0].activeTurn?.tokenUsageSamples.map(\.usage),
      [
        firstUsage, secondUsage, thirdUsage,
      ])

    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      status: .completed,
      at: start.addingTimeInterval(12)
    )

    let completedRows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(
      completedRows[0].recentRuns[0].tokenUsageSamples.map(\.usage),
      [
        firstUsage, secondUsage, thirdUsage,
      ])
  }

  func testTokenUsageRoundHistorySkipsContextEstimateUpdates() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    store.UpsertTurnStarted(endpointId: "ep-1", threadId: "thread-1", turnId: "turn-1", at: start)

    for index in 0..<60 {
      var estimate = TokenUsageInfo()
      estimate.totalTokens = 10_000 + index
      estimate.contextWindow = 128_000
      store.UpdateTokenUsage(
        endpointId: "ep-1",
        threadId: "thread-1",
        turnId: "turn-1",
        tokenUsageTotal: nil,
        tokenUsageLast: estimate,
        observedAt: start.addingTimeInterval(Double(index))
      )
    }

    var firstRound = TokenUsageInfo()
    firstRound.totalTokens = 1_200
    firstRound.inputTokens = 900
    firstRound.cachedInputTokens = 300
    firstRound.outputTokens = 300
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      tokenUsageTotal: nil,
      tokenUsageLast: firstRound,
      observedAt: start.addingTimeInterval(61)
    )

    var secondRound = TokenUsageInfo()
    secondRound.totalTokens = 1_700
    secondRound.inputTokens = 1_100
    secondRound.outputTokens = 600
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      tokenUsageTotal: nil,
      tokenUsageLast: secondRound,
      observedAt: start.addingTimeInterval(62)
    )

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows[0].tokenUsageLast?.totalTokens, 1_700)
    XCTAssertEqual(rows[0].tokenUsageSamples.map(\.usage), [firstRound, secondRound])
    XCTAssertEqual(
      rows[0].tokenUsageSamples.map(\.observedAt),
      [
        start.addingTimeInterval(61),
        start.addingTimeInterval(62),
      ])
  }

  func testContextEstimateDoesNotOverwriteArchivedRoundUsage() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    store.UpsertTurnStarted(endpointId: "ep-1", threadId: "thread-1", turnId: "turn-1", at: start)

    var roundUsage = TokenUsageInfo()
    roundUsage.totalTokens = 1_200
    roundUsage.inputTokens = 800
    roundUsage.outputTokens = 400
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      tokenUsageTotal: nil,
      tokenUsageLast: roundUsage,
      observedAt: start.addingTimeInterval(1)
    )
    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      status: .completed,
      at: start.addingTimeInterval(2)
    )

    var estimate = TokenUsageInfo()
    estimate.totalTokens = 42_000
    estimate.contextWindow = 128_000
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      tokenUsageTotal: nil,
      tokenUsageLast: estimate,
      observedAt: start.addingTimeInterval(3)
    )

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows[0].recentRuns[0].tokenUsage, roundUsage)
    XCTAssertEqual(rows[0].recentRuns[0].tokenUsageSamples.map(\.usage), [roundUsage])
  }

  func testDelegateTurnDoesNotInheritRegularTurnTokenHistory() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    store.UpsertTurnStarted(
      endpointId: "ep-1", threadId: "main-thread", turnId: "turn-1", at: start)

    var regularUsage = TokenUsageInfo()
    regularUsage.totalTokens = 8_000
    regularUsage.inputTokens = 6_200
    regularUsage.outputTokens = 1_800
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "main-thread",
      turnId: "turn-1",
      tokenUsageTotal: nil,
      tokenUsageLast: regularUsage,
      observedAt: start.addingTimeInterval(1)
    )
    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: "main-thread",
      turnId: "turn-1",
      status: .completed,
      at: start.addingTimeInterval(2)
    )

    store.UpsertTurnStarted(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: "delegate-thread:post-turn-review-0",
      at: start.addingTimeInterval(3)
    )
    store.UpdateTurnMetadata(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: "delegate-thread:post-turn-review-0",
      turn: [
        "scope": "delegate",
        "taskKind": "post_turn_completion_review",
        "sessionSource": "subagent_review",
        "subAgentSource": "review",
        "parentTurnId": "turn-1",
        "threadName": "Post-turn review",
      ],
      at: start.addingTimeInterval(3)
    )

    var rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows[0].activeTurn?.turnId, "post-turn-review-0")
    XCTAssertEqual(rows[0].scope, "delegate")
    XCTAssertEqual(rows[0].taskKind, "post_turn_completion_review")
    XCTAssertEqual(rows[0].parentTurnId, "turn-1")
    XCTAssertNil(rows[0].tokenUsageLast)
    XCTAssertTrue(rows[0].tokenUsageSamples.isEmpty)
    XCTAssertEqual(rows[0].recentRuns.first?.tokenUsage, regularUsage)

    var delegateUsage = TokenUsageInfo()
    delegateUsage.totalTokens = 3_200
    delegateUsage.inputTokens = 2_700
    delegateUsage.outputTokens = 500
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: "delegate-thread:post-turn-review-0",
      tokenUsageTotal: nil,
      tokenUsageLast: delegateUsage,
      observedAt: start.addingTimeInterval(4)
    )

    rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows[0].tokenUsageLast, delegateUsage)
    XCTAssertEqual(rows[0].tokenUsageSamples.map(\.usage), [delegateUsage])
  }

  func testDelegateCompletionIsArchivedOnceAcrossCompletionSources() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let turnKey = "delegate-thread:post-turn-review-0"

    store.UpsertTurnStarted(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: turnKey,
      at: start
    )
    store.UpdateTurnMetadata(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: turnKey,
      turn: [
        "scope": "delegate",
        "taskKind": "post_turn_completion_review",
        "sessionSource": "subagent_review",
        "subAgentSource": "review",
        "parentTurnId": "turn-1",
      ],
      at: start
    )
    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: turnKey,
      status: .completed,
      at: start.addingTimeInterval(1)
    )
    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: nil,
      turnId: "post-turn-review-0",
      status: .completed,
      at: start.addingTimeInterval(2)
    )

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows[0].recentRuns.map(\.turnId), ["post-turn-review-0"])
    XCTAssertEqual(rows[0].recentRuns.first?.scope, "delegate")
    XCTAssertEqual(rows[0].recentRuns.first?.taskKind, "post_turn_completion_review")
  }

  func testApplyItemMetadataExtractsPromptPreviewFromStringAndArrayContent() {
    let store = TurnStore()
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    store.ApplyItemMetadata(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      item: [
        "type": "userMessage",
        "content": [
          "Summarize",
          ["type": "text", "text": "this diff"],
          ["type": "input_text", "text": "quickly"],
        ],
      ],
      at: now
    )

    var rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows.first?.promptPreview, "Summarize this diff quickly")

    store.ApplyItemMetadata(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      item: [
        "type": "userMessage",
        "content": "Single string prompt",
      ],
      at: now.addingTimeInterval(1)
    )

    rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows.first?.promptPreview, "Single string prompt")
  }

  func testApplyItemMetadataExtractsPromptPreviewFromPascalCaseUserMessageType() {
    let store = TurnStore()
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    store.ApplyItemMetadata(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      item: [
        "type": "UserMessage",
        "content": [
          ["type": "text", "text": "Plan"],
          ["type": "text", "text": "next steps"],
        ],
      ],
      at: now
    )

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows.first?.promptPreview, "Plan next steps")
  }

  func testTurnMetadataCapturesThinkingLevelAndPersistsToHistory() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let turn: [String: Any] = [
      "id": "turn-1",
      "model": "gpt-5",
      "modelProvider": "openai",
      "reasoningEffort": "high",
    ]

    store.UpsertTurnStarted(endpointId: "ep-1", threadId: "thread-1", turnId: "turn-1", at: start)
    store.UpdateTurnMetadata(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      turn: turn,
      at: start.addingTimeInterval(1)
    )
    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: "thread-1",
      turnId: "turn-1",
      status: .completed,
      at: start.addingTimeInterval(2)
    )

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows.first?.thinkingLevel, "high")
    XCTAssertEqual(rows.first?.recentRuns.first?.thinkingLevel, "high")
  }

  func testCompletedRunHistoryIsCappedAtFifty() {
    let store = TurnStore()
    let base = Date(timeIntervalSince1970: 1_700_000_000)

    for index in 0..<55 {
      let start = base.addingTimeInterval(Double(index) * 10)
      let end = start.addingTimeInterval(2)
      let turnId = "turn-\(index)"
      store.UpsertTurnStarted(endpointId: "ep-1", threadId: "thread-1", turnId: turnId, at: start)
      store.MarkTurnCompleted(
        endpointId: "ep-1",
        threadId: "thread-1",
        turnId: turnId,
        status: .completed,
        at: end
      )
    }

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows[0].recentRuns.count, 50)
    XCTAssertEqual(rows[0].recentRuns.first?.turnId, "turn-54")
    XCTAssertEqual(rows[0].recentRuns.last?.turnId, "turn-5")
  }

  func testCompletedRunHistoryIsIsolatedPerEndpoint() {
    let store = TurnStore()
    let base = Date(timeIntervalSince1970: 1_700_000_000)

    store.UpsertTurnStarted(endpointId: "ep-1", threadId: "thread-a", turnId: "turn-a", at: base)
    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: "thread-a",
      turnId: "turn-a",
      status: .completed,
      at: base.addingTimeInterval(1)
    )

    store.UpsertTurnStarted(
      endpointId: "ep-2",
      threadId: "thread-b",
      turnId: "turn-b",
      at: base.addingTimeInterval(2)
    )
    store.MarkTurnCompleted(
      endpointId: "ep-2",
      threadId: "thread-b",
      turnId: "turn-b",
      status: .interrupted,
      at: base.addingTimeInterval(3)
    )

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1", "ep-2"])
      .sorted { $0.endpointId < $1.endpointId }
    XCTAssertEqual(rows.count, 2)
    XCTAssertEqual(rows[0].endpointId, "ep-1")
    XCTAssertEqual(rows[0].recentRuns.map(\.turnId), ["turn-a"])
    XCTAssertEqual(rows[1].endpointId, "ep-2")
    XCTAssertEqual(rows[1].recentRuns.map(\.turnId), ["turn-b"])
    XCTAssertEqual(rows[1].recentRuns.first?.status, .interrupted)
  }
}
