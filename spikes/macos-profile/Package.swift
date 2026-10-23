// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RelayProfilePreparation",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RelayProfile", targets: ["RelayProfile"]),
        .executable(name: "relay-profile-prep", targets: ["RelayProfileDemo"]),
    ],
    targets: [
        .target(name: "RelayProfile"),
        .executableTarget(name: "RelayProfileDemo", dependencies: ["RelayProfile"]),
        .testTarget(name: "RelayProfileTests", dependencies: ["RelayProfile"]),
    ]
)
