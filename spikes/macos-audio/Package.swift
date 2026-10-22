// swift-tools-version: 6.0
import PackageDescription

// Mac-only audio spike. Pinned single-producer/single-consumer ring, rather
// than another home-grown lock-free queue. The upstream zlib-style license
// remains in the dependency; see README.md for source/attribution.
let package = Package(
    name: "RelayAudioSpike",
    platforms: [.macOS("14.2")],
    products: [
        .library(name: "RelayAudioBuffer", targets: ["RelayAudioBuffer"]),
        .executable(name: "relay-audio-spike", targets: ["RelayAudioSpike"])
    ],
    dependencies: [
        .package(url: "https://github.com/michaeltyson/TPCircularBuffer.git",
                 revision: "cc520397504bb72bc6df79ff03eb72988a6dc50d")
    ],
    targets: [
        .target(
            name: "RelayAudioBuffer",
            dependencies: [
                .product(name: "TPCircularBuffer", package: "TPCircularBuffer")
            ]
        ),
        .executableTarget(
            name: "RelayAudioSpike",
            dependencies: ["RelayAudioBuffer"]
        ),
        .testTarget(
            name: "RelayAudioBufferTests",
            dependencies: ["RelayAudioBuffer"]
        )
    ]
)
