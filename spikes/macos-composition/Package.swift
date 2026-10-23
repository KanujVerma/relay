// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "RelayContextComposition", platforms: [.macOS(.v15)],
    products: [.library(name: "RelayContextComposition", targets: ["RelayContextComposition"])],
    dependencies: [.package(path: "../macos-session")],
    targets: [
        .target(name: "RelayContextComposition", dependencies: [.product(name: "RelayNativeSession", package: "macos-session")]),
        .testTarget(name: "RelayContextCompositionTests", dependencies: ["RelayContextComposition"]),
    ])
