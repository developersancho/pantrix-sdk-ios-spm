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
        .binaryTarget(name: "PantrixCore", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.8/PantrixCore-1.0.0-beta.8.xcframework.zip", checksum: "c56d91b6d3c5637cd4766308626192e34647bf340f4f0581c6720b0d337f2533"),
        .binaryTarget(name: "Pantrix", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.8/Pantrix-1.0.0-beta.8.xcframework.zip", checksum: "d79a2288e2b043b00dcf8c3743dc8615ca6c504f47083e071af64a5da0e5d4c5"),
        .binaryTarget(name: "PantrixSwiftUI", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.8/PantrixSwiftUI-1.0.0-beta.8.xcframework.zip", checksum: "39b62425fa9fa556dd24c28fc8f2a13784aaba93101945a4bee03618a8c372ba"),
        .binaryTarget(name: "PantrixCrash", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.8/PantrixCrash-1.0.0-beta.8.xcframework.zip", checksum: "1183038bb17465acd0a70919695b4db3ec9ac5c4ab1be8df382caed413a8ae17"),
        .binaryTarget(name: "PantrixInspectorKit", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.8/PantrixInspectorKit-1.0.0-beta.8.xcframework.zip", checksum: "f68f691df32e0f444ae55a9fa8a07fc158ec5c543fc3c01a8e762eda40ceae31"),
        .binaryTarget(name: "PantrixInspector", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.8/PantrixInspector-1.0.0-beta.8.xcframework.zip", checksum: "4bb9a60fdd9f41f5833a9c8df8a12b819e93b9e93f0453dc3a3e28359a740e3d"),
        .binaryTarget(name: "PantrixFeedbackKit", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.8/PantrixFeedbackKit-1.0.0-beta.8.xcframework.zip", checksum: "d1878d583354a13fb73a9d4f1fd180f48238dd67b272b0181e68815fe1aa38df"),
        .binaryTarget(name: "PantrixFeedback", url: "https://github.com/developersancho/pantrix-sdk-ios-spm/releases/download/1.0.0-beta.8/PantrixFeedback-1.0.0-beta.8.xcframework.zip", checksum: "0d825e94a67f5f8ff725eabbd5dd3aae5a6d1fc9d7dfeb564a55510abd81fbcf"),
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
