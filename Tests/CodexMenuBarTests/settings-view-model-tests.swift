import XCTest

@testable import CodexMenuBar

@MainActor
final class SettingsViewModelTests: XCTestCase {
  func testLaunchAtLoginToggleRegistersAndUnregistersMainApp() {
    let manager = FakeLoginItemManager(status: .notRegistered)
    let model = SettingsViewModel(loginItemManager: manager)

    XCTAssertFalse(model.isLaunchAtLoginRequested)

    model.SetLaunchAtLoginEnabled(true)

    XCTAssertEqual(manager.requests, [true])
    XCTAssertEqual(model.launchAtLoginStatus, .enabled)
    XCTAssertTrue(model.isLaunchAtLoginRequested)
    XCTAssertNil(model.launchAtLoginError)

    model.SetLaunchAtLoginEnabled(false)

    XCTAssertEqual(manager.requests, [true, false])
    XCTAssertEqual(model.launchAtLoginStatus, .notRegistered)
    XCTAssertFalse(model.isLaunchAtLoginRequested)
  }

  func testLaunchAtLoginRequiresApprovalCountsAsRequested() {
    let model = SettingsViewModel(loginItemManager: FakeLoginItemManager(status: .requiresApproval))

    XCTAssertTrue(model.isLaunchAtLoginRequested)
    XCTAssertEqual(
      model.launchAtLoginStatusTitle,
      "Approve CodexMenuBar in System Settings to finish enabling launch at login."
    )
  }

  func testLaunchAtLoginFailureKeepsSystemStatusAndShowsError() {
    let manager = FakeLoginItemManager(status: .notRegistered)
    manager.error = FakeLoginItemError()
    let model = SettingsViewModel(loginItemManager: manager)

    model.SetLaunchAtLoginEnabled(true)

    XCTAssertEqual(manager.requests, [true])
    XCTAssertEqual(model.launchAtLoginStatus, .notRegistered)
    XCTAssertTrue(
      model.launchAtLoginStatusTitle.hasPrefix("Could not update launch at login:"),
      model.launchAtLoginStatusTitle
    )
  }

  func testOpenLoginItemsSettingsDelegatesToManager() {
    let manager = FakeLoginItemManager(status: .requiresApproval)
    let model = SettingsViewModel(loginItemManager: manager)

    model.OpenLoginItemsSettings()

    XCTAssertEqual(manager.openSystemSettingsCount, 1)
  }
}

@MainActor
private final class FakeLoginItemManager: LoginItemManaging {
  var Status: LoginItemStatus
  var requests: [Bool] = []
  var openSystemSettingsCount = 0
  var error: Error?

  init(status: LoginItemStatus) {
    Status = status
  }

  func SetEnabled(_ isEnabled: Bool) throws {
    requests.append(isEnabled)
    if let error {
      throw error
    }
    Status = isEnabled ? .enabled : .notRegistered
  }

  func OpenSystemSettingsLoginItems() {
    openSystemSettingsCount += 1
  }
}

private struct FakeLoginItemError: Error {}
