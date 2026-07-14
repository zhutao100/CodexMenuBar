import Foundation

enum SleepPreventionMode: Equatable {
  case systemOnly
  case systemAndDisplay

  fileprivate var activityOptions: ProcessInfo.ActivityOptions {
    switch self {
    case .systemOnly:
      return [.idleSystemSleepDisabled]
    case .systemAndDisplay:
      return [.idleSystemSleepDisabled, .idleDisplaySleepDisabled]
    }
  }

  fileprivate var activityReason: String {
    switch self {
    case .systemOnly:
      return "CodexMenuBar has active Codex sessions"
    case .systemAndDisplay:
      return "CodexMenuBar has active Codex sessions and is keeping the display awake"
    }
  }
}

@MainActor
protocol SleepPreventionManaging: AnyObject {
  var isPreventingSleep: Bool { get }
  var activeMode: SleepPreventionMode? { get }

  func Start(mode: SleepPreventionMode)
  func Stop()
}

@MainActor
final class ProcessInfoSleepPreventionManager: SleepPreventionManaging {
  private struct Activity {
    let mode: SleepPreventionMode
    let token: NSObjectProtocol
  }

  private let processInfo: ProcessInfo
  private var activity: Activity?

  init(processInfo: ProcessInfo = .processInfo) {
    self.processInfo = processInfo
  }

  var isPreventingSleep: Bool {
    activity != nil
  }

  var activeMode: SleepPreventionMode? {
    activity?.mode
  }

  func Start(mode: SleepPreventionMode) {
    guard activity?.mode != mode else {
      return
    }

    let newActivity = Activity(
      mode: mode,
      token: processInfo.beginActivity(
        options: mode.activityOptions,
        reason: mode.activityReason
      )
    )

    if let activity {
      processInfo.endActivity(activity.token)
    }
    activity = newActivity
  }

  func Stop() {
    guard let activity else {
      return
    }

    processInfo.endActivity(activity.token)
    self.activity = nil
  }
}

@MainActor
final class AutomaticSleepPreventionController {
  private let manager: SleepPreventionManaging

  private(set) var activeSessionCount = 0

  init(manager: SleepPreventionManaging = ProcessInfoSleepPreventionManager()) {
    self.manager = manager
  }

  var isPreventingSleep: Bool {
    manager.isPreventingSleep
  }

  var activeMode: SleepPreventionMode? {
    manager.activeMode
  }

  func Update(
    isEnabled: Bool,
    keepDisplayAwake: Bool,
    isConnected: Bool,
    activeSessionCount: Int
  ) {
    self.activeSessionCount = isConnected ? max(0, activeSessionCount) : 0

    guard isEnabled, isConnected, self.activeSessionCount > 0 else {
      if manager.isPreventingSleep {
        manager.Stop()
      }
      return
    }

    let desiredMode: SleepPreventionMode =
      keepDisplayAwake ? .systemAndDisplay : .systemOnly
    if !manager.isPreventingSleep || manager.activeMode != desiredMode {
      manager.Start(mode: desiredMode)
    }
  }

  func Stop() {
    activeSessionCount = 0
    if manager.isPreventingSleep {
      manager.Stop()
    }
  }
}
