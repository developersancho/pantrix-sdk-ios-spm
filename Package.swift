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
        // Opt-in Alamofire tracking. Only apps that use it pull Alamofire in.
        .library(name: "PantrixAlamofire", targets: ["PantrixAlamofire"]),
    ],
    dependencies: [
        // Used ONLY by the opt-in PantrixAlamofire target.
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.12.0"),
    ],
    targets: [
        // Closed source — the compiled binary xcframework.
        .binaryTarget(
            name: "PantrixCore",
            url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-alpha.5/PantrixCore-1.0.0-alpha.5.xcframework.zip",
            checksum: "67ccd60619510ff8dd60ad429acad7b2cd9ff1a9a8077bc6db0eff7a0543b47d"
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
        // Open source — Alamofire EventMonitor glue over the public trackHttp facade.
        .target(
            name: "PantrixAlamofire",
            dependencies: ["PantrixCore", .product(name: "Alamofire", package: "Alamofire")]
        ),
    ]
)
