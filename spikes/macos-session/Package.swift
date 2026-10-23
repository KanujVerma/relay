// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RelayNativeSession",
    platforms: [.macOS("14.2")],
    products: [
        .library(name: "RelayNativeSession", targets: ["RelayNativeSession"]),
        .library(name: "RelaySessionCapture", targets: ["RelaySessionCapture"]),
        .executable(name: "relay-native-session", targets: ["RelaySessionCLI"])
    ],
    dependencies: [
        .package(path: "../macos-audio"), .package(path: "../macos-audio/asr"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "c79c4106b954f81205113c3343e5a7e59a1089b5")
    ],
    targets: [
        .target(name: "RelayNativeSession", dependencies: [
            .product(name: "RelayAudioBuffer", package: "macos-audio")
        ]),
        .target(name: "RelaySessionCapture", dependencies: ["RelayNativeSession",
            .product(name: "RelayLocalASR", package: "asr"),
            .product(name: "RelayAudioBuffer", package: "macos-audio"),
            .product(name: "FluidAudio", package: "FluidAudio")]),
        .executableTarget(name: "RelaySessionCLI", dependencies: ["RelaySessionCapture", "RelayNativeSession"]),
        .testTarget(name: "RelayNativeSessionTests", dependencies: ["RelayNativeSession"]),
        .testTarget(name: "RelaySessionCaptureTests", dependencies: ["RelaySessionCapture",
            .product(name: "RelayLocalASR", package: "asr"),
            .product(name: "RelayAudioBuffer", package: "macos-audio")])
    ]
)
