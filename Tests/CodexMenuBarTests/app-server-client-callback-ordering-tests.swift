import XCTest

@testable import CodexMenuBar

@MainActor
final class AppServerClientCallbackOrderingTests: XCTestCase {
  func testCallbackQueuePreservesReconnectSnapshotOrdering() async {
    let callbackQueue = OrderedMainActorCallbackQueue(
      label: "com.codex.CodexMenuBarTests.callback-ordering")
    let expected = [
      "runtime-ids-cleared",
      "reconnecting",
      "connected",
      "snapshot-reconciled",
      "runtime-ids-restored",
    ]
    var observed: [String] = []
    let delivered = expectation(description: "ordered callbacks delivered")
    delivered.expectedFulfillmentCount = expected.count

    for event in expected {
      callbackQueue.Enqueue {
        observed.append(event)
        delivered.fulfill()
      }
    }

    await fulfillment(of: [delivered], timeout: 2)
    XCTAssertEqual(observed, expected)
  }
}
