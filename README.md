# Quick Share for macOS

A native macOS Quick Share client for sending and receiving files with nearby
Android, Windows, and ChromeOS devices.

It uses Google's open-source
[Nearby Connections](https://github.com/google/nearby) transport, with macOS
support maintained in the
[`tarbum/nearby`](https://github.com/tarbum/nearby/tree/macos-port) fork.

No Wine, Windows VM, or third-party Quick Share UI is involved.

<a href="https://www.buymeacoffee.com/tarbum">
  <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="40">
</a>

If you find this useful, you can buy me a coffee. Donations go toward a paid
Apple Developer Program membership and a Developer ID certificate, so releases
can be properly signed and notarized.

## AI disclosure

Development of this project was assisted by AI tools.

## Requirements

- macOS 14 or newer
- Apple Silicon Mac for the current release build
- Xcode with Swift 6 to build from source

## Installing

Download the latest DMG from
[GitHub Releases](https://github.com/tarbum/quickshare-mac/releases/latest).

1. Open the DMG.
2. Drag **QuickShareMac.app** to `/Applications`.
3. Because the build is not notarized, macOS may block the first launch:
   - Right-click the app → **Open**, or
   - Open **System Settings → Privacy & Security → Open Anyway**
4. Allow the requested permissions:
   - **Local Network** for mDNS discovery and transfers
   - **Bluetooth** for BLE discovery
   - **Location** for CoreWLAN hotspot/Wi-Fi Direct joins
   - **Notifications** optionally; the in-app approval panel is used if
     notifications are unavailable

To receive files, leave the app running in the menu bar.

If you want it to start automatically, add it under
**System Settings → General → Login Items**.

## Using Quick Share

- **Receive** — leave the app running in the menu bar. Incoming transfers prompt
  to Accept, Always Allow, Decline, or Block.
- **Send** — menu bar → **Send Files…**, or Finder → right-click →
  **Services → Send with Quick Share**.
- **Manage devices** — **Settings → General → Approval**.

## Building from source

```sh
git clone https://github.com/tarbum/quickshare-mac.git
cd quickshare-mac
./build_app.sh
```

The build script creates:

```
QuickShareMac.app
QuickShareMac.zip
QuickShareMac.dmg
```

The Nearby Connections dependency tracks the
[`debug-logging`](https://github.com/tarbum/nearby/tree/debug-logging) branch of
`tarbum/nearby`, which carries diagnostics patches to the transport (framework
logs to `os_log`, bounded and serialized hotspot joins, chunk-size override).
`./build_app.sh` refreshes it to the branch tip before building, so no sibling
checkout is needed; `Package.resolved` records the revision the last build used.

```sh
git clone https://github.com/tarbum/quickshare-mac.git
cd quickshare-mac && ./build_app.sh
```

## Diagnostics

A rotating log is written to `~/Library/Logs/QuickShareMac/QuickShareMac.log`.
It captures the app's activity list, per-transfer throughput (MB/s, per second),
partial-transfer state, and the Nearby Connections framework's own logs
(medium selection, Wi-Fi Direct/hotspot joins, scan results), which are
otherwise sent to a stderr that GUI apps never see.

From a terminal, the same framework logs are also visible in unified logging:

```sh
log stream --level debug --predicate 'subsystem == "com.google.nearby"'
```

**Settings → General → Diagnostics** reveals the file in Finder.

## Limitations

- The Mac cannot host Wi-Fi Direct or a hotspot
- Both devices must share a LAN or the peer must offer a direct upgrade
- Device allow/block decisions are based on advertised device names
- The current release build is arm64 only
- Notifications may be unavailable; the fallback approval panel still works
- The app is not sandboxed and needs Local Network, Bluetooth, and Location
  permissions for full functionality

## Dependencies

- [`tarbum/nearby`](https://github.com/tarbum/nearby/tree/macos-port) — fork of
  Google Nearby Connections with the macOS Quick Share changes (Apache-2.0)
- [SwiftProtobuf](https://github.com/apple/swift-protobuf)

## License

Apache License 2.0. See `LICENSE` and `NOTICE`.

## Links

- Repository: https://github.com/tarbum/quickshare-mac
- Releases: https://github.com/tarbum/quickshare-mac/releases
- Buy me a coffee: https://www.buymeacoffee.com/tarbum
