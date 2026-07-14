import AppKit
import XCTest

@MainActor
class CodexMenuBarUITestCase: XCTestCase {
  private let statusItemTitle = "CodexUITest"

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func LaunchSettingsWindow(
    fixture: String? = nil,
    additionalArguments: [String] = [],
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> (
    app: XCUIApplication, window: XCUIElement
  ) {
    let app = LaunchApp(
      startScreen: "Settings",
      fixture: fixture,
      additionalArguments: additionalArguments
    )
    let settingsWindow = SettingsWindow(in: app)
    XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5), file: file, line: line)
    return (app, settingsWindow)
  }

  func LaunchStatusCenter(
    fixture: String? = "active-turn", file: StaticString = #filePath, line: UInt = #line
  ) throws -> (app: XCUIApplication, window: XCUIElement) {
    let app = LaunchApp(statusSurface: "popover", fixture: fixture)
    let statusItem = try StatusItem(in: app)

    XCTAssertTrue(statusItem.waitForExistence(timeout: 10), file: file, line: line)
    XCTAssertTrue(EnsureStatusPopoverOpen(in: app, statusItem: statusItem), file: file, line: line)
    let statusCenterButton = app.buttons["status.statusCenter"]
    XCTAssertTrue(statusCenterButton.waitForExistence(timeout: 5), file: file, line: line)
    statusCenterButton.click()

    let statusWindow = app.windows["Codex Status Center"]
    XCTAssertTrue(statusWindow.waitForExistence(timeout: 5), file: file, line: line)
    return (app, statusWindow)
  }

  func LaunchApp(
    startScreen: String? = nil,
    statusSurface: String? = nil,
    fixture: String? = nil,
    additionalArguments: [String] = []
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
    app.launchArguments += additionalArguments
    app.launchEnvironment["CODEXMENUBAR_UI_TEST_STATUS_TITLE"] = statusItemTitle
    app.launchEnvironment["CODEXMENUBAR_UI_TEST_DEFAULTS_SUITE"] =
      "com.codex.CodexMenuBar.UITests.\(UUID().uuidString)"
    app.launch()
    return app
  }

  func SettingsWindow(in app: XCUIApplication) -> XCUIElement {
    app.windows["CodexMenuBar Settings"]
  }

  func StatusItem(in app: XCUIApplication) throws -> XCUIElement {
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

  func EnsureStatusPopoverOpen(
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

  func ContextMenuItem(named title: String, app: XCUIApplication) throws -> XCUIElement {
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

  func CompletedRunRow(containing turnId: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@",
        "turn.completedRun.row.", turnId)
    ).firstMatch
  }

  func CompletedRunPrompt(containing turnId: String, in app: XCUIApplication) -> XCUIElement {
    app.staticTexts.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@",
        "turn.completedRun.prompt.", turnId)
    ).firstMatch
  }

  func CompletedRunPromptToggle(
    containing turnId: String,
    in app: XCUIApplication
  ) -> XCUIElement {
    app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@",
        "turn.completedRun.promptSection.", turnId)
    ).firstMatch
  }

  func WaitForStringValue(
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

  func WaitForStringValueContaining(
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

  func WaitForStringLabelContaining(
    of element: XCUIElement,
    text expected: String,
    timeout: TimeInterval = 5
  )
    -> Bool
  {
    let predicate = NSPredicate(format: "label CONTAINS %@", expected)
    let expectation = expectation(for: predicate, evaluatedWith: element)
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  func WaitForStringLabelChange(
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

  func AssertFrame(
    _ actual: CGRect,
    matches expected: CGRect,
    accuracy: CGFloat = 1,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
  }

  func WaitForNonExistence(of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    let predicate = NSPredicate(format: "exists == false")
    let expectation = expectation(for: predicate, evaluatedWith: element)
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  func WaitForPasteboardContaining(_ expected: String, timeout: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if NSPasteboard.general.string(forType: .string)?.contains(expected) == true {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return false
  }

  func WaitForPowerAssertion(
    containing expected: String,
    exists: Bool,
    timeout: TimeInterval = 10
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      let containsExpected = PowerAssertionsOutput().contains(expected)
      if containsExpected == exists {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    } while Date() < deadline

    return PowerAssertionsOutput().contains(expected) == exists
  }

  func PowerAssertionsOutput() -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["-g", "assertions"]
    process.standardOutput = output
    process.standardError = output

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return "pmset failed: \(error.localizedDescription)"
    }

    let data = output.fileHandleForReading.readDataToEndOfFile()
    return String(decoding: data, as: UTF8.self)
  }

  func WaitForQueryCount(
    _ query: XCUIElementQuery,
    equals expectedCount: Int,
    timeout: TimeInterval = 5
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if query.count == expectedCount {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return query.count == expectedCount
  }

  func ClickAwayFromStatusPopover(statusItem: XCUIElement) {
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

  func AttachScreenshot(named name: String, app: XCUIApplication) {
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

  func CroppedStatusSurfaceScreenshot(app: XCUIApplication) -> Data? {
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
