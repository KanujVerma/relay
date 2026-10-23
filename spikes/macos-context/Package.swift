// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RelayScreenContext",
    platforms: [.macOS(.v14)],
    products: [.library(name: "RelayScreenContext", targets: ["RelayScreenContext"])],
    targets: [
        .target(name: "RelayScreenContext"),
        .testTarget(name: "RelayScreenContextTests", dependencies: ["RelayScreenContext"], resources: [.copy("Fixtures")]),
    ]
)
