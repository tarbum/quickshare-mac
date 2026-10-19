import Foundation
import AppKit
import NearbyConnections
import SwiftProtobuf
import UserNotifications

private enum QuickShareNotification {
  static let category = "QUICKSHARE_INCOMING_TRANSFER"
  static let accept = "QUICKSHARE_ACCEPT"
  static let decline = "QUICKSHARE_DECLINE"
  static let alwaysAllow = "QUICKSHARE_ALWAYS_ALLOW"
  static let block = "QUICKSHARE_BLOCK"
  static let endpointKey = "endpointID"
}

final class QuickShareService: NSObject, ObservableObject {
  static let shared = QuickShareService()

  private let serviceID = "NearbySharing"

  private lazy var connectionManager = ConnectionManager(
    serviceID: serviceID, strategy: .pointToPoint, queue: .main)
  private lazy var advertiser = Advertiser(connectionManager: connectionManager)
  private lazy var discoverer = Discoverer(connectionManager: connectionManager)

  private var sessions: [EndpointID: TransferSession] = [:]
  private var peerNames: [EndpointID: String] = [:]
  private var outgoing: OutgoingTransfer?

  private let trustStore = DeviceTrustStore.shared
  private struct PendingApproval {
    var request: IncomingRequest
    var timeout: DispatchWorkItem
  }
  private var pendingApprovals: [EndpointID: PendingApproval] = [:]
  private var connectedEndpoints: Set<EndpointID> = []
  private var scheduledDisconnects: [EndpointID: DispatchWorkItem] = [:]

  @Published var peers: [DiscoveredPeer] = []
  @Published var incomingRequests: [IncomingRequest] = []
  @Published var notificationsAllowed: Bool?
  @Published var isDiscovering = false
  @Published var lastSendCompleted = false
  @Published var bleEnabled: Bool {
    didSet {
      guard oldValue != bleEnabled else { return }
      UserDefaults.standard.set(bleEnabled, forKey: Self.bleEnabledKey)
      if isReceiving {
        scheduleAdvertisingRestart()
      }
    }
  }

  var wifiLanEnabled = true

  var allowSameNamePeers = false

  private var transferMediums: Set<Medium> {
    var mediums: Set<Medium> = [.wifiHotspot, .wifiDirect]
    if wifiLanEnabled { mediums.insert(.wifiLAN) }
    if bleEnabled { mediums.insert(.ble) }
    return mediums
  }

  @Published var isReceiving = false
  @Published var statusMessage = "Starting…"
  @Published var lastError: String?
  @Published var log: [String] = []
  @Published var receivedItems: [ReceivedItem] = []
  @Published var deviceName: String {
    didSet {
      guard oldValue != deviceName else { return }
      UserDefaults.standard.set(deviceName, forKey: Self.deviceNameKey)
      if isReceiving {
        scheduleAdvertisingRestart()
      }
    }
  }

  private static let deviceNameKey = "QuickShareMac.deviceName"
  private static let bleEnabledKey = "QuickShareMac.bleEnabled"

  private var advertisingRestartWorkItem: DispatchWorkItem?
  private var advertisingGeneration = 0
  private var isStartingAdvertising = false

  override init() {
    self.deviceName =
      UserDefaults.standard.string(forKey: Self.deviceNameKey)
      ?? Host.current().localizedName
      ?? "Mac"
    self.bleEnabled =
      UserDefaults.standard.object(forKey: Self.bleEnabledKey) as? Bool ?? true
    super.init()
    connectionManager.delegate = self
    advertiser.delegate = self
    discoverer.delegate = self
  }

  func start() {
    guard !isReceiving, !isStartingAdvertising else { return }
    cancelScheduledAdvertisingRestart()
    advertisingGeneration += 1
    startAdvertising()
  }

  func stop() {
    guard isReceiving else { return }
    cancelScheduledAdvertisingRestart()
    advertisingGeneration += 1
    advertiser.stopAdvertising { [weak self] error in
      DispatchQueue.main.async {
        self?.isReceiving = false
        self?.statusMessage = "Paused"
        if let error = error {
          self?.appendLog("stop advertising: \(error.localizedDescription)")
        }
      }
    }
  }

  func toggle() {
    isReceiving ? stop() : start()
  }

  private func scheduleDisconnect(
    endpointID: EndpointID, after delay: TimeInterval = 1.5, reason: String
  ) {
    guard connectedEndpoints.contains(endpointID) else { return }
    scheduledDisconnects[endpointID]?.cancel()

    let work = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      self.scheduledDisconnects.removeValue(forKey: endpointID)
      guard self.connectedEndpoints.remove(endpointID) != nil else { return }
      self.appendLog("disconnecting from \(endpointID) (\(reason))")
      self.connectionManager.disconnect(from: endpointID) { error in
        guard let error = error else { return }
        DispatchQueue.main.async {
          self.appendLog(
            "disconnect from \(endpointID) failed: \(error.localizedDescription)")
        }
      }
    }
    scheduledDisconnects[endpointID] = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  private func cancelScheduledDisconnect(_ endpointID: EndpointID) {
    scheduledDisconnects.removeValue(forKey: endpointID)?.cancel()
  }

  func configureNotifications() {
    let center = UNUserNotificationCenter.current()
    center.delegate = self

    let accept = UNNotificationAction(
      identifier: QuickShareNotification.accept, title: "Accept")
    let decline = UNNotificationAction(
      identifier: QuickShareNotification.decline, title: "Decline")
    let alwaysAllow = UNNotificationAction(
      identifier: QuickShareNotification.alwaysAllow, title: "Always Allow")
    let block = UNNotificationAction(
      identifier: QuickShareNotification.block, title: "Block Device")

    let category = UNNotificationCategory(
      identifier: QuickShareNotification.category,
      actions: [accept, alwaysAllow, decline, block],
      intentIdentifiers: [],
      options: [.customDismissAction])
    center.setNotificationCategories([category])

    center.getNotificationSettings { [weak self] settings in
      DispatchQueue.main.async {
        self?.notificationsAllowed = Self.isAllowed(settings.authorizationStatus)
      }
    }

    center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
      DispatchQueue.main.async {
        self?.notificationsAllowed = granted
        if let error = error {
          self?.appendLog("notification permission error: \(error.localizedDescription)")
        } else if !granted {
          self?.appendLog(
            "notifications are disabled; using the in-app approval prompt and menu bar")
        }
      }
    }
  }

  private static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
    status == .authorized || status == .provisional
  }

  func refreshNotificationAuthorization() {
    UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
      DispatchQueue.main.async {
        self?.notificationsAllowed = Self.isAllowed(settings.authorizationStatus)
      }
    }
  }

  func approve(_ request: IncomingRequest, alwaysAllow: Bool = false) {
    DispatchQueue.main.async {
      if alwaysAllow {
        self.trustStore.allow(request.peerName)
        self.appendLog("always allowing \(request.peerName)")
      }
      self.finishApproval(endpointID: request.endpointID, accepted: true)
    }
  }

  func decline(_ request: IncomingRequest, blockDevice: Bool = false) {
    DispatchQueue.main.async {
      if blockDevice {
        self.trustStore.block(request.peerName)
        self.appendLog("blocking \(request.peerName)")
      }
      self.finishApproval(endpointID: request.endpointID, accepted: false)
    }
  }

  private func finishApproval(endpointID: EndpointID, accepted: Bool) {
    guard let pending = pendingApprovals.removeValue(forKey: endpointID) else { return }
    pending.timeout.cancel()
    removeIncomingRequest(endpointID)
    ApprovalPanelController.shared.close()
    UNUserNotificationCenter.current().removeDeliveredNotifications(
      withIdentifiers: [notificationIdentifier(for: endpointID)])

    guard let session = sessions[endpointID] else { return }
    if accepted {
      session.approved = true
      statusMessage = "Receiving \(pending.request.summary) from \(session.peerName)"
      appendLog("accepted transfer from \(session.peerName)")
      send(FrameCodec.response(.accept), to: endpointID)
    } else {
      statusMessage = "Declined transfer from \(session.peerName)"
      appendLog("declined transfer from \(session.peerName)")
      send(FrameCodec.response(.reject), to: endpointID)
      sessions.removeValue(forKey: endpointID)

      scheduleDisconnect(
        endpointID: endpointID, after: 2.0, reason: "transfer declined")
    }
  }

  private func requestApproval(for session: TransferSession, endpointID: EndpointID) {
    let summary = Self.summary(for: Array(session.attachments.values))
    let request = IncomingRequest(
      endpointID: endpointID, peerName: session.peerName,
      summary: summary, date: Date())

    let timeout = DispatchWorkItem { [weak self] in
      DispatchQueue.main.async {
        guard let self = self,
          let pending = self.pendingApprovals[endpointID]
        else { return }
        self.appendLog(
          "approval timed out for \(pending.request.peerName); declining transfer")
        self.finishApproval(endpointID: endpointID, accepted: false)
      }
    }
    pendingApprovals[endpointID] = PendingApproval(request: request, timeout: timeout)
    incomingRequests.append(request)
    incomingRequests.sort { $0.date < $1.date }
    DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: timeout)

    statusMessage = "\(session.peerName) wants to send \(summary)"
    appendLog("waiting for approval: \(session.peerName) -> \(summary)")
    postApprovalNotification(for: request)
    if notificationsAllowed != true {
      ApprovalPanelController.shared.show(request, service: self)
    }
  }

  private func removeIncomingRequest(_ endpointID: EndpointID) {
    incomingRequests.removeAll { $0.endpointID == endpointID }
  }

  private func cancelPendingApproval(endpointID: EndpointID, reason: String) {
    guard let pending = pendingApprovals.removeValue(forKey: endpointID) else { return }
    pending.timeout.cancel()
    removeIncomingRequest(endpointID)
    ApprovalPanelController.shared.close()
    UNUserNotificationCenter.current().removeDeliveredNotifications(
      withIdentifiers: [notificationIdentifier(for: endpointID)])
    appendLog("cancelled pending transfer from \(pending.request.peerName): \(reason)")
  }

  private func notificationIdentifier(for endpointID: EndpointID) -> String {
    "quickshare-incoming-\(endpointID)"
  }

  private func postApprovalNotification(for request: IncomingRequest) {
    let content = UNMutableNotificationContent()
    content.title = "Incoming Quick Share"
    content.subtitle = request.peerName
    content.body = "\(request.summary). Accept, decline, allow this device, or block it."
    content.sound = .default
    content.categoryIdentifier = QuickShareNotification.category
    content.userInfo = [QuickShareNotification.endpointKey: request.endpointID]

    let notification = UNNotificationRequest(
      identifier: notificationIdentifier(for: request.endpointID),
      content: content, trigger: nil)
    UNUserNotificationCenter.current().add(notification) { [weak self] error in
      if let error = error {
        DispatchQueue.main.async {
          self?.appendLog("could not post approval notification: \(error.localizedDescription)")
        }
      }
    }
  }

  private static func summary(for attachments: [IncomingAttachment]) -> String {
    guard !attachments.isEmpty else { return "a transfer" }
    let count = attachments.count
    let names = attachments
      .sorted { $0.payloadID < $1.payloadID }
      .prefix(3)
      .map(\.name)
      .joined(separator: ", ")
    let itemLabel = count == 1 ? "1 item" : "\(count) items"
    return attachments.count > 3 ? "\(itemLabel): \(names), …" : "\(itemLabel): \(names)"
  }

  func startDiscovery() {
    guard !isDiscovering else { return }
    peers = []
    isDiscovering = true
    discoverer.startDiscovery(mediums: transferMediums) { [weak self] error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if let error = error {
          self.isDiscovering = false
          self.appendLog("discovery failed: \(error.localizedDescription)")
          self.lastError = error.localizedDescription
        }
      }
    }
  }

  func stopDiscovery() {
    guard isDiscovering else { return }
    discoverer.stopDiscovery()
    isDiscovering = false
  }

  func beginSendFromFinder(files: [URL]) {
    let fileManager = FileManager.default
    let regularFiles = files.filter { url in
      var isDirectory: ObjCBool = false
      return url.isFileURL
        && fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        && !isDirectory.boolValue
    }

    guard !regularFiles.isEmpty else {
      lastError = "Quick Share can only send files, not folders."
      NSSound.beep()
      return
    }

    appendLog(
      "Finder service: sending \(regularFiles.map(\.lastPathComponent).joined(separator: ", "))")
    lastError = nil
    startDiscovery()
    SendPanelController.shared.show(files: regularFiles, service: self)
  }

  func send(files: [URL], to peer: DiscoveredPeer) {
    guard !files.isEmpty else { return }
    cancelScheduledDisconnect(peer.endpointID)
    let transfer = OutgoingTransfer(peer: peer, files: files.map { OutgoingFile(url: $0) })
    outgoing = transfer
    lastSendCompleted = false
    statusMessage = "Connecting to \(peer.name)…"
    appendLog("sending \(files.count) file(s) to \(peer.name)")
    let context = QuickShareAdvertisement.make(deviceName: deviceName)
    discoverer.requestConnection(
      to: peer.endpointID, using: context, mediums: transferMediums
    ) { [weak self] error in
      DispatchQueue.main.async {
        if let error = error {
          self?.appendLog("connect failed: \(error.localizedDescription)")
          self?.lastError = error.localizedDescription
          self?.outgoing = nil
        }
      }
    }
  }

  private func sendOutgoingPayloads(_ transfer: OutgoingTransfer, to endpointID: EndpointID) {
    guard !transfer.startedPayloads else { return }
    transfer.startedPayloads = true
    for file in transfer.files {
      appendLog("sending \(file.name) (\(file.size) bytes)")
      _ = connectionManager.sendResource(
        at: file.url, withName: file.name, to: [endpointID], id: file.payloadID
      ) { [weak self] error in
        if let error = error {
          DispatchQueue.main.async {
            self?.appendLog("send failed for \(file.name): \(error.localizedDescription)")
            self?.lastError = error.localizedDescription
          }
        }
      }
    }
  }

  private func scheduleAdvertisingRestart() {
    advertisingRestartWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      self?.restartAdvertising()
    }
    advertisingRestartWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
  }

  private func cancelScheduledAdvertisingRestart() {
    advertisingRestartWorkItem?.cancel()
    advertisingRestartWorkItem = nil
  }

  private func restartAdvertising() {
    advertisingRestartWorkItem = nil
    guard isReceiving else { return }
    if isStartingAdvertising {
      scheduleAdvertisingRestart()
      return
    }
    advertisingGeneration += 1
    let generation = advertisingGeneration
    advertiser.stopAdvertising { [weak self] error in
      DispatchQueue.main.async {
        guard let self = self, self.advertisingGeneration == generation else { return }
        self.isReceiving = false
        if let error = error {
          self.appendLog("stop advertising: \(error.localizedDescription)")
        }
        self.startAdvertising()
      }
    }
  }

  private func startAdvertising() {
    guard !isStartingAdvertising else { return }
    isStartingAdvertising = true
    let context = QuickShareAdvertisement.make(
      deviceName: deviceName, deviceType: .laptop)
    let mediums = transferMediums
    let transport = mediums.contains(.wifiLAN)
      ? "Wi-Fi LAN + BLE + Hotspot + Direct"
      : "BLE + Hotspot + Direct"

    statusMessage = "Advertising as \(deviceName)…"
    advertiser.startAdvertising(using: context, mediums: mediums) { [weak self] error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.isStartingAdvertising = false
        if let error = error {
          self.isReceiving = false
          self.lastError = error.localizedDescription
          self.statusMessage = "Could not start receiving"
          self.appendLog("start advertising failed: \(error.localizedDescription)")
        } else {
          self.isReceiving = true
          self.lastError = nil
          self.statusMessage = "Visible as \(self.deviceName)"
          self.appendLog("Advertising on \(transport) (_FC9F5ED42C8A._tcp)")
        }
      }
    }
  }

  private func send(_ frame: Nearby_Sharing_Service_Proto_Frame, to endpointID: EndpointID) {
    guard let data = FrameCodec.serialize(frame) else {
      appendLog("failed to serialize frame")
      return
    }
    _ = connectionManager.send(data, to: [endpointID])
  }

  private func handleOutgoing(
    frame: Nearby_Sharing_Service_Proto_Frame, from endpointID: EndpointID
  ) {
    appendLog("outgoing frame \(frame.v1.type) from \(endpointID)")
    guard let outgoing = outgoing, outgoing.peer.endpointID == endpointID else {
      appendLog("frame for unknown endpoint \(endpointID)")
      return
    }

    switch frame.v1.type {
    case .pairedKeyEncryption:
      send(FrameCodec.pairedKeyResult(.unable), to: endpointID)

    case .pairedKeyResult:
      if !outgoing.sentIntroduction {
        outgoing.sentIntroduction = true
        send(outgoing.introductionFrame, to: endpointID)
        statusMessage = "Waiting for \(outgoing.peer.name) to accept…"
      }

    case .response:
      let status = frame.v1.connectionResponse.status
      appendLog("peer response: \(status)")
      if status == .accept {
        statusMessage = "Sending to \(outgoing.peer.name)…"
        sendOutgoingPayloads(outgoing, to: endpointID)
      } else {
        appendLog("peer rejected the transfer (\(status))")
        statusMessage = "Transfer rejected"
        self.outgoing = nil

        scheduleDisconnect(
          endpointID: endpointID, after: 0, reason: "send rejected")
      }

    case .cancel:
      appendLog("peer cancelled the transfer")
      self.outgoing = nil
      scheduleDisconnect(
        endpointID: endpointID, after: 0, reason: "send cancelled")

    default:
      appendLog("unhandled outgoing frame \(frame.v1.type)")
    }
  }

  private func handle(frame: Nearby_Sharing_Service_Proto_Frame, from endpointID: EndpointID) {
    guard let session = sessions[endpointID] else {
      handleOutgoing(frame: frame, from: endpointID)
      return
    }

    switch frame.v1.type {
    case .pairedKeyEncryption:
      appendLog("paired key encryption from \(session.peerName)")
      send(FrameCodec.pairedKeyResult(.unable), to: endpointID)

    case .pairedKeyResult:
      appendLog("paired key result \(frame.v1.pairedKeyResult.status) from \(session.peerName)")
      if let outgoing = outgoing, outgoing.peer.endpointID == endpointID,
        !outgoing.sentIntroduction
      {
        outgoing.sentIntroduction = true
        send(outgoing.introductionFrame, to: endpointID)
        statusMessage = "Waiting for \(outgoing.peer.name) to accept…"
      }

    case .response:
      let status = frame.v1.connectionResponse.status
      appendLog("peer response: \(status)")
      if let outgoing = outgoing, outgoing.peer.endpointID == endpointID {
        if status == .accept {
          statusMessage = "Sending to \(outgoing.peer.name)…"
          sendOutgoingPayloads(outgoing, to: endpointID)
        } else {
          appendLog("peer rejected the transfer (\(status))")
          statusMessage = "Transfer rejected"
          outgoing.sentIntroduction = false
          self.outgoing = nil
          scheduleDisconnect(
            endpointID: endpointID, after: 0, reason: "send rejected")
        }
      }

    case .introduction:

      cancelScheduledDisconnect(endpointID)
      let introduction = frame.v1.introduction
      let attachments = introduction.incomingAttachments
      guard !attachments.isEmpty else {
        appendLog("introduction without supported attachments")
        send(FrameCodec.response(.unsupportedAttachmentType), to: endpointID)
        return
      }
      guard !session.approved, pendingApprovals[endpointID] == nil else { return }

      session.attachments = Dictionary(
        uniqueKeysWithValues: attachments.map { ($0.payloadID, $0) })
      session.introduced = true
      statusMessage = "Receiving \(attachments.count) item(s) from \(session.peerName)"
      appendLog(
        "introduction: \(attachments.map { "\($0.kind)/\($0.name)" }.joined(separator: ", "))")

      switch trustStore.decision(for: session.peerName) {
      case .block:
        appendLog("rejected transfer from blocked device \(session.peerName)")
        statusMessage = "Blocked \(session.peerName)"
        send(FrameCodec.response(.reject), to: endpointID)
        sessions.removeValue(forKey: endpointID)
        scheduleDisconnect(
          endpointID: endpointID, after: 2.0, reason: "device blocked")
      case .allow:
        appendLog("auto-accepting transfer from allowed device \(session.peerName)")
        session.approved = true
        statusMessage = "Receiving \(attachments.count) item(s) from \(session.peerName)"
        send(FrameCodec.response(.accept), to: endpointID)
      case .ask:
        requestApproval(for: session, endpointID: endpointID)
      }

    case .cancel:
      appendLog("peer \(session.peerName) cancelled the transfer")
      cancelPendingApproval(endpointID: endpointID, reason: "sender cancelled")
      sessions.removeValue(forKey: endpointID)

      scheduleDisconnect(
        endpointID: endpointID, after: 0, reason: "sender cancelled")

    case .bindings:
      appendLog("ignoring binding frame")

    default:
      appendLog("unhandled frame type \(frame.v1.type)")
    }
  }

  private func finishAttachment(
    session: TransferSession, payloadID: Int64, endpointID: EndpointID
  ) {
    guard let attachment = session.attachments[payloadID] else { return }
    guard !session.completedPayloads.contains(payloadID) else { return }

    let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser

    do {
      let item: ReceivedItem
      switch attachment.kind {
      case .file:
        let sourceURL = session.resourceURLs[payloadID]
        let data = session.payloadData[payloadID]
        guard sourceURL != nil || data != nil else { return }

        let preferred = DownloadNaming.sanitize(
          attachment.name.isEmpty
            ? (session.resourceNames[payloadID] ?? "Quick Share file")
            : attachment.name)
        let destination = DownloadNaming.uniqueURL(in: directory, preferredName: preferred)

        if let sourceURL = sourceURL, sourceURL.isFileURL {
          try FileManager.default.moveItem(at: sourceURL, to: destination)
        } else if let data = data {
          try data.write(to: destination)
        }

        item = ReceivedItem(
          name: destination.lastPathComponent, url: destination, date: Date(),
          kind: attachment.mimeType)
        appendLog("saved \(destination.lastPathComponent)")

      case .text:
        guard let data = session.payloadData[payloadID] else { return }
        let title = DownloadNaming.sanitize(attachment.name)
        let preferred = title.hasSuffix(".txt") ? title : "\(title).txt"
        let destination = DownloadNaming.uniqueURL(in: directory, preferredName: preferred)
        try data.write(to: destination)

        if session.attachments.count == 1,
          let string = String(data: data, encoding: .utf8)
        {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(string, forType: .string)
        }
        item = ReceivedItem(
          name: destination.lastPathComponent, url: destination, date: Date(), kind: "text")
        appendLog("saved text \(destination.lastPathComponent)")

      case .wifiCredentials:
        guard let data = session.payloadData[payloadID] else { return }
        let destination = DownloadNaming.uniqueURL(
          in: directory, preferredName: "Wi-Fi credentials.txt")
        try data.write(to: destination)
        item = ReceivedItem(
          name: destination.lastPathComponent, url: destination, date: Date(), kind: "wifi")
        appendLog("saved Wi-Fi credentials")
      }

      session.completedPayloads.insert(payloadID)
      receivedItems.insert(item, at: 0)
      statusMessage = session.pendingCount == 0
        ? "Transfer complete"
        : "Receiving \(session.pendingCount) item(s)…"
      if session.pendingCount == 0 {
        sessions.removeValue(forKey: endpointID)

        scheduleDisconnect(
          endpointID: endpointID, after: 0, reason: "transfer complete")
      }
    } catch {
      appendLog("failed to save attachment: \(error.localizedDescription)")
      lastError = error.localizedDescription
      send(FrameCodec.response(.notEnoughSpace), to: endpointID)
      scheduleDisconnect(
        endpointID: endpointID, after: 2.0, reason: "save failed")
    }
  }

  func appendLog(_ message: String) {
    let line = "\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))  \(message)"
    print("[QuickShare] \(line)")
    fflush(stdout)
    log.append(line)
    if log.count > 200 {
      log.removeFirst(log.count - 200)
    }
  }
}

extension QuickShareService: AdvertiserDelegate {
  func advertiser(
    _ advertiser: Advertiser, didReceiveConnectionRequestFrom endpointID: EndpointID,
    with context: Data, connectionRequestHandler: @escaping (Bool) -> Void
  ) {
    let advertisement = QuickShareAdvertisement.parse(context)
    let name = advertisement?.deviceName ?? "Nearby device"
    peerNames[endpointID] = name

    if trustStore.decision(for: name) == .block {
      appendLog("refused connection from blocked device \(name) (\(endpointID))")
      statusMessage = "Blocked \(name)"
      connectionRequestHandler(false)
      return
    }

    appendLog("connection request from \(name) (\(endpointID))")

    connectionRequestHandler(true)
  }
}

extension QuickShareService: DiscovererDelegate {
  func discoverer(
    _ discoverer: Discoverer, didFind endpointID: EndpointID, with context: Data
  ) {
    guard let advertisement = QuickShareAdvertisement.parse(context) else { return }
    let name = advertisement.deviceName.isEmpty
      ? "Nearby device \(endpointID.prefix(4))"
      : advertisement.deviceName
    if name == deviceName && !allowSameNamePeers {
      return
    }
    let peer = DiscoveredPeer(
      endpointID: endpointID, name: name, deviceType: advertisement.deviceType)
    if let index = peers.firstIndex(where: { $0.endpointID == endpointID }) {
      peers[index] = peer
    } else {
      peers.append(peer)
      appendLog("found \(name)")
      if outgoing == nil && isDiscovering {
        statusMessage = peers.count == 1
          ? "Found \(name)"
          : "Found \(peers.count) devices"
      }
    }
  }

  func discoverer(_ discoverer: Discoverer, didLose endpointID: EndpointID) {
    peers.removeAll { $0.endpointID == endpointID }
    if isDiscovering && peers.isEmpty {
      statusMessage = "Searching for nearby devices…"
    }
  }
}

extension QuickShareService: ConnectionManagerDelegate {
  func connectionManager(
    _ connectionManager: ConnectionManager, didChangeTo state: ConnectionState,
    for endpointID: EndpointID
  ) {
    switch state {
    case .connecting:
      statusMessage = "Connecting…"
      appendLog("connecting to \(endpointID)")

    case .connected:
      cancelScheduledDisconnect(endpointID)
      connectedEndpoints.insert(endpointID)
      if let outgoing = outgoing, outgoing.peer.endpointID == endpointID {
        appendLog("connected to \(outgoing.peer.name) for sending")
        statusMessage = "Connected to \(outgoing.peer.name)"
        send(FrameCodec.pairedKeyEncryption(), to: endpointID)
        return
      }

      let name = peerNames[endpointID] ?? sessions[endpointID]?.peerName ?? "Nearby device"
      let session = TransferSession(endpointID: endpointID, peerName: name)
      sessions[endpointID] = session
      appendLog("connected to \(name)")
      statusMessage = "Connected to \(name)"
      send(FrameCodec.pairedKeyEncryption(), to: endpointID)

    case .rejected:
      appendLog("connection rejected: \(endpointID)")
      cancelScheduledDisconnect(endpointID)
      connectedEndpoints.remove(endpointID)
      cancelPendingApproval(endpointID: endpointID, reason: "connection rejected")
      sessions.removeValue(forKey: endpointID)
      peerNames.removeValue(forKey: endpointID)
      if outgoing?.peer.endpointID == endpointID {
        outgoing = nil
      }
      statusMessage = "Connection rejected"

    case .disconnected:
      appendLog("disconnected: \(endpointID)")
      cancelScheduledDisconnect(endpointID)
      connectedEndpoints.remove(endpointID)
      cancelPendingApproval(endpointID: endpointID, reason: "peer disconnected")
      sessions.removeValue(forKey: endpointID)
      peerNames.removeValue(forKey: endpointID)
      if outgoing?.peer.endpointID == endpointID {
        outgoing = nil
      }
      if sessions.isEmpty {
        statusMessage = isReceiving ? "Visible as \(deviceName)" : "Paused"
      }

    @unknown default:
      break
    }
  }

  func connectionManager(
    _ connectionManager: ConnectionManager, didReceive data: Data, withID payloadID: PayloadID,
    from endpointID: EndpointID
  ) {
    appendLog("rx \(data.count)B id=\(payloadID) from \(endpointID)")

    if let session = sessions[endpointID], session.attachments[payloadID] != nil {
      guard session.approved else {
        appendLog("ignored payload \(payloadID) before transfer approval")
        return
      }
      session.payloadData[payloadID] = data
      if let attachment = session.attachments[payloadID] {
        let hasFileData = attachment.kind == .file && session.payloadData[payloadID] != nil
        if attachment.kind == .text || attachment.kind == .wifiCredentials
          || hasFileData || session.resourceURLs[payloadID] != nil
        {
          finishAttachment(session: session, payloadID: payloadID, endpointID: endpointID)
        }
      }
      return
    }

    guard let frame = try? FrameCodec.decode(data) else {
      appendLog("ignored \(data.count)-byte payload (id \(payloadID))")
      return
    }
    handle(frame: frame, from: endpointID)
  }

  func connectionManager(
    _ connectionManager: ConnectionManager, didReceive stream: InputStream,
    withID payloadID: PayloadID, from endpointID: EndpointID,
    cancellationToken token: CancellationToken
  ) {
    appendLog("ignoring stream payload \(payloadID)")
  }

  func connectionManager(
    _ connectionManager: ConnectionManager, didStartReceivingResourceWithID payloadID: PayloadID,
    from endpointID: EndpointID, at localURL: URL, withName name: String,
    cancellationToken token: CancellationToken
  ) {
    guard let session = sessions[endpointID] else { return }
    session.resourceURLs[payloadID] = localURL
    session.resourceNames[payloadID] = name
    appendLog("receiving resource \(name) (id \(payloadID))")
  }

  func connectionManager(
    _ connectionManager: ConnectionManager, didReceiveTransferUpdate update: TransferUpdate,
    from endpointID: EndpointID, forPayload payloadID: PayloadID
  ) {
    if let outgoing = outgoing, outgoing.peer.endpointID == endpointID,
      let file = outgoing.files.first(where: { $0.payloadID == payloadID })
    {
      switch update {
      case .success:
        outgoing.completedPayloads.insert(payloadID)
        appendLog("sent \(file.name)")
        if outgoing.completedPayloads.count == outgoing.files.count {
          statusMessage = "Sent to \(outgoing.peer.name)"
          appendLog("transfer complete")
          lastSendCompleted = true

          scheduleDisconnect(
            endpointID: endpointID, after: 60, reason: "send complete (fallback)")
          DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.outgoing === outgoing {
              self?.outgoing = nil
            }
          }
        }
      case .failure:
        appendLog("failed to send \(file.name)")
        lastError = "Failed to send \(file.name)"
        scheduleDisconnect(
          endpointID: endpointID, after: 0, reason: "send failed")
      case .canceled:
        appendLog("sending \(file.name) cancelled")
        scheduleDisconnect(
          endpointID: endpointID, after: 0, reason: "send cancelled")
      case .progress(let progress):
        statusMessage =
          "Sending \(file.name)… \(Int(progress.fractionCompleted * 100))%"
      }
      return
    }

    guard let session = sessions[endpointID] else { return }
    guard session.approved else { return }
    switch update {
    case .success:
      finishAttachment(session: session, payloadID: payloadID, endpointID: endpointID)
    case .canceled:
      appendLog("transfer cancelled for payload \(payloadID)")
      sessions.removeValue(forKey: endpointID)
      scheduleDisconnect(
        endpointID: endpointID, after: 0, reason: "transfer cancelled")
    case .failure:
      appendLog("transfer failed for payload \(payloadID)")
      lastError = "Transfer failed"
      sessions.removeValue(forKey: endpointID)
      scheduleDisconnect(
        endpointID: endpointID, after: 0, reason: "transfer failed")
    case .progress(let progress):
      if let attachment = session.attachments[payloadID] {
        statusMessage = "Receiving \(attachment.name)… \(Int(progress.fractionCompleted * 100))%"
      }
    }
  }
}

extension QuickShareService: UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    defer { completionHandler() }

    guard
      let endpointID = response.notification.request.content.userInfo[
        QuickShareNotification.endpointKey] as? String
    else { return }

    DispatchQueue.main.async {
      guard let pending = self.pendingApprovals[endpointID] else { return }
      let request = pending.request

      switch response.actionIdentifier {
      case QuickShareNotification.accept:
        self.approve(request)
      case QuickShareNotification.alwaysAllow:
        self.approve(request, alwaysAllow: true)
      case QuickShareNotification.decline:
        self.decline(request)
      case QuickShareNotification.block:
        self.decline(request, blockDevice: true)
      case UNNotificationDismissActionIdentifier:

        self.decline(request)
      case UNNotificationDefaultActionIdentifier:
        ApprovalPanelController.shared.show(request, service: self)
      default:
        break
      }
    }
  }
}
