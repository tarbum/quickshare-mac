import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject var service: QuickShareService
  @ObservedObject private var trust = DeviceTrustStore.shared
  @ObservedObject private var updates = UpdateChecker.shared
  @State private var chunkKiB = TransferTuning.chunkSizeKiB

  var body: some View {
    TabView {
      Form {
        Section("Device") {
          TextField("Device name", text: $service.deviceName)
          Toggle("Receive from nearby devices", isOn: Binding(
            get: { service.isReceiving },
            set: { $0 ? service.start() : service.stop() }
          ))
          Toggle("Advertise over Bluetooth LE", isOn: $service.bleEnabled)
        }

        Section("Approval") {
          Toggle("Ask before receiving", isOn: $trust.askBeforeReceiving)
          Text(
            "When off, unknown devices are accepted automatically. Blocked devices are always refused."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          LabeledContent("Notifications", value: notificationStatus)
          Button("Open Notification Settings") {
            if let url = URL(
              string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
            {
              NSWorkspace.shared.open(url)
            }
          }
        }

        Section("Updates") {
          LabeledContent("Current version", value: updates.currentVersion)
          HStack {
            Button("Check Now") {
              updates.checkForUpdates(manual: true)
            }
            if updates.isChecking {
              ProgressView().controlSize(.small)
            }
          }
          if let error = updates.lastError {
            Text(error).font(.caption).foregroundStyle(.red)
          }
        }

        Section("Always allowed") {
          if trust.allowedDevices.isEmpty {
            Text("No devices").foregroundStyle(.secondary)
          } else {
            ForEach(trust.allowedDevices, id: \.self) { name in
              HStack {
                Text(name)
                Spacer()
                Button {
                  trust.removeAllowed(name)
                } label: {
                  Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
              }
            }
          }
        }

        Section("Blocked") {
          if trust.blockedDevices.isEmpty {
            Text("No devices").foregroundStyle(.secondary)
          } else {
            ForEach(trust.blockedDevices, id: \.self) { name in
              HStack {
                Text(name)
                Spacer()
                Button {
                  trust.removeBlocked(name)
                } label: {
                  Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
              }
            }
          }
        }

        Section("Status") {
          Text(service.statusMessage)
          if let error = service.lastError {
            Text(error).foregroundStyle(.red)
          }
        }

        Section("Diagnostics") {
          LabeledContent("Log file") {
            Text(Diagnostics.logURL.path)
              .font(.caption)
              .textSelection(.enabled)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          HStack {
            Button("Reveal Log in Finder") { Diagnostics.revealLog() }
            Button("Copy Path") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(Diagnostics.logURL.path, forType: .string)
            }
          }
          Text(
            "Includes framework logs (Wi-Fi scan/join attempts, medium upgrades) and per-transfer throughput."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Picker("Payload chunk size", selection: $chunkKiB) {
            ForEach(TransferTuning.chunkSizeChoices, id: \.self) { kib in
              Text(TransferTuning.label(for: kib)).tag(kib)
            }
          }
          .onChange(of: chunkKiB) { _, value in
            TransferTuning.chunkSizeKiB = value
          }
          Text(
            "Larger chunks cut per-frame overhead on Wi-Fi (LAN, hotspot, direct); BLE is unaffected. Applies to new connections. Frames stay under the 1 MiB peer read limit."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Section("Protocol") {
          LabeledContent("Service ID", value: "NearbySharing")
          LabeledContent("mDNS", value: "_FC9F5ED42C8A._tcp")
          LabeledContent(
            "Transport",
            value: service.bleEnabled
              ? "Wi-Fi LAN + BLE + Hotspot + Direct"
              : "Wi-Fi LAN + Hotspot + Direct")
          LabeledContent("Hotspot / Direct", value: "Client / join only")
          LabeledContent("Visibility", value: "Everyone on this network")
        }
      }
      .formStyle(.grouped)
      .tabItem { Label("General", systemImage: "gearshape") }

      VStack(alignment: .leading) {
        ScrollView {
          Text(service.log.joined(separator: "\n"))
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        HStack {
          Button("Reveal Full Log") { Diagnostics.revealLog() }
          Spacer()
        }
      }
      .padding()
      .tabItem { Label("Log", systemImage: "text.alignleft") }
    }
    .frame(width: 480, height: 420)
    .onAppear { service.refreshNotificationAuthorization() }
  }

  private var notificationStatus: String {
    switch service.notificationsAllowed {
    case true?: return "Allowed"
    case false?: return "Denied or unavailable"
    case nil: return "Unknown"
    }
  }
}
