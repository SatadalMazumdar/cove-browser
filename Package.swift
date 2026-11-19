// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clove",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Clove", path: "Sources/Clove")
    ]
)
