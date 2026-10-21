import Foundation
import UniformTypeIdentifiers
import NearbyConnections

struct DiscoveredPeer: Identifiable, Equatable {
  var id: EndpointID { endpointID }
  let endpointID: EndpointID
  let name: String
  let deviceType: QuickShareAdvertisement.DeviceType
}

struct OutgoingFile {
  let url: URL
  let name: String
  let mimeType: String
  let size: Int64
  let attachmentID: Int64
  let payloadID: Int64

  init(url: URL) {
    self.url = url
    self.name = url.lastPathComponent
    let type = UTType(filenameExtension: url.pathExtension)
    self.mimeType = type?.preferredMIMEType ?? "application/octet-stream"
    let values = try? url.resourceValues(forKeys: [.fileSizeKey])
    self.size = Int64(values?.fileSize ?? 0)
    self.attachmentID = Int64.random(in: 1...Int64.max)
    self.payloadID = Int64.random(in: 1...Int64.max)
  }

  var metadataType: Nearby_Sharing_Service_Proto_FileMetadata.TypeEnum {
    let type = UTType(filenameExtension: url.pathExtension)
    if type?.conforms(to: .image) == true { return .image }
    if type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true {
      return .video
    }
    if type?.conforms(to: .audio) == true { return .audio }
    return .document
  }
}

final class OutgoingTransfer {
  let peer: DiscoveredPeer
  let files: [OutgoingFile]
  var sentIntroduction = false
  var completedPayloads: Set<Int64> = []
  var startedPayloads = false
  /// Set when payload bytes start flowing, used for throughput reporting.
  var startedAt: Date?
  var payloadStartedAt: [Int64: Date] = [:]
  /// Throttled throughput sampler per payload.
  var progressSamplers: [Int64: ProgressSampler] = [:]

  init(peer: DiscoveredPeer, files: [OutgoingFile]) {
    self.peer = peer
    self.files = files
  }

  var introductionFrame: Nearby_Sharing_Service_Proto_Frame {
    var frame = Nearby_Sharing_Service_Proto_Frame()
    frame.version = .v1
    frame.v1.type = .introduction
    var introduction = Nearby_Sharing_Service_Proto_IntroductionFrame()
    introduction.useCase = .nearbyShare
    introduction.startTransfer = true
    for file in files {
      var metadata = Nearby_Sharing_Service_Proto_FileMetadata()
      metadata.id = file.attachmentID
      metadata.name = file.name
      metadata.size = file.size
      metadata.payloadID = file.payloadID
      metadata.mimeType = file.mimeType
      metadata.type = file.metadataType
      metadata.parentFolder = ""
      introduction.fileMetadata.append(metadata)
    }
    frame.v1.introduction = introduction
    return frame
  }
}
