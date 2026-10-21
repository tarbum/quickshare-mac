import SwiftUI
import AppKit

@main
struct QuickShareMacApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var service = QuickShareService.shared

  var body: some Scene {
    MenuBarExtra {
      MenuView(service: service)
    } label: {
      Image(systemName: service.isReceiving
        ? "arrow.left.arrow.right.circle.fill"
        : "arrow.left.arrow.right.circle")
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(service: service)
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var testSender: SelfTestSender?

  func applicationDidFinishLaunching(_ notification: Notification) {
    Diagnostics.start()
    LocationPermission.shared.request()
    QuickShareService.shared.configureNotifications()
    NSApp.servicesProvider = ServicesProvider.shared
    NSUpdateDynamicServices()
    let args = CommandLine.arguments
    if args.contains("--no-wifi-lan") {
      QuickShareService.shared.wifiLanEnabled = false
    }
    if args.contains("--scan-wifi") {
      HotspotDiagnostics.scan()
      return
    }
    if let index = args.firstIndex(of: "--join-hotspot"), index + 2 < args.count {
      HotspotDiagnostics.join(ssid: args[index + 1], password: args[index + 2])
      return
    }
    if let index = args.firstIndex(of: "--send-test") {
      let target = index + 1 < args.count ? args[index + 1] : nil
      let sender = SelfTestSender(targetName: target)
      testSender = sender
      sender.start()
    } else if let index = args.firstIndex(of: "--send-file"), index + 1 < args.count {
      let path = args[index + 1]
      let target = index + 2 < args.count ? args[index + 2] : nil
      let service = QuickShareService.shared
      service.allowSameNamePeers = true
      service.startDiscovery()
      let deadline = Date().addingTimeInterval(40)
      var sent = false
      Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
        if !sent,
          let peer = service.peers.first(where: { target == nil || $0.name == target })
        {
          sent = true
          service.send(files: [URL(fileURLWithPath: path)], to: peer)
        }
        if service.lastSendCompleted {
          timer.invalidate()
          print("[send-file] complete")
          exit(0)
        }
        if Date() > deadline {
          timer.invalidate()
          print("[send-file] timeout; peers=\(service.peers.map(\.name))")
          exit(2)
        }
      }
    } else {
      QuickShareService.shared.start()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    QuickShareService.shared.stop()
  }
}

struct MenuView: View {
  @ObservedObject var service: QuickShareService
  @Environment(\.openSettings) private var openSettings
  @State private var showPeerPicker = false
  @State private var filesToSend: [URL] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: "arrow.left.arrow.right.circle.fill")
          .font(.title2)
        VStack(alignment: .leading, spacing: 2) {
          Text("Quick Share").font(.headline)
          Text(service.statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        Spacer()
        Toggle("", isOn: Binding(
          get: { service.isReceiving },
          set: { $0 ? service.start() : service.stop() }
        ))
        .toggleStyle(.switch)
        .labelsHidden()
      }

      if let error = service.lastError {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
          .lineLimit(2)
      }

      ForEach(service.incomingRequests) { request in
        VStack(alignment: .leading, spacing: 6) {
          Text("Incoming from \(request.peerName)")
            .font(.callout).bold()
          Text(request.summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(3)
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
            Button("Block") {
              service.decline(request, blockDevice: true)
            }
          }
          .font(.caption)
        }
      }

      Divider()

      if service.receivedItems.isEmpty {
        Text("Waiting for files")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Text("Recent").font(.caption).foregroundStyle(.secondary)
        ForEach(service.receivedItems.prefix(5)) { item in
          HStack(spacing: 8) {
            Image(systemName: icon(for: item.kind))
            VStack(alignment: .leading, spacing: 1) {
              Text(item.name).font(.callout).lineLimit(1)
              Text(item.date, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
              NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
              Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
          }
        }
      }

      Divider()

      HStack {
        Button("Send Files…") {
          let panel = NSOpenPanel()
          panel.allowsMultipleSelection = true
          panel.canChooseFiles = true
          panel.canChooseDirectories = false
          panel.prompt = "Send"
          if panel.runModal() == .OK, !panel.urls.isEmpty {
            filesToSend = panel.urls
            service.startDiscovery()
            showPeerPicker = true
          }
        }
        Button("Downloads") {
          if let url = FileManager.default.urls(
            for: .downloadsDirectory, in: .userDomainMask).first
          {
            NSWorkspace.shared.open(url)
          }
        }
        Spacer()
        Button {
          if let url = URL(string: "https://www.buymeacoffee.com/tarbum") {
            NSWorkspace.shared.open(url)
          }
        } label: {
          Image(systemName: "cup.and.saucer.fill")
            .foregroundStyle(.orange)
        }
        .buttonStyle(.borderless)
        .help("Buy me a coffee")
        .accessibilityLabel("Buy me a coffee")
        Button {
          UpdateChecker.shared.checkForUpdates(manual: true)
        } label: {
          Image(systemName: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.borderless)
        .help("Check for Updates")
        Button {

          NSApplication.shared.activate(ignoringOtherApps: true)
          openSettings()
        } label: {
          Image(systemName: "gearshape")
        }
        .buttonStyle(.borderless)
        Button {
          NSApplication.shared.terminate(nil)
        } label: {
          Image(systemName: "power")
        }
        .buttonStyle(.borderless)
      }
      .font(.caption)
    }
    .padding(14)
    .frame(width: 340)
    .sheet(isPresented: $showPeerPicker, onDismiss: {
      service.stopDiscovery()
    }) {
      PeerPickerView(service: service, files: filesToSend)
    }
  }

  private func icon(for kind: String) -> String {
    if kind.hasPrefix("image/") { return "photo" }
    if kind.hasPrefix("video/") { return "film" }
    if kind.hasPrefix("audio/") { return "music.note" }
    if kind == "text" { return "doc.text" }
    if kind == "wifi" { return "wifi" }
    return "doc"
  }
}
