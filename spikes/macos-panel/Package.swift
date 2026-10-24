// swift-tools-version: 6.2
import PackageDescription

// Ordinary session app and independently testable panel state.
let package = Package(
    name: "RelayPanelPrototype",
    platforms: [.macOS("15.2")],
    products: [
        .library(name: "RelayPanelState", targets: ["RelayPanelState"]),
        .library(name: "RelaySessionPanel", targets: ["RelaySessionPanel"]),
        .executable(name: "relay-panel-session", targets: ["RelayPanelSession"]),
        .executable(name: "relay-panel-demo", targets: ["RelayPanelDemo"]),
    ],
    dependencies: [.package(path: "../macos-session"), .package(path: "../macos-profile"), .package(path: "../macos-account"), .package(path: "../macos-audio"), .package(path:"../macos-composition"), .package(path:"../macos-context"), .package(path:"../macos-controls")],
    targets: [
        .target(name: "RelayPanelState"),
        .target(name: "RelaySessionPanel", dependencies: [.product(name: "RelayNativeSession", package: "macos-session"), .product(name:"RelayContextComposition",package:"macos-composition"), .product(name:"RelayAccount",package:"macos-account")]),
        .executableTarget(name: "RelayPanelSession", dependencies: ["RelaySessionPanel", .product(name:"RelaySessionCapture",package:"macos-session"), .product(name:"RelayProfile",package:"macos-profile"), .product(name:"RelayAccount",package:"macos-account"), .product(name:"RelayAudioBuffer",package:"macos-audio"), .product(name:"RelayContextComposition",package:"macos-composition"), .product(name:"RelayScreenContext",package:"macos-context"), .product(name:"RelayControls",package:"macos-controls")]),
        .testTarget(name: "RelaySessionPanelTests", dependencies: ["RelaySessionPanel",.product(name:"RelayProfile",package:"macos-profile"),.product(name:"RelayAccount",package:"macos-account")]),
        .executableTarget(name: "RelayPanelDemo", dependencies: ["RelayPanelState"]),
        .testTarget(name: "RelayPanelStateTests", dependencies: ["RelayPanelState"]),
        .testTarget(name:"RelaySessionApplicationTests",dependencies:["RelayPanelSession"]),
    ]
)
