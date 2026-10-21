import CoreWLAN
import Foundation

enum WiFiRadio {
  enum Result {
    case alreadyOn
    case turnedOn
    case unavailable
    case failed(String)
  }

  static func ensurePoweredOn() -> Result {
    guard let interface = CWWiFiClient.shared().interface() else {
      return .unavailable
    }
    if interface.powerOn() {
      return .alreadyOn
    }
    do {
      try interface.setPower(true)
    } catch {
      return .failed(error.localizedDescription)
    }
    return interface.powerOn()
      ? .turnedOn
      : .failed("the Wi-Fi radio did not report powered on")
  }
}
