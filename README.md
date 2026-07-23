# Pantrix iOS SDK

Closed-source Pantrix SDK for iOS, distributed as precompiled
binary `XCFramework`s through Swift Package Manager.

[![Release](https://img.shields.io/github/v/release/developersancho/pantrix-sdk-ios-spm?include_prereleases&sort=semver&label=release)](https://github.com/developersancho/pantrix-sdk-ios-spm/releases)
[![Swift Package Manager](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)](https://www.swift.org/package-manager/)
[![Platform](https://img.shields.io/badge/platform-iOS%2013%2B-lightgrey.svg)](#requirements)
[![License](https://img.shields.io/github/license/developersancho/pantrix-sdk-ios-spm)](LICENSE)

> **Distribution package.** This repository ships every Pantrix module as a
> precompiled, closed binary `XCFramework` — core + the `Pantrix` umbrella + the
> opt-in SwiftUI / crash / inspector / feedback add-ons — plus the thin
> `PantrixAlamofire` **source** adapter (it shares your app's own Alamofire). Apps
> use `import Pantrix` and add any opt-in module they need. Generated automatically
> from the private source repository on every release — please don't edit files
> here by hand.

## Requirements

| Tool / OS | Minimum |
|-----------|---------|
| iOS       | 13.0    |
| Xcode     | 16.0    |
| Swift     | 6.0     |

## Installation

### Xcode

1. **File → Add Package Dependencies…**
2. Paste the package URL:
   ```
   https://github.com/developersancho/pantrix-sdk-ios-spm
   ```
3. Pick the version — currently **`1.0.0-beta.3`** — and add the **`Pantrix`** library to your app target.

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/developersancho/pantrix-sdk-ios-spm.git", exact: "1.0.0-beta.3"),
],
```

…and add the product to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "Pantrix", package: "pantrix-sdk-ios-spm"),
        // Optional — only if you use the SwiftUI helpers (see "SwiftUI" below).
        // UIKit-only apps should NOT add this; it links SwiftUI.framework.
        .product(name: "PantrixSwiftUI", package: "pantrix-sdk-ios-spm"),
        // Optional — the Alamofire add-on (see "Alamofire" below). You must ALSO add Alamofire to your
        // own Package.swift + this target — it's a source adapter that shares your app's single Alamofire.
        .product(name: "PantrixAlamofire", package: "pantrix-sdk-ios-spm"),
        // Optional — only if you want automatic fatal-crash reporting (see "Crash reporting" below).
        .product(name: "PantrixCrash", package: "pantrix-sdk-ios-spm"),
        // Optional — only for the on-device debug inspector (see "On-device inspector" below).
        // Debug-only: it refuses to activate in a non-debuggable build.
        .product(name: "PantrixInspector", package: "pantrix-sdk-ios-spm"),
        // Optional — only for the in-app user-feedback tool (see "In-app feedback" below).
        // Debug-only, like the inspector.
        .product(name: "PantrixFeedback", package: "pantrix-sdk-ios-spm"),
    ]
),
```

> `exact:` pins this release and also works for pre-releases. For a stable
> release you may prefer `from: "1.0.0-beta.3"` to automatically receive future
> minor and patch updates.

## Usage

```swift
import Pantrix

// Configure and start the SDK once, early in the app lifecycle
// (e.g. your `App` initializer or `AppDelegate`).
Pantrix.initialize(with: PantrixConfig(token: "px_…", url: "https://your.endpoint") { config in
    config.enableLogging = true
})
Pantrix.start()

// Pause / resume collection, or tear everything down.
Pantrix.stop()
Pantrix.shutdown()
```

## HTTP tracking

Pantrix can record the HTTP requests your app makes — **observe-only**: it reads `URLSessionTaskMetrics`
and does **not** re-issue requests, so your TLS pinning, cookies, cache and streaming are untouched.
Build your session from `Pantrix.instrumentedSession` instead of `URLSession(...)`; your own delegate
still receives every callback:

```swift
import Pantrix

let session = Pantrix.instrumentedSession(configuration: .default, delegate: myDelegate)
session.dataTask(with: url) { data, response, error in /* … */ }.resume()
```

Only **method / url / status / timing** are captured by default. Request/response headers and bodies
are opt-in via `PantrixConfig` (`trackHttpHeaders` / `trackHttpBody`), and are redacted (sensitive
headers stripped, secret keys masked, bodies capped at 256 KB).

- Only sessions you build through `instrumentedSession` are observed — **not** `URLSession.shared`,
  background sessions, pre-existing sessions, or other SDKs' sessions.
- The SDK never captures its own upload/config traffic (those use their own sessions).
- **Response bodies** are captured automatically only for delegate-based data tasks
  (`dataTask(with:).resume()` with no completion handler). For completion-handler / `async` / Alamofire
  requests, report the body you already hold: `Pantrix.trackHttp(…, responseBody:, responseContentType:)`.
- For non-`URLSession` stacks, the same manual `Pantrix.trackHttp(...)` reports the whole exchange.
- Turn it all off with `eventTypeBlocklist = ["network"]`.

### Alamofire

If your app uses [Alamofire](https://github.com/Alamofire/Alamofire), add the **`PantrixAlamofire`**
product **and add Alamofire to your own package + target**. Unlike the other modules it ships as a thin
**source** adapter, so it shares your app's single Alamofire copy — but SPM only lets your code
`import Alamofire` (which you need to build a `Session`) if you declare it yourself: add
`.package(url: "https://github.com/Alamofire/Alamofire", from: "5.12.0")` and, in your target,
`.product(name: "Alamofire", package: "Alamofire")`. Then attach the Pantrix `EventMonitor` when building
your `Session` — every request is tracked (response body included), tagged `client: "alamofire"`, without
changing the request:

```swift
import PantrixAlamofire
import Alamofire

let session = Session(eventMonitors: [PantrixEventMonitor()])
session.request("https://api.example.com/users").responseDecodable(of: [User].self) { … }
```

### Crash reporting

The optional **`PantrixCrash`** product captures fatal crashes and reports them on the next launch.
It installs process-global signal / exception handlers, so it is opt-in and **not** part of the
umbrella — add the product deliberately and call `enable()` once, right after `initialize`:

```swift
import PantrixCrash

Pantrix.initialize(with: config)
PantrixCrash.enable()
```

Handled (non-fatal) exceptions don't need this add-on — report them anytime with
`Pantrix.trackException(error)`. Crash stack frames are symbolicated server-side from your dSYMs;
the device only sends addresses. Coexists with other crash reporters (Crashlytics/Sentry) by chaining
their handlers, but running a single primary reporter is recommended.

### Symbolication — upload your dSYMs

A crash frame is a slid hex address with no symbols. The **only** thing that turns it back into a
function name is that build's **dSYM**, matched by its image UUID — so every released build's dSYMs
must be uploaded once. Xcode deletes dSYMs when a build machine is recycled, so do it at archive time.
This package ships a helper, `Scripts/pantrix-upload-dsym.sh`, inside its SwiftPM checkout.

**Recommended — an Xcode Archive post-action** (fires on ⌘⇧A → TestFlight/App Store, and sees the
complete `dSYMs/` incl. the prebuilt `PantrixCore.framework.dSYM`):

1. **Product → Scheme → Edit Scheme… → Archive → Post-actions → `+` → New Run Script Action.**
2. Set **Provide build settings from** to your app target (so `$ARCHIVE_PATH` is defined).
3. Paste:

   ```sh
   "${BUILD_DIR%/Build/*}/SourcePackages/checkouts/pantrix-sdk-ios-spm/Scripts/pantrix-upload-dsym.sh" \
     --archive "$ARCHIVE_PATH"
   ```

**Credentials** — put a **gitignored** `.pantrixrc` at your repo root (the script walks up from
`$SRCROOT` to find it), or set the same names as CI secrets:

```sh
PANTRIX_API_URL="https://<your-pantrix-host>/api"
PANTRIX_CI_KEY="pxu_…"   # a CI key (key_type=CI) — NOT your SDK ingest key
```

> The CI key is **not** the SDK key you pass to `initialize`. The SDK key ships inside the app and the
> backend **rejects it here (401)** so nobody can poison your symbols. Never commit either key, and
> never let the CI key ship in the app.

**CI / release pipeline** — after `xcodebuild archive`, point the same script at the `.xcarchive`
(credentials from the environment):

```sh
SPM_CHECKOUT="$(find ~/Library/Developer/Xcode/DerivedData -type d \
  -path '*/SourcePackages/checkouts/pantrix-sdk-ios-spm' | head -1)"

PANTRIX_API_URL="…" PANTRIX_CI_KEY="pxu_…" \
  "$SPM_CHECKOUT/Scripts/pantrix-upload-dsym.sh" --archive build/MyApp.xcarchive
```

Bitcode is gone (Xcode 14+), so your archive's dSYMs already match the App Store binary — there is
**no** manual "download dSYMs from App Store Connect" step.

## SwiftUI

The optional **`PantrixSwiftUI`** product adds opt-in, developer-named helpers for SwiftUI — the
counterpart of the automatic UIKit view-controller tracking (which can't see SwiftUI screens). Add
the `PantrixSwiftUI` product (see [Installation](#installation)) and `import PantrixSwiftUI`. Each
helper takes a stable `name`; **only that name (and any metadata you pass) leaves the device** — no
view text, and no navigation argument values, are ever collected.

```swift
import PantrixSwiftUI

// Screen — report a SwiftUI screen when it appears (tagged so it's distinct from a manual trackScreen)
HomeView()
    .trackScreen("Home")

// Taps — use trackedTap for a Button (it already owns a click), trackTap for a plain view
Button(action: trackedTap("save_button") { viewModel.save() }) { Text("Save") }
Text("Subscribe").trackTap("subscribe_row") { subscribe() }

// Tap + long-press
row.trackTaps("list_item", onLongPress: { showMenu() }) { open() }

// Scroll — pair the container marker with the content modifier
ScrollView {
    LazyVStack { /* rows */ }
        .trackScroll("product_feed")
}
.pantrixScrollContainer()

// Navigation (iOS 16+) — report each NavigationStack destination; each route names itself
NavigationStack(path: $path) { /* … */ }
    .trackNavigation(path: path)   // Route: Hashable & PantrixScreenNameProviding

// Anything the modifiers can't reach — emit from inside a handler you own
Button { PantrixTrack.tap("save_button"); viewModel.save() } label: { Text("Save") }
```

### Availability

The `PantrixSwiftUI` product itself builds at the package floor (**iOS 13**), but several helpers rely
on newer SwiftUI APIs and are **documented no-ops** below their floor — attaching them does no harm,
they just don't report until the OS supports them:

| Helper | Works from | Below that |
|---|---|---|
| `trackScreen`, `trackTap`, `trackTaps`, `trackedTap`, `trackScroll`, `trackDrag`, `PantrixTrack.*` | iOS 13 | — |
| `trackScreen` re-report on a name change | iOS 14 | reports on appear only |
| `trackHover` | iOS 13.4 | no-op |
| `trackFocus(isFocused:)` | iOS 14 | no-op (use `trackedEditingChanged` for a `TextField`) |
| `trackNavigation(path:)` | iOS 16 | not available (`NavigationStack` is iOS 16) |

## On-device inspector

The optional **`PantrixInspector`** product is a **debug-only**, read-only UI that shows the telemetry
Pantrix has already stored — the queued events, captured HTTP exchanges, pending crashes, and live
device/performance signals. It ships as source and refuses to activate in a non-debuggable build, so it is
safe to leave wired in. Add the `PantrixInspector` product and call `enable()` once, ideally behind your
own `#if DEBUG`:

```swift
import PantrixInspector

Pantrix.initialize(with: config)
#if DEBUG
PantrixInspector.enable()
#endif

// Then open it from a debug affordance:
PantrixInspector.present(from: self)            // UIKit
let vc = PantrixInspector.makeViewController()  // SwiftUI — host it yourself
```

Gate your own "Open Inspector" button on `PantrixInspector.isAvailable` so a release build (which won't
open it) doesn't show a dead menu item. Optional zero-code launchers — a device **shake** or a floating
**bubble** — are off by default:

```swift
var config = InspectorConfiguration()
config.enablesShakeToOpen = true
config.showsFloatingBubble = true
PantrixInspector.enable(config)
```

The inspector activates only on **iOS 15+** in a **debuggable** build (App Store builds show nothing). To
reach it in **TestFlight** QA, set `config.allowsInReleaseBuilds = true` — a deliberate opt-in. Network
request/response bodies appear only if you enabled HTTP body capture; the same redaction is applied. Full
guide: [`Docs/PANTRIX_INSPECTOR.md`](Docs/PANTRIX_INSPECTOR.md).

## In-app feedback

The optional **`PantrixFeedback`** product is a **debug-only** in-app user-feedback tool: it captures a
screenshot of the current screen, lets the user annotate it (PencilKit) and type a message, then opens the
system **mail composer or share sheet** addressed to an e-mail **you** configure. It depends on nothing else
(no backend, no analytics event) and, like the inspector, refuses to activate in a non-debuggable build —
**feedback never reaches Pantrix**, only the destination the user picks.

```swift
import PantrixFeedback

#if DEBUG
var config = FeedbackConfiguration()
config.recipientEmail = "feedback@yourteam.com"
config.enablesShakeGesture = true   // optional: open on a device shake (CoreMotion)
PantrixFeedback.enable(config)
#endif

// Open it from your own "Send Feedback" button:
PantrixFeedback.show(from: self)               // UIKit
// let vc = topViewController; PantrixFeedback.show(from: vc)  // SwiftUI
```

Gate your affordance on `PantrixFeedback.isAvailable`. Reach it in **TestFlight** QA with
`config.debugOnly = false`. If you also use `PantrixInspector`'s shake, enable shake on **only one** of them
(the other gets a button) — a single shake would otherwise open both. Full guide:
[`Docs/PANTRIX_FEEDBACK.md`](Docs/PANTRIX_FEEDBACK.md).

## App Store submission checklist

Pantrix ships an Apple **privacy manifest** (`PrivacyInfo.xcprivacy`) inside the framework, so the
required-reason APIs it uses (`SystemBootTime`, `UserDefaults`, `FileTimestamp`) are **already
declared for you** — you don't need to add them to your app. Xcode picks them up automatically in
**Product → Archive → Privacy Report**.

Three things are still on you:

### 1. Privacy nutrition label (App Store Connect)

Pantrix collects the data below. Declare it under **App Store Connect → App Privacy**, or your label
will contradict the generated Privacy Report.

| App Store Connect category | Collected because | Linked to user | Used for tracking |
|---|---|---|---|
| Identifiers → **Device ID** | `installId`, plus `identifierForVendor` when `collectDeviceId` is on (**on by default**) | Yes | No |
| Identifiers → **User ID** | only if you call `Pantrix.setUser(userId:)` | Yes | No |
| Usage Data → **Product Interaction** | screen views + custom events | Yes | No |
| Diagnostics → **Crash Data** | crash reports | Yes | No |
| Diagnostics → **Performance Data** | CPU / memory / network throughput | Yes | No |
| Diagnostics → **Other Diagnostic Data** | device, session and lifecycle diagnostics | Yes | No |

Purposes: **Analytics** and **App Functionality**. Pantrix performs **no** tracking as Apple defines
it (no data brokers, no cross-app/website joining for advertising), so *Used for Tracking* is **No**
everywhere and **no ATT prompt is required** — Pantrix never touches the IDFA.

> Anything **you** put into custom-event attributes or user properties is yours to declare. Don't
> pass names, emails or other PII unless your label says so.

### 2. Use HTTPS for the ingest URL

Point `PantrixConfig.url` at an **`https://`** endpoint. `allowInsecureConnection` exists only for
local debugging against a dev server — shipping it forces an
`NSAppTransportSecurity` / `NSAllowsArbitraryLoads` exception in your `Info.plist`, which App Review
will ask you to justify.

### 3. Export compliance

Pantrix uses only Apple's standard cryptography — HTTPS, plus CryptoKit AES-GCM when you opt into
`storageEncryption` (**off by default**). This normally falls under the standard exemption, so most
apps declare `ITSAppUsesNonExemptEncryption = false` in `Info.plist`. Confirm with whoever owns
compliance at your company.

## Versioning

This package follows [Semantic Versioning](https://semver.org). Pre-release
builds are tagged like `1.0.0-alpha.1` and must be referenced explicitly with
`exact:`, since SwiftPM excludes pre-releases from `from:` / range requirements.

**Latest release:** `1.0.0-beta.3`

## License

Distributed under the terms of the [LICENSE](LICENSE) file in this repository.

---

<sub>This README is generated on every release by the source repo's <code>Scripts/make-readme.sh</code> — do not edit by hand.</sub>
