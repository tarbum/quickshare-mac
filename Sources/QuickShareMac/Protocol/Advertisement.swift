import Foundation

struct QuickShareAdvertisement {
  enum DeviceType: UInt8 {
    case unknown = 0
    case phone = 1
    case tablet = 2
    case laptop = 3
    case car = 4
    case foldable = 5
    case xr = 6
  }

  var deviceName: String
  var deviceType: DeviceType
  var salt: Data
  var encryptedMetadataKey: Data

  static let saltSize = 2
  static let metadataKeySize = 14

  static func make(deviceName: String, deviceType: DeviceType = .laptop) -> Data {
    var data = Data()
    let versionBits: UInt8 = 0
    let hasNameBits: UInt8 = 0
    let typeBits = (deviceType.rawValue & 0b111) << 1
    data.append(versionBits | hasNameBits | typeBits)

    data.append(Data.randomBytes(saltSize))
    data.append(Data.randomBytes(metadataKeySize))

    var name = Data(deviceName.utf8)
    if name.count > 255 {
      name = name.prefix(255)
    }
    data.append(UInt8(name.count))
    data.append(name)
    return data
  }

  static func parse(_ data: Data) -> QuickShareAdvertisement? {
    let bytes = [UInt8](data)
    guard bytes.count >= 1 + saltSize + metadataKeySize else { return nil }

    let first = bytes[0]
    let hasDeviceName = ((first >> 4) & 0b1) == 0
    let deviceType = DeviceType(rawValue: (first >> 1) & 0b111) ?? .unknown
    var index = 1

    let salt = Data(bytes[index..<(index + saltSize)])
    index += saltSize
    let key = Data(bytes[index..<(index + metadataKeySize)])
    index += metadataKeySize

    var name = ""
    if hasDeviceName {
      guard index < bytes.count else { return nil }
      let length = Int(bytes[index])
      index += 1
      guard length > 0, index + length <= bytes.count else { return nil }
      name = String(decoding: bytes[index..<(index + length)], as: UTF8.self)
    }

    return QuickShareAdvertisement(
      deviceName: name, deviceType: deviceType, salt: salt, encryptedMetadataKey: key)
  }
}

extension Data {
  static func randomBytes(_ count: Int) -> Data {
    var data = Data(count: count)
    data.withUnsafeMutableBytes { buffer in
      if let base = buffer.baseAddress {
        arc4random_buf(base, count)
      }
    }
    return data
  }
}
