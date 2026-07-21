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
        // Opt-in crash reporting. Its handlers grab process-global signal state — add it deliberately.
        .library(name: "PantrixCrash", targets: ["PantrixCrash"]),
        // Opt-in on-device debug inspector. Lists ONLY the view target; its data layer
        // (PantrixInspectorKit) reaches consumers through the view target's `@_exported import`, so a
        // single `import PantrixInspector` names `InspectorConfiguration`. Link a debug/QA app target only.
        .library(name: "PantrixInspector", targets: ["PantrixInspector"]),
        // Opt-in in-app user-feedback tool (screenshot → annotate → e-mail/share). Lists ONLY the view
        // target; its pure logic (PantrixFeedbackKit) reaches consumers through the view target's
        // `@_exported import`, so a single `import PantrixFeedback` names `FeedbackConfiguration`.
        .library(name: "PantrixFeedback", targets: ["PantrixFeedback"]),
    ],
    dependencies: [
        // Used ONLY by the opt-in PantrixAlamofire target.
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.12.0"),
    ],
    targets: [
        // Closed source — the compiled binary xcframework.
        .binaryTarget(
            name: "PantrixCore",
            url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.1/PantrixCore-1.0.0-beta.1.xcframework.zip",
            checksum: "c94e88d00f4188759a5e66ac3e44f26004e6a45571c080338e7b6d3a5de5a3b6"
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
        // Open source — crash add-on. The C target holds the async-signal-safe capture layer (it MUST
        // be C: the Swift runtime is not async-signal-safe); the Swift target is the facade over it +
        // the public reportCrash. Both compile in the consumer's build (Swift 5 mode for the Swift one).
        .target(
            name: "PantrixCrashC"
        ),
        .target(
            name: "PantrixCrash",
            dependencies: ["PantrixCore", "PantrixCrashC"]
        ),
        // Open source — inspector data layer. Pure Foundation + SQLite3; does NOT depend on the binary
        // core (it opens pntrx.db read-only itself), so it links sqlite3 here — the core's link is not
        // transitive. Compiles in the consumer's build under Swift 5 mode.
        .target(
            name: "PantrixInspectorKit",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // Open source — inspector view + presentation. `@_exported import PantrixInspectorKit` re-exports
        // the Kit so a host names `InspectorConfiguration` with one `import PantrixInspector`.
        .target(
            name: "PantrixInspector",
            dependencies: ["PantrixInspectorKit"]
        ),
        // Open source — feedback pure logic. Pure Foundation; does NOT depend on the binary core (feedback
        // talks to no backend and emits no analytics event). Compiles in the consumer's build under Swift 5.
        .target(
            name: "PantrixFeedbackKit"
        ),
        // Open source — feedback view + presentation. `@_exported import PantrixFeedbackKit` re-exports the
        // Kit so a host names `FeedbackConfiguration` with one `import PantrixFeedback`.
        .target(
            name: "PantrixFeedback",
            dependencies: ["PantrixFeedbackKit"]
        ),
    ]
)
