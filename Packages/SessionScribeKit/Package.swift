// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SessionScribeKit",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "SSCore", targets: ["SSCore"]),
        .library(name: "SSAudio", targets: ["SSAudio"]),
        .library(name: "SSTranscription", targets: ["SSTranscription"]),
        .library(name: "SSUI", targets: ["SSUI"]),
    ],
    targets: [
        .target(name: "SSCore"),
        .target(name: "SSAudio", dependencies: ["SSCore"]),
        .target(name: "SSTranscription", dependencies: ["SSCore"]),
        .target(name: "SSUI", dependencies: ["SSCore", "SSAudio", "SSTranscription"]),
        .testTarget(name: "SSCoreTests", dependencies: ["SSCore"]),
        .testTarget(name: "SSAudioTests", dependencies: ["SSAudio"]),
        .testTarget(name: "SSTranscriptionTests", dependencies: ["SSTranscription", "SSAudio"]),
    ]
)
