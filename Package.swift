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
            url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-alpha.1/PantrixCore-1.0.0-alpha.1.xcframework.zip",
            checksum: "b97b68869696363ce016e0d0dea1e165cdc9dc8b9a0da5f98c7f638bfd3122f2"
        ),
        // Thin open umbrella so consumers just `import Pantrix`.
        .target(
            name: "Pantrix",
            dependencies: ["PantrixCore"]
        ),
    ]
)
