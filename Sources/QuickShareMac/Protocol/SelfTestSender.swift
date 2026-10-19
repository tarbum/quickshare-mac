import Foundation
import NearbyConnections

final class SelfTestSender: NSObject {
  private let connectionManager = ConnectionManager(
    serviceID: "NearbySharing", strategy: .pointToPoint, queue: .main)
  private lazy var discoverer = Discoverer(connectionManager: connectionManager)
  private let targetName: String?
  private var endpointID: EndpointID?
  private var sentIntroduction = false
  private var sentPayload = false

  init(targetName: String?) {
    self.targetName = targetName
    super.init()
    connectionManager.delegate = self
    discoverer.delegate = self
  }

  func start() {
    print("[test-sender] discovering…")
    discoverer.startDiscovery(mediums: [.wifiLAN]) { error in
      if let error = error {
        print("[test-sender] discovery failed: \(error.localizedDescription)")
        exit(1)
      }
    }
  }

  private func send(_ frame: Nearby_Sharing_Service_Proto_Frame, to endpointID: EndpointID) {
    guard let data = FrameCodec.serialize(frame) else { return }
    _ = connectionManager.send(data, to: [endpointID])
  }

  private func sendIntroduction(to endpointID: EndpointID) {
    let text = "Quick Share macOS loopback test \(Date())"
    let payloadID: Int64 = 424242
    var frame = Nearby_Sharing_Service_Proto_Frame()
    frame.version = .v1
    frame.v1.type = .introduction
    var intro = Nearby_Sharing_Service_Proto_IntroductionFrame()
    var textMeta = Nearby_Sharing_Service_Proto_TextMetadata()
    textMeta.id = 1
    textMeta.type = .text
    textMeta.textTitle = "Quick Share Test"
    textMeta.payloadID = payloadID
    textMeta.size = Int64(text.utf8.count)
    intro.textMetadata = [textMeta]
    intro.startTransfer = true
    intro.useCase = .nearbyShare
    frame.v1.introduction = intro
    send(frame, to: endpointID)
    print("[test-sender] sent introduction (\(text.utf8.count) bytes)")

    pendingText = Data(text.utf8)
    pendingPayloadID = payloadID
  }

  private var pendingText: Data?
  private var pendingPayloadID: Int64?
}

extension SelfTestSender: DiscovererDelegate {
  func discoverer(
    _ discoverer: Discoverer, didFind endpointID: EndpointID, with context: Data
  ) {
    let advertisement = QuickShareAdvertisement.parse(context)
    let name = advertisement?.deviceName ?? "(no name)"
    print("[test-sender] found \(endpointID): \(name)")
    guard !sentIntroduction else { return }
    if let targetName = targetName, advertisement?.deviceName != targetName {
      return
    }
    self.endpointID = endpointID
    discoverer.stopDiscovery()
    let localInfo = QuickShareAdvertisement.make(deviceName: "QuickShare Test Sender")
    discoverer.requestConnection(
      to: endpointID, using: localInfo, mediums: [.wifiLAN]
    ) { error in
      if let error = error {
        print("[test-sender] connect failed: \(error.localizedDescription)")
        exit(1)
      }
    }
  }

  func discoverer(_ discoverer: Discoverer, didLose endpointID: EndpointID) {}
}

extension SelfTestSender: ConnectionManagerDelegate {
  func connectionManager(
    _ connectionManager: ConnectionManager, didChangeTo state: ConnectionState,
    for endpointID: EndpointID
  ) {
    print("[test-sender] state \(state) for \(endpointID)")
    if state == .connected {
      send(FrameCodec.pairedKeyEncryption(), to: endpointID)
    }
  }

  func connectionManager(
    _ connectionManager: ConnectionManager, didReceive data: Data, withID payloadID: PayloadID,
    from endpointID: EndpointID
  ) {
    guard let frame = try? FrameCodec.decode(data) else {
      print("[test-sender] payload \(payloadID), \(data.count) bytes")
      return
    }
    switch frame.v1.type {
    case .pairedKeyEncryption:
      send(FrameCodec.pairedKeyResult(.unable), to: endpointID)
    case .pairedKeyResult:
      if !sentIntroduction {
        sentIntroduction = true
        sendIntroduction(to: endpointID)
      }
    case .response:
      print("[test-sender] response \(frame.v1.connectionResponse.status)")
      if frame.v1.connectionResponse.status == .accept,
        let text = pendingText,
        let payloadID = pendingPayloadID,
        !sentPayload
      {
        sentPayload = true
        _ = connectionManager.send(text, to: [endpointID], id: payloadID) { error in
          if let error = error {
            print("[test-sender] payload send failed: \(error.localizedDescription)")
          } else {
            print("[test-sender] sent text payload \(payloadID)")
          }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
          print("[test-sender] done")
          exit(0)
        }
      }
    case .cancel:
      print("[test-sender] cancelled")
      exit(1)
    default:
      break
    }
  }

  func connectionManager(
    _ connectionManager: ConnectionManager, didReceive stream: InputStream,
    withID payloadID: PayloadID, from endpointID: EndpointID,
    cancellationToken token: CancellationToken
  ) {}

  func connectionManager(
    _ connectionManager: ConnectionManager, didStartReceivingResourceWithID payloadID: PayloadID,
    from endpointID: EndpointID, at localURL: URL, withName name: String,
    cancellationToken token: CancellationToken
  ) {}

  func connectionManager(
    _ connectionManager: ConnectionManager, didReceiveTransferUpdate update: TransferUpdate,
    from endpointID: EndpointID, forPayload payloadID: PayloadID
  ) {
    print("[test-sender] transfer \(update) \(payloadID)")
  }
}
