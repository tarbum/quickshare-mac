import AppKit
import SwiftUI

final class ApprovalPanelController {
  static let shared = ApprovalPanelController()

  private var panel: NSPanel?

  func show(_ request: IncomingRequest, service: QuickShareService) {
    DispatchQueue.main.async {
      self.close()
      let view = ApprovalPromptView(request: request, service: service)
      let hosting = NSHostingView(rootView: view)
      let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 460, height: 190),
        styleMask: [.titled], backing: .buffered, defer: false)
      panel.title = "Incoming Quick Share"
      panel.level = .floating
      panel.isFloatingPanel = true
      panel.hidesOnDeactivate = false
      panel.isMovableByWindowBackground = true
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      panel.standardWindowButton(.closeButton)?.isHidden = true
      panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
      panel.standardWindowButton(.zoomButton)?.isHidden = true
      panel.contentView = hosting
      panel.center()
      panel.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
      self.panel = panel
    }
  }

  func close() {
    panel?.orderOut(nil)
    panel = nil
  }
}

private struct ApprovalPromptView: View {
  let request: IncomingRequest
  @ObservedObject var service: QuickShareService

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Image(systemName: "arrow.down.circle.fill")
          .font(.system(size: 34))
          .foregroundStyle(.tint)
        VStack(alignment: .leading, spacing: 3) {
          Text(request.peerName).font(.headline)
          Text("wants to send you something")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }

      Text(request.summary)
        .font(.callout)
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)

      HStack(spacing: 8) {
        Button("Accept") {
          service.approve(request)
        }
        Button("Always Allow") {
          service.approve(request, alwaysAllow: true)
        }
        Button("Decline") {
          service.decline(request)
        }
        .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Block") {
          service.decline(request, blockDevice: true)
        }
      }
    }
    .padding(20)
    .frame(width: 460)
  }
}
