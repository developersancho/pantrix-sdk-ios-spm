// swift-tools-version: 5.9
import PackageDescription

// GENERATED on each release by Scripts/make-spm-package.sh — do not edit by hand.
// Source lives in the private repo: developersancho/pantrix-sdk-ios
let package = Package(
    name: "Pantrix",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "Pantrix", targets: ["Pantrix"]),
    ],
    targets: [
        // Closed source — the compiled binary xcframework.
        .binaryTarget(
            name: "PantrixCore",
            url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-alpha.2/PantrixCore-1.0.0-alpha.2.xcframework.zip",
            checksum: "d9003fe35940f7bc8a8e8e4487cb3d19539ccd6fc25f599f4dc85c1521411b19"
        ),
        // Thin open umbrella so consumers just `import Pantrix`.
        .target(
            name: "Pantrix",
            dependencies: ["PantrixCore"]
        ),
    ]
)
