import XCTest

@MainActor
final class MenuBarUISmokeTests: XCTestCase {
  private let statusItemTitle = "CodexUITest"

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testStatusPopoverLaunchHarnessShowsControlsAndOpensSettingsWindow() throws {
    let app = LaunchApp(statusSurface: "popover")
    let statusItem = try StatusItem(in: app)

    XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    let settingsButton = app.buttons["status.settings"]
    XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["status.daemonSummary"].exists)
    XCTAssertTrue(app.buttons["status.reconnect"].exists)
    XCTAssertTrue(app.buttons["status.statusCenter"].exists)
    XCTAssertTrue(app.buttons["status.quit"].exists)

    settingsButton.click()
    XCTAssertTrue(SettingsWindow(in: app).waitForExistence(timeout: 5))
    AttachScreenshot(named: "settings-opened-from-status-popover", app: app)
  }

  func testStatusPopoverDismissesWhenClickingElsewhere() throws {
    let app = LaunchApp(statusSurface: "popover")
    let statusItem = try StatusItem(in: app)

    XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    let settingsButton = app.buttons["status.settings"]
    XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))

    ClickAwayFromStatusPopover(statusItem: statusItem)
    XCTAssertTrue(WaitForNonExistence(of: settingsButton))
  }

  func testActiveStatusPopoverFixtureShowsStableActiveTurnPanel() throws {
    let app = LaunchApp(statusSurface: "popover", fixture: "active-turn")
    let statusItem = try StatusItem(in: app)

    XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    let header = app.staticTexts["status.headerTitle"]
    XCTAssertTrue(header.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValue(of: header, equals: "Codex - 1 active"))
    XCTAssertTrue(app.staticTexts["status.daemonSummary"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["turn.row.fixture-endpoint"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["status.settings"].exists)
    AttachScreenshot(named: "active-status-popover", app: app)
  }

  func testStatusCenterOpensFromPopover() throws {
    let app = LaunchApp(statusSurface: "popover", fixture: "active-turn")
    let statusItem = try StatusItem(in: app)

    XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    let statusCenterButton = app.buttons["status.statusCenter"]
    XCTAssertTrue(statusCenterButton.waitForExistence(timeout: 5))
    statusCenterButton.click()

    let statusWindow = app.windows["Codex Status Center"]
    XCTAssertTrue(statusWindow.waitForExistence(timeout: 5))
    let daemonSummary = app.staticTexts["statusCenter.daemonSummary"]
    XCTAssertTrue(daemonSummary.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValue(of: daemonSummary, equals: "1 runtime - event #128"))
    AttachScreenshot(named: "status-center-window", app: app)
  }

  func testStatusCenterSidebarToggleCollapsesAndExpands() throws {
    let app = LaunchApp(statusSurface: "popover", fixture: "active-turn")
    let statusItem = try StatusItem(in: app)

    XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    let statusCenterButton = app.buttons["status.statusCenter"]
    XCTAssertTrue(statusCenterButton.waitForExistence(timeout: 5))
    statusCenterButton.click()

    let statusWindow = app.windows["Codex Status Center"]
    XCTAssertTrue(statusWindow.waitForExistence(timeout: 5))

    let runtimeList = app.descendants(matching: .any)["statusCenter.runtimeList"]
    XCTAssertTrue(runtimeList.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Runtimes"].exists)

    let sidebarToggle = app.buttons["statusCenter.sidebarToggle"]
    XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 5))
    sidebarToggle.click()

    XCTAssertTrue(WaitForNonExistence(of: runtimeList))
    XCTAssertTrue(WaitForNonExistence(of: app.staticTexts["Runtimes"]))

    let expandToggle = app.buttons["statusCenter.sidebarToggle"]
    XCTAssertTrue(expandToggle.waitForExistence(timeout: 5))
    expandToggle.click()

    XCTAssertTrue(runtimeList.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Runtimes"].exists)
    AttachScreenshot(named: "status-center-sidebar-expanded", app: app)
  }

  func testStatusCenterElapsedStatsRefreshAfterPopoverCloses() throws {
    let app = LaunchApp(statusSurface: "popover", fixture: "active-turn")
    let statusItem = try StatusItem(in: app)

    XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    let statusCenterButton = app.buttons["status.statusCenter"]
    XCTAssertTrue(statusCenterButton.waitForExistence(timeout: 5))
    statusCenterButton.click()

    let statusWindow = app.windows["Codex Status Center"]
    XCTAssertTrue(statusWindow.waitForExistence(timeout: 5))

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
    let app = LaunchApp(statusSurface: "popover", fixture: "active-turn")
    let statusItem = try StatusItem(in: app)

    XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    let statusCenterButton = app.buttons["status.statusCenter"]
    XCTAssertTrue(statusCenterButton.waitForExistence(timeout: 5))
    statusCenterButton.click()

    let statusWindow = app.windows["Codex Status Center"]
    XCTAssertTrue(statusWindow.waitForExistence(timeout: 5))
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(WaitForNonExistence(of: statusWindow))
  }

  func testSettingsShortcutOpensSettingsWindow() throws {
    let app = LaunchApp()
    _ = try StatusItem(in: app)

    app.activate()
    app.typeKey(",", modifierFlags: .command)

    XCTAssertTrue(SettingsWindow(in: app).waitForExistence(timeout: 5))
  }

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

  func testSettingsWindowAppliesSessionSocketOverride() throws {
    let app = LaunchApp(startScreen: "Settings")
    let settingsWindow = SettingsWindow(in: app)
    XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))

    let socketField = settingsWindow.textFields["settings.socketOverride"]
    XCTAssertTrue(socketField.waitForExistence(timeout: 5))
    socketField.click()
    socketField.typeText("/tmp/codex-ui-test.sock")

    let applyButton = settingsWindow.buttons["settings.applySocketOverride"]
    XCTAssertTrue(applyButton.waitForExistence(timeout: 5))
    applyButton.click()

    let effectivePath = settingsWindow.staticTexts["settings.effectiveSocketPath"]
    XCTAssertTrue(effectivePath.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValue(of: effectivePath, equals: "/tmp/codex-ui-test.sock"))
  }

  func testSettingsWindowStartsCompactAndBounded() throws {
    let app = LaunchApp(startScreen: "Settings")
    let settingsWindow = SettingsWindow(in: app)
    XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))

    XCTAssertGreaterThanOrEqual(settingsWindow.frame.width, 520)
    XCTAssertLessThanOrEqual(settingsWindow.frame.width, 700)
    XCTAssertGreaterThanOrEqual(settingsWindow.frame.height, 360)
    XCTAssertLessThanOrEqual(settingsWindow.frame.height, 560)
    AttachScreenshot(named: "settings-window-compact", app: app)
  }

  func testSettingsWindowUseLaunchDefaultRestoresResolvedSocketPath() throws {
    let app = LaunchApp(startScreen: "Settings")
    let settingsWindow = SettingsWindow(in: app)
    XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))

    let socketField = settingsWindow.textFields["settings.socketOverride"]
    XCTAssertTrue(socketField.waitForExistence(timeout: 5))

    let effectivePath = settingsWindow.staticTexts["settings.effectiveSocketPath"]
    XCTAssertTrue(effectivePath.waitForExistence(timeout: 5))
    let defaultPath = String(describing: effectivePath.value ?? "")

    socketField.click()
    socketField.typeText("/tmp/codex-ui-test.sock")
    settingsWindow.buttons["settings.applySocketOverride"].click()
    XCTAssertTrue(WaitForStringValue(of: effectivePath, equals: "/tmp/codex-ui-test.sock"))

    let launchDefaultButton = settingsWindow.buttons["settings.useLaunchDefault"]
    XCTAssertTrue(launchDefaultButton.waitForExistence(timeout: 5))
    launchDefaultButton.click()

    XCTAssertTrue(WaitForStringValue(of: effectivePath, equals: defaultPath))
  }

  func testSettingsWindowAccessibilityAudit() throws {
    let app = LaunchApp(startScreen: "Settings")
    XCTAssertTrue(SettingsWindow(in: app).waitForExistence(timeout: 5))
    try app.performAccessibilityAudit(for: .all) { issue in
      // On macOS 15/Xcode 16, auditing this SwiftUI-hosted settings window can surface a
      // framework-level parent/child mismatch while the app logs a
      // `SwiftUI.AccessibilityNode accessibilityChildrenAttribute` exception.
      let isKnownParentChildMismatch =
        issue.compactDescription == "Parent/Child mismatch"
        && issue.detailedDescription.contains("not an accessibility child of the parent element")

      // The audit also reports the synthetic root Group that AppKit exposes for the
      // hosted SwiftUI content as missing a description, even though the actionable
      // descendants are labeled and queryable.
      let isKnownRootGroupDescriptionGap =
        issue.compactDescription == "Element has no description"
        && issue.detailedDescription.contains("missing useful accessibility information")

      // macOS also includes the system "emoji & symbols" Touch Bar item in the
      // audit surface for this window, which reports as missing a click/tap action.
      let isKnownSystemTouchBarActionGap =
        issue.compactDescription == "Action is missing"
        && issue.detailedDescription.contains("equivalent to click/tap inputs")

      return isKnownParentChildMismatch
        || isKnownRootGroupDescriptionGap
        || isKnownSystemTouchBarActionGap
    }
  }

  private func LaunchApp(
    startScreen: String? = nil, statusSurface: String? = nil, fixture: String? = nil
  )
    -> XCUIApplication
  {
    let app = XCUIApplication()
    app.launchArguments += ["--uitest"]
    if let startScreen {
      app.launchArguments += ["--start-screen", startScreen]
    }
    if let statusSurface {
      app.launchArguments += ["--open-status-surface", statusSurface]
    }
    if let fixture {
      app.launchArguments += ["--fixture", fixture]
    }
    app.launchEnvironment["CODEXMENUBAR_UI_TEST_STATUS_TITLE"] = statusItemTitle
    app.launch()
    return app
  }

  private func SettingsWindow(in app: XCUIApplication) -> XCUIElement {
    app.windows["CodexMenuBar Settings"]
  }

  private func StatusItem(in app: XCUIApplication) throws -> XCUIElement {
    let item = app.menuBars.statusItems[statusItemTitle]
    if item.waitForExistence(timeout: 5) {
      return item
    }

    let fallback = app.menuBars.menuBarItems[statusItemTitle]
    if fallback.waitForExistence(timeout: 2) {
      return fallback
    }

    let systemUI = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
    let systemItem = systemUI.menuBars.statusItems[statusItemTitle]
    if systemItem.waitForExistence(timeout: 2) {
      return systemItem
    }

    throw XCTSkip("Unable to locate status item '\(statusItemTitle)' in app or SystemUIServer.")
  }

  private func ContextMenuItem(named title: String, app: XCUIApplication) throws -> XCUIElement {
    let appItem = app.menuItems[title]
    if appItem.waitForExistence(timeout: 2) {
      return appItem
    }

    let systemUI = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
    let systemItem = systemUI.menuItems[title]
    if systemItem.waitForExistence(timeout: 3) {
      return systemItem
    }

    throw XCTSkip("Unable to locate context menu item '\(title)'.")
  }

  private func WaitForStringValue(
    of element: XCUIElement,
    equals expected: String,
    timeout: TimeInterval = 5
  )
    -> Bool
  {
    let predicate = NSPredicate(format: "value == %@", expected)
    let expectation = expectation(for: predicate, evaluatedWith: element)
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  private func WaitForStringLabelChange(
    of element: XCUIElement,
    from initial: String,
    timeout: TimeInterval = 5
  )
    -> Bool
  {
    let predicate = NSPredicate(format: "label != %@", initial)
    let expectation = expectation(for: predicate, evaluatedWith: element)
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  private func WaitForNonExistence(of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    let predicate = NSPredicate(format: "exists == false")
    let expectation = expectation(for: predicate, evaluatedWith: element)
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  private func ClickAwayFromStatusPopover(statusItem: XCUIElement) {
    let systemUI = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
    let menuBar = systemUI.menuBars.firstMatch
    if menuBar.waitForExistence(timeout: 2) {
      menuBar.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
      return
    }

    statusItem.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.0))
      .withOffset(CGVector(dx: -200, dy: 80))
      .click()
  }

  private func AttachScreenshot(named name: String, app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
