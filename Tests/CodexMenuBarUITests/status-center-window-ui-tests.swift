import AppKit
import XCTest

@MainActor
final class StatusCenterWindowUITests: CodexMenuBarUITestCase {
  func testStatusCenterOpensFromPopover() throws {
    let (app, _) = try LaunchStatusCenter(fixture: "active-turn")
    let daemonSummary = app.staticTexts["statusCenter.daemonSummary"]
    XCTAssertTrue(daemonSummary.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValue(of: daemonSummary, equals: "1 runtime - event #128"))
    AttachScreenshot(named: "status-center-window", app: app)
  }

  func testStatusCenterSidebarToggleCollapsesAndExpands() throws {
    let (app, statusWindow) = try LaunchStatusCenter(fixture: "active-turn")

    let runtimeList = app.descendants(matching: .any)["statusCenter.runtimeList"]
    let resizeHandle = app.descendants(matching: .any)["statusCenter.sidebarResizeHandle"]
    XCTAssertTrue(runtimeList.waitForExistence(timeout: 5))
    XCTAssertTrue(resizeHandle.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Runtimes"].exists)
    let compactSidebarWidth = resizeHandle.frame.midX - statusWindow.frame.minX
    XCTAssertLessThanOrEqual(compactSidebarWidth, 245)

    let sidebarToggle = app.buttons["statusCenter.sidebarToggle"]
    XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 5))
    sidebarToggle.click()

    XCTAssertTrue(WaitForNonExistence(of: runtimeList))
    XCTAssertTrue(WaitForNonExistence(of: app.staticTexts["Runtimes"]))
    let collapsedRuntime = app.buttons["statusCenter.collapsedRuntime.fixture-endpoint"]
    XCTAssertTrue(collapsedRuntime.waitForExistence(timeout: 5))
    let collapsedRuntimeIcon = app.descendants(matching: .any)[
      "statusCenter.collapsedRuntime.icon.fixture-endpoint"]
    XCTAssertTrue(collapsedRuntimeIcon.waitForExistence(timeout: 5))
    XCTAssertGreaterThanOrEqual(collapsedRuntime.frame.width, 30)
    XCTAssertGreaterThanOrEqual(collapsedRuntime.frame.height, 30)
    XCTAssertGreaterThanOrEqual(collapsedRuntimeIcon.frame.width, 17)
    XCTAssertGreaterThanOrEqual(collapsedRuntimeIcon.frame.height, 17)
    XCTAssertEqual(collapsedRuntimeIcon.frame.midX, collapsedRuntime.frame.midX, accuracy: 1)
    XCTAssertEqual(collapsedRuntimeIcon.frame.midY, collapsedRuntime.frame.midY, accuracy: 1)
    AttachScreenshot(named: "status-center-sidebar-collapsed-runtime-icon", app: app)

    let expandToggle = app.buttons["statusCenter.sidebarToggle"]
    XCTAssertTrue(expandToggle.waitForExistence(timeout: 5))
    expandToggle.click()

    XCTAssertTrue(runtimeList.waitForExistence(timeout: 5))
    XCTAssertTrue(resizeHandle.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Runtimes"].exists)
    let expandedSidebarWidth = resizeHandle.frame.midX - statusWindow.frame.minX
    XCTAssertLessThan(abs(expandedSidebarWidth - compactSidebarWidth), 10)
    AttachScreenshot(named: "status-center-sidebar-expanded", app: app)
  }

  func testStatusCenterShowsDockIcon() throws {
    _ = try LaunchStatusCenter(fixture: "active-turn")

    let dock = XCUIApplication(bundleIdentifier: "com.apple.dock")
    let dockItem = dock.dockItems["CodexMenuBar"]
    XCTAssertTrue(dockItem.waitForExistence(timeout: 5))
  }

  func testStatusCenterEmptyStateIsCenteredWithoutRuntimes() throws {
    let (app, statusWindow) = try LaunchStatusCenter(fixture: nil)
    let emptyState = app.descendants(matching: .any)["statusCenter.empty"]
    XCTAssertTrue(emptyState.waitForExistence(timeout: 5))

    let emptyTitle = app.staticTexts["No Codex runtimes"]
    XCTAssertTrue(emptyTitle.waitForExistence(timeout: 5))
    XCTAssertLessThan(abs(emptyTitle.frame.midY - statusWindow.frame.midY), 120)
    XCTAssertGreaterThan(emptyTitle.frame.midX, statusWindow.frame.midX)
    AttachScreenshot(named: "status-center-empty", app: app)
  }

  func testStatusCenterElapsedStatsRefreshAfterPopoverCloses() throws {
    let (app, _) = try LaunchStatusCenter(fixture: "active-turn")

    let turnRow = app.buttons
      .matching(identifier: "turn.row.fixture-endpoint")
      .matching(NSPredicate(format: "label CONTAINS %@", "Working"))
      .firstMatch
    XCTAssertTrue(turnRow.waitForExistence(timeout: 5))
    let initialElapsed = String(describing: turnRow.label)
    XCTAssertFalse(initialElapsed.isEmpty)
    XCTAssertTrue(WaitForStringLabelChange(of: turnRow, from: initialElapsed, timeout: 4))
    AttachScreenshot(named: "status-center-elapsed-refreshed", app: app)
  }

  func testStatusCenterClosesWithCommandW() throws {
    let (app, statusWindow) = try LaunchStatusCenter(fixture: "active-turn")
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(WaitForNonExistence(of: statusWindow))
  }
}
