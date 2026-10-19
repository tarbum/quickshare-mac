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
    .package(
      name: "NearbyConnections",
      url: "https://github.com/tarbum/nearby.git",
      revision: "0736243f3176baa3542cc70591afc88da1409799"
    ),
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.39.0"),
  ],
  targets: [
    .executableTarget(
      name: "QuickShareMac",
      dependencies: [
        .product(name: "NearbyConnections", package: "NearbyConnections"),
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ],
      path: "Sources/QuickShareMac",
      swiftSettings: [
        .swiftLanguageMode(.v5)
      ]
    )
  ]
)
