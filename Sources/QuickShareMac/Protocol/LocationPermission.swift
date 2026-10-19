import CoreLocation
import Foundation

final class LocationPermission: NSObject, CLLocationManagerDelegate {
  static let shared = LocationPermission()

  private let manager = CLLocationManager()

  private(set) var status: CLAuthorizationStatus = .notDetermined

  func request() {
    manager.delegate = self
    status = manager.authorizationStatus
    if status == .notDetermined {
      manager.requestAlwaysAuthorization()
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    status = manager.authorizationStatus
    print("[QuickShare] location authorization status=\(manager.authorizationStatus.rawValue)")
    fflush(stdout)
  }
}
