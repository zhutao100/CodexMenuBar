import AppKit
import XCTest

@MainActor
final class StatusCenterPromptHistoryUITests: CodexMenuBarUITestCase {
  func testStatusCenterActivePromptFoldsToFiveLinesAndExpands() throws {
    let (app, _) = try LaunchStatusCenter(fixture: "active-turn")

    let prompt = app.staticTexts["turn.prompt.fixture-endpoint"]
    XCTAssertTrue(prompt.waitForExistence(timeout: 5))
    XCTAssertTrue(
      WaitForStringValueContaining(of: prompt, text: "Show five prompt lines by default."))
    XCTAssertFalse(
      String(describing: prompt.value ?? "").contains(
        "Reveal this sixth active prompt line only after expansion."))

    let promptToggle = app.buttons["turn.promptSection.fixture-endpoint"]
    XCTAssertTrue(promptToggle.waitForExistence(timeout: 5))
    promptToggle.click()
    let expandedPrompt = app.staticTexts["turn.prompt.fixture-endpoint"]
    XCTAssertTrue(
      WaitForStringValueContaining(
        of: expandedPrompt, text: "Reveal this sixth active prompt line only after expansion."))

    promptToggle.click()
    let refoldedPrompt = app.staticTexts["turn.prompt.fixture-endpoint"]
    XCTAssertTrue(
      WaitForStringValueContaining(of: refoldedPrompt, text: "Show five prompt lines by default."))
    XCTAssertFalse(
      String(describing: refoldedPrompt.value ?? "").contains(
        "Reveal this sixth active prompt line only after expansion."))
    AttachScreenshot(named: "status-center-active-prompt-folded", app: app)
  }

  func testStatusCenterRuntimeHistorySectionsBrowseOlderEntries() throws {
    let (app, _) = try LaunchStatusCenter(fixture: "active-turn")

    let planPosition = app.descendants(matching: .any)[
      "turn.planHistory.position.fixture-endpoint"]
    XCTAssertTrue(planPosition.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValue(of: planPosition, equals: "3-8 of 8"))

    let olderPlan = app.buttons["turn.planHistory.older.fixture-endpoint"]
    XCTAssertTrue(olderPlan.waitForExistence(timeout: 5))
    XCTAssertTrue(olderPlan.isEnabled)
    olderPlan.click()
    XCTAssertTrue(WaitForStringValue(of: planPosition, equals: "1-2 of 8"))

    let filePosition = app.descendants(matching: .any)[
      "turn.filesHistory.position.fixture-endpoint"]
    XCTAssertTrue(filePosition.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValue(of: filePosition, equals: "3-10 of 10"))

    let olderFiles = app.buttons["turn.filesHistory.older.fixture-endpoint"]
    XCTAssertTrue(olderFiles.waitForExistence(timeout: 5))
    XCTAssertTrue(olderFiles.isEnabled)
    olderFiles.click()
    XCTAssertTrue(WaitForStringValue(of: filePosition, equals: "1-2 of 10"))

    let newerFiles = app.buttons["turn.filesHistory.newer.fixture-endpoint"]
    XCTAssertTrue(newerFiles.waitForExistence(timeout: 5))
    XCTAssertTrue(newerFiles.isEnabled)
    newerFiles.click()
    XCTAssertTrue(WaitForStringValue(of: filePosition, equals: "3-10 of 10"))

    let commandPosition = app.descendants(matching: .any)[
      "turn.commandsHistory.position.fixture-endpoint"]
    XCTAssertTrue(commandPosition.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValue(of: commandPosition, equals: "2-6 of 6"))

    let olderCommands = app.buttons["turn.commandsHistory.older.fixture-endpoint"]
    XCTAssertTrue(olderCommands.waitForExistence(timeout: 5))
    XCTAssertTrue(olderCommands.isEnabled)
    olderCommands.click()
    XCTAssertTrue(WaitForStringValue(of: commandPosition, equals: "1-1 of 6"))

    AttachScreenshot(named: "status-center-runtime-history-browsing", app: app)
  }
}
