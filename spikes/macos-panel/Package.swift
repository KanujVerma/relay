// swift-tools-version: 6.0
import PackageDescription

// Isolated mock-only UI spike. Does not link Core Audio, ASR, OAuth, or inference.
let package = Package(
    name: "RelayPanelPrototype",
    platforms: [.macOS("14.2")],
    products: [
        .library(name: "RelayPanelState", targets: ["RelayPanelState"]),
        .library(name: "RelaySessionPanel", targets: ["RelaySessionPanel"]),
        .executable(name: "relay-panel-session", targets: ["RelayPanelSession"]),
        .executable(name: "relay-panel-demo", targets: ["RelayPanelDemo"]),
    ],
    dependencies: [.package(path: "../macos-session"), .package(path: "../macos-profile"), .package(path: "../macos-audio")],
    targets: [
        .target(name: "RelayPanelState"),
        .target(name: "RelaySessionPanel", dependencies: [.product(name: "RelayNativeSession", package: "macos-session")]),
        .executableTarget(name: "RelayPanelSession", dependencies: ["RelaySessionPanel", .product(name:"RelaySessionCapture",package:"macos-session"), .product(name:"RelayProfile",package:"macos-profile"), .product(name:"RelayAudioBuffer",package:"macos-audio")]),
        .testTarget(name: "RelaySessionPanelTests", dependencies: ["RelaySessionPanel"]),
        .executableTarget(name: "RelayPanelDemo", dependencies: ["RelayPanelState"]),
        .testTarget(name: "RelayPanelStateTests", dependencies: ["RelayPanelState"]),
    ]
)
