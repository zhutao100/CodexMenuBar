import XCTest

@testable import CodexMenuBar

final class CodexdSocketConfigurationTests: XCTestCase {
  func testSessionOverrideTakesPrecedenceOverLaunchEnvironment() {
    let configuration = CodexdSocketConfiguration.Resolve(
      sessionOverride: "  /tmp/session.sock  ",
      environment: [
        "CODEXD_SOCKET_PATH": "/tmp/env.sock",
        "CODEX_HOME": "/tmp/codex-home",
      ],
      homeDirectory: "/Users/tester"
    )

    XCTAssertEqual(configuration.source, .sessionOverride)
    XCTAssertEqual(configuration.resolvedSocketPath, "/tmp/session.sock")
  }

  func testLaunchEnvironmentSocketPathBeatsCodexHome() {
    let configuration = CodexdSocketConfiguration.Resolve(
      environment: [
        "CODEXD_SOCKET_PATH": "/tmp/env.sock",
        "CODEX_HOME": "/tmp/codex-home",
      ],
      homeDirectory: "/Users/tester"
    )

    XCTAssertEqual(configuration.source, .environmentSocketPath)
    XCTAssertEqual(configuration.resolvedSocketPath, "/tmp/env.sock")
  }

  func testDefaultSocketPathFallsBackToHomeCodexRuntime() {
    let configuration = CodexdSocketConfiguration.Resolve(
      environment: [:],
      homeDirectory: "/Users/tester"
    )

    XCTAssertEqual(configuration.source, .defaultCodexHome)
    XCTAssertEqual(
      configuration.resolvedSocketPath,
      "/Users/tester/.codex/runtime/codexd/codexd.sock"
    )
  }
}
