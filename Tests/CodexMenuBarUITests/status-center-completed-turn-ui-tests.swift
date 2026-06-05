import AppKit
import XCTest

@MainActor
final class StatusCenterCompletedTurnUITests: CodexMenuBarUITestCase {
  func testStatusCenterCompletedTurnTokenUsageHistoryBrowsesRounds() throws {
    let (app, _) = try LaunchStatusCenter(fixture: "completed-turn-history")

    let completedSection = app.buttons["turn.completedTurnsSection.fixture-endpoint"]
    XCTAssertTrue(completedSection.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringLabelContaining(of: completedSection, text: "Completed Turns (7)"))

    let runPosition = app.descendants(matching: .any)["turn.runsHistory.position.fixture-endpoint"]
    XCTAssertTrue(runPosition.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValue(of: runPosition, equals: "1-5 of 7"))

    let completedRunRows = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "turn.completedRun.row."))
    XCTAssertTrue(WaitForQueryCount(completedRunRows, equals: 5, timeout: 5))

    let latestRun = CompletedRunRow(containing: "completed-history-turn-6", in: app)
    XCTAssertTrue(latestRun.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringLabelContaining(of: latestRun, text: " · latest"))
    XCTAssertFalse(CompletedRunRow(containing: "completed-history-turn-0", in: app).exists)

    XCTAssertTrue(WaitForStringValueContaining(of: latestRun, text: "Tokens: 82.5k"))

    latestRun.click()

    let prompt = CompletedRunPrompt(containing: "completed-history-turn-6", in: app)
    XCTAssertTrue(prompt.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValueContaining(of: prompt, text: "Line three must remain visible"))
    XCTAssertTrue(WaitForStringValueContaining(of: prompt, text: "Line five should remain"))
    XCTAssertFalse(
      String(describing: prompt.value ?? "").contains(
        "Line six should appear only after expanding the completed prompt."))

    let promptToggle = CompletedRunPromptToggle(containing: "completed-history-turn-6", in: app)
    XCTAssertTrue(promptToggle.waitForExistence(timeout: 5))
    promptToggle.click()
    let expandedPrompt = CompletedRunPrompt(containing: "completed-history-turn-6", in: app)
    XCTAssertTrue(
      WaitForStringValueContaining(
        of: expandedPrompt,
        text: "Line six should appear only after expanding the completed prompt."))

    promptToggle.click()
    let refoldedPrompt = CompletedRunPrompt(containing: "completed-history-turn-6", in: app)
    XCTAssertFalse(
      String(describing: refoldedPrompt.value ?? "").contains(
        "Line six should appear only after expanding the completed prompt."))

    let position = app.descendants(matching: .any).matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@",
        "turn.completedRun.tokenUsageHistory.position.", "completed-history-turn-6")
    ).firstMatch
    XCTAssertTrue(position.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValue(of: position, equals: "1 of 3"))

    let title = app.descendants(matching: .any).matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@",
        "turn.completedRun.tokenUsageHistory.title.", "completed-history-turn-6")
    ).firstMatch
    let detail = app.descendants(matching: .any).matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@",
        "turn.completedRun.tokenUsageHistory.detail.", "completed-history-turn-6")
    ).firstMatch
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    XCTAssertTrue(detail.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValue(of: title, equals: "Completed regular turn"))
    XCTAssertTrue(String(describing: detail.value ?? "").contains("In: 15.6k"))

    let earlierButton = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@", "turn.completedRun.tokenUsageHistory.earlier.")
    ).firstMatch
    XCTAssertTrue(earlierButton.waitForExistence(timeout: 5))
    XCTAssertTrue(earlierButton.isEnabled)
    earlierButton.click()
    XCTAssertTrue(WaitForStringValue(of: position, equals: "2 of 3"))
    XCTAssertTrue(String(describing: detail.value ?? "").contains("In: 11.3k"))

    earlierButton.click()
    XCTAssertTrue(WaitForStringValue(of: position, equals: "3 of 3"))
    XCTAssertTrue(String(describing: detail.value ?? "").contains("In: 7.2k"))

    let newerButton = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "turn.completedRun.tokenUsageHistory.newer.")
    ).firstMatch
    XCTAssertTrue(newerButton.waitForExistence(timeout: 5))
    XCTAssertTrue(newerButton.isEnabled)
    newerButton.click()
    XCTAssertTrue(WaitForStringValue(of: position, equals: "2 of 3"))

    let olderRunsButton = app.buttons["turn.runsHistory.older.fixture-endpoint"]
    XCTAssertTrue(olderRunsButton.waitForExistence(timeout: 5))
    XCTAssertTrue(olderRunsButton.isEnabled)
    olderRunsButton.click()
    XCTAssertTrue(WaitForStringValue(of: runPosition, equals: "6-7 of 7"))
    XCTAssertTrue(WaitForQueryCount(completedRunRows, equals: 2, timeout: 5))
    XCTAssertTrue(CompletedRunRow(containing: "completed-history-turn-1", in: app).exists)
    XCTAssertTrue(CompletedRunRow(containing: "completed-history-turn-0", in: app).exists)
    XCTAssertFalse(CompletedRunRow(containing: "completed-history-turn-6", in: app).exists)

    let newerRunsButton = app.buttons["turn.runsHistory.newer.fixture-endpoint"]
    XCTAssertTrue(newerRunsButton.waitForExistence(timeout: 5))
    XCTAssertTrue(newerRunsButton.isEnabled)
    newerRunsButton.click()
    XCTAssertTrue(WaitForStringValue(of: runPosition, equals: "1-5 of 7"))
    AttachScreenshot(named: "status-center-completed-turn-token-history", app: app)
  }

  func testStatusCenterCompletedTurnPromptIsFullyReadableAndCopyable() throws {
    let (app, _) = try LaunchStatusCenter(fixture: "completed-turn-history")

    let reviewRun = CompletedRunRow(containing: "completed-review-turn", in: app)
    XCTAssertTrue(reviewRun.waitForExistence(timeout: 5))
    reviewRun.click()

    let prompt = CompletedRunPrompt(containing: "completed-review-turn", in: app)
    XCTAssertTrue(prompt.waitForExistence(timeout: 5))
    XCTAssertTrue(
      WaitForStringValueContaining(
        of: prompt, text: "Confirm copying the entire prompt remains available."))
    XCTAssertFalse(
      String(describing: prompt.value ?? "").contains(
        "Confirm this sixth review line appears only after expansion."))

    let promptToggle = CompletedRunPromptToggle(containing: "completed-review-turn", in: app)
    XCTAssertTrue(promptToggle.waitForExistence(timeout: 5))
    promptToggle.click()
    let expandedPrompt = CompletedRunPrompt(containing: "completed-review-turn", in: app)
    XCTAssertTrue(
      WaitForStringValueContaining(
        of: expandedPrompt, text: "Confirm this sixth review line appears only after expansion."))

    NSPasteboard.general.clearContents()
    let copyButton = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@",
        "turn.completedRun.copyPrompt.", "completed-review-turn")
    ).firstMatch
    XCTAssertTrue(copyButton.waitForExistence(timeout: 5))
    copyButton.click()
    XCTAssertTrue(
      WaitForPasteboardContaining("Confirm copying the entire prompt remains available."))
    AttachScreenshot(named: "status-center-completed-turn-prompt-copy", app: app)
  }

  func testStatusCenterPostTurnReviewLifecycleRefreshesTokensAndDedupesCompletion() throws {
    let (app, _) = try LaunchStatusCenter(fixture: "post-turn-review-lifecycle")

    let row = app.buttons["turn.row.fixture-endpoint"]
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringLabelContaining(of: row, text: "Post-turn review"))

    let title = app.descendants(matching: .any)["turn.tokenUsageHistory.title.fixture-endpoint"]
    let usageDetail = app.descendants(matching: .any)[
      "turn.tokenUsageHistory.detail.fixture-endpoint"]
    XCTAssertTrue(title.waitForExistence(timeout: 6))
    XCTAssertTrue(usageDetail.waitForExistence(timeout: 6))
    XCTAssertTrue(WaitForStringValue(of: title, equals: "Current post-turn review", timeout: 6))
    XCTAssertTrue(String(describing: usageDetail.value ?? "").contains("In: 3.4k"))

    let completedSection = app.buttons["turn.completedTurnsSection.fixture-endpoint"]
    XCTAssertTrue(completedSection.waitForExistence(timeout: 30))
    XCTAssertTrue(
      WaitForStringLabelContaining(of: completedSection, text: "Completed Turns (2)", timeout: 30))
    XCTAssertFalse(String(describing: completedSection.label).contains("Completed Turns (3)"))

    let completedRunPredicate = NSPredicate(
      format: "identifier BEGINSWITH %@", "turn.completedRun.row.")
    let completedRunRows = app.buttons.matching(completedRunPredicate)
    XCTAssertTrue(WaitForQueryCount(completedRunRows, equals: 2, timeout: 5))

    let reviewRunRows = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
        "turn.completedRun.row.", "Post-turn review · Completed"))
    XCTAssertTrue(WaitForQueryCount(reviewRunRows, equals: 1, timeout: 5))

    let latestRows = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
        "turn.completedRun.row.", " · latest"))
    XCTAssertTrue(WaitForQueryCount(latestRows, equals: 1, timeout: 5))

    let reviewRow = reviewRunRows.element(boundBy: 0)
    XCTAssertTrue(WaitForStringLabelContaining(of: reviewRow, text: " · latest"))
    XCTAssertTrue(WaitForStringValueContaining(of: reviewRow, text: "Review target"))
    XCTAssertTrue(WaitForStringValueContaining(of: reviewRow, text: "fixture-delegate-thread"))
    reviewRow.click()

    let reviewDetails = app.staticTexts.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "turn.completedRun.details.")
    ).element(boundBy: 0)
    XCTAssertTrue(reviewDetails.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValueContaining(of: reviewDetails, text: "Post-turn review"))
    XCTAssertTrue(WaitForStringValueContaining(of: reviewDetails, text: "fixture-delegate-thread"))
    XCTAssertTrue(WaitForStringValueContaining(of: reviewDetails, text: "Review target"))

    let reviewPrompt = CompletedRunPrompt(containing: "fixture-delegate-thread:0", in: app)
    XCTAssertTrue(reviewPrompt.waitForExistence(timeout: 5))
    XCTAssertTrue(
      WaitForStringValueContaining(of: reviewPrompt, text: "Review target post-turn review prompt.")
    )
    XCTAssertFalse(
      String(describing: reviewPrompt.value ?? "").contains("Stale duplicate review prompt"))
    AttachScreenshot(named: "status-center-post-turn-review-lifecycle", app: app)
  }
}
