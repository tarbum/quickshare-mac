import Foundation
import AppKit
import NearbyConnections

struct ReceivedItem: Identifiable {
  let id = UUID()
  let name: String
  let url: URL
  let date: Date
  let kind: String
}

struct IncomingRequest: Identifiable {
  let endpointID: EndpointID
  let peerName: String
  let summary: String
  let date: Date

  var id: EndpointID { endpointID }
}

final class TransferSession {
  let endpointID: EndpointID
  var peerName: String
  var attachments: [Int64: IncomingAttachment] = [:]
  var payloadData: [Int64: Data] = [:]
  var resourceURLs: [Int64: URL] = [:]
  var resourceNames: [Int64: String] = [:]
  var completedPayloads: Set<Int64> = []
  /// Wall-clock time each payload started arriving, for throughput reporting.
  var payloadStartedAt: [Int64: Date] = [:]
  /// Throttled throughput sampler per payload.
  var progressSamplers: [Int64: ProgressSampler] = [:]
  var introduced = false
  var approved = false
  var createdAt = Date()

  init(endpointID: EndpointID, peerName: String) {
    self.endpointID = endpointID
    self.peerName = peerName
  }

  var pendingCount: Int {
    max(0, attachments.count - completedPayloads.count)
  }
}

enum DownloadNaming {
  static func uniqueURL(in directory: URL, preferredName: String) -> URL {
    let fileManager = FileManager.default
    var candidate = directory.appendingPathComponent(preferredName)
    if !fileManager.fileExists(atPath: candidate.path) {
      return candidate
    }
    let base = candidate.deletingPathExtension().lastPathComponent
    let ext = candidate.pathExtension
    var index = 1
    while true {
      let name = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
      candidate = directory.appendingPathComponent(name)
      if !fileManager.fileExists(atPath: candidate.path) {
        return candidate
      }
      index += 1
    }
  }

  static func sanitize(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleaned = trimmed.replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")
    return cleaned.isEmpty ? "Quick Share item" : cleaned
  }
}
