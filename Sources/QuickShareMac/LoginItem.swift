import Combine
import ServiceManagement

final class LoginItem: ObservableObject {
  static let shared = LoginItem()

  @Published private(set) var isEnabled = false
  @Published private(set) var needsApproval = false
  @Published private(set) var lastError: String?

  private init() {
    refresh()
  }

  func refresh() {
    let status = SMAppService.mainApp.status
    isEnabled = status == .enabled || status == .requiresApproval
    needsApproval = status == .requiresApproval
  }

  func setEnabled(_ enabled: Bool) {
    lastError = nil
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      lastError = error.localizedDescription
    }
    refresh()
  }

  func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}
