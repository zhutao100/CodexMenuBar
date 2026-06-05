import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let turnStore = TurnStore()
  private lazy var model = MenuBarViewModel(turnStore: turnStore)
  private let settingsModel = SettingsViewModel()
  private lazy var statusMenu = StatusMenuController(model: model)
  private let appServerClient = AppServerClient()
  private let terminalLauncher = TerminalLauncher()
  private lazy var statusWindowController = StatusWindowController(
    model: model,
    onOpenTerminal: { [weak self] workingDirectory in
      self?.terminalLauncher.OpenTerminal(at: workingDirectory)
    },
    onVisibilityChanged: { [weak self] isVisible in
      self?.SetStatusWindowVisibility(isVisible)
    }
  )
  private lazy var settingsWindowController = SettingsWindowController(
    model: settingsModel,
    onApplySocketOverride: { [weak self] socketPath in
      self?.appServerClient.UpdateSocketPathOverride(socketPath)
    },
    onReconnect: { [weak self] in
      self?.appServerClient.Restart()
    },
    onQuickStart: { [weak self] in
      self?.terminalLauncher.LaunchQuickStart()
    }
  )

  private var timer: Timer?
  private var isPopoverVisible = false
  private var isStatusWindowVisible = false

  private var isLiveSurfaceVisible: Bool {
    isPopoverVisible || isStatusWindowVisible
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    ApplyActivationPolicy()
    ConfigureMainMenu()
    ConfigureStatusMenu()
    ConfigureClient()
    if !IsUITestMode() {
      appServerClient.Start()
    }
    ApplyUITestFixtureIfRequested()
    if ShouldLaunchIntoSettings() {
      ShowSettingsWindow()
    }
    PresentUITestSurfaceIfRequested()
  }

  func applicationWillTerminate(_ notification: Notification) {
    StopTimer()
    appServerClient.Stop()
  }

  private func ConfigureMainMenu() {
    let mainMenu = NSMenu(title: "CodexMenuBar")

    let appMenu = AddSubmenu(title: "CodexMenuBar", to: mainMenu)
    appMenu.addItem(
      MenuItem(
        title: "About CodexMenuBar",
        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
        target: NSApp
      ))
    appMenu.addItem(.separator())

    appMenu.addItem(
      MenuItem(
        title: "Settings...",
        action: #selector(OnMenuSettings(_:)),
        keyEquivalent: ",",
        target: self
      ))
    appMenu.addItem(.separator())

    let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
    let servicesMenu = NSMenu(title: "Services")
    servicesItem.submenu = servicesMenu
    appMenu.addItem(servicesItem)
    NSApp.servicesMenu = servicesMenu
    appMenu.addItem(.separator())

    appMenu.addItem(
      MenuItem(
        title: "Hide CodexMenuBar",
        action: #selector(NSApplication.hide(_:)),
        keyEquivalent: "h",
        target: NSApp
      ))
    appMenu.addItem(
      MenuItem(
        title: "Hide Others",
        action: #selector(NSApplication.hideOtherApplications(_:)),
        keyEquivalent: "h",
        target: NSApp,
        modifierMask: [.command, .option]
      ))
    appMenu.addItem(
      MenuItem(
        title: "Show All",
        action: #selector(NSApplication.unhideAllApplications(_:)),
        target: NSApp
      ))
    appMenu.addItem(.separator())

    appMenu.addItem(
      MenuItem(
        title: "Quit CodexMenuBar",
        action: #selector(OnMenuQuit(_:)),
        keyEquivalent: "q",
        target: self
      ))

    let fileMenu = AddSubmenu(title: "File", to: mainMenu)
    fileMenu.addItem(
      MenuItem(
        title: "Close Window",
        action: #selector(NSWindow.performClose(_:)),
        keyEquivalent: "w"
      ))

    let editMenu = AddSubmenu(title: "Edit", to: mainMenu)
    editMenu.addItem(MenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
    editMenu.addItem(
      MenuItem(
        title: "Redo",
        action: Selector(("redo:")),
        keyEquivalent: "z",
        modifierMask: [.command, .shift]
      ))

    editMenu.addItem(.separator())
    editMenu.addItem(MenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
    editMenu.addItem(
      MenuItem(
        title: "Copy",
        action: #selector(NSText.copy(_:)),
        keyEquivalent: "c"
      ))
    editMenu.addItem(
      MenuItem(
        title: "Paste",
        action: #selector(NSText.paste(_:)),
        keyEquivalent: "v"
      ))
    editMenu.addItem(
      MenuItem(
        title: "Paste and Match Style",
        action: #selector(NSTextView.pasteAsPlainText(_:)),
        keyEquivalent: "v",
        modifierMask: [.command, .option, .shift]
      ))

    editMenu.addItem(MenuItem(title: "Delete", action: #selector(NSText.delete(_:))))
    editMenu.addItem(.separator())
    editMenu.addItem(
      MenuItem(
        title: "Select All",
        action: #selector(NSText.selectAll(_:)),
        keyEquivalent: "a"
      ))

    let viewMenu = AddSubmenu(title: "View", to: mainMenu)
    viewMenu.addItem(
      MenuItem(
        title: "Status Center",
        action: #selector(OnMenuStatusCenter(_:)),
        target: self
      ))
    viewMenu.addItem(
      MenuItem(
        title: "Quick Start",
        action: #selector(OnMenuQuickStart(_:)),
        target: self
      ))
    viewMenu.addItem(
      MenuItem(
        title: "Reconnect codexd",
        action: #selector(OnMenuReconnect(_:)),
        target: self
      ))

    let windowMenu = AddSubmenu(title: "Window", to: mainMenu)
    NSApp.windowsMenu = windowMenu

    windowMenu.addItem(
      MenuItem(
        title: "Minimize",
        action: #selector(NSWindow.performMiniaturize(_:)),
        keyEquivalent: "m"
      ))
    windowMenu.addItem(
      MenuItem(
        title: "Zoom",
        action: #selector(NSWindow.performZoom(_:))
      ))
    windowMenu.addItem(.separator())

    windowMenu.addItem(
      MenuItem(
        title: "Bring All to Front",
        action: #selector(NSApplication.arrangeInFront(_:)),
        target: NSApp
      ))

    NSApp.mainMenu = mainMenu
  }

  private func AddSubmenu(title: String, to menu: NSMenu) -> NSMenu {
    let item = NSMenuItem()
    let submenu = NSMenu(title: title)
    item.submenu = submenu
    menu.addItem(item)
    return submenu
  }

  private func MenuItem(
    title: String,
    action: Selector?,
    keyEquivalent: String = "",
    target: AnyObject? = nil,
    modifierMask: NSEvent.ModifierFlags = .command
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    item.target = target
    item.keyEquivalentModifierMask = modifierMask
    return item
  }

  private func ConfigureStatusMenu() {
    statusMenu.ReconnectHandler = { [weak self] in
      self?.appServerClient.Restart()
    }
    statusMenu.QuitHandler = {
      NSApplication.shared.terminate(nil)
    }
    statusMenu.QuickStartHandler = { [weak self] in
      self?.terminalLauncher.LaunchQuickStart()
    }
    statusMenu.SettingsHandler = { [weak self] in
      self?.ShowSettingsWindow()
    }
    statusMenu.StatusCenterHandler = { [weak self] in
      self?.ShowStatusWindow()
    }
    statusMenu.OpenTerminalHandler = { [weak self] workingDirectory in
      self?.terminalLauncher.OpenTerminal(at: workingDirectory)
    }

    statusMenu.PopoverVisibilityChanged = { [weak self] isShown in
      guard let self else {
        return
      }

      self.isPopoverVisible = isShown
      if isShown {
        self.model.SyncSectionDisclosureState()
        self.model.InvalidateView()
      }
      self.RefreshLiveSurfaceTimer(tickImmediately: isShown)
    }
  }

  private func ConfigureClient() {
    appServerClient.OnStateChange = { [weak self] state in
      guard let self else {
        return
      }
      self.model.connectionState = state
      self.settingsModel.connectionState = state
      self.model.InvalidateView()
    }

    appServerClient.OnEndpointIdsChanged = { [weak self] endpointIds in
      guard let self else {
        return
      }
      self.model.SetEndpointIds(endpointIds)
      self.model.InvalidateView()
    }

    appServerClient.OnDiagnosticsChanged = { [weak self] diagnostics in
      guard let self else {
        return
      }
      self.model.codexdDiagnostics = diagnostics
      self.model.InvalidateView()
    }

    appServerClient.OnNotification = { [weak self] method, params in
      guard let self else {
        return
      }
      self.HandleNotification(method: method, params: params)
    }
  }

  private func ShowSettingsWindow() {
    settingsWindowController.Show()
  }

  private func ShowStatusWindow() {
    isStatusWindowVisible = true
    ApplyActivationPolicy()
    statusWindowController.Show()
  }

  private func SetStatusWindowVisibility(_ isVisible: Bool) {
    isStatusWindowVisible = isVisible
    ApplyActivationPolicy()
    if isVisible {
      model.InvalidateView()
    }
    RefreshLiveSurfaceTimer(tickImmediately: isVisible)
  }

  private func ApplyActivationPolicy() {
    let targetPolicy: NSApplication.ActivationPolicy = isStatusWindowVisible ? .regular : .accessory
    if NSApplication.shared.activationPolicy() != targetPolicy {
      NSApplication.shared.setActivationPolicy(targetPolicy)
    }
  }

  @objc
  private func OnMenuSettings(_ sender: Any?) {
    _ = sender
    ShowSettingsWindow()
  }

  @objc
  private func OnMenuStatusCenter(_ sender: Any?) {
    _ = sender
    ShowStatusWindow()
  }

  @objc
  private func OnMenuQuickStart(_ sender: Any?) {
    _ = sender
    terminalLauncher.LaunchQuickStart()
  }

  @objc
  private func OnMenuReconnect(_ sender: Any?) {
    _ = sender
    appServerClient.Restart()
  }

  @objc
  private func OnMenuQuit(_ sender: Any?) {
    _ = sender
    NSApplication.shared.terminate(nil)
  }

  private func IsUITestMode() -> Bool {
    ProcessInfo.processInfo.arguments.contains("--uitest")
  }

  private func ShouldLaunchIntoSettings() -> Bool {
    guard let startScreen = ArgumentValue(after: "--start-screen") else {
      return false
    }
    return startScreen.caseInsensitiveCompare("settings") == .orderedSame
  }

  private func PresentUITestSurfaceIfRequested() {
    guard IsUITestMode(),
      let rawSurface = ArgumentValue(after: "--open-status-surface"),
      let surface = StatusMenuController.UITestSurface(
        rawValue: rawSurface.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    else {
      return
    }

    DispatchQueue.main.async { [weak self] in
      self?.statusMenu.PresentUITestSurface(surface)
    }
  }

  private func ApplyUITestFixtureIfRequested() {
    guard IsUITestMode(), let fixture = ArgumentValue(after: "--fixture") else {
      return
    }

    if fixture.caseInsensitiveCompare("delegate-turn") == .orderedSame {
      ApplyDelegateUITestFixture()
      return
    }

    if fixture.caseInsensitiveCompare("post-turn-review-lifecycle") == .orderedSame {
      ApplyPostTurnReviewLifecycleUITestFixture()
      return
    }

    if fixture.caseInsensitiveCompare("completed-turn-history") == .orderedSame {
      ApplyCompletedTurnHistoryUITestFixture()
      return
    }

    guard fixture.caseInsensitiveCompare("active-turn") == .orderedSame else {
      return
    }

    let endpointId = "fixture-endpoint"
    let threadId = "fixture-thread"
    let turnId = "2"
    let now = Date()
    let startedAt = now.addingTimeInterval(-96)
    let cwd = NSHomeDirectory().appending("/workspace/agentic-tools/CodexMenuBar")
    let activePrompt = """
      Polish the active turn menu bar panel and make the settings window compact.
      Keep the status header controls discoverable on hover.
      Make runtime expansion feel steady in the popover.
      Center collapsed status center runtime icons.
      Show five prompt lines by default.
      Reveal this sixth active prompt line only after expansion.
      Keep the prompt foldable again after review.
      """

    settingsModel.connectionState = .connected
    model.connectionState = .connected
    model.codexdDiagnostics = CodexdDiagnostics(
      resolvedSocketPath: "/tmp/codexd-fixture.sock",
      connectedAt: now,
      protocolVersion: 1,
      capabilities: ["eventReplay", "runtimeState"],
      lastEventSeq: 128
    )
    model.SetEndpointIds([endpointId])
    turnStore.UpdateRuntimeMetadata(endpointId: endpointId, cwd: cwd, sessionSource: "codex")
    SeedCompletedUITestTurn(
      endpointId: endpointId,
      threadId: threadId,
      turnId: "fixture-turn-bootstrap",
      prompt: "Set up an initial status center scaffold.",
      startedAt: now.addingTimeInterval(-4_200),
      endedAt: now.addingTimeInterval(-4_020),
      tokenUsage: TokenUsageInfo(
        inputTokens: 9_600,
        cachedInputTokens: 2_400,
        outputTokens: 1_500,
        reasoningTokens: 620,
        totalTokens: 11_100,
        contextWindow: 128_000
      ),
      command: "swift test --filter TurnStoreHistoryTests",
      changedPath: "Tests/CodexMenuBarTests/turn-store-history-tests.swift"
    )
    SeedCompletedUITestTurn(
      endpointId: endpointId,
      threadId: threadId,
      turnId: "fixture-turn-status-center",
      prompt: "Add a resizable status center sidebar.",
      startedAt: now.addingTimeInterval(-2_400),
      endedAt: now.addingTimeInterval(-2_190),
      tokenUsage: TokenUsageInfo(
        inputTokens: 18_200,
        cachedInputTokens: 7_100,
        outputTokens: 2_650,
        reasoningTokens: 1_100,
        totalTokens: 20_850,
        contextWindow: 128_000
      ),
      tokenUsageSamples: [
        TokenUsageInfo(
          inputTokens: 11_400,
          cachedInputTokens: 4_600,
          outputTokens: 1_480,
          reasoningTokens: 560,
          totalTokens: 12_880,
          contextWindow: 128_000
        ),
        TokenUsageInfo(
          inputTokens: 18_200,
          cachedInputTokens: 7_100,
          outputTokens: 2_650,
          reasoningTokens: 1_100,
          totalTokens: 20_850,
          contextWindow: 128_000
        ),
      ],
      command: "./scripts/ui/ui_loop.sh --scheme CodexMenuBarUI --destination platform=macOS",
      changedPath: "Sources/CodexMenuBar/status-window-controller.swift"
    )
    turnStore.ApplyThreadSnapshot(
      endpointId: endpointId,
      thread: [
        "id": threadId,
        "title": "Menu bar polish",
        "cwd": cwd,
        "turns": [
          [
            "id": turnId,
            "model": "gpt-5-codex",
            "modelProvider": "OpenAI",
            "thinkingLevel": "medium",
            "items": [
              [
                "type": "user_message",
                "content": activePrompt,
              ]
            ],
          ]
        ],
      ],
      at: now
    )
    turnStore.UpsertTurnStarted(
      endpointId: endpointId, threadId: threadId, turnId: turnId, at: startedAt)
    turnStore.UpdateTurnMetadata(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      turn: [
        "promptPreview": activePrompt,
        "model": "gpt-5-codex",
        "modelProvider": "OpenAI",
        "thinkingLevel": "medium",
      ],
      at: startedAt.addingTimeInterval(1)
    )
    turnStore.RecordProgress(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      category: .reasoning,
      state: .started,
      label: "Planning UI polish",
      at: startedAt.addingTimeInterval(8)
    )
    turnStore.RecordProgress(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      category: .tool,
      state: .started,
      label: "Running verification loop",
      at: startedAt.addingTimeInterval(34)
    )
    for command in [
      CommandSummary(
        command: "fd-x -t f -d 4 .",
        status: .completed,
        exitCode: 0,
        durationMs: 170
      ),
      CommandSummary(
        command: "rg-x -n \"Turn Token Usage\" Sources Tests",
        status: .completed,
        exitCode: 0,
        durationMs: 240
      ),
      CommandSummary(
        command: "sed-x -n '1,220p' Sources/CodexMenuBar/turn-menu-row-view.swift",
        status: .completed,
        exitCode: 0,
        durationMs: 120
      ),
      CommandSummary(
        command: "swift test --filter TurnStoreHistoryTests",
        status: .completed,
        exitCode: 0,
        durationMs: 1_200
      ),
      CommandSummary(
        command: "./scripts/build.sh",
        status: .completed,
        exitCode: 0,
        durationMs: 8_400
      ),
      CommandSummary(
        command: "./scripts/ui/ui_loop.sh --scheme CodexMenuBarUI --destination platform=macOS",
        status: .inProgress,
        exitCode: nil,
        durationMs: nil
      ),
    ] {
      turnStore.RecordCommand(endpointId: endpointId, turnId: turnId, command: command)
    }
    for change in [
      FileChangeSummary(path: "Sources/CodexMenuBar/app-delegate.swift", kind: .update),
      FileChangeSummary(path: "Sources/CodexMenuBar/menu-bar-view-model.swift", kind: .update),
      FileChangeSummary(path: "Sources/CodexMenuBar/status-menu-controller.swift", kind: .update),
      FileChangeSummary(path: "Sources/CodexMenuBar/status-window-controller.swift", kind: .update),
      FileChangeSummary(
        path: "Sources/CodexMenuBar/settings-window-controller.swift", kind: .update),
      FileChangeSummary(path: "Sources/CodexMenuBar/turn-menu-row-view.swift", kind: .update),
      FileChangeSummary(path: "Sources/CodexMenuBar/turn-store.swift", kind: .update),
      FileChangeSummary(
        path: "Tests/CodexMenuBarTests/menu-bar-view-model-tests.swift", kind: .update),
      FileChangeSummary(
        path: "Tests/CodexMenuBarTests/turn-store-history-tests.swift", kind: .update),
      FileChangeSummary(
        path: "Tests/CodexMenuBarUITests/status-center-token-usage-ui-tests.swift",
        kind: .update),
    ] {
      turnStore.RecordFileChange(endpointId: endpointId, turnId: turnId, change: change)
    }
    turnStore.UpdatePlan(
      endpointId: endpointId,
      turnId: turnId,
      steps: [
        PlanStepInfo(description: "Audit current AppKit status item shell", status: .completed),
        PlanStepInfo(description: "Trace live token updates from codexd", status: .completed),
        PlanStepInfo(description: "Add current-turn token round browsing", status: .completed),
        PlanStepInfo(description: "Page long plan histories in runtime panels", status: .completed),
        PlanStepInfo(description: "Page active file and command histories", status: .completed),
        PlanStepInfo(description: "Stabilize popover sizing and active rows", status: .inProgress),
        PlanStepInfo(description: "Run UI loop on macOS 15 VM", status: .pending),
        PlanStepInfo(description: "Run UI loop on macOS 26 VM", status: .pending),
      ],
      explanation: "Fixture state for deterministic menu bar UI verification."
    )
    turnStore.UpdateGitInfo(
      endpointId: endpointId, gitInfo: GitInfo(branch: "main", sha: "fixture"))
    turnStore.UpdateTokenUsage(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      tokenUsageTotal: TokenUsageInfo(
        inputTokens: 24_800,
        cachedInputTokens: 10_200,
        outputTokens: 4_200,
        reasoningTokens: 1_600,
        totalTokens: 29_000,
        contextWindow: 128_000
      ),
      tokenUsageLast: TokenUsageInfo(
        inputTokens: 6_400,
        cachedInputTokens: 3_200,
        outputTokens: 1_100,
        reasoningTokens: 420,
        totalTokens: 7_500,
        contextWindow: 128_000
      ),
      observedAt: startedAt.addingTimeInterval(36)
    )
    turnStore.UpdateTokenUsage(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      tokenUsageTotal: TokenUsageInfo(
        inputTokens: 33_900,
        cachedInputTokens: 14_700,
        outputTokens: 6_000,
        reasoningTokens: 2_350,
        totalTokens: 39_900,
        contextWindow: 128_000
      ),
      tokenUsageLast: TokenUsageInfo(
        inputTokens: 9_100,
        cachedInputTokens: 4_500,
        outputTokens: 1_800,
        reasoningTokens: 750,
        totalTokens: 10_900,
        contextWindow: 128_000
      ),
      observedAt: startedAt.addingTimeInterval(64)
    )
    turnStore.UpdateTokenUsage(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      tokenUsageTotal: TokenUsageInfo(
        inputTokens: 42_000,
        cachedInputTokens: 18_000,
        outputTokens: 8_400,
        reasoningTokens: 3_200,
        totalTokens: 53_600,
        contextWindow: 128_000
      ),
      tokenUsageLast: TokenUsageInfo(
        inputTokens: 12_800,
        cachedInputTokens: 6_400,
        outputTokens: 2_100,
        reasoningTokens: 900,
        totalTokens: 15_800,
        contextWindow: 128_000
      ),
      observedAt: startedAt.addingTimeInterval(92)
    )

    // Codex can stream total-only context estimates between model-response token rounds.
    // The round history should not expose those estimates as browseable ghost entries.
    for index in 0..<60 {
      turnStore.UpdateTokenUsage(
        endpointId: endpointId,
        threadId: threadId,
        turnId: turnId,
        tokenUsageTotal: nil,
        tokenUsageLast: TokenUsageInfo(
          totalTokens: 54_000 + (index * 37),
          contextWindow: 128_000
        ),
        observedAt: startedAt.addingTimeInterval(93 + Double(index))
      )
    }

    // codexd emits runtimeUpsert snapshots before forwarded runtime notifications.
    // Replaying an active turn must not replay its round history into itself.
    for index in 0..<4 {
      turnStore.UpsertTurnStarted(
        endpointId: endpointId,
        threadId: threadId,
        turnId: turnId,
        at: startedAt.addingTimeInterval(160 + Double(index))
      )
    }
    model.SyncSectionDisclosureState()
    model.InvalidateView()
  }

  private func ApplyCompletedTurnHistoryUITestFixture() {
    let endpointId = "fixture-endpoint"
    let threadId = "fixture-thread"
    let reviewThreadId = "fixture-review-thread"
    let now = Date()
    let cwd = NSHomeDirectory().appending("/workspace/agentic-tools/CodexMenuBar")
    let completionPrompt = """
      Exercise completed-turn token usage history controls.
      Verify the regular completion prompt comes from the codexd completion payload.
      Line three must remain visible in expanded history.
      Line four should remain in the folded prompt.
      Line five should remain in the folded prompt.
      Line six should appear only after expanding the completed prompt.
      Line seven verifies the prompt can fold again.
      """
    let reviewPrompt = """
      Review the completed turn for regressions.
      Confirm the folded prompt starts with five lines.
      Confirm the prompt view can expand to the full text.
      Confirm copying the entire prompt remains available.
      Confirm line five remains visible before expansion.
      Confirm this sixth review line appears only after expansion.
      Confirm the prompt can be folded after expansion.
      """

    settingsModel.connectionState = .connected
    model.connectionState = .connected
    model.codexdDiagnostics = CodexdDiagnostics(
      resolvedSocketPath: "/tmp/codexd-fixture.sock",
      connectedAt: now,
      protocolVersion: 1,
      capabilities: ["eventReplay", "runtimeState"],
      lastEventSeq: 256
    )
    model.SetEndpointIds([endpointId])
    turnStore.UpdateRuntimeMetadata(endpointId: endpointId, cwd: cwd, sessionSource: "codex")

    var completedHistoryThreadTotal = TokenUsageInfo()
    for index in 0..<5 {
      let turnId = "completed-history-turn-\(index)"
      let usage = TokenUsageInfo(
        inputTokens: 4_000 + (index * 300),
        cachedInputTokens: 1_000 + (index * 120),
        outputTokens: 700 + (index * 80),
        reasoningTokens: 200 + (index * 30),
        totalTokens: 4_700 + (index * 380),
        contextWindow: 128_000
      )
      completedHistoryThreadTotal = completedHistoryThreadTotal.adding(usage)
      SeedCompletedUITestTurn(
        endpointId: endpointId,
        threadId: threadId,
        turnId: turnId,
        prompt: "Older completed turn \(index).",
        startedAt: now.addingTimeInterval(-7_200 + Double(index * 480)),
        endedAt: now.addingTimeInterval(-7_080 + Double(index * 480)),
        tokenUsage: usage,
        threadUsageTotal: completedHistoryThreadTotal,
        command: "./scripts/verify_fast.sh --older \(index)",
        changedPath: "Sources/CodexMenuBar/turn-store.swift"
      )
    }

    SeedCompletedUITestTurn(
      endpointId: endpointId,
      threadId: reviewThreadId,
      turnId: "completed-review-turn",
      prompt: reviewPrompt,
      startedAt: now.addingTimeInterval(-1_500),
      endedAt: now.addingTimeInterval(-1_320),
      tokenUsage: TokenUsageInfo(
        inputTokens: 8_800,
        cachedInputTokens: 3_100,
        outputTokens: 1_300,
        reasoningTokens: 420,
        totalTokens: 10_100,
        contextWindow: 128_000
      ),
      command: "./scripts/verify_fast.sh --review",
      changedPath: "Sources/CodexMenuBar/turn-menu-row-view.swift"
    )
    turnStore.UpdateTurnMetadata(
      endpointId: endpointId,
      threadId: reviewThreadId,
      turnId: "completed-review-turn",
      turn: [
        "promptPreview": reviewPrompt,
        "scope": "delegate",
        "taskKind": "post_turn_completion_review",
        "sessionSource": "subagent_review",
        "subAgentSource": "review",
        "parentTurnId": "completed-history-turn-4",
        "threadName": "Post-turn review",
        "model": "gpt-5-review",
        "modelProvider": "OpenAI",
        "thinkingLevel": "high",
      ],
      at: now.addingTimeInterval(-1_300)
    )

    let latestStartedAt = now.addingTimeInterval(-900)
    let latestTurnId = "completed-history-turn-6"
    let latestTurnKey = "\(threadId):\(latestTurnId)"
    HandleNotification(
      method: "turn/started",
      params: [
        "endpointId": endpointId,
        "threadId": threadId,
        "fromSnapshot": true,
        "turn": [
          "id": latestTurnId,
          "key": latestTurnKey,
          "status": "inProgress",
          "tokenUsageBaseline": TokenUsagePayload(total: completedHistoryThreadTotal),
        ],
      ])
    turnStore.RecordProgress(
      endpointId: endpointId,
      threadId: threadId,
      turnId: latestTurnId,
      turnKey: latestTurnKey,
      category: .reasoning,
      state: .started,
      label: "Reviewing implementation path",
      at: latestStartedAt.addingTimeInterval(12)
    )
    turnStore.RecordProgress(
      endpointId: endpointId,
      threadId: threadId,
      turnId: latestTurnId,
      turnKey: latestTurnKey,
      category: .tool,
      state: .started,
      label: "Running verification",
      at: latestStartedAt.addingTimeInterval(54)
    )
    turnStore.RecordCommand(
      endpointId: endpointId,
      turnId: latestTurnId,
      turnKey: latestTurnKey,
      threadId: threadId,
      command: CommandSummary(
        command: "./scripts/verify_fast.sh",
        status: .completed,
        exitCode: 0,
        durationMs: 180_000
      )
    )
    turnStore.RecordFileChange(
      endpointId: endpointId,
      turnId: latestTurnId,
      turnKey: latestTurnKey,
      threadId: threadId,
      change: FileChangeSummary(
        path: "Sources/CodexMenuBar/turn-menu-row-view.swift", kind: .update)
    )
    let latestSamples = [
      TokenUsageInfo(
        inputTokens: 7_200,
        cachedInputTokens: 2_600,
        outputTokens: 900,
        reasoningTokens: 240,
        totalTokens: 8_100,
        contextWindow: 128_000
      ),
      TokenUsageInfo(
        inputTokens: 11_300,
        cachedInputTokens: 4_100,
        outputTokens: 1_640,
        reasoningTokens: 520,
        totalTokens: 12_940,
        contextWindow: 128_000
      ),
      TokenUsageInfo(
        inputTokens: 15_600,
        cachedInputTokens: 5_900,
        outputTokens: 2_400,
        reasoningTokens: 870,
        totalTokens: 18_000,
        contextWindow: 128_000
      ),
    ]
    let latestCumulativeTotals = [
      completedHistoryThreadTotal.adding(
        TokenUsageInfo(
          inputTokens: 7_200,
          cachedInputTokens: 2_600,
          outputTokens: 900,
          reasoningTokens: 240,
          totalTokens: 8_100,
          contextWindow: 128_000
        )),
      completedHistoryThreadTotal.adding(
        TokenUsageInfo(
          inputTokens: 18_500,
          cachedInputTokens: 6_700,
          outputTokens: 2_540,
          reasoningTokens: 760,
          totalTokens: 21_040,
          contextWindow: 128_000
        )),
      completedHistoryThreadTotal.adding(
        TokenUsageInfo(
          inputTokens: 70_400,
          cachedInputTokens: 23_000,
          outputTokens: 12_100,
          reasoningTokens: 4_200,
          totalTokens: 82_500,
          contextWindow: 128_000
        )),
    ]
    for (index, sample) in latestSamples.enumerated() {
      if index == 2 {
        HandleNotification(
          method: "item/started",
          params: [
            "endpointId": endpointId,
            "threadId": threadId,
            "turnId": latestTurnId,
            "turnKey": latestTurnKey,
            "item": [
              "type": "contextCompaction"
            ],
          ]
        )
        HandleNotification(
          method: "item/completed",
          params: [
            "endpointId": endpointId,
            "threadId": threadId,
            "turnId": latestTurnId,
            "turnKey": latestTurnKey,
            "item": [
              "type": "contextCompaction"
            ],
          ]
        )
      }
      turnStore.UpdateTokenUsage(
        endpointId: endpointId,
        threadId: threadId,
        turnId: latestTurnId,
        turnKey: latestTurnKey,
        tokenUsageTotal: latestCumulativeTotals[index],
        tokenUsageLast: sample,
        observedAt: latestStartedAt.addingTimeInterval(60 + Double(index * 12))
      )
    }
    HandleNotification(
      method: "turn/completed",
      params: [
        "endpointId": endpointId,
        "threadId": threadId,
        "fromSnapshot": true,
        "turn": [
          "id": latestTurnId,
          "key": latestTurnKey,
          "status": "completed",
        ],
      ]
    )
    HandleNotification(
      method: "turn/completed",
      params: [
        "endpointId": endpointId,
        "threadId": threadId,
        "turn": [
          "id": latestTurnId,
          "key": latestTurnKey,
          "status": "completed",
          "promptPreview": completionPrompt,
          "model": "gpt-5-codex",
          "modelProvider": "OpenAI",
          "thinkingLevel": "medium",
        ],
      ]
    )
    turnStore.Tick(now: Date().addingTimeInterval(11))
    model.SyncSectionDisclosureState()
    model.InvalidateView()
  }

  private func ApplyDelegateUITestFixture() {
    let endpointId = "fixture-endpoint"
    let mainThreadId = "fixture-main-thread"
    let delegateThreadId = "fixture-delegate-thread"
    let delegateTurnId = "post-turn-review-0"
    let delegateTurnKey = "\(delegateThreadId):\(delegateTurnId)"
    let now = Date()
    let startedAt = now.addingTimeInterval(-74)
    let cwd = NSHomeDirectory().appending("/workspace/agentic-tools/CodexMenuBar")

    settingsModel.connectionState = .connected
    model.connectionState = .connected
    model.codexdDiagnostics = CodexdDiagnostics(
      resolvedSocketPath: "/tmp/codexd-fixture.sock",
      connectedAt: now,
      protocolVersion: 1,
      capabilities: ["eventReplay", "runtimeState"],
      lastEventSeq: 192
    )
    model.SetEndpointIds([endpointId])
    turnStore.UpdateRuntimeMetadata(endpointId: endpointId, cwd: cwd, sessionSource: "codex")
    SeedCompletedUITestTurn(
      endpointId: endpointId,
      threadId: mainThreadId,
      turnId: "regular-turn",
      prompt: "Implement the status center runtime history.",
      startedAt: now.addingTimeInterval(-1_200),
      endedAt: now.addingTimeInterval(-1_020),
      tokenUsage: TokenUsageInfo(
        inputTokens: 18_200,
        cachedInputTokens: 7_100,
        outputTokens: 2_650,
        reasoningTokens: 1_100,
        totalTokens: 20_850,
        contextWindow: 128_000
      ),
      command: "./scripts/verify_fast.sh",
      changedPath: "Sources/CodexMenuBar/turn-store.swift"
    )

    turnStore.UpsertTurnStarted(
      endpointId: endpointId,
      threadId: delegateThreadId,
      turnId: delegateTurnId,
      turnKey: delegateTurnKey,
      at: startedAt
    )
    turnStore.UpdateTurnMetadata(
      endpointId: endpointId,
      threadId: delegateThreadId,
      turnId: delegateTurnId,
      turnKey: delegateTurnKey,
      turn: [
        "scope": "delegate",
        "taskKind": "post_turn_completion_review",
        "sessionSource": "subagent_review",
        "subAgentSource": "review",
        "parentTurnId": "regular-turn",
        "threadName": "Post-turn review",
        "model": "gpt-5-review",
        "modelProvider": "OpenAI",
        "thinkingLevel": "high",
        "cwd": cwd,
      ],
      at: startedAt
    )
    turnStore.RecordProgress(
      endpointId: endpointId,
      threadId: delegateThreadId,
      turnId: delegateTurnId,
      turnKey: delegateTurnKey,
      category: .reasoning,
      state: .started,
      label: "Reviewing completed turn",
      at: startedAt.addingTimeInterval(8)
    )
    turnStore.UpdateTokenUsage(
      endpointId: endpointId,
      threadId: delegateThreadId,
      turnId: delegateTurnId,
      turnKey: delegateTurnKey,
      tokenUsageTotal: TokenUsageInfo(
        inputTokens: 2_100,
        cachedInputTokens: 900,
        outputTokens: 420,
        reasoningTokens: 120,
        totalTokens: 2_520,
        contextWindow: 128_000
      ),
      tokenUsageLast: TokenUsageInfo(
        inputTokens: 2_100,
        cachedInputTokens: 900,
        outputTokens: 420,
        reasoningTokens: 120,
        totalTokens: 2_520,
        contextWindow: 128_000
      ),
      observedAt: startedAt.addingTimeInterval(18)
    )
    turnStore.UpdateTokenUsage(
      endpointId: endpointId,
      threadId: delegateThreadId,
      turnId: delegateTurnId,
      turnKey: delegateTurnKey,
      tokenUsageTotal: TokenUsageInfo(
        inputTokens: 5_500,
        cachedInputTokens: 2_200,
        outputTokens: 940,
        reasoningTokens: 300,
        totalTokens: 6_440,
        contextWindow: 128_000
      ),
      tokenUsageLast: TokenUsageInfo(
        inputTokens: 3_400,
        cachedInputTokens: 1_300,
        outputTokens: 520,
        reasoningTokens: 180,
        totalTokens: 3_920,
        contextWindow: 128_000
      ),
      observedAt: startedAt.addingTimeInterval(46)
    )
    model.SyncSectionDisclosureState()
    model.InvalidateView()
  }

  private func ApplyPostTurnReviewLifecycleUITestFixture() {
    let endpointId = "fixture-endpoint"
    let mainThreadId = "fixture-main-thread"
    let delegateThreadId = "fixture-delegate-thread"
    let delegateTurnId = "0"
    let delegateTurnKey = "\(delegateThreadId):\(delegateTurnId)"
    let now = Date()
    let cwd = NSHomeDirectory().appending("/workspace/agentic-tools/CodexMenuBar")

    settingsModel.connectionState = .connected
    model.connectionState = .connected
    model.codexdDiagnostics = CodexdDiagnostics(
      resolvedSocketPath: "/tmp/codexd-fixture.sock",
      connectedAt: now,
      protocolVersion: 1,
      capabilities: ["eventReplay", "runtimeState"],
      lastEventSeq: 224
    )
    model.SetEndpointIds([endpointId])
    turnStore.UpdateRuntimeMetadata(endpointId: endpointId, cwd: cwd, sessionSource: "codex")
    SeedCompletedUITestTurn(
      endpointId: endpointId,
      threadId: mainThreadId,
      turnId: "regular-turn",
      prompt: "Implement the status center runtime history.",
      startedAt: now.addingTimeInterval(-1_200),
      endedAt: now.addingTimeInterval(-1_020),
      tokenUsage: TokenUsageInfo(
        inputTokens: 18_200,
        cachedInputTokens: 7_100,
        outputTokens: 2_650,
        reasoningTokens: 1_100,
        totalTokens: 20_850,
        contextWindow: 128_000
      ),
      command: "./scripts/verify_fast.sh",
      changedPath: "Sources/CodexMenuBar/turn-store.swift"
    )

    HandleNotification(
      method: "turn/started",
      params: [
        "endpointId": endpointId,
        "threadId": delegateThreadId,
        "turn": [
          "id": delegateTurnId,
          "key": delegateTurnKey,
          "status": "inProgress",
          "scope": "delegate",
          "taskKind": "post_turn_completion_review",
          "sessionSource": "subagent_review",
          "subAgentSource": "review",
          "parentTurnId": "regular-turn",
          "threadName": "Post-turn review",
          "promptPreview": "Review target post-turn review prompt.",
          "model": "gpt-5-review",
          "modelProvider": "OpenAI",
          "thinkingLevel": "high",
          "cwd": cwd,
        ],
      ]
    )
    HandleNotification(
      method: "turn/progressTrace",
      params: [
        "endpointId": endpointId,
        "threadId": delegateThreadId,
        "turnId": delegateTurnId,
        "turnKey": delegateTurnKey,
        "category": "reasoning",
        "state": "started",
        "label": "Reviewing completed turn",
      ]
    )
    model.SyncSectionDisclosureState()
    model.InvalidateView()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
      guard let self else {
        return
      }
      let tokenUsage: [String: Any] = [
        "modelContextWindow": 128_000,
        "total": [
          "inputTokens": 5_500,
          "cachedInputTokens": 2_200,
          "outputTokens": 940,
          "reasoningOutputTokens": 300,
          "totalTokens": 6_440,
        ],
        "last": [
          "inputTokens": 3_400,
          "cachedInputTokens": 1_300,
          "outputTokens": 520,
          "reasoningOutputTokens": 180,
          "totalTokens": 3_920,
        ],
      ]
      self.HandleNotification(
        method: "turn/contextUpdated",
        params: [
          "endpointId": endpointId,
          "threadId": delegateThreadId,
          "turnId": delegateTurnId,
          "turnKey": delegateTurnKey,
          "scope": "delegate",
          "taskKind": "post_turn_completion_review",
          "sessionSource": "subagent_review",
          "subAgentSource": "review",
          "parentTurnId": "regular-turn",
          "threadName": "Post-turn review",
          "model": "gpt-5-review",
          "modelProvider": "OpenAI",
          "thinkingLevel": "high",
          "cwd": cwd,
        ]
      )
      self.HandleNotification(
        method: "thread/tokenUsage/updated",
        params: [
          "endpointId": endpointId,
          "threadId": delegateThreadId,
          "turnKey": delegateTurnKey,
          "tokenUsage": tokenUsage,
        ]
      )
      self.model.SyncSectionDisclosureState()
      self.model.InvalidateView()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 24.0) { [weak self] in
      guard let self else {
        return
      }
      let completedAt = Date()
      self.HandleNotification(
        method: "thread/snapshotSummary",
        params: [
          "endpointId": endpointId,
          "activeTurnKeys": [],
        ]
      )
      self.HandleNotification(
        method: "turn/completed",
        params: [
          "endpointId": endpointId,
          "threadId": delegateThreadId,
          "turn": [
            "id": delegateTurnId,
            "key": delegateTurnKey,
            "status": "completed",
          ],
        ]
      )
      self.turnStore.Tick(now: completedAt.addingTimeInterval(12))
      self.HandleNotification(
        method: "turn/contextUpdated",
        params: [
          "endpointId": endpointId,
          "threadId": mainThreadId,
          "turnId": "regular-turn",
          "turnKey": "\(mainThreadId):regular-turn",
          "scope": "primary",
          "taskKind": "user",
          "sessionSource": "codex",
          "model": "gpt-5-codex",
          "cwd": cwd,
        ]
      )
      self.HandleNotification(
        method: "turn/completed",
        params: [
          "endpointId": endpointId,
          "turn": [
            "id": delegateTurnId,
            "key": "stale-\(delegateTurnKey)",
            "status": "completed",
            "promptPreview": "Stale duplicate review prompt must not replace archived prompt.",
            "threadName": "Stale post-turn review",
          ],
        ]
      )
      self.model.SyncSectionDisclosureState()
      self.model.InvalidateView()
    }
  }

  private func TokenUsagePayload(total: TokenUsageInfo, last: TokenUsageInfo? = nil) -> [String:
    Any]
  {
    var payload: [String: Any] = [
      "total": TokenUsageBreakdownPayload(total)
    ]
    if let contextWindow = total.contextWindow ?? last?.contextWindow {
      payload["modelContextWindow"] = contextWindow
    }
    if let last {
      payload["last"] = TokenUsageBreakdownPayload(last)
    }
    return payload
  }

  private func TokenUsageBreakdownPayload(_ usage: TokenUsageInfo) -> [String: Any] {
    [
      "inputTokens": usage.inputTokens,
      "cachedInputTokens": usage.cachedInputTokens,
      "outputTokens": usage.outputTokens,
      "reasoningOutputTokens": usage.reasoningTokens,
      "totalTokens": usage.totalTokens,
    ]
  }

  private func SeedCompletedUITestTurn(
    endpointId: String,
    threadId: String,
    turnId: String,
    prompt: String,
    startedAt: Date,
    endedAt: Date,
    tokenUsage: TokenUsageInfo,
    tokenUsageSamples: [TokenUsageInfo]? = nil,
    threadUsageTotal: TokenUsageInfo? = nil,
    command: String,
    changedPath: String
  ) {
    turnStore.UpsertTurnStarted(
      endpointId: endpointId, threadId: threadId, turnId: turnId, at: startedAt)
    turnStore.UpdateTurnMetadata(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      turn: [
        "model": "gpt-5-codex",
        "modelProvider": "OpenAI",
        "thinkingLevel": "medium",
        "items": [
          [
            "type": "user_message",
            "content": prompt,
          ]
        ],
      ],
      at: startedAt
    )
    turnStore.RecordProgress(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      category: .reasoning,
      state: .started,
      label: "Reviewing implementation path",
      at: startedAt.addingTimeInterval(12)
    )
    turnStore.RecordProgress(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      category: .tool,
      state: .started,
      label: "Running verification",
      at: startedAt.addingTimeInterval(54)
    )
    turnStore.RecordCommand(
      endpointId: endpointId,
      turnId: turnId,
      command: CommandSummary(
        command: command,
        status: .completed,
        exitCode: 0,
        durationMs: Int(max(1.0, endedAt.timeIntervalSince(startedAt)) * 1000)
      )
    )
    turnStore.RecordFileChange(
      endpointId: endpointId,
      turnId: turnId,
      change: FileChangeSummary(path: changedPath, kind: .update)
    )
    let samples = tokenUsageSamples ?? [tokenUsage]
    for (index, sample) in samples.enumerated() {
      turnStore.UpdateTokenUsage(
        endpointId: endpointId,
        threadId: threadId,
        turnId: turnId,
        tokenUsageTotal: index == samples.count - 1 ? threadUsageTotal ?? tokenUsage : nil,
        tokenUsageLast: sample,
        observedAt: startedAt.addingTimeInterval(60 + Double(index * 12))
      )
    }
    turnStore.MarkTurnCompleted(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      status: .completed,
      at: endedAt
    )
  }

  private func ArgumentValue(after option: String) -> String? {
    let arguments = ProcessInfo.processInfo.arguments
    guard let optionIndex = arguments.firstIndex(of: option),
      arguments.indices.contains(optionIndex + 1)
    else {
      return nil
    }
    return arguments[optionIndex + 1]
  }

  private func StartTimer() {
    guard timer == nil else {
      return
    }
    timer = Timer.scheduledTimer(
      timeInterval: 1.0,
      target: self,
      selector: #selector(OnTimerTick),
      userInfo: nil,
      repeats: true
    )
  }

  private func StopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func RefreshLiveSurfaceTimer(tickImmediately: Bool) {
    guard isLiveSurfaceVisible else {
      StopTimer()
      return
    }

    StartTimer()
    if tickImmediately {
      OnTimerTick()
    }
  }

  @objc
  private func OnTimerTick() {
    let now = Date()
    turnStore.Tick(now: now)
    model.now = now
    model.SyncSectionDisclosureState()
    model.InvalidateView()
  }

  private func HandleNotification(method: String, params: [String: Any]) {
    let now = Date()
    switch method {
    case "runtime/metadata":
      HandleRuntimeMetadata(params: params)
    case "thread/snapshot":
      HandleThreadSnapshot(params: params)
    case "thread/snapshotSummary":
      HandleThreadSnapshotSummary(params: params)
    case "thread/started":
      HandleThreadStarted(params: params)
    case "thread/tokenUsage/updated":
      HandleTokenUsageUpdated(params: params)
    case "turn/started":
      HandleTurnStarted(params: params)
    case "turn/completed":
      HandleTurnCompleted(params: params)
    case "turn/contextUpdated", "turn/stateUpdated":
      HandleTurnContextUpdated(params: params)
    case "turn/progressTrace":
      HandleTurnProgressTrace(params: params)
    case "turn/plan/updated":
      HandleTurnPlanUpdated(params: params)
    case "item/started":
      HandleItemLifecycle(params: params, state: .started)
    case "item/completed":
      HandleItemLifecycle(params: params, state: .completed)
    case "error":
      HandleError(params: params)
    case "account/rateLimits/updated":
      HandleRateLimitsUpdated(params: params)
    default:
      break
    }
    turnStore.Tick(now: now)
    if isLiveSurfaceVisible {
      model.SyncSectionDisclosureState()
    }

    let isHighFrequencyUpdate = method == "turn/progressTrace"
    let shouldInvalidate =
      method == "turn/started"
      || method == "turn/completed"
      || method == "thread/snapshotSummary"
      || (isLiveSurfaceVisible && !isHighFrequencyUpdate)
    if shouldInvalidate {
      model.InvalidateView()
    }
  }

  private func HandleRuntimeMetadata(params: [String: Any]) {
    let endpointId = params["endpointId"] as? String ?? "unknown"
    let cwd = params["cwd"] as? String
    let sessionSource = params["sessionSource"] as? String
    turnStore.UpdateRuntimeMetadata(endpointId: endpointId, cwd: cwd, sessionSource: sessionSource)
  }

  private func HandleTurnStarted(params: [String: Any]) {
    let endpointId = params["endpointId"] as? String ?? "unknown"
    guard
      let turn = params["turn"] as? [String: Any],
      let turnId = turn["id"] as? String
    else {
      return
    }
    let turnKey = ResolveTurnKey(params: params, turn: turn)
    let threadId = ResolveThreadId(
      params: params, endpointId: endpointId, turnId: turnId, turnKey: turnKey)
    let tokenUsageCumulativeBaseline = ParseTokenUsageCumulativeBaseline(
      turn["tokenUsageBaseline"] ?? turn["token_usage_baseline"])
    turnStore.ClearError(endpointId: endpointId)
    turnStore.UpsertTurnStarted(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      turnKey: turnKey,
      tokenUsageCumulativeBaseline: tokenUsageCumulativeBaseline,
      at: Date())
    turnStore.UpdateTurnMetadata(
      endpointId: endpointId, threadId: threadId, turnId: turnId, turnKey: turnKey, turn: turn,
      at: Date())
    ApplyTokenUsageIfPresent(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      turnKey: turnKey,
      payload: turn["tokenUsage"]
    )
  }

  private func HandleTurnCompleted(params: [String: Any]) {
    let endpointId = params["endpointId"] as? String ?? "unknown"
    guard
      let turn = params["turn"] as? [String: Any],
      let turnId = turn["id"] as? String
    else {
      return
    }
    let turnKey = ResolveTurnKey(params: params, turn: turn)
    let hasExplicitThreadId =
      (StringValue(params["threadId"]) ?? StringValue(params["thread_id"])) != nil
    let threadId = ResolveCompletionThreadId(
      params: params, endpointId: endpointId, turnId: turnId, turnKey: turnKey)
    let status = CompletedStatusFromServerValue(turn["status"] as? String)
    let fromSnapshot = params["fromSnapshot"] as? Bool ?? false
    if fromSnapshot {
      turnStore.MarkTurnCompletedIfPresent(
        endpointId: endpointId,
        threadId: threadId,
        turnId: turnId,
        turnKey: turnKey,
        status: status,
        at: Date()
      )
      turnStore.UpdateTurnMetadata(
        endpointId: endpointId, threadId: threadId, turnId: turnId, turnKey: turnKey, turn: turn,
        at: Date())
      ApplyTokenUsageIfPresent(
        endpointId: endpointId,
        threadId: threadId,
        turnId: turnId,
        turnKey: turnKey,
        payload: turn["tokenUsage"]
      )
      return
    }
    let archived = turnStore.MarkTurnCompleted(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      turnKey: turnKey,
      status: status,
      at: Date()
    )
    let canPatchArchivedCompletion = archived || hasExplicitThreadId
    if canPatchArchivedCompletion {
      turnStore.UpdateTurnMetadata(
        endpointId: endpointId, threadId: threadId, turnId: turnId, turnKey: turnKey, turn: turn,
        at: Date())
      ApplyTokenUsageIfPresent(
        endpointId: endpointId,
        threadId: threadId,
        turnId: turnId,
        turnKey: turnKey,
        payload: turn["tokenUsage"]
      )
    }
  }

  private func HandleTurnContextUpdated(params: [String: Any]) {
    let endpointId = params["endpointId"] as? String ?? "unknown"
    let turnKey = ResolveTurnKey(params: params)
    let paramsThreadId = StringValue(params["threadId"]) ?? StringValue(params["thread_id"])
    guard
      let turnId = StringValue(params["turnId"]) ?? StringValue(params["turn_id"])
        ?? turnStore.ResolveKnownTurnId(
          endpointId: endpointId,
          turnKey: turnKey,
          threadId: paramsThreadId
        )
    else {
      return
    }
    let threadId = ResolveThreadId(
      params: params, endpointId: endpointId, turnId: turnId, turnKey: turnKey)

    turnStore.UpdateTurnMetadata(
      endpointId: endpointId, threadId: threadId, turnId: turnId, turnKey: turnKey, turn: params,
      at: Date())
    ApplyTokenUsageIfPresent(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      turnKey: turnKey,
      payload: params["tokenUsage"]
    )
  }

  private func HandleThreadSnapshot(params: [String: Any]) {
    guard
      let endpointId = params["endpointId"] as? String,
      let thread = params["thread"] as? [String: Any]
    else {
      return
    }
    turnStore.ApplyThreadSnapshot(endpointId: endpointId, thread: thread, at: Date())
  }

  private func HandleThreadSnapshotSummary(params: [String: Any]) {
    guard let endpointId = params["endpointId"] as? String else {
      return
    }

    let activeTurnKeys = params["activeTurnKeys"] as? [String] ?? []
    turnStore.ReconcileSnapshotActiveTurns(
      endpointId: endpointId,
      activeTurnKeys: activeTurnKeys,
      at: Date()
    )
  }

  private func HandleTurnProgressTrace(params: [String: Any]) {
    let endpointId = params["endpointId"] as? String ?? "unknown"

    guard
      let turnId = StringValue(params["turnId"]) ?? StringValue(params["turn_id"]),
      let categoryRaw = params["category"] as? String,
      let stateRaw = params["state"] as? String,
      let category = ProgressCategory(rawValue: categoryRaw),
      let state = ProgressState(rawValue: stateRaw)
    else {
      return
    }
    let turnKey = ResolveTurnKey(params: params)
    let threadId = ResolveThreadId(
      params: params, endpointId: endpointId, turnId: turnId, turnKey: turnKey)

    let label = params["label"] as? String
    turnStore.RecordProgress(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      turnKey: turnKey,
      category: category,
      state: state,
      label: label,
      at: Date()
    )
  }

  private func HandleItemLifecycle(params: [String: Any], state: ProgressState) {
    let endpointId = params["endpointId"] as? String ?? "unknown"

    guard
      let turnId = StringValue(params["turnId"]) ?? StringValue(params["turn_id"]),
      let item = params["item"] as? [String: Any],
      let itemType = item["type"] as? String
    else {
      return
    }
    let turnKey = ResolveTurnKey(params: params)
    let threadId = ResolveThreadId(
      params: params, endpointId: endpointId, turnId: turnId, turnKey: turnKey)

    turnStore.ApplyItemMetadata(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      turnKey: turnKey,
      item: item,
      at: Date()
    )

    ExtractItemDetails(
      endpointId: endpointId, threadId: threadId, turnId: turnId, turnKey: turnKey, item: item,
      itemType: itemType)

    guard let category = CategoryFromItemType(itemType) else {
      return
    }

    turnStore.RecordProgress(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      turnKey: turnKey,
      category: category,
      state: state,
      label: nil,
      at: Date()
    )
  }

  private func ExtractItemDetails(
    endpointId: String,
    threadId: String?,
    turnId: String,
    turnKey: String?,
    item: [String: Any],
    itemType: String
  ) {
    switch itemType {
    case "commandExecution":
      let command = StringValue(item["command"]) ?? "unknown"
      let statusStr = (item["status"] as? String) ?? "inProgress"
      let exitCode = item["exitCode"] as? Int ?? item["exit_code"] as? Int
      let durationMs = item["durationMs"] as? Int ?? item["duration_ms"] as? Int
      turnStore.RecordCommand(
        endpointId: endpointId,
        turnId: turnId,
        turnKey: turnKey,
        threadId: threadId,
        command: CommandSummary(
          command: command,
          status: CommandExecutionState(serverValue: statusStr),
          exitCode: exitCode,
          durationMs: durationMs
        )
      )
    case "fileChange":
      guard let changes = item["changes"] as? [[String: Any]] else { return }
      for change in changes {
        guard let path = StringValue(change["path"]) else { continue }
        let kindStr: String
        if let kindDict = change["kind"] as? [String: Any], let type = kindDict["type"] as? String {
          kindStr = type
        } else if let kind = change["kind"] as? String {
          kindStr = kind
        } else {
          kindStr = "Update"
        }
        turnStore.RecordFileChange(
          endpointId: endpointId,
          turnId: turnId,
          turnKey: turnKey,
          threadId: threadId,
          change: FileChangeSummary(path: path, kind: FileChangeKind(serverValue: kindStr))
        )
      }
    default:
      break
    }
  }

  private func HandleThreadStarted(params: [String: Any]) {
    guard let endpointId = params["endpointId"] as? String else { return }
    guard let thread = params["thread"] as? [String: Any] else { return }

    if let gitInfoDict = thread["gitInfo"] as? [String: Any] {
      let branch = StringValue(gitInfoDict["branch"])
      let sha = StringValue(gitInfoDict["sha"])
      if branch != nil || sha != nil {
        turnStore.UpdateGitInfo(
          endpointId: endpointId, gitInfo: GitInfo(branch: branch, sha: sha))
      }
    }

    if let source = StringValue(thread["source"]) {
      turnStore.UpdateSessionSource(endpointId: endpointId, source: source)
    }

    turnStore.ApplyThreadSnapshot(endpointId: endpointId, thread: thread, at: Date())
  }

  private func HandleTokenUsageUpdated(params: [String: Any]) {
    guard let endpointId = params["endpointId"] as? String else { return }
    guard let usage = params["tokenUsage"] as? [String: Any] else { return }
    let threadId = StringValue(params["threadId"]) ?? StringValue(params["thread_id"])
    let turnId = StringValue(params["turnId"]) ?? StringValue(params["turn_id"])
    let turnKey = ResolveTurnKey(params: params)

    let parsedUsage = ParseThreadTokenUsage(usage)

    turnStore.UpdateTokenUsage(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      turnKey: turnKey,
      tokenUsageTotal: parsedUsage.total,
      tokenUsageLast: parsedUsage.last
    )
  }

  private func ApplyTokenUsageIfPresent(
    endpointId: String,
    threadId: String?,
    turnId: String,
    turnKey: String?,
    payload: Any?
  ) {
    guard let usage = payload as? [String: Any] else {
      return
    }
    let parsedUsage = ParseThreadTokenUsage(usage)
    turnStore.UpdateTokenUsage(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      turnKey: turnKey,
      tokenUsageTotal: parsedUsage.total,
      tokenUsageLast: parsedUsage.last
    )
  }

  private func ParseTokenUsageCumulativeBaseline(_ payload: Any?) -> TokenUsageInfo? {
    guard let usage = payload as? [String: Any] else {
      return nil
    }
    return ParseThreadTokenUsage(usage).total
  }

  private func ParseThreadTokenUsage(_ usage: [String: Any]) -> (
    total: TokenUsageInfo?, last: TokenUsageInfo?
  ) {
    var totalInfo: TokenUsageInfo?
    let contextWindow =
      usage["modelContextWindow"] as? Int ?? usage["model_context_window"] as? Int
    if let total = usage["total"] as? [String: Any] {
      totalInfo = ParseTokenUsageBreakdown(total)
      totalInfo?.contextWindow = contextWindow
    }

    var lastInfo: TokenUsageInfo?
    if let last = usage["last"] as? [String: Any] {
      lastInfo = ParseTokenUsageBreakdown(last)
      lastInfo?.contextWindow = contextWindow
    }

    return (totalInfo, lastInfo)
  }

  private func ParseTokenUsageBreakdown(_ dict: [String: Any]) -> TokenUsageInfo {
    var info = TokenUsageInfo()
    info.totalTokens = dict["totalTokens"] as? Int ?? dict["total_tokens"] as? Int ?? 0
    info.inputTokens = dict["inputTokens"] as? Int ?? dict["input_tokens"] as? Int ?? 0
    info.cachedInputTokens =
      dict["cachedInputTokens"] as? Int ?? dict["cached_input_tokens"] as? Int ?? 0
    info.outputTokens = dict["outputTokens"] as? Int ?? dict["output_tokens"] as? Int ?? 0
    info.reasoningTokens =
      dict["reasoningOutputTokens"] as? Int ?? dict["reasoning_output_tokens"] as? Int ?? 0
    return info
  }

  private func HandleTurnPlanUpdated(params: [String: Any]) {
    let endpointId = params["endpointId"] as? String ?? "unknown"
    guard let turnId = StringValue(params["turnId"]) ?? StringValue(params["turn_id"]) else {
      return
    }

    let explanation = StringValue(params["explanation"])
    let steps = ParsePlanSteps(params["plan"])
    let turnKey = ResolveTurnKey(params: params)
    let threadId = ResolveThreadId(
      params: params, endpointId: endpointId, turnId: turnId, turnKey: turnKey)

    turnStore.UpdatePlan(
      endpointId: endpointId,
      turnId: turnId,
      turnKey: turnKey,
      threadId: threadId,
      steps: steps,
      explanation: explanation
    )
  }

  private func HandleError(params: [String: Any]) {
    let endpointId = params["endpointId"] as? String ?? "unknown"

    guard let errorDict = params["error"] as? [String: Any] else { return }
    let message = StringValue(errorDict["message"]) ?? "Unknown error"
    let details =
      StringValue(errorDict["additionalDetails"])
      ?? StringValue(errorDict["additional_details"])
    let willRetry = params["willRetry"] as? Bool ?? params["will_retry"] as? Bool ?? false

    turnStore.RecordError(
      endpointId: endpointId,
      error: ErrorInfo(message: message, details: details, willRetry: willRetry, occurredAt: Date())
    )
  }

  private func HandleRateLimitsUpdated(params: [String: Any]) {
    guard let rateLimitsDict = params["rateLimits"] as? [String: Any] else { return }

    var info = RateLimitInfo()
    info.remaining = rateLimitsDict["remaining"] as? Int
    info.limit = rateLimitsDict["limit"] as? Int

    if let resetsAtRaw = rateLimitsDict["resetsAt"] as? Int
      ?? rateLimitsDict["resets_at"] as? Int
    {
      info.resetsAt = Date(timeIntervalSince1970: TimeInterval(resetsAtRaw))
    }

    turnStore.UpdateRateLimits(rateLimits: info)
  }

  private func CategoryFromItemType(_ itemType: String) -> ProgressCategory? {
    switch itemType {
    case "commandExecution", "mcpToolCall", "collabToolCall", "webSearch", "imageView":
      return .tool
    case "fileChange":
      return .edit
    case "reasoning":
      return .reasoning
    case "agentMessage":
      return .gen
    case "contextCompaction":
      return .waiting
    default:
      return nil
    }
  }

  private func CompletedStatusFromServerValue(_ serverValue: String?) -> TurnExecutionStatus {
    guard let serverValue else {
      return .completed
    }
    let parsed = TurnExecutionStatus(serverValue: serverValue)
    if parsed == .inProgress {
      return .completed
    }
    return parsed
  }

  private func ResolveThreadId(
    params: [String: Any],
    endpointId: String,
    turnId: String,
    turnKey: String? = nil
  ) -> String? {
    if let threadId = StringValue(params["threadId"]) ?? StringValue(params["thread_id"]) {
      return threadId
    }

    return turnStore.ResolveThreadId(endpointId: endpointId, turnId: turnId, turnKey: turnKey)
  }

  private func ResolveCompletionThreadId(
    params: [String: Any],
    endpointId: String,
    turnId: String,
    turnKey: String? = nil
  ) -> String? {
    if let threadId = StringValue(params["threadId"]) ?? StringValue(params["thread_id"]) {
      return threadId
    }

    return turnStore.ResolveActiveThreadId(endpointId: endpointId, turnId: turnId, turnKey: turnKey)
  }

  private func ResolveTurnKey(params: [String: Any], turn: [String: Any]? = nil) -> String? {
    if let turn,
      let turnKey = StringValue(turn["key"]) ?? StringValue(turn["turnKey"])
        ?? StringValue(turn["turn_key"])
    {
      return turnKey
    }
    return StringValue(params["turnKey"]) ?? StringValue(params["turn_key"])
      ?? StringValue(params["key"])
  }

  private func StringValue(_ value: Any?) -> String? {
    guard let value = value as? String else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

func ParsePlanSteps(_ value: Any?) -> [PlanStepInfo] {
  guard let planArray = value as? [[String: Any]] else {
    return []
  }

  return planArray.map { step in
    let description =
      NonEmptyPlanString(step["step"])
      ?? NonEmptyPlanString(step["description"])
      ?? NonEmptyPlanString(step["title"])
      ?? "Unknown step"
    let status = NonEmptyPlanString(step["status"]) ?? "pending"
    return PlanStepInfo(description: description, status: PlanStepStatus(serverValue: status))
  }
}

private func NonEmptyPlanString(_ value: Any?) -> String? {
  guard let value = value as? String else {
    return nil
  }
  let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.isEmpty ? nil : trimmed
}
