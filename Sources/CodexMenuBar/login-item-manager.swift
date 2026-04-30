import ServiceManagement

enum LoginItemStatus: Equatable {
  case enabled
  case requiresApproval
  case notRegistered
  case notFound
}

@MainActor
protocol LoginItemManaging: AnyObject {
  var Status: LoginItemStatus { get }

  func SetEnabled(_ isEnabled: Bool) throws
  func OpenSystemSettingsLoginItems()
}

@MainActor
final class ServiceManagementLoginItemManager: LoginItemManaging {
  var Status: LoginItemStatus {
    LoginItemStatus(SMAppService.mainApp.status)
  }

  func SetEnabled(_ isEnabled: Bool) throws {
    let service = SMAppService.mainApp

    if isEnabled {
      switch service.status {
      case .enabled, .requiresApproval:
        return
      case .notRegistered, .notFound:
        try service.register()
      @unknown default:
        try service.register()
      }
      return
    }

    switch service.status {
    case .enabled, .requiresApproval:
      try service.unregister()
    case .notRegistered, .notFound:
      return
    @unknown default:
      try service.unregister()
    }
  }

  func OpenSystemSettingsLoginItems() {
    SMAppService.openSystemSettingsLoginItems()
  }
}

extension LoginItemStatus {
  fileprivate init(_ status: SMAppService.Status) {
    switch status {
    case .enabled:
      self = .enabled
    case .requiresApproval:
      self = .requiresApproval
    case .notRegistered:
      self = .notRegistered
    case .notFound:
      self = .notFound
    @unknown default:
      self = .notFound
    }
  }
}
