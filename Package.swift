// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Qwen3TTSStudio",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Qwen3TTSStudio",
            path: "Sources"
        )
    ]
)
