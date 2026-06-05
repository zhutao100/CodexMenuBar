import AppKit
import XCTest

@MainActor
final class StatusPopoverUITests: CodexMenuBarUITestCase {
  func testStatusPopoverLaunchHarnessShowsControlsAndOpensSettingsWindow() throws {
    let app = LaunchApp(statusSurface: "popover")
    let statusItem = try StatusItem(in: app)

    XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    let settingsButton = app.buttons["status.settings"]
    let reconnectButton = app.buttons["status.reconnect"]
    XCTAssertTrue(EnsureStatusPopoverOpen(in: app, statusItem: statusItem))
    XCTAssertTrue(app.staticTexts["status.daemonSummary"].exists)
    XCTAssertTrue(reconnectButton.exists)
    XCTAssertTrue(app.buttons["status.statusCenter"].exists)
    XCTAssertTrue(app.buttons["status.quit"].exists)
    XCTAssertLessThanOrEqual(reconnectButton.frame.width, 44)

    settingsButton.click()
    XCTAssertTrue(SettingsWindow(in: app).waitForExistence(timeout: 5))
    AttachScreenshot(named: "settings-opened-from-status-popover", app: app)
  }

  func testStatusPopoverHeaderActionsShowHoverHelpWithoutRelayout() throws {
    let app = LaunchApp(statusSurface: "popover")
    let statusItem = try StatusItem(in: app)

    XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    XCTAssertTrue(EnsureStatusPopoverOpen(in: app, statusItem: statusItem))

    let reconnectButton = app.buttons["status.reconnect"]
    let statusCenterButton = app.buttons["status.statusCenter"]
    let daemonSummary = app.staticTexts["status.daemonSummary"]
    let hoverHelp = app.staticTexts["status.headerActionHoverHelp"]
    XCTAssertTrue(reconnectButton.waitForExistence(timeout: 5))
    XCTAssertTrue(statusCenterButton.waitForExistence(timeout: 5))
    XCTAssertTrue(daemonSummary.waitForExistence(timeout: 5))
    XCTAssertFalse(hoverHelp.exists)

    let reconnectFrame = reconnectButton.frame
    let statusCenterFrame = statusCenterButton.frame

    reconnectButton.hover()
    XCTAssertTrue(hoverHelp.waitForExistence(timeout: 5))
    XCTAssertTrue(
      WaitForStringValueContaining(
        of: hoverHelp, text: "Reconnect to codexd and refresh all runtime state"))
    AssertFrame(reconnectButton.frame, matches: reconnectFrame)
    AssertFrame(statusCenterButton.frame, matches: statusCenterFrame)
    AttachScreenshot(named: "status-popover-header-action-hover-help", app: app)

    daemonSummary.hover()
    XCTAssertTrue(WaitForNonExistence(of: hoverHelp))
    AssertFrame(reconnectButton.frame, matches: reconnectFrame)
    AssertFrame(statusCenterButton.frame, matches: statusCenterFrame)
  }

  func testStatusPopoverDismissesWhenClickingElsewhere() throws {
    let app = LaunchApp(statusSurface: "popover")
    let statusItem = try StatusItem(in: app)

    XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    let settingsButton = app.buttons["status.settings"]
    XCTAssertTrue(EnsureStatusPopoverOpen(in: app, statusItem: statusItem))

    ClickAwayFromStatusPopover(statusItem: statusItem)
    XCTAssertTrue(WaitForNonExistence(of: settingsButton))
  }

  func testActiveStatusPopoverFixtureShowsStableActiveTurnPanel() throws {
    let app = LaunchApp(statusSurface: "popover", fixture: "active-turn")
    let statusItem = try StatusItem(in: app)

    XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    XCTAssertTrue(EnsureStatusPopoverOpen(in: app, statusItem: statusItem))
    let header = app.staticTexts["status.headerTitle"]
    XCTAssertTrue(header.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValue(of: header, equals: "Codex - 1 active"))
    XCTAssertTrue(app.staticTexts["status.daemonSummary"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["turn.row.fixture-endpoint"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["status.settings"].exists)
    AttachScreenshot(named: "active-status-popover", app: app)
  }
}
