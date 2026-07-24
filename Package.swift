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
        .binaryTarget(name: "PantrixCore", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.11/PantrixCore-1.0.0-beta.11.xcframework.zip", checksum: "1cab2b8e9ee30b30acdf4386c1929dfcda96da941d53f765a6db71634ec0f5fc"),
        .binaryTarget(name: "Pantrix", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.11/Pantrix-1.0.0-beta.11.xcframework.zip", checksum: "f2f3c80f622d6197ac5030d4caee00de811445724b21ba262e13ef7652157da4"),
        .binaryTarget(name: "PantrixSwiftUI", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.11/PantrixSwiftUI-1.0.0-beta.11.xcframework.zip", checksum: "e8a7332e94f44949af55e16df849821b10bcf02699259d821eec85f97245050b"),
        .binaryTarget(name: "PantrixCrash", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.11/PantrixCrash-1.0.0-beta.11.xcframework.zip", checksum: "24f52038e5287e59e7f0b6a5661e0907e51282322f25469903964429e3101ce8"),
        .binaryTarget(name: "PantrixInspectorKit", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.11/PantrixInspectorKit-1.0.0-beta.11.xcframework.zip", checksum: "9a884256094383627a4f2d5db06b2f9c6751b17d4a02f640bb339f2ce004795d"),
        .binaryTarget(name: "PantrixInspector", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.11/PantrixInspector-1.0.0-beta.11.xcframework.zip", checksum: "65e87760a3a02f0412783795cb93d94eab54157b55acfdbadcc6241c2c9d9766"),
        .binaryTarget(name: "PantrixFeedbackKit", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.11/PantrixFeedbackKit-1.0.0-beta.11.xcframework.zip", checksum: "d866b23352d7480ed3a8357f102f144abcb9611651f36c968a0deb8817e27833"),
        .binaryTarget(name: "PantrixFeedback", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.11/PantrixFeedback-1.0.0-beta.11.xcframework.zip", checksum: "c1b27d02d662fa8e645b445b7fb6de86af1b268ece4c2b4213c10ace7abcb005"),
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
