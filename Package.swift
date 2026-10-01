// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kill9",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Kill9", path: "Sources/Kill9")
    ]
)
