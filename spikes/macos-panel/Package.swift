// swift-tools-version: 6.0
import PackageDescription

// Isolated mock-only UI spike. Does not link Core Audio, ASR, OAuth, or inference.
let package = Package(
    name: "RelayPanelPrototype",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RelayPanelState", targets: ["RelayPanelState"]),
        .executable(name: "relay-panel-demo", targets: ["RelayPanelDemo"]),
    ],
    targets: [
        .target(name: "RelayPanelState"),
        .executableTarget(name: "RelayPanelDemo", dependencies: ["RelayPanelState"]),
        .testTarget(name: "RelayPanelStateTests", dependencies: ["RelayPanelState"]),
    ]
)
