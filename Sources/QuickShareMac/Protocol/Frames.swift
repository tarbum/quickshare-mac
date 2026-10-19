import Foundation
import SwiftProtobuf

enum FrameCodec {
  static func decode(_ data: Data) throws -> Nearby_Sharing_Service_Proto_Frame? {
    do {
      let frame = try Nearby_Sharing_Service_Proto_Frame(serializedBytes: data)
      guard frame.version == .v1, frame.hasV1 else { return nil }
      return frame
    } catch {
      return nil
    }
  }

  static func pairedKeyEncryption() -> Nearby_Sharing_Service_Proto_Frame {
    var frame = Nearby_Sharing_Service_Proto_Frame()
    frame.version = .v1
    frame.v1.type = .pairedKeyEncryption
    var encryption = Nearby_Sharing_Service_Proto_PairedKeyEncryptionFrame()

    encryption.signedData = Data.randomBytes(72)
    encryption.secretIDHash = Data.randomBytes(6)
    frame.v1.pairedKeyEncryption = encryption
    return frame
  }

  static func pairedKeyResult(
    _ status: Nearby_Sharing_Service_Proto_PairedKeyResultFrame.Status
  ) -> Nearby_Sharing_Service_Proto_Frame {
    var frame = Nearby_Sharing_Service_Proto_Frame()
    frame.version = .v1
    frame.v1.type = .pairedKeyResult
    var result = Nearby_Sharing_Service_Proto_PairedKeyResultFrame()
    result.status = status
    result.osType = .macos
    frame.v1.pairedKeyResult = result
    return frame
  }

  static func response(
    _ status: Nearby_Sharing_Service_Proto_ConnectionResponseFrame.Status
  ) -> Nearby_Sharing_Service_Proto_Frame {
    var frame = Nearby_Sharing_Service_Proto_Frame()
    frame.version = .v1
    frame.v1.type = .response
    var response = Nearby_Sharing_Service_Proto_ConnectionResponseFrame()
    response.status = status
    frame.v1.connectionResponse = response
    return frame
  }

  static func cancel() -> Nearby_Sharing_Service_Proto_Frame {
    var frame = Nearby_Sharing_Service_Proto_Frame()
    frame.version = .v1
    frame.v1.type = .cancel
    return frame
  }

  static func serialize(_ frame: Nearby_Sharing_Service_Proto_Frame) -> Data? {
    try? frame.serializedData()
  }
}

struct IncomingAttachment {
  enum Kind {
    case file
    case text
    case wifiCredentials
  }

  var kind: Kind
  var name: String
  var mimeType: String
  var size: Int64
  var payloadID: Int64
  var textType: Nearby_Sharing_Service_Proto_TextMetadata.TypeEnum?
}

extension Nearby_Sharing_Service_Proto_IntroductionFrame {
  var incomingAttachments: [IncomingAttachment] {
    var result: [IncomingAttachment] = []
    for file in fileMetadata {
      result.append(
        IncomingAttachment(
          kind: .file,
          name: file.hasName ? file.name : "file-\(file.payloadID)",
          mimeType: file.hasMimeType ? file.mimeType : "application/octet-stream",
          size: file.size,
          payloadID: file.payloadID,
          textType: nil))
    }
    for text in textMetadata {
      result.append(
        IncomingAttachment(
          kind: .text,
          name: text.hasTextTitle ? text.textTitle : "Shared text",
          mimeType: "text/plain",
          size: text.size,
          payloadID: text.payloadID,
          textType: text.type))
    }
    for wifi in wifiCredentialsMetadata {
      result.append(
        IncomingAttachment(
          kind: .wifiCredentials,
          name: wifi.hasSsid ? wifi.ssid : "Wi-Fi",
          mimeType: "application/octet-stream",
          size: 0,
          payloadID: wifi.payloadID,
          textType: nil))
    }
    return result
  }
}
