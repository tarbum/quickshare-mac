import CoreLocation
import CoreWLAN
import Foundation

enum HotspotDiagnostics {
  static func scan() {
    LocationPermission.shared.request()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      guard let interface = CWWiFiClient.shared().interface() else {
        print("[hotspot] no Wi-Fi interface")
        exit(2)
      }
      print("[hotspot] location status=\(LocationPermission.shared.status.rawValue)")
      do {
        let networks = try interface.scanForNetworks(withSSID: nil)
        for network in networks.sorted(by: { $0.rssiValue > $1.rssiValue }) {
          print("[hotspot] ssid=\(network.ssid ?? "?") rssi=\(network.rssiValue)")
        }
        exit(0)
      } catch {
        print("[hotspot] scan failed: \(error)")
        exit(1)
      }
    }
  }

  static func join(ssid: String, password: String) {
    LocationPermission.shared.request()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      guard let interface = CWWiFiClient.shared().interface() else {
        print("[hotspot] no Wi-Fi interface")
        exit(2)
      }
      do {
        let networks = try interface.scanForNetworks(
          withSSID: ssid.data(using: .utf8))
        guard let network = networks.max(by: { $0.rssiValue < $1.rssiValue }) else {
          print("[hotspot] SSID not found: \(ssid)")
          exit(1)
        }
        try interface.associate(to: network, password: password)
        print("[hotspot] joined \(ssid)")
        exit(0)
      } catch {
        print("[hotspot] join failed: \(error)")
        exit(1)
      }
    }
  }
}
