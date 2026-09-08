// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "xjtts",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "xjtts",
            path: "Sources"
        )
    ]
)
