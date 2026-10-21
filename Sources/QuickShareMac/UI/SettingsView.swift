import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject var service: QuickShareService
  @ObservedObject private var trust = DeviceTrustStore.shared
  @ObservedObject private var updates = UpdateChecker.shared
  @ObservedObject private var loginItem = LoginItem.shared

  var body: some View {
    TabView {
      Form {
        Section("Device") {
          TextField("Device name", text: $service.deviceName)
          Toggle("Receive from nearby devices", isOn: Binding(
            get: { service.isReceiving },
            set: { $0 ? service.start() : service.stop() }
          ))
        }

        Section("Startup") {
          Toggle("Launch at login", isOn: Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
          ))
          if loginItem.needsApproval {
            HStack {
              Text("Approve Quick Share in System Settings > General > Login Items.")
                .font(.caption)
                .foregroundStyle(.secondary)
              Button("Open Login Items") {
                loginItem.openSystemSettings()
              }
            }
          }
          if let error = loginItem.lastError {
            Text(error)
              .font(.caption)
              .foregroundStyle(.red)
          }
        }

        Section("Transports") {
          Toggle("Bluetooth LE", isOn: $service.bleEnabled)
          Toggle("Wi-Fi LAN", isOn: $service.wifiLanEnabled)
          Toggle("Wi-Fi Hotspot", isOn: $service.wifiHotspotEnabled)
          Toggle("Wi-Fi Direct", isOn: $service.wifiDirectEnabled)
          Text("Changes restart advertising and apply to new connections.")
            .font(.caption)
            .foregroundStyle(.secondary)
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
      }
      .padding()
      .tabItem { Label("Log", systemImage: "text.alignleft") }
    }
    .frame(width: 480, height: 420)
    .onAppear {
      service.refreshNotificationAuthorization()
      loginItem.refresh()
    }
  }

  private var notificationStatus: String {
    switch service.notificationsAllowed {
    case true?: return "Allowed"
    case false?: return "Denied or unavailable"
    case nil: return "Unknown"
    }
  }
}
