import Foundation

final class DeviceTrustStore: ObservableObject {
  enum Decision {
    case allow
    case block
    case ask
  }

  static let shared = DeviceTrustStore()

  @Published private(set) var allowedDevices: [String]
  @Published private(set) var blockedDevices: [String]
  @Published var askBeforeReceiving: Bool {
    didSet {
      defaults.set(askBeforeReceiving, forKey: Self.askKey)
    }
  }

  private let defaults = UserDefaults.standard

  private static let allowedKey = "QuickShareMac.allowedDevices"
  private static let blockedKey = "QuickShareMac.blockedDevices"
  private static let askKey = "QuickShareMac.askBeforeReceiving"

  private init() {
    allowedDevices = defaults.stringArray(forKey: Self.allowedKey) ?? []
    blockedDevices = defaults.stringArray(forKey: Self.blockedKey) ?? []
    askBeforeReceiving = defaults.object(forKey: Self.askKey) as? Bool ?? true
  }

  func decision(for deviceName: String) -> Decision {
    let key = Self.normalize(deviceName)
    if blockedDevices.contains(where: { Self.normalize($0) == key }) {
      return .block
    }
    if allowedDevices.contains(where: { Self.normalize($0) == key }) {
      return .allow
    }
    return askBeforeReceiving ? .ask : .allow
  }

  func allow(_ deviceName: String) {
    let name = Self.displayName(deviceName)
    guard !name.isEmpty else { return }
    blockedDevices.removeAll { Self.normalize($0) == Self.normalize(name) }
    if !allowedDevices.contains(where: { Self.normalize($0) == Self.normalize(name) }) {
      allowedDevices.append(name)
      allowedDevices.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
      save()
    }
  }

  func block(_ deviceName: String) {
    let name = Self.displayName(deviceName)
    guard !name.isEmpty else { return }
    allowedDevices.removeAll { Self.normalize($0) == Self.normalize(name) }
    if !blockedDevices.contains(where: { Self.normalize($0) == Self.normalize(name) }) {
      blockedDevices.append(name)
      blockedDevices.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
      save()
    }
  }

  func removeAllowed(_ deviceName: String) {
    allowedDevices.removeAll { Self.normalize($0) == Self.normalize(deviceName) }
    save()
  }

  func removeBlocked(_ deviceName: String) {
    blockedDevices.removeAll { Self.normalize($0) == Self.normalize(deviceName) }
    save()
  }

  private func save() {
    defaults.set(allowedDevices, forKey: Self.allowedKey)
    defaults.set(blockedDevices, forKey: Self.blockedKey)
  }

  private static func normalize(_ name: String) -> String {
    displayName(name).lowercased()
  }

  private static func displayName(_ name: String) -> String {
    String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(128))
  }
}
