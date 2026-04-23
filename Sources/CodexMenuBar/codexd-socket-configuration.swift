import Foundation

enum CodexdSocketSource: Equatable {
  case sessionOverride
  case environmentSocketPath
  case environmentCodexHome
  case defaultCodexHome

  var description: String {
    switch self {
    case .sessionOverride:
      return "Using the Settings override for this app session."
    case .environmentSocketPath:
      return "Using CODEXD_SOCKET_PATH from the launch environment."
    case .environmentCodexHome:
      return "Using CODEX_HOME/runtime/codexd/codexd.sock from the launch environment."
    case .defaultCodexHome:
      return "Using the default ~/.codex/runtime/codexd/codexd.sock path."
    }
  }
}

struct CodexdSocketConfiguration: Equatable {
  let source: CodexdSocketSource
  let resolvedSocketPath: String

  static func Resolve(
    sessionOverride: String? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    homeDirectory: String = NSHomeDirectory()
  ) -> Self {
    if let overridePath = NormalizedPath(sessionOverride) {
      return Self(source: .sessionOverride, resolvedSocketPath: ExpandedPath(overridePath))
    }

    if let exactOverride = NormalizedPath(environment["CODEXD_SOCKET_PATH"]) {
      return Self(source: .environmentSocketPath, resolvedSocketPath: ExpandedPath(exactOverride))
    }

    if let codexHome = NormalizedPath(environment["CODEX_HOME"]) {
      return Self(
        source: .environmentCodexHome,
        resolvedSocketPath: SocketPath(fromCodexHome: codexHome)
      )
    }

    return Self(
      source: .defaultCodexHome,
      resolvedSocketPath: SocketPath(fromCodexHome: "\(homeDirectory)/.codex")
    )
  }

  private static func SocketPath(fromCodexHome codexHome: String) -> String {
    let expandedHome = ExpandedPath(codexHome)
    return
      URL(fileURLWithPath: expandedHome)
      .appendingPathComponent("runtime")
      .appendingPathComponent("codexd")
      .appendingPathComponent("codexd.sock")
      .path
  }
}

private func NormalizedPath(_ value: String?) -> String? {
  guard let value else {
    return nil
  }

  let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.isEmpty ? nil : trimmed
}

private func ExpandedPath(_ value: String) -> String {
  (value as NSString).expandingTildeInPath
}
