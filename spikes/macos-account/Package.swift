// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RelayAccountSetup",
    platforms: [.macOS("15.2")],
    products: [.library(name: "RelayAccount", targets: ["RelayAccount"])],
    dependencies: [.package(path: "../macos-profile")],
    targets: [
        .target(name: "RelayAccount", dependencies: [.product(name: "RelayProfile", package: "macos-profile")]),
        .testTarget(name: "RelayAccountTests", dependencies: ["RelayAccount"]),
    ]
)
