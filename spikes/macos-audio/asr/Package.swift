// swift-tools-version: 6.0
import PackageDescription

// Optional, isolated ASR package. The existing microphone/system-audio SwiftPM
// package stays lightweight and does not download ASR model weights in CI.
// FluidAudio source is pinned; the model weights have a DIFFERENT NVIDIA license.
let package = Package(
    name: "RelayLocalASR",
    platforms: [.macOS("14.2")],
    products: [
        .library(name: "RelayLocalASR", targets: ["RelayLocalASR"]),
        .executable(name: "relay-asr-spike", targets: ["RelayLocalASRCLI"])
    ],
    dependencies: [
        .package(path: ".."),
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            revision: "c79c4106b954f81205113c3343e5a7e59a1089b5"
        )
    ],
    targets: [
        .target(
            name: "RelayLocalASR",
            dependencies: [
                .product(name: "RelayAudioBuffer", package: "RelayAudioSpike"),
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        ),
        .executableTarget(
            name: "RelayLocalASRCLI",
            dependencies: [
                "RelayLocalASR",
                .product(name: "RelayAudioBuffer", package: "RelayAudioSpike")
            ]
        ),
        .testTarget(
            name: "RelayLocalASRTests",
            dependencies: [
                "RelayLocalASR",
                .product(name: "RelayAudioBuffer", package: "RelayAudioSpike")
            ]
        )
    ]
)
