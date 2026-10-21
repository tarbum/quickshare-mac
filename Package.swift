// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "QuickShareMac",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "QuickShareMac", targets: ["QuickShareMac"])
  ],
  dependencies: [
    // Fork with the diagnostics patches (framework logs to os_log, bounded and
    // serialized hotspot joins, payload chunk-size override). Tracking the
    // branch means local builds pick up fork changes; Package.resolved records
    // the revision each build actually used.
    .package(
      url: "https://github.com/tarbum/nearby.git",
      branch: "debug-logging"
    ),
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.39.0"),
  ],
  targets: [
    .executableTarget(
      name: "QuickShareMac",
      dependencies: [
        .product(name: "NearbyConnections", package: "nearby"),
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ],
      path: "Sources/QuickShareMac",
      swiftSettings: [
        .swiftLanguageMode(.v5)
      ]
    )
  ]
)
