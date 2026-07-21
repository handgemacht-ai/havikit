// swift-tools-version:5.10
import PackageDescription

// HaviKit — the on-device HAVI mobile feedback SDK (design §1). A local SPM
// package (precedent: AzureSpeech) the app consumes as iOS 17. macOS is also
// declared so the pure-logic targets (envelope builder + secret scrub) run under
// `swift test` on the Mac host without a Simulator; nothing in these two
// work-items touches UIKit.
let package = Package(
    name: "HaviKit",
    platforms: [.iOS(.v17), .macOS(.v12)],
    products: [
        .library(name: "HaviKit", targets: ["HaviKit"]),
    ],
    targets: [
        .target(name: "HaviKit"),
        .testTarget(name: "HaviKitTests", dependencies: ["HaviKit"]),
    ]
)
