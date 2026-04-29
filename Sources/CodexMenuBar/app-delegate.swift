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

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.accessory)
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

      self.model.isPopoverShown = isShown
      if isShown {
        self.model.SyncSectionDisclosureState()
        self.model.InvalidateView()
        self.StartTimer()
        self.OnTimerTick()
      } else {
        self.StopTimer()
      }
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
    statusWindowController.Show()
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
    guard IsUITestMode(),
      ArgumentValue(after: "--fixture")?.caseInsensitiveCompare("active-turn") == .orderedSame
    else {
      return
    }

    let endpointId = "fixture-endpoint"
    let threadId = "fixture-thread"
    let turnId = "fixture-turn"
    let now = Date()
    let startedAt = now.addingTimeInterval(-96)
    let cwd = NSHomeDirectory().appending("/workspace/agentic-tools/CodexMenuBar")

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
                "content":
                  "Polish the active turn menu bar panel and make the settings window compact.",
              ]
            ],
          ]
        ],
      ],
      at: now
    )
    turnStore.UpsertTurnStarted(
      endpointId: endpointId, threadId: threadId, turnId: turnId, at: startedAt)
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
    turnStore.RecordCommand(
      endpointId: endpointId,
      turnId: turnId,
      command: CommandSummary(
        command: "./scripts/ui/ui_loop.sh --scheme CodexMenuBarUI --destination platform=macOS",
        status: .inProgress,
        exitCode: nil,
        durationMs: nil
      )
    )
    turnStore.RecordFileChange(
      endpointId: endpointId,
      turnId: turnId,
      change: FileChangeSummary(
        path: "Sources/CodexMenuBar/status-menu-controller.swift", kind: .update)
    )
    turnStore.RecordFileChange(
      endpointId: endpointId,
      turnId: turnId,
      change: FileChangeSummary(
        path: "Sources/CodexMenuBar/settings-window-controller.swift", kind: .update)
    )
    turnStore.UpdatePlan(
      endpointId: endpointId,
      turnId: turnId,
      steps: [
        PlanStepInfo(description: "Audit current AppKit status item shell", status: .completed),
        PlanStepInfo(description: "Stabilize popover sizing and active rows", status: .inProgress),
        PlanStepInfo(description: "Verify screenshots and accessibility", status: .pending),
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
      )
    )
    model.SyncSectionDisclosureState()
    model.InvalidateView()
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

  @objc
  private func OnTimerTick() {
    let now = Date()
    turnStore.Tick(now: now)
    model.now = now
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
    if model.isPopoverShown {
      model.SyncSectionDisclosureState()
    }

    let isHighFrequencyUpdate = method == "turn/progressTrace"
    let shouldInvalidate =
      method == "turn/started"
      || method == "turn/completed"
      || method == "thread/snapshotSummary"
      || (model.isPopoverShown && !isHighFrequencyUpdate)
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
    let threadId = ResolveThreadId(params: params, endpointId: endpointId, turnId: turnId)
    turnStore.ClearError(endpointId: endpointId)
    turnStore.UpsertTurnStarted(
      endpointId: endpointId, threadId: threadId, turnId: turnId, at: Date())
    turnStore.UpdateTurnMetadata(
      endpointId: endpointId, threadId: threadId, turnId: turnId, turn: turn, at: Date())
  }

  private func HandleTurnCompleted(params: [String: Any]) {
    let endpointId = params["endpointId"] as? String ?? "unknown"
    guard
      let turn = params["turn"] as? [String: Any],
      let turnId = turn["id"] as? String
    else {
      return
    }
    let threadId = ResolveThreadId(params: params, endpointId: endpointId, turnId: turnId)
    let status = CompletedStatusFromServerValue(turn["status"] as? String)
    let fromSnapshot = params["fromSnapshot"] as? Bool ?? false
    if fromSnapshot {
      turnStore.MarkTurnCompletedIfPresent(
        endpointId: endpointId,
        threadId: threadId,
        turnId: turnId,
        status: status,
        at: Date()
      )
      turnStore.UpdateTurnMetadata(
        endpointId: endpointId, threadId: threadId, turnId: turnId, turn: turn, at: Date())
      return
    }
    turnStore.MarkTurnCompleted(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      status: status,
      at: Date()
    )
    turnStore.UpdateTurnMetadata(
      endpointId: endpointId, threadId: threadId, turnId: turnId, turn: turn, at: Date())
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
    let threadId = ResolveThreadId(params: params, endpointId: endpointId, turnId: turnId)

    let label = params["label"] as? String
    turnStore.RecordProgress(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
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
    let threadId = ResolveThreadId(params: params, endpointId: endpointId, turnId: turnId)

    turnStore.ApplyItemMetadata(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      item: item,
      at: Date()
    )

    ExtractItemDetails(
      endpointId: endpointId, turnId: turnId, item: item, itemType: itemType)

    guard let category = CategoryFromItemType(itemType) else {
      return
    }

    turnStore.RecordProgress(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      category: category,
      state: state,
      label: nil,
      at: Date()
    )
  }

  private func ExtractItemDetails(
    endpointId: String, turnId: String, item: [String: Any], itemType: String
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

    func ParseInfo(_ dict: [String: Any]) -> TokenUsageInfo {
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

    var totalInfo: TokenUsageInfo?
    if let total = usage["total"] as? [String: Any] {
      totalInfo = ParseInfo(total)
      totalInfo?.contextWindow = nil
    }

    var lastInfo: TokenUsageInfo?
    if let last = usage["last"] as? [String: Any] {
      lastInfo = ParseInfo(last)
    }

    let contextWindow =
      usage["modelContextWindow"] as? Int ?? usage["model_context_window"] as? Int
    lastInfo?.contextWindow = contextWindow

    turnStore.UpdateTokenUsage(
      endpointId: endpointId,
      threadId: threadId,
      turnId: turnId,
      tokenUsageTotal: totalInfo,
      tokenUsageLast: lastInfo
    )
  }

  private func HandleTurnPlanUpdated(params: [String: Any]) {
    let endpointId = params["endpointId"] as? String ?? "unknown"
    guard let turnId = StringValue(params["turnId"]) ?? StringValue(params["turn_id"]) else {
      return
    }

    let explanation = StringValue(params["explanation"])
    var steps: [PlanStepInfo] = []

    if let planArray = params["plan"] as? [[String: Any]] {
      for step in planArray {
        let desc =
          StringValue(step["description"]) ?? StringValue(step["title"]) ?? "Unknown step"
        let statusStr = (step["status"] as? String) ?? "pending"
        steps.append(
          PlanStepInfo(description: desc, status: PlanStepStatus(serverValue: statusStr)))
      }
    }

    turnStore.UpdatePlan(
      endpointId: endpointId, turnId: turnId, steps: steps, explanation: explanation)
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
    turnId: String
  ) -> String? {
    if let threadId = StringValue(params["threadId"]) ?? StringValue(params["thread_id"]) {
      return threadId
    }

    return turnStore.ResolveThreadId(endpointId: endpointId, turnId: turnId)
  }

  private func StringValue(_ value: Any?) -> String? {
    guard let value = value as? String else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
