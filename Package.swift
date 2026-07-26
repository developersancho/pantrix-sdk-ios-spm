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
        .binaryTarget(name: "PantrixCore", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.12/PantrixCore-1.0.0-beta.12.xcframework.zip", checksum: "65cfc779550c6ee22b9a104c764277f6d3185ef34423f39caca5e8dd7ed26d92"),
        .binaryTarget(name: "Pantrix", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.12/Pantrix-1.0.0-beta.12.xcframework.zip", checksum: "c83c134a2abcc2886fd469bebceff65019575cbeb9da8422bc7483da0e4a2dea"),
        .binaryTarget(name: "PantrixSwiftUI", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.12/PantrixSwiftUI-1.0.0-beta.12.xcframework.zip", checksum: "29fa3d6361ceb8e833ff204d51d244e7508f39eb65b198392445495d0def874b"),
        .binaryTarget(name: "PantrixCrash", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.12/PantrixCrash-1.0.0-beta.12.xcframework.zip", checksum: "798f79a84ec85a2e4eb1dd1f6e10fbfc81f2e9338662ec261000fdf2352ad5f8"),
        .binaryTarget(name: "PantrixInspectorKit", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.12/PantrixInspectorKit-1.0.0-beta.12.xcframework.zip", checksum: "e8e9f806908cee225944a2bbc0bf5218343c28bb73592b12d239ee922d662078"),
        .binaryTarget(name: "PantrixInspector", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.12/PantrixInspector-1.0.0-beta.12.xcframework.zip", checksum: "e50a84c08cf98204b3d92c4f4562a3e2ce32f99a81ed0a9ecddb2cbd5dfd408b"),
        .binaryTarget(name: "PantrixFeedbackKit", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.12/PantrixFeedbackKit-1.0.0-beta.12.xcframework.zip", checksum: "a9d45a9dfcf320512de52d4174a51030d5d534393c9a1ddfe91feabfa0c5fe51"),
        .binaryTarget(name: "PantrixFeedback", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.12/PantrixFeedback-1.0.0-beta.12.xcframework.zip", checksum: "240dd81e10dc397d8ccafd516d729598d0bc8b9056ce3c352e64afcd9acdfe8b"),
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
