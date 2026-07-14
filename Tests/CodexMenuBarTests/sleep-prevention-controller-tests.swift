import XCTest

@testable import CodexMenuBar

@MainActor
final class AutomaticSleepPreventionControllerTests: XCTestCase {
  func testStartsForConnectedActiveSessionsAndChangesModeWithoutStopping() {
    let manager = FakeSleepPreventionManager()
    let controller = AutomaticSleepPreventionController(manager: manager)

    controller.Update(
      isEnabled: true,
      keepDisplayAwake: false,
      isConnected: true,
      activeSessionCount: 2
    )
    controller.Update(
      isEnabled: true,
      keepDisplayAwake: false,
      isConnected: true,
      activeSessionCount: 2
    )
    controller.Update(
      isEnabled: true,
      keepDisplayAwake: true,
      isConnected: true,
      activeSessionCount: 2
    )

    XCTAssertEqual(
      manager.events,
      [.start(.systemOnly), .start(.systemAndDisplay)]
    )
    XCTAssertEqual(controller.activeSessionCount, 2)
    XCTAssertTrue(controller.isPreventingSleep)
    XCTAssertEqual(controller.activeMode, .systemAndDisplay)
  }

  func testStopsWhenTheLastActiveSessionFinishesOrPauses() {
    let manager = FakeSleepPreventionManager()
    let controller = AutomaticSleepPreventionController(manager: manager)

    controller.Update(
      isEnabled: true,
      keepDisplayAwake: false,
      isConnected: true,
      activeSessionCount: 1
    )
    controller.Update(
      isEnabled: true,
      keepDisplayAwake: false,
      isConnected: true,
      activeSessionCount: 0
    )

    XCTAssertEqual(manager.events, [.start(.systemOnly), .stop])
    XCTAssertEqual(controller.activeSessionCount, 0)
    XCTAssertFalse(controller.isPreventingSleep)
    XCTAssertNil(controller.activeMode)
  }

  func testStopsWhenDisabledOrDisconnected() {
    let manager = FakeSleepPreventionManager()
    let controller = AutomaticSleepPreventionController(manager: manager)

    controller.Update(
      isEnabled: true,
      keepDisplayAwake: false,
      isConnected: true,
      activeSessionCount: 1
    )
    controller.Update(
      isEnabled: false,
      keepDisplayAwake: false,
      isConnected: true,
      activeSessionCount: 1
    )
    controller.Update(
      isEnabled: true,
      keepDisplayAwake: false,
      isConnected: false,
      activeSessionCount: 1
    )

    XCTAssertEqual(manager.events, [.start(.systemOnly), .stop])
    XCTAssertEqual(controller.activeSessionCount, 0)
    XCTAssertFalse(controller.isPreventingSleep)
  }

  func testReconnectWaitsForAuthoritativeActiveSessionCount() {
    let manager = FakeSleepPreventionManager()
    let controller = AutomaticSleepPreventionController(manager: manager)

    controller.Update(
      isEnabled: true,
      keepDisplayAwake: false,
      isConnected: true,
      activeSessionCount: 1
    )
    controller.Update(
      isEnabled: true,
      keepDisplayAwake: false,
      isConnected: false,
      activeSessionCount: 1
    )
    controller.Update(
      isEnabled: true,
      keepDisplayAwake: false,
      isConnected: true,
      activeSessionCount: 0
    )

    XCTAssertEqual(manager.events, [.start(.systemOnly), .stop])
    XCTAssertFalse(controller.isPreventingSleep)

    controller.Update(
      isEnabled: true,
      keepDisplayAwake: false,
      isConnected: true,
      activeSessionCount: 1
    )

    XCTAssertEqual(manager.events, [.start(.systemOnly), .stop, .start(.systemOnly)])
    XCTAssertTrue(controller.isPreventingSleep)
  }
}

@MainActor
private final class FakeSleepPreventionManager: SleepPreventionManaging {
  enum Event: Equatable {
    case start(SleepPreventionMode)
    case stop
  }

  private(set) var isPreventingSleep = false
  private(set) var activeMode: SleepPreventionMode?
  private(set) var events: [Event] = []

  func Start(mode: SleepPreventionMode) {
    events.append(.start(mode))
    isPreventingSleep = true
    activeMode = mode
  }

  func Stop() {
    events.append(.stop)
    isPreventingSleep = false
    activeMode = nil
  }
}
