import AppKit
import XCTest

@MainActor
final class StatusCenterTokenUsageUITests: CodexMenuBarUITestCase {
  func testStatusCenterTokenUsageHistoryBrowsesEarlierTurnsWithoutContextEstimateGhosts() throws {
    let (app, _) = try LaunchStatusCenter(fixture: "active-turn")

    let position = app.descendants(matching: .any)[
      "turn.tokenUsageHistory.position.fixture-endpoint"]
    XCTAssertTrue(position.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValue(of: position, equals: "1 of 6"))

    let title = app.descendants(matching: .any)["turn.tokenUsageHistory.title.fixture-endpoint"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValue(of: title, equals: "Current regular turn"))

    let subtitle = app.descendants(matching: .any)[
      "turn.tokenUsageHistory.subtitle.fixture-endpoint"]
    XCTAssertTrue(subtitle.waitForExistence(timeout: 5))
    XCTAssertTrue(
      WaitForStringValueContaining(of: subtitle, text: "Round 3 of 3 · Active now · 1 chat turn"))
    XCTAssertFalse(String(describing: subtitle.value ?? "").contains("Turn 2"))

    let earlierButton = app.buttons["turn.tokenUsageHistory.earlier.fixture-endpoint"]
    XCTAssertTrue(earlierButton.waitForExistence(timeout: 5))
    XCTAssertTrue(earlierButton.isEnabled)
    earlierButton.click()

    let detail = app.descendants(matching: .any)["turn.tokenUsageHistory.detail.fixture-endpoint"]
    XCTAssertTrue(detail.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValue(of: position, equals: "2 of 6"))
    XCTAssertTrue(WaitForStringValue(of: title, equals: "Current regular turn"))
    XCTAssertTrue(String(describing: detail.value ?? "").contains("In: 9.1k"))

    earlierButton.click()
    XCTAssertTrue(WaitForStringValue(of: position, equals: "3 of 6"))
    XCTAssertTrue(WaitForStringValue(of: title, equals: "Current regular turn"))
    XCTAssertTrue(String(describing: detail.value ?? "").contains("In: 6.4k"))

    earlierButton.click()
    XCTAssertTrue(WaitForStringValue(of: position, equals: "4 of 6"))
    XCTAssertTrue(WaitForStringValue(of: title, equals: "Latest completed regular turn"))
    XCTAssertTrue(String(describing: detail.value ?? "").contains("In: 18.2k"))

    earlierButton.click()
    XCTAssertTrue(WaitForStringValue(of: position, equals: "5 of 6"))
    XCTAssertTrue(WaitForStringValue(of: title, equals: "Latest completed regular turn"))
    XCTAssertTrue(String(describing: detail.value ?? "").contains("In: 11.4k"))

    earlierButton.click()
    XCTAssertTrue(WaitForStringValue(of: position, equals: "6 of 6"))
    XCTAssertTrue(WaitForStringValue(of: title, equals: "Earlier regular turn"))

    let newerButton = app.buttons["turn.tokenUsageHistory.newer.fixture-endpoint"]
    XCTAssertTrue(newerButton.waitForExistence(timeout: 5))
    newerButton.click()
    XCTAssertTrue(WaitForStringValue(of: position, equals: "5 of 6"))

    let latestButton = app.buttons["turn.tokenUsageHistory.latest.fixture-endpoint"]
    XCTAssertTrue(latestButton.waitForExistence(timeout: 5))
    XCTAssertTrue(latestButton.isEnabled)
    latestButton.click()
    XCTAssertTrue(WaitForStringValue(of: position, equals: "1 of 6"))
    XCTAssertTrue(WaitForStringValue(of: title, equals: "Current regular turn"))
    XCTAssertTrue(String(describing: detail.value ?? "").contains("In: 12.8k"))

    AttachScreenshot(named: "status-center-token-history", app: app)
  }

  func testStatusCenterDelegateTurnUsesDelegateTokenHistory() throws {
    let (app, _) = try LaunchStatusCenter(fixture: "delegate-turn")

    let row = app.buttons["turn.row.fixture-endpoint"]
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringLabelContaining(of: row, text: "Post-turn review"))

    let details = app.descendants(matching: .any)["turn.details.fixture-endpoint"]
    XCTAssertTrue(details.waitForExistence(timeout: 5))
    XCTAssertTrue(
      WaitForStringValueContaining(of: details, text: "Review target: previous completed turn"))
    XCTAssertFalse(String(describing: details.value ?? "").contains("Turn:"))

    let position = app.descendants(matching: .any)[
      "turn.tokenUsageHistory.position.fixture-endpoint"]
    XCTAssertTrue(position.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValue(of: position, equals: "1 of 3"))

    let title = app.descendants(matching: .any)["turn.tokenUsageHistory.title.fixture-endpoint"]
    let usageDetail = app.descendants(matching: .any)[
      "turn.tokenUsageHistory.detail.fixture-endpoint"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    XCTAssertTrue(usageDetail.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValue(of: title, equals: "Current post-turn review"))
    XCTAssertTrue(String(describing: usageDetail.value ?? "").contains("In: 3.4k"))

    let threadTokenSection = app.buttons["turn.threadTokenSection.fixture-endpoint"]
    XCTAssertTrue(threadTokenSection.waitForExistence(timeout: 5))
    XCTAssertTrue(
      WaitForStringLabelContaining(of: threadTokenSection, text: "Thread Token Usage - 6.4k"))

    let sessionTokenSection = app.buttons["turn.sessionTokenSection.fixture-endpoint"]
    XCTAssertTrue(sessionTokenSection.waitForExistence(timeout: 5))
    XCTAssertTrue(
      WaitForStringLabelContaining(of: sessionTokenSection, text: "Session Token Usage - 27.3k"))
    let sessionTokenSubtitle = app.descendants(matching: .any)[
      "turn.sessionTokenUsage.subtitle.fixture-endpoint"]
    XCTAssertTrue(sessionTokenSubtitle.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValueContaining(of: sessionTokenSubtitle, text: "2 threads"))

    let tokenUsageSection = app.buttons["turn.tokenUsageSection.fixture-endpoint"]
    XCTAssertTrue(tokenUsageSection.waitForExistence(timeout: 5))
    tokenUsageSection.click()
    XCTAssertTrue(WaitForNonExistence(of: position))
    tokenUsageSection.click()
    XCTAssertTrue(position.waitForExistence(timeout: 5))

    let earlierButton = app.buttons["turn.tokenUsageHistory.earlier.fixture-endpoint"]
    XCTAssertTrue(earlierButton.waitForExistence(timeout: 5))
    XCTAssertTrue(earlierButton.isEnabled)
    earlierButton.click()
    XCTAssertTrue(WaitForStringValue(of: position, equals: "2 of 3"))
    XCTAssertTrue(WaitForStringValue(of: title, equals: "Current post-turn review"))
    XCTAssertTrue(String(describing: usageDetail.value ?? "").contains("In: 2.1k"))

    earlierButton.click()
    XCTAssertTrue(WaitForStringValue(of: position, equals: "3 of 3"))
    XCTAssertTrue(WaitForStringValue(of: title, equals: "Latest completed regular turn"))
    XCTAssertTrue(String(describing: usageDetail.value ?? "").contains("In: 18.2k"))
    AttachScreenshot(named: "status-center-delegate-token-history", app: app)
  }
}
