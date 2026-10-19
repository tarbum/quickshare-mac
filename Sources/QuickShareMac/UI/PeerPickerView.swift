import SwiftUI

struct PeerPickerView: View {
  @ObservedObject var service: QuickShareService
  let files: [URL]
  var onClose: (() -> Void)? = nil
  @Environment(\.dismiss) private var dismiss

  private func close() {
    if let onClose = onClose {
      onClose()
    } else {
      dismiss()
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Send to a nearby device").font(.headline)
          Text(files.map(\.lastPathComponent).joined(separator: ", "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        Spacer()
        Button("Cancel") { close() }
      }

      Divider()

      if service.peers.isEmpty {
        HStack(spacing: 10) {
          ProgressView().controlSize(.small)
          Text("Searching for nearby devices…")
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
      } else {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(service.peers) { peer in
              Button {
                service.send(files: files, to: peer)
                close()
              } label: {
                HStack {
                  Image(systemName: "laptopcomputer.and.iphone")
                  VStack(alignment: .leading, spacing: 1) {
                    Text(peer.name)
                    Text(peer.endpointID)
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                  }
                  Spacer()
                  Image(systemName: "paperplane")
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              Divider()
            }
          }
        }
        .frame(minHeight: 140, maxHeight: 240)
      }

      Text("The other device must have Quick Share open and visible.")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .padding(16)
    .frame(width: 380)
    .onAppear { service.startDiscovery() }
    .onDisappear { service.stopDiscovery() }
  }
}
