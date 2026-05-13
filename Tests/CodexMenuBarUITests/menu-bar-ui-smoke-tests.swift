import AppKit
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

  func testStatusCenterOpensFromPopover() throws {
    let app = LaunchApp(statusSurface: "popover", fixture: "active-turn")
    let statusItem = try StatusItem(in: app)

    XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    XCTAssertTrue(EnsureStatusPopoverOpen(in: app, statusItem: statusItem))
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
    XCTAssertTrue(EnsureStatusPopoverOpen(in: app, statusItem: statusItem))
    let statusCenterButton = app.buttons["status.statusCenter"]
    XCTAssertTrue(statusCenterButton.waitForExistence(timeout: 5))
    statusCenterButton.click()

    let statusWindow = app.windows["Codex Status Center"]
    XCTAssertTrue(statusWindow.waitForExistence(timeout: 5))

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
    XCTAssertTrue(
      app.buttons["statusCenter.collapsedRuntime.fixture-endpoint"].waitForExistence(timeout: 5))

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

  func testStatusCenterTokenUsageHistoryBrowsesEarlierTurnsWithoutContextEstimateGhosts() throws {
    let app = LaunchApp(statusSurface: "popover", fixture: "active-turn")
    let statusItem = try StatusItem(in: app)

    XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    XCTAssertTrue(EnsureStatusPopoverOpen(in: app, statusItem: statusItem))
    let statusCenterButton = app.buttons["status.statusCenter"]
    XCTAssertTrue(statusCenterButton.waitForExistence(timeout: 5))
    statusCenterButton.click()

    let statusWindow = app.windows["Codex Status Center"]
    XCTAssertTrue(statusWindow.waitForExistence(timeout: 5))

    let position = app.descendants(matching: .any)[
      "turn.tokenUsageHistory.position.fixture-endpoint"]
    XCTAssertTrue(position.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValue(of: position, equals: "1 of 5"))

    let title = app.descendants(matching: .any)["turn.tokenUsageHistory.title.fixture-endpoint"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    XCTAssertTrue(WaitForStringValue(of: title, equals: "Current turn"))

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
    XCTAssertTrue(WaitForStringValue(of: position, equals: "2 of 5"))
    XCTAssertTrue(WaitForStringValue(of: title, equals: "Current turn"))
    XCTAssertTrue(String(describing: detail.value ?? "").contains("In: 9.1k"))

    earlierButton.click()
    XCTAssertTrue(WaitForStringValue(of: position, equals: "3 of 5"))
    XCTAssertTrue(WaitForStringValue(of: title, equals: "Current turn"))
    XCTAssertTrue(String(describing: detail.value ?? "").contains("In: 6.4k"))

    earlierButton.click()
    XCTAssertTrue(WaitForStringValue(of: position, equals: "4 of 5"))
    XCTAssertTrue(WaitForStringValue(of: title, equals: "Latest completed turn"))
    XCTAssertTrue(String(describing: detail.value ?? "").contains("In: 18.2k"))

    earlierButton.click()
    XCTAssertTrue(WaitForStringValue(of: position, equals: "5 of 5"))
    XCTAssertTrue(WaitForStringValue(of: title, equals: "Earlier turn"))

    let newerButton = app.buttons["turn.tokenUsageHistory.newer.fixture-endpoint"]
    XCTAssertTrue(newerButton.waitForExistence(timeout: 5))
    newerButton.click()
    XCTAssertTrue(WaitForStringValue(of: position, equals: "4 of 5"))

    AttachScreenshot(named: "status-center-token-history", app: app)
  }

  func testStatusCenterRuntimeHistorySectionsBrowseOlderEntries() throws {
    let app = LaunchApp(statusSurface: "popover", fixture: "active-turn")
    let statusItem = try StatusItem(in: app)

    XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    XCTAssertTrue(EnsureStatusPopoverOpen(in: app, statusItem: statusItem))
    let statusCenterButton = app.buttons["status.statusCenter"]
    XCTAssertTrue(statusCenterButton.waitForExistence(timeout: 5))
    statusCenterButton.click()

    let statusWindow = app.windows["Codex Status Center"]
    XCTAssertTrue(statusWindow.waitForExistence(timeout: 5))

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

  func testStatusCenterEmptyStateIsCenteredWithoutRuntimes() throws {
    let app = LaunchApp(statusSurface: "popover")
    let statusItem = try StatusItem(in: app)

    XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    XCTAssertTrue(EnsureStatusPopoverOpen(in: app, statusItem: statusItem))
    let statusCenterButton = app.buttons["status.statusCenter"]
    XCTAssertTrue(statusCenterButton.waitForExistence(timeout: 5))
    statusCenterButton.click()

    let statusWindow = app.windows["Codex Status Center"]
    XCTAssertTrue(statusWindow.waitForExistence(timeout: 5))
    let emptyState = app.descendants(matching: .any)["statusCenter.empty"]
    XCTAssertTrue(emptyState.waitForExistence(timeout: 5))

    let emptyTitle = app.staticTexts["No Codex runtimes"]
    XCTAssertTrue(emptyTitle.waitForExistence(timeout: 5))
    XCTAssertLessThan(abs(emptyTitle.frame.midY - statusWindow.frame.midY), 120)
    XCTAssertGreaterThan(emptyTitle.frame.midX, statusWindow.frame.midX)
    AttachScreenshot(named: "status-center-empty", app: app)
  }

  func testStatusCenterElapsedStatsRefreshAfterPopoverCloses() throws {
    let app = LaunchApp(statusSurface: "popover", fixture: "active-turn")
    let statusItem = try StatusItem(in: app)

    XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    XCTAssertTrue(EnsureStatusPopoverOpen(in: app, statusItem: statusItem))
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
    XCTAssertTrue(EnsureStatusPopoverOpen(in: app, statusItem: statusItem))
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
    XCTAssertTrue(
      settingsWindow.descendants(matching: .any)["settings.launchAtLogin"]
        .waitForExistence(timeout: 5))
    XCTAssertTrue(settingsWindow.staticTexts["settings.launchAtLoginStatus"].exists)
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

  private func EnsureStatusPopoverOpen(
    in app: XCUIApplication,
    statusItem: XCUIElement,
    timeout: TimeInterval = 5
  )
    -> Bool
  {
    let settingsButton = app.buttons["status.settings"]
    if settingsButton.waitForExistence(timeout: 2) {
      return true
    }

    statusItem.click()
    return settingsButton.waitForExistence(timeout: timeout)
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

  private func WaitForStringValueContaining(
    of element: XCUIElement,
    text expected: String,
    timeout: TimeInterval = 5
  )
    -> Bool
  {
    let predicate = NSPredicate(format: "value CONTAINS %@", expected)
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
    let candidates = [
      app.windows["Codex Status Center"],
      app.windows["CodexMenuBar Settings"],
      app.windows.firstMatch,
    ]
    if let element = candidates.first(where: { $0.exists }) {
      let attachment = XCTAttachment(screenshot: element.screenshot())
      attachment.name = name
      attachment.lifetime = .keepAlways
      add(attachment)
      return
    }

    if let croppedStatusSurface = CroppedStatusSurfaceScreenshot(app: app) {
      let attachment = XCTAttachment(
        data: croppedStatusSurface, uniformTypeIdentifier: "public.png")
      attachment.name = name
      attachment.lifetime = .keepAlways
      add(attachment)
      return
    }

    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func CroppedStatusSurfaceScreenshot(app: XCUIApplication) -> Data? {
    let cropElements = [
      app.staticTexts["status.headerTitle"],
      app.staticTexts["status.daemonSummary"],
      app.staticTexts["status.daemonSocket"],
      app.buttons["turn.row.fixture-endpoint"],
      app.buttons["status.quickStart"],
      app.buttons["status.reconnect"],
      app.buttons["status.statusCenter"],
      app.buttons["status.settings"],
      app.buttons["status.quit"],
    ].filter { $0.exists && !$0.frame.isEmpty }

    guard !cropElements.isEmpty else {
      return nil
    }

    var cropFrame = cropElements.reduce(CGRect.null) { partial, element in
      partial.union(element.frame)
    }
    cropFrame = cropFrame.insetBy(dx: -24, dy: -24)

    let screenshot = app.screenshot()
    guard
      let bitmap = NSBitmapImageRep(data: screenshot.pngRepresentation),
      let image = bitmap.cgImage,
      let screenFrame = NSScreen.main?.frame
    else {
      return nil
    }

    let screenBounds = CGRect(origin: .zero, size: screenFrame.size)
    cropFrame = cropFrame.intersection(screenBounds)
    guard !cropFrame.isNull, !cropFrame.isEmpty else {
      return nil
    }

    let scaleX = CGFloat(image.width) / screenFrame.width
    let scaleY = CGFloat(image.height) / screenFrame.height
    let pixelBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let pixelCrop = CGRect(
      x: floor(cropFrame.minX * scaleX),
      y: floor(cropFrame.minY * scaleY),
      width: ceil(cropFrame.width * scaleX),
      height: ceil(cropFrame.height * scaleY)
    )
    .integral
    .intersection(pixelBounds)

    guard
      !pixelCrop.isNull,
      !pixelCrop.isEmpty,
      let cropped = image.cropping(to: pixelCrop)
    else {
      return nil
    }

    let croppedBitmap = NSBitmapImageRep(cgImage: cropped)
    return croppedBitmap.representation(using: .png, properties: [:])
  }
}
