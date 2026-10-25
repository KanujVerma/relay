// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RelayControls",
    platforms: [.macOS(.v15)],
    products: [.library(name: "RelayControls", targets: ["RelayControls"])],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", revision: "772133d9dbe800fdac0473226822994c5c162c58"),
    ],
    targets: [
        .target(name: "RelayControls", dependencies: ["KeyboardShortcuts"]),
        .testTarget(name: "RelayControlsTests", dependencies: ["RelayControls"]),
    ]
)
