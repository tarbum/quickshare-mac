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

If you want it to start automatically, enable **Launch at login** in Quick Share
settings.

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

The Nearby Connections dependency is pinned to a specific commit of
`tarbum/nearby`; SwiftPM fetches it automatically.

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
