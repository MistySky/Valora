// swift-tools-version: 6.4
import PackageDescription

// Valora: Swift 6 language mode migration of the Alcove music revival sources.
// Deployment baseline is macOS 27.0; no compatibility layer for older systems.
let package = Package(
    name: "Valora",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "Valora", targets: ["Valora"]),
        .executable(name: "ValoraNativeHost", targets: ["ValoraNativeHost"])
    ],
    dependencies: [
        // Local compatibility package: upstream source + reviewed V0029-R1 patch.
        .package(path: "Vendor/Convoy")
    ],
    targets: [
        .target(name: "ReferenceCore"),
        .target(
            name: "ChromeBridgeKit",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .target(
            name: "NativeBridge",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOKit"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "ValoraNativeHost",
            dependencies: ["ChromeBridgeKit"],
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "Valora",
            dependencies: [
                "NativeBridge", "ReferenceCore", "ChromeBridgeKit",
                .product(name: "DownloadEngine", package: "Convoy")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("EventKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVKit")
            ]
        ),
        .testTarget(name: "ReferenceCoreTests", dependencies: ["ReferenceCore"]),
        .testTarget(name: "ValoraTests", dependencies: ["Valora", "ReferenceCore", "ChromeBridgeKit"])
    ],
    swiftLanguageModes: [.v6]
)
