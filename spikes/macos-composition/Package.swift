// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "RelayContextComposition", platforms: [.macOS(.v15)],
    products: [.library(name: "RelayContextComposition", targets: ["RelayContextComposition"])],
    dependencies: [.package(path: "../macos-session"), .package(path: "../macos-context"), .package(path: "../macos-controls")],
    targets: [
        .target(name: "RelayContextComposition", dependencies: [.product(name: "RelayNativeSession", package: "macos-session"), .product(name: "RelayScreenContext", package: "macos-context"), .product(name: "RelayControls", package: "macos-controls")]),
        .testTarget(name: "RelayContextCompositionTests", dependencies: ["RelayContextComposition"]),
    ])
