// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clove",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Clove",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Clove",
            // The app bundle keeps Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
