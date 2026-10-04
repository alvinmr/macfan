// swift-tools-version: 6.2
import PackageDescription

/// Approachable Concurrency: `async` functions run where they're called unless marked
/// `@concurrent`, and conformances can be inferred as isolated.
let approachableConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

/// The app is UI code: it lives on the main actor unless it says otherwise.
/// Libraries do *not* get this; they ship `nonisolated` APIs and let callers decide.
let appSettings = approachableConcurrency + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "MacFan",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacFan", targets: ["MacFan"]),
        .executable(name: "macfan-helper", targets: ["MacFanHelper"]),
        .executable(name: "macfan", targets: ["MacFanCLI"]),
        .library(name: "MacFanCore", targets: ["MacFanCore"]),
    ],
    dependencies: [
        // Self-updates for the app. Pinned exactly: the release workflow uses the same version's tools.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // Layout-exact C declarations for the AppleSMC user client and the
        // private IOHIDEventSystem temperature API. No logic lives here.
        .target(
            name: "CPrivateIOKit",
            linkerSettings: [.linkedFramework("IOKit")]
        ),

        // Talks to the System Management Controller: read/write keys, decode values, fan control.
        .target(
            name: "SMCKit",
            dependencies: ["CPrivateIOKit"],
            swiftSettings: approachableConcurrency,
            linkerSettings: [.linkedFramework("IOKit")]
        ),

        // Platform-independent domain: sensors, fans, curves, safety, history, logging.
        .target(
            name: "MacFanCore",
            dependencies: ["SMCKit", "CPrivateIOKit"],
            swiftSettings: approachableConcurrency,
            linkerSettings: [.linkedFramework("IOKit")]
        ),

        // The XPC contract shared by the app and the privileged helper.
        .target(name: "MacFanXPC", swiftSettings: approachableConcurrency),

        // Root daemon that performs SMC writes on behalf of the app.
        .executableTarget(
            name: "MacFanHelper",
            dependencies: ["SMCKit", "MacFanXPC"],
            swiftSettings: approachableConcurrency
        ),

        // `macfan` command-line tool: inspect sensors, fans and raw SMC keys.
        .executableTarget(
            name: "MacFanCLI",
            dependencies: ["MacFanCore", "SMCKit"],
            swiftSettings: approachableConcurrency
        ),

        // The SwiftUI app.
        .executableTarget(
            name: "MacFan",
            dependencies: [
                "MacFanCore",
                "MacFanXPC",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: appSettings
        ),

        .testTarget(name: "SMCKitTests", dependencies: ["SMCKit"], swiftSettings: approachableConcurrency),
        .testTarget(name: "MacFanCoreTests", dependencies: ["MacFanCore"], swiftSettings: approachableConcurrency),
    ]
)
