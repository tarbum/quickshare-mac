import AppKit
import SwiftUI

final class SendPanelController: NSObject, NSWindowDelegate {
  static let shared = SendPanelController()

  private var panel: NSPanel?
  private weak var service: QuickShareService?

  func show(files: [URL], service: QuickShareService) {
    DispatchQueue.main.async {
      self.close()
      self.service = service
      let view = PeerPickerView(
        service: service, files: files,
        onClose: { [weak self] in self?.close() })
      let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
      panel.title = "Send with Quick Share"
      panel.isReleasedWhenClosed = false
      panel.isMovableByWindowBackground = true
      panel.level = .floating
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      panel.delegate = self
      panel.contentView = NSHostingView(rootView: view)
      panel.center()
      panel.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
      self.panel = panel
    }
  }

  func close() {
    guard let panel = panel else { return }
    self.panel = nil
    panel.delegate = nil
    panel.close()
    service?.stopDiscovery()
  }

  func windowWillClose(_ notification: Notification) {
    panel = nil
    service?.stopDiscovery()
  }
}
