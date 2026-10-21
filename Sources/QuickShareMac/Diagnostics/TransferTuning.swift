import Foundation

/// Opt-in wire tuning for the Nearby Connections core.
///
/// The framework ships a 64 KiB payload chunk (`kMediumDefaultMaxTransmitPacketSize`,
/// flag 45669529). The chunk size is not negotiated — the peer reassembles by
/// byte offset — so it can be raised locally as long as one frame stays below
/// `kMediumMaxAllowedReadBytes` (1 MiB, enforced by the reader). The framework
/// exposes no runtime API for flags, so the value is exported through the
/// environment and read in `BaseEndpointChannel::GetDefaultMaxTransmitPacketSize`.
///
/// Applies to Wi-Fi LAN, hotspot, and direct channels. BLE/BLE-L2CAP override
/// the chunk size with their own small values and are unaffected.
enum TransferTuning {
  static let chunkSizeKey = "QuickShareMac.chunkSizeKiB"
  /// 0 means "keep the framework default".
  static let chunkSizeChoices = [0, 128, 256, 512]

  static var chunkSizeKiB: Int {
    get { UserDefaults.standard.integer(forKey: chunkSizeKey) }
    set {
      UserDefaults.standard.set(newValue, forKey: chunkSizeKey)
      apply()
    }
  }

  static func label(for kib: Int) -> String {
    kib > 0 ? "\(kib) KiB" : "Default (64 KiB)"
  }

  /// Must run before a connection opens its payload channels. Runs at launch and
  /// whenever the setting changes; existing connections keep their chunk size.
  static func apply() {
    var kib = chunkSizeKiB
    let arguments = CommandLine.arguments
    if let index = arguments.firstIndex(of: "--chunk-kib"), index + 1 < arguments.count,
      let value = Int(arguments[index + 1])
    {
      kib = value
      UserDefaults.standard.set(value, forKey: chunkSizeKey)
    }
    if (16...512).contains(kib) {
      setenv("NEARBY_CHUNK_SIZE_KIB", String(kib), 1)
      Diagnostics.log("payload chunk size: \(kib) KiB (framework default is 64 KiB)")
    } else {
      unsetenv("NEARBY_CHUNK_SIZE_KIB")
      Diagnostics.log("payload chunk size: framework default (64 KiB)")
    }
  }
}
