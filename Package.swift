// swift-tools-version: 6.2.4
import PackageDescription

let package = Package(
  name: "CodexMenuBar",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(
      name: "CodexMenuBar",
      targets: ["CodexMenuBar"]
    )
  ],
  targets: [
    .executableTarget(
      name: "CodexMenuBar",
      resources: [
        .copy("Resources/svgs/codex-app.svg"),
        .copy("Resources/svgs/codex.svg"),
      ],
      swiftSettings: [
        .unsafeFlags(["-swift-version", "6"])
      ]
    ),
    .testTarget(
      name: "CodexMenuBarTests",
      dependencies: [
        "SwiftPMSandboxTestingBootstrap",  // macos-sandbox-testing
        "CodexMenuBar",
      ],
      swiftSettings: [
        .unsafeFlags(["-swift-version", "6"])
      ]
    ),
    // macos-sandbox-testing: begin
    .target(
      name: "SwiftPMSandboxTestingBootstrap",
      path: "Sources/SwiftPMSandboxTestingBootstrap",
      publicHeadersPath: "include"
    ),
    // macos-sandbox-testing: end
  ]
)
