// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RelayNativeSession",
    platforms: [.macOS("14.2")],
    products: [.library(name: "RelayNativeSession", targets: ["RelayNativeSession"])],
    dependencies: [.package(path: "../macos-audio")],
    targets: [
        .target(name: "RelayNativeSession", dependencies: [
            .product(name: "RelayAudioBuffer", package: "macos-audio")
        ]),
        .testTarget(name: "RelayNativeSessionTests", dependencies: ["RelayNativeSession"])
    ]
)
