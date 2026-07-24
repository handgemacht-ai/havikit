// swift-tools-version:5.10
import PackageDescription

// HaviKit — the on-device HAVI mobile feedback SDK for iOS. Distributed as a
// standalone Swift Package (`handgemacht-ai/havikit`) and consumed by host apps
// as a versioned dependency. macOS is also declared so the pure-logic targets
// (envelope builder + secret scrub) run under `swift test` on a Mac host with no
// Simulator; the UIKit capture/overlay surface compiles only where
// `canImport(UIKit)` holds (iOS), so those suites run under `xcodebuild test`
// against an iOS Simulator.
let package = Package(
    name: "HaviKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "HaviKit", targets: ["HaviKit"]),
    ],
    targets: [
        .target(name: "HaviKit"),
        .testTarget(
            name: "HaviKitTests",
            dependencies: ["HaviKit"],
            resources: [.process("Fixtures/havi-envelope-golden.json")]
        ),
    ]
)
