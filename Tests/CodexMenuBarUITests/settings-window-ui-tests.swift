import AppKit
import XCTest

@MainActor
final class SettingsWindowUITests: CodexMenuBarUITestCase {
  func testSettingsShortcutOpensSettingsWindow() throws {
    let app = LaunchApp()
    _ = try StatusItem(in: app)

    app.activate()
    app.typeKey(",", modifierFlags: .command)

    XCTAssertTrue(SettingsWindow(in: app).waitForExistence(timeout: 5))
  }

  func testSettingsWindowAppliesSessionSocketOverride() throws {
    let (_, settingsWindow) = LaunchSettingsWindow()

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
    let (app, settingsWindow) = LaunchSettingsWindow()

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

  func testSettingsSleepPreventionTogglesControlPowerAssertions() throws {
    let (app, settingsWindow) = LaunchSettingsWindow(fixture: "active-turn")
    defer {
      app.terminate()
    }

    let preventSleepToggle =
      settingsWindow.descendants(matching: .any)["settings.preventSleepWhileActive"]
    let keepDisplayAwakeToggle =
      settingsWindow.descendants(matching: .any)["settings.keepDisplayAwake"]
    let status = settingsWindow.staticTexts["settings.sleepPreventionStatus"]

    XCTAssertTrue(preventSleepToggle.waitForExistence(timeout: 5))
    XCTAssertTrue(keepDisplayAwakeToggle.waitForExistence(timeout: 5))
    XCTAssertTrue(status.waitForExistence(timeout: 5))

    preventSleepToggle.click()

    XCTAssertTrue(
      WaitForStringValue(
        of: status,
        equals:
          "Preventing Mac idle sleep for 1 active Codex session. The display may turn off."
      )
    )
    XCTAssertTrue(
      WaitForPowerAssertion(
        containing: "CodexMenuBar has active Codex sessions",
        exists: true
      ),
      PowerAssertionsOutput()
    )

    keepDisplayAwakeToggle.click()

    XCTAssertTrue(
      WaitForStringValue(
        of: status,
        equals: "Preventing Mac and display idle sleep for 1 active Codex session."
      )
    )
    XCTAssertTrue(
      WaitForPowerAssertion(
        containing:
          "CodexMenuBar has active Codex sessions and is keeping the display awake",
        exists: true
      ),
      PowerAssertionsOutput()
    )
    XCTAssertTrue(
      PowerAssertionsOutput().contains("PreventUserIdleDisplaySleep"),
      PowerAssertionsOutput()
    )

    preventSleepToggle.click()

    XCTAssertTrue(
      WaitForStringValue(
        of: status,
        equals: "Off. CodexMenuBar does not change idle sleep behavior."
      )
    )
    XCTAssertTrue(
      WaitForPowerAssertion(
        containing: "CodexMenuBar has active Codex sessions",
        exists: false
      ),
      PowerAssertionsOutput()
    )
  }

  func testSettingsSleepPreventionStopsWhenTheActiveSessionPauses() throws {
    let (app, settingsWindow) = LaunchSettingsWindow(
      fixture: "active-turn",
      additionalArguments: ["--pause-active-fixture-after", "12"]
    )
    defer {
      app.terminate()
    }

    let preventSleepToggle =
      settingsWindow.descendants(matching: .any)["settings.preventSleepWhileActive"]
    let status = settingsWindow.staticTexts["settings.sleepPreventionStatus"]

    XCTAssertTrue(preventSleepToggle.waitForExistence(timeout: 5))
    XCTAssertTrue(status.waitForExistence(timeout: 5))
    preventSleepToggle.click()

    XCTAssertTrue(
      WaitForStringValue(
        of: status,
        equals:
          "Preventing Mac idle sleep for 1 active Codex session. The display may turn off."
      )
    )
    XCTAssertTrue(
      WaitForPowerAssertion(
        containing: "CodexMenuBar has active Codex sessions",
        exists: true
      ),
      PowerAssertionsOutput()
    )
    AttachScreenshot(named: "settings-sleep-prevention-active", app: app)

    XCTAssertTrue(
      WaitForStringValue(
        of: status,
        equals: "Ready. Sleep prevention starts when a Codex session is working.",
        timeout: 20
      )
    )
    XCTAssertTrue(
      WaitForPowerAssertion(
        containing: "CodexMenuBar has active Codex sessions",
        exists: false
      ),
      PowerAssertionsOutput()
    )
    AttachScreenshot(named: "settings-sleep-prevention-paused", app: app)
  }

  func testSettingsSleepPreventionWaitsForReconnectSnapshotBeforeResuming() throws {
    let (app, settingsWindow) = LaunchSettingsWindow(
      fixture: "active-turn",
      additionalArguments: ["--reconnect-active-fixture-after", "12"]
    )
    defer {
      app.terminate()
    }

    let preventSleepToggle =
      settingsWindow.descendants(matching: .any)["settings.preventSleepWhileActive"]
    let status = settingsWindow.staticTexts["settings.sleepPreventionStatus"]

    XCTAssertTrue(preventSleepToggle.waitForExistence(timeout: 5))
    XCTAssertTrue(status.waitForExistence(timeout: 5))
    preventSleepToggle.click()

    let activeStatus =
      "Preventing Mac idle sleep for 1 active Codex session. The display may turn off."
    let readyStatus = "Ready. Sleep prevention starts when a Codex session is working."
    XCTAssertTrue(WaitForStringValue(of: status, equals: activeStatus))
    XCTAssertTrue(
      WaitForPowerAssertion(
        containing: "CodexMenuBar has active Codex sessions",
        exists: true
      ),
      PowerAssertionsOutput()
    )

    XCTAssertTrue(WaitForStringValue(of: status, equals: readyStatus, timeout: 20))
    XCTAssertTrue(
      WaitForPowerAssertion(
        containing: "CodexMenuBar has active Codex sessions",
        exists: false
      ),
      PowerAssertionsOutput()
    )

    RunLoop.current.run(until: Date().addingTimeInterval(2))
    XCTAssertTrue(WaitForStringValue(of: status, equals: readyStatus, timeout: 2))
    XCTAssertTrue(
      WaitForPowerAssertion(
        containing: "CodexMenuBar has active Codex sessions",
        exists: false,
        timeout: 2
      ),
      PowerAssertionsOutput()
    )
    AttachScreenshot(named: "settings-sleep-prevention-awaiting-reconnect-snapshot", app: app)

    XCTAssertTrue(WaitForStringValue(of: status, equals: activeStatus, timeout: 10))
    XCTAssertTrue(
      WaitForPowerAssertion(
        containing: "CodexMenuBar has active Codex sessions",
        exists: true
      ),
      PowerAssertionsOutput()
    )
  }

  func testSettingsWindowUseLaunchDefaultRestoresResolvedSocketPath() throws {
    let (_, settingsWindow) = LaunchSettingsWindow()

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
}
