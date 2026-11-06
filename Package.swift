// swift-tools-version: 6.4
import PackageDescription

// Valora: Swift 6 language mode migration of the Alcove music revival sources.
// Deployment baseline is macOS 27.0; no compatibility layer for older systems.
let package = Package(
    name: "Valora",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "Valora", targets: ["Valora"])
    ],
    targets: [
        .target(name: "ReferenceCore"),
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
            name: "Valora",
            dependencies: [
                "NativeBridge", "ReferenceCore"
            ],
            // Development-only verification suites, audits and preview surfaces
            // are compiled out of release builds. The users' release app must
            // not contain their implementations or executable entry points.
            swiftSettings: [
                .define("VALORA_DEVELOPMENT", .when(configuration: .debug))
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
        .testTarget(name: "ValoraTests", dependencies: ["Valora", "ReferenceCore"])
    ],
    swiftLanguageModes: [.v6]
)
