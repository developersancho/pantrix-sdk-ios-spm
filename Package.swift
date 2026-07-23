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
        .binaryTarget(name: "PantrixCore", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.7/PantrixCore-1.0.0-beta.7.xcframework.zip", checksum: "ddfc254c871e95d528c7a4195b4dee2860ba5327445a891bd7836e1b4c6eaff4"),
        .binaryTarget(name: "Pantrix", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.7/Pantrix-1.0.0-beta.7.xcframework.zip", checksum: "4858a0def1d7cb612a319c4f6b669c05e0a19fe4645f57939610fb31faa71850"),
        .binaryTarget(name: "PantrixSwiftUI", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.7/PantrixSwiftUI-1.0.0-beta.7.xcframework.zip", checksum: "6aa621e5984e81eacc6c1a1477a60d0ebde933a42d3ac409f23e34163fffb89c"),
        .binaryTarget(name: "PantrixCrash", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.7/PantrixCrash-1.0.0-beta.7.xcframework.zip", checksum: "9d401c99e4d90a78faa918bc8144508d88ea6ed60e3bb7bcfa37fa4614e0ebb2"),
        .binaryTarget(name: "PantrixInspectorKit", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.7/PantrixInspectorKit-1.0.0-beta.7.xcframework.zip", checksum: "17a1382b63e1521f2cbc8b473582e6832d8fc95bc1c3d204b6a3e00c3a2377a4"),
        .binaryTarget(name: "PantrixInspector", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.7/PantrixInspector-1.0.0-beta.7.xcframework.zip", checksum: "0655b8139e8be1f68a630ec4940cce86a1fcbf6b6c70a531c8c95e49d2a1403b"),
        .binaryTarget(name: "PantrixFeedbackKit", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.7/PantrixFeedbackKit-1.0.0-beta.7.xcframework.zip", checksum: "dc83f199551a890245f2cafef031554005d2a4806f1d88400ef91fa56cd4af68"),
        .binaryTarget(name: "PantrixFeedback", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.7/PantrixFeedback-1.0.0-beta.7.xcframework.zip", checksum: "8ccd2168bf29d9b7d37a2fcd03b13c79bff67a12aaa7199a3d241d61af419d29"),
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
