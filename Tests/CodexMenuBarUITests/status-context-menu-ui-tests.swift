import AppKit
import XCTest

@MainActor
final class StatusContextMenuUITests: CodexMenuBarUITestCase {
  func testStatusContextMenuLaunchHarnessShowsMenuItems() throws {
    let app = LaunchApp(statusSurface: "context-menu")
    let statusItem = try StatusItem(in: app)

    XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    XCTAssertTrue(
      try ContextMenuItem(named: "Reconnect codexd", app: app).waitForExistence(timeout: 5))
    XCTAssertTrue(try ContextMenuItem(named: "Quick Start", app: app).waitForExistence(timeout: 5))
    XCTAssertTrue(
      try ContextMenuItem(named: "Status Center...", app: app).waitForExistence(timeout: 5))
    XCTAssertTrue(try ContextMenuItem(named: "Settings...", app: app).waitForExistence(timeout: 5))
    XCTAssertTrue(
      try ContextMenuItem(named: "Quit CodexMenuBar", app: app).waitForExistence(timeout: 5))
  }
}
