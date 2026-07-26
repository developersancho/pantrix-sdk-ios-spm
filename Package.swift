// swift-tools-version: 5.9
import PackageDescription

// GENERATED on each release by Scripts/make-spm-package.sh — do not edit by hand.
// Source lives in the private repo: developersancho/pantrix-sdk-ios
//
// Every module ships as a closed binary XCFramework EXCEPT PantrixAlamofire, which is a SOURCE target: it
// interoperates with the consumer's own Alamofire (a host passes `PantrixEventMonitor` into its own
// `Session`), so it must compile against and share that single Alamofire copy — a binary framework would
// embed a second Alamofire and split the `EventMonitor` conformance. A binaryTarget cannot declare
// dependencies, so each library product lists its full binary closure (e.g. PantrixSwiftUI pulls in
// PantrixCore). PantrixCrashC is folded into PantrixCrash's framework (not a separate binary). The
// Inspector/Feedback Kits stay separate binaries so their view target's `@_exported import` re-export resolves.
let package = Package(
    name: "Pantrix",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        // Umbrella — `import Pantrix` (re-exports PantrixCore).
        .library(name: "Pantrix", targets: ["Pantrix", "PantrixCore"]),
        // Opt-in SwiftUI helpers. UIKit-only apps should NOT add this — it links SwiftUI.framework.
        .library(name: "PantrixSwiftUI", targets: ["PantrixSwiftUI", "PantrixCore"]),
        // Opt-in Alamofire tracking. Ships as a thin SOURCE adapter (`PantrixEventMonitor`) that shares your
        // app's single Alamofire — SPM pulls Alamofire in transitively via this package's dependency below.
        .library(name: "PantrixAlamofire", targets: ["PantrixAlamofire", "PantrixCore"]),
        // Opt-in crash reporting. Its handlers grab process-global signal state — add it deliberately.
        .library(name: "PantrixCrash", targets: ["PantrixCrash", "PantrixCore"]),
        // Opt-in on-device debug inspector. The Kit reaches consumers via the view's `@_exported import`.
        .library(name: "PantrixInspector", targets: ["PantrixInspector", "PantrixInspectorKit"]),
        // Opt-in in-app user-feedback tool. The Kit reaches consumers via the view's `@_exported import`.
        .library(name: "PantrixFeedback", targets: ["PantrixFeedback", "PantrixFeedbackKit"]),
        // No-op twins of the two debug tools (Android's `-noop` analogue). Same PUBLIC API as the real
        // products but inert, and SOURCE with NO Kit dependency — a host links one of these in a Release
        // build INSTEAD of the real product so none of the debug-tool code (or its Kit) ships in that binary.
        // SPM has no per-configuration dependency (unlike Gradle's `releaseImplementation`); guard the import
        // with your own flag and link the chosen product per Xcode configuration.
        .library(name: "PantrixInspectorNoop", targets: ["PantrixInspectorNoop"]),
        .library(name: "PantrixFeedbackNoop", targets: ["PantrixFeedbackNoop"]),
    ],
    dependencies: [
        // Pulled in ONLY by the source PantrixAlamofire adapter. SPM resolves ONE shared Alamofire across
        // your app and this adapter, so `PantrixEventMonitor` and your own `Session` speak the same types.
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.12.0"),
    ],
    targets: [
        .binaryTarget(name: "PantrixCore", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.13/PantrixCore-1.0.0-beta.13.xcframework.zip", checksum: "05307801f901fcabb045cfcd4a39eb95204cdb5c771080079869db224b37afa8"),
        .binaryTarget(name: "Pantrix", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.13/Pantrix-1.0.0-beta.13.xcframework.zip", checksum: "f43458a5b93a037f1b86a3701c76f8331a466ce523485f63db96e3d0a0727ead"),
        .binaryTarget(name: "PantrixSwiftUI", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.13/PantrixSwiftUI-1.0.0-beta.13.xcframework.zip", checksum: "26e283537dc62b3242e09c91f5447340c8cdc8588921974471832dd69ae20b01"),
        .binaryTarget(name: "PantrixCrash", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.13/PantrixCrash-1.0.0-beta.13.xcframework.zip", checksum: "6c18ab39d327be260489606b98a77825ec64378ef92fb443a5a2527c37bdb8cf"),
        .binaryTarget(name: "PantrixInspectorKit", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.13/PantrixInspectorKit-1.0.0-beta.13.xcframework.zip", checksum: "17f7ae7637e004108a51b1a6ecf397a5fb576ea54d5029c0401b35b9e817fc3d"),
        .binaryTarget(name: "PantrixInspector", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.13/PantrixInspector-1.0.0-beta.13.xcframework.zip", checksum: "f1cfc98f04c05a62053ebfa437c8107883ce3c25fce48185ab5be7230c43a8a5"),
        .binaryTarget(name: "PantrixFeedbackKit", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.13/PantrixFeedbackKit-1.0.0-beta.13.xcframework.zip", checksum: "f89a2e0b0fbe6abc51fb1e0412c9059ee76256be240f220f643289e4d6197734"),
        .binaryTarget(name: "PantrixFeedback", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.13/PantrixFeedback-1.0.0-beta.13.xcframework.zip", checksum: "ce625af83c426bc67b49431e406f02513553b0042d0e155ad4a91a464b42de85"),
        // SOURCE adapter (not a binary) — see the header note. Compiles in the consumer's build against the
        // binary PantrixCore and the shared Alamofire.
        .target(
            name: "PantrixAlamofire",
            dependencies: [
                "PantrixCore",
                .product(name: "Alamofire", package: "Alamofire"),
            ],
            path: "Sources/PantrixAlamofire"
        ),
        // No-op twins — inert SOURCE stubs of the two debug tools' public API (see the products above). No
        // Kit dependency, so linking a noop ships none of the real inspector/feedback code.
        .target(name: "PantrixInspectorNoop", path: "Sources/PantrixInspectorNoop"),
        .target(name: "PantrixFeedbackNoop", path: "Sources/PantrixFeedbackNoop"),
    ]
)
