// swift-tools-version: 5.9
import PackageDescription

// GENERATED on each release by Scripts/make-spm-package.sh — do not edit by hand.
// Source lives in the private repo: developersancho/pantrix-sdk-ios
let package = Package(
    name: "Pantrix",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(name: "Pantrix", targets: ["Pantrix"]),
        // Opt-in SwiftUI helpers. UIKit-only apps should NOT add this — it links SwiftUI.framework.
        .library(name: "PantrixSwiftUI", targets: ["PantrixSwiftUI"]),
    ],
    targets: [
        // Closed source — the compiled binary xcframework.
        .binaryTarget(
            name: "PantrixCore",
            url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-alpha.3/PantrixCore-1.0.0-alpha.3.xcframework.zip",
            checksum: "24d5d23f27ac4a01c35ee35c892b60669cb3cfd26c2299c965d926ce7eb9ebd9"
        ),
        // Thin open umbrella so consumers just `import Pantrix`.
        .target(
            name: "Pantrix",
            dependencies: ["PantrixCore"]
        ),
        // Open source — SwiftUI glue, compiled in the consumer's build against the binary core.
        // The consumer builds this under swift-tools 5.9 (Swift 5 language mode), so it must stay
        // free of Swift-6-only syntax (see Scripts/build-xcframework.sh notes and the source repo).
        .target(
            name: "PantrixSwiftUI",
            dependencies: ["PantrixCore"]
        ),
    ]
)
