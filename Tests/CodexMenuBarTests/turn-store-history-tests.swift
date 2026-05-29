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

  func testSessionTokenUsageAggregatesLatestThreadTotals() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    store.UpsertTurnStarted(
      endpointId: "ep-1", threadId: "main-thread", turnId: "turn-1", at: start)

    var mainTotal = TokenUsageInfo()
    mainTotal.totalTokens = 10_000
    mainTotal.inputTokens = 7_000
    mainTotal.cachedInputTokens = 2_000
    mainTotal.outputTokens = 3_000
    var mainRound = TokenUsageInfo()
    mainRound.totalTokens = 2_500
    mainRound.inputTokens = 1_800
    mainRound.outputTokens = 700
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "main-thread",
      turnId: "turn-1",
      tokenUsageTotal: mainTotal,
      tokenUsageLast: mainRound,
      observedAt: start.addingTimeInterval(1)
    )

    store.UpsertTurnStarted(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: "delegate-thread:post-turn-review-0",
      at: start.addingTimeInterval(2)
    )
    var delegateTotal = TokenUsageInfo()
    delegateTotal.totalTokens = 3_200
    delegateTotal.inputTokens = 2_700
    delegateTotal.cachedInputTokens = 800
    delegateTotal.outputTokens = 500
    delegateTotal.reasoningTokens = 120
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: "delegate-thread:post-turn-review-0",
      tokenUsageTotal: delegateTotal,
      tokenUsageLast: delegateTotal,
      observedAt: start.addingTimeInterval(3)
    )

    var rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows[0].sessionTokenUsage?.threadCount, 2)
    XCTAssertEqual(rows[0].sessionTokenUsage?.usage.totalTokens, 13_200)
    XCTAssertEqual(rows[0].sessionTokenUsage?.usage.inputTokens, 9_700)
    XCTAssertEqual(rows[0].sessionTokenUsage?.usage.cachedInputTokens, 2_800)
    XCTAssertEqual(rows[0].sessionTokenUsage?.usage.outputTokens, 3_500)
    XCTAssertEqual(rows[0].sessionTokenUsage?.usage.reasoningTokens, 120)
    XCTAssertNil(rows[0].sessionTokenUsage?.usage.contextWindow)

    var updatedMainTotal = TokenUsageInfo()
    updatedMainTotal.totalTokens = 12_400
    updatedMainTotal.inputTokens = 8_400
    updatedMainTotal.cachedInputTokens = 2_800
    updatedMainTotal.outputTokens = 4_000
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "main-thread",
      turnId: "turn-1",
      tokenUsageTotal: updatedMainTotal,
      tokenUsageLast: mainRound,
      observedAt: start.addingTimeInterval(4)
    )

    rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows[0].sessionTokenUsage?.threadCount, 2)
    XCTAssertEqual(rows[0].sessionTokenUsage?.usage.totalTokens, 15_600)
    XCTAssertEqual(rows[0].sessionTokenUsage?.usage.inputTokens, 11_100)
    XCTAssertEqual(rows[0].sessionTokenUsage?.usage.cachedInputTokens, 3_600)
    XCTAssertEqual(rows[0].sessionTokenUsage?.usage.outputTokens, 4_500)
  }

  func testTurnKeyOnlyTokenUsageContributesToSessionAggregateByResolvedThread() {
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

    var firstTotal = TokenUsageInfo()
    firstTotal.totalTokens = 3_200
    firstTotal.inputTokens = 2_700
    firstTotal.outputTokens = 500
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: nil,
      turnId: nil,
      turnKey: turnKey,
      tokenUsageTotal: firstTotal,
      tokenUsageLast: firstTotal,
      observedAt: start.addingTimeInterval(1)
    )

    var secondTotal = TokenUsageInfo()
    secondTotal.totalTokens = 4_100
    secondTotal.inputTokens = 3_400
    secondTotal.outputTokens = 700
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: turnKey,
      tokenUsageTotal: secondTotal,
      tokenUsageLast: secondTotal,
      observedAt: start.addingTimeInterval(2)
    )

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows[0].sessionTokenUsage?.threadCount, 1)
    XCTAssertEqual(rows[0].sessionTokenUsage?.usage.totalTokens, 4_100)
    XCTAssertEqual(rows[0].sessionTokenUsage?.usage.inputTokens, 3_400)
    XCTAssertEqual(rows[0].sessionTokenUsage?.usage.outputTokens, 700)
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

  func testTurnKeyOnlyTokenUsageRefreshesActivePostTurnReview() {
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

    var delegateUsage = TokenUsageInfo()
    delegateUsage.totalTokens = 3_920
    delegateUsage.inputTokens = 3_400
    delegateUsage.cachedInputTokens = 1_300
    delegateUsage.outputTokens = 520
    delegateUsage.reasoningTokens = 180
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: nil,
      turnKey: turnKey,
      tokenUsageTotal: nil,
      tokenUsageLast: delegateUsage,
      observedAt: start.addingTimeInterval(1)
    )

    var rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows[0].activeTurn?.turnId, "post-turn-review-0")
    XCTAssertEqual(rows[0].turnKey, turnKey)
    XCTAssertEqual(rows[0].tokenUsageLast, delegateUsage)
    XCTAssertEqual(rows[0].tokenUsageSamples.map(\.usage), [delegateUsage])

    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: turnKey,
      status: .completed,
      at: start.addingTimeInterval(2)
    )
    rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows[0].recentRuns.first?.tokenUsage, delegateUsage)
    XCTAssertEqual(rows[0].recentRuns.first?.tokenUsageSamples.map(\.usage), [delegateUsage])
  }

  func testRegularTurnAfterDelegateDoesNotInheritDelegateMetadata() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let delegateTurnKey = "delegate-thread:post-turn-review-0"

    store.UpsertTurnStarted(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: delegateTurnKey,
      at: start
    )
    store.UpdateTurnMetadata(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: delegateTurnKey,
      turn: [
        "scope": "delegate",
        "taskKind": "post_turn_completion_review",
        "sessionSource": "subagent_review",
        "subAgentSource": "review",
        "parentTurnId": "turn-1",
        "threadName": "Post-turn review",
        "model": "gpt-5-review",
        "modelProvider": "openai",
        "thinkingLevel": "high",
        "cwd": "/tmp/review",
      ],
      at: start
    )
    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: delegateTurnKey,
      status: .completed,
      at: start.addingTimeInterval(1)
    )

    store.UpsertTurnStarted(
      endpointId: "ep-1",
      threadId: "main-thread",
      turnId: "turn-2",
      at: start.addingTimeInterval(2)
    )
    store.UpdateTurnMetadata(
      endpointId: "ep-1",
      threadId: "main-thread",
      turnId: "turn-2",
      turn: [
        "id": "turn-2"
      ],
      at: start.addingTimeInterval(2)
    )

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows[0].activeTurn?.turnId, "turn-2")
    XCTAssertEqual(rows[0].threadId, "main-thread")
    XCTAssertNil(rows[0].turnKey)
    XCTAssertNil(rows[0].scope)
    XCTAssertNil(rows[0].taskKind)
    XCTAssertNil(rows[0].sessionSource)
    XCTAssertNil(rows[0].subAgentSource)
    XCTAssertNil(rows[0].parentTurnId)
    XCTAssertNil(rows[0].threadName)
    XCTAssertNil(rows[0].model)
    XCTAssertNil(rows[0].modelProvider)
    XCTAssertNil(rows[0].thinkingLevel)
    XCTAssertNil(rows[0].cwd)
    XCTAssertEqual(rows[0].recentRuns.first?.scope, "delegate")
    XCTAssertEqual(rows[0].recentRuns.first?.taskKind, "post_turn_completion_review")
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
    XCTAssertEqual(rows[0].turnKey, turnKey)
    XCTAssertEqual(rows[0].recentRuns.map(\.turnId), ["post-turn-review-0"])
    XCTAssertEqual(rows[0].recentRuns.first?.scope, "delegate")
    XCTAssertEqual(rows[0].recentRuns.first?.taskKind, "post_turn_completion_review")
    XCTAssertEqual(rows[0].recentRuns.first?.turnKey, turnKey)
  }

  func testDelegateCompletionIsDedupedAfterRuntimeUpsertReconciliation() {
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
        "threadName": "Post-turn review",
        "model": "gpt-5-review",
      ],
      at: start
    )

    var usage = TokenUsageInfo()
    usage.totalTokens = 3_920
    usage.inputTokens = 3_400
    usage.outputTokens = 520
    store.UpdateTokenUsage(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: turnKey,
      tokenUsageTotal: nil,
      tokenUsageLast: usage,
      observedAt: start.addingTimeInterval(1)
    )

    store.ReconcileSnapshotActiveTurns(
      endpointId: "ep-1",
      activeTurnKeys: [],
      at: start.addingTimeInterval(2)
    )
    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: turnKey,
      status: .completed,
      at: start.addingTimeInterval(3)
    )
    store.Tick(now: start.addingTimeInterval(14))
    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: nil,
      turnId: "post-turn-review-0",
      turnKey: "stale-\(turnKey)",
      status: .completed,
      at: start.addingTimeInterval(15)
    )

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows[0].recentRuns.map(\.turnId), ["post-turn-review-0"])
    XCTAssertEqual(rows[0].recentRuns.first?.threadId, "delegate-thread")
    XCTAssertEqual(rows[0].recentRuns.first?.turnKey, turnKey)
    XCTAssertEqual(rows[0].recentRuns.first?.threadName, "Post-turn review")
    XCTAssertEqual(rows[0].recentRuns.first?.model, "gpt-5-review")
    XCTAssertEqual(rows[0].recentRuns.first?.tokenUsage, usage)
  }

  func testDelegateCompletionIsDedupedWhenCompletionSourcesUseDifferentTurnKeys() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    store.UpsertTurnStarted(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: "delegate-thread:post-turn-review-0",
      at: start
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
      ],
      at: start
    )
    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: "delegate-thread:post-turn-review-0",
      status: .completed,
      at: start.addingTimeInterval(1)
    )
    store.Tick(now: start.addingTimeInterval(12))

    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: "updated-delegate-thread:post-turn-review-0",
      status: .completed,
      at: start.addingTimeInterval(13)
    )

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows[0].threadId, "delegate-thread")
    XCTAssertEqual(rows[0].turnKey, "delegate-thread:post-turn-review-0")
    XCTAssertEqual(rows[0].taskKind, "post_turn_completion_review")
    XCTAssertEqual(rows[0].recentRuns.map(\.turnId), ["post-turn-review-0"])
    XCTAssertEqual(rows[0].recentRuns.first?.threadId, "delegate-thread")
    XCTAssertEqual(rows[0].recentRuns.first?.turnKey, "delegate-thread:post-turn-review-0")
  }

  func testPostTurnReviewCompletionWithoutThreadIsDedupedAfterRetention() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    store.UpsertTurnStarted(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: "delegate-thread:post-turn-review-0",
      at: start
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
        "model": "gpt-5-review",
      ],
      at: start
    )
    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "post-turn-review-0",
      turnKey: "delegate-thread:post-turn-review-0",
      status: .completed,
      at: start.addingTimeInterval(1)
    )
    store.Tick(now: start.addingTimeInterval(12))

    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: nil,
      turnId: "post-turn-review-0",
      turnKey: "stale-delegate-thread:post-turn-review-0",
      status: .completed,
      at: start.addingTimeInterval(13)
    )

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows[0].recentRuns.map(\.turnId), ["post-turn-review-0"])
    XCTAssertEqual(rows[0].recentRuns.first?.threadId, "delegate-thread")
    XCTAssertEqual(rows[0].recentRuns.first?.turnKey, "delegate-thread:post-turn-review-0")
    XCTAssertEqual(rows[0].recentRuns.first?.taskKind, "post_turn_completion_review")
  }

  func testPostTurnReviewRuntimeTurnIdDedupesStaleCompletionKeyAfterRetention() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    store.UpsertTurnStarted(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "0",
      turnKey: "delegate-thread:0",
      at: start
    )
    store.UpdateTurnMetadata(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "0",
      turnKey: "delegate-thread:0",
      turn: [
        "scope": "delegate",
        "taskKind": "post_turn_completion_review",
        "sessionSource": "subagent_review",
        "subAgentSource": "review",
        "parentTurnId": "turn-1",
        "threadName": "Post-turn review",
        "model": "gpt-5-review",
      ],
      at: start
    )
    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: "delegate-thread",
      turnId: "0",
      turnKey: "delegate-thread:0",
      status: .completed,
      at: start.addingTimeInterval(1)
    )
    store.Tick(now: start.addingTimeInterval(12))

    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: nil,
      turnId: "0",
      turnKey: "stale-delegate-thread:0",
      status: .completed,
      at: start.addingTimeInterval(13)
    )

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows[0].recentRuns.map(\.turnId), ["0"])
    XCTAssertEqual(rows[0].recentRuns.first?.threadId, "delegate-thread")
    XCTAssertEqual(rows[0].recentRuns.first?.turnKey, "delegate-thread:0")
    XCTAssertEqual(rows[0].recentRuns.first?.taskKind, "post_turn_completion_review")
  }

  func testStaleCompletionKeyDoesNotArchiveNewActiveRuntimeTurnId() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    store.UpsertTurnStarted(
      endpointId: "ep-1",
      threadId: "delegate-thread-new",
      turnId: "0",
      turnKey: "delegate-thread-new:0",
      at: start
    )
    store.UpdateTurnMetadata(
      endpointId: "ep-1",
      threadId: "delegate-thread-new",
      turnId: "0",
      turnKey: "delegate-thread-new:0",
      turn: [
        "scope": "delegate",
        "taskKind": "post_turn_completion_review",
        "sessionSource": "subagent_review",
        "subAgentSource": "review",
        "parentTurnId": "turn-2",
      ],
      at: start
    )

    let archived = store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: nil,
      turnId: "0",
      turnKey: "stale-delegate-thread:0",
      status: .completed,
      at: start.addingTimeInterval(1)
    )

    XCTAssertFalse(archived)
    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(rows[0].activeTurn?.turnId, "0")
    XCTAssertEqual(rows[0].activeTurn?.turnKey, "delegate-thread-new:0")
    XCTAssertEqual(rows[0].activeTurn?.status, .inProgress)
    XCTAssertTrue(rows[0].recentRuns.isEmpty)
  }

  func testPostTurnReviewCompletionsWithSameTurnIdAndDifferentThreadsAreDistinct() {
    let store = TurnStore()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    store.UpsertTurnStarted(
      endpointId: "ep-1",
      threadId: "delegate-thread-a",
      turnId: "post-turn-review-0",
      turnKey: "delegate-thread-a:post-turn-review-0",
      at: start
    )
    store.UpdateTurnMetadata(
      endpointId: "ep-1",
      threadId: "delegate-thread-a",
      turnId: "post-turn-review-0",
      turnKey: "delegate-thread-a:post-turn-review-0",
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
      threadId: "delegate-thread-a",
      turnId: "post-turn-review-0",
      turnKey: "delegate-thread-a:post-turn-review-0",
      status: .completed,
      at: start.addingTimeInterval(1)
    )

    store.UpsertTurnStarted(
      endpointId: "ep-1",
      threadId: "delegate-thread-b",
      turnId: "post-turn-review-0",
      turnKey: "delegate-thread-b:post-turn-review-0",
      at: start.addingTimeInterval(2)
    )
    store.UpdateTurnMetadata(
      endpointId: "ep-1",
      threadId: "delegate-thread-b",
      turnId: "post-turn-review-0",
      turnKey: "delegate-thread-b:post-turn-review-0",
      turn: [
        "scope": "delegate",
        "taskKind": "post_turn_completion_review",
        "sessionSource": "subagent_review",
        "subAgentSource": "review",
        "parentTurnId": "turn-2",
      ],
      at: start.addingTimeInterval(2)
    )
    store.MarkTurnCompleted(
      endpointId: "ep-1",
      threadId: "delegate-thread-b",
      turnId: "post-turn-review-0",
      turnKey: "delegate-thread-b:post-turn-review-0",
      status: .completed,
      at: start.addingTimeInterval(3)
    )

    let rows = store.EndpointRows(activeEndpointIds: ["ep-1"])
    XCTAssertEqual(
      rows[0].recentRuns.map(\.turnKey),
      ["delegate-thread-b:post-turn-review-0", "delegate-thread-a:post-turn-review-0"]
    )
    XCTAssertEqual(rows[0].recentRuns.map(\.parentTurnId), ["turn-2", "turn-1"])
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
