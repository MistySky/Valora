// swift-tools-version: 5.9
// Valora local compatibility package for TheDynamicPunk/Convoy DownloadEngine.
// Only DownloadEngine is included. The Convoy app, Sparkle, browser host and
// extensions are intentionally absent.
import PackageDescription

let package = Package(
    name: "Convoy",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DownloadEngine", targets: ["DownloadEngine"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "DownloadEngine",
            dependencies: [.product(name: "Logging", package: "swift-log")]
        )
    ]
)
