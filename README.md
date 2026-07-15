# Pantrix iOS SDK

Closed-source Pantrix SDK for Apple platforms, distributed as a precompiled
binary `XCFramework` through Swift Package Manager.

[![Release](https://img.shields.io/github/v/release/developersancho/pantrix-sdk-ios-spm?include_prereleases&sort=semver&label=release)](https://github.com/developersancho/pantrix-sdk-ios-spm/releases)
[![Swift Package Manager](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)](https://www.swift.org/package-manager/)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2015%2B%20%7C%20macOS%2012%2B-lightgrey.svg)](#requirements)
[![License](https://img.shields.io/github/license/developersancho/pantrix-sdk-ios-spm)](LICENSE)

> **Distribution package.** This repository ships a precompiled
> `PantrixCore.xcframework` plus a thin `Pantrix` umbrella module, so apps only
> need `import Pantrix`. It is generated automatically from the private source
> repository on every release — please don't edit files here by hand.

## Requirements

| Tool / OS | Minimum |
|-----------|---------|
| iOS       | 15.0    |
| macOS     | 12.0    |
| Xcode     | 16.0    |
| Swift     | 6.0     |

## Installation

### Xcode

1. **File → Add Package Dependencies…**
2. Paste the package URL:
   ```
   https://github.com/developersancho/pantrix-sdk-ios-spm
   ```
3. Pick the version — currently **`1.0.0-alpha.4`** — and add the **`Pantrix`** library to your app target.

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/developersancho/pantrix-sdk-ios-spm.git", exact: "1.0.0-alpha.4"),
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
        // Optional — only if you use Alamofire (see "Alamofire" below). Pulls Alamofire in.
        .product(name: "PantrixAlamofire", package: "pantrix-sdk-ios-spm"),
    ]
),
```

> `exact:` pins this release and also works for pre-releases. For a stable
> release you may prefer `from: "1.0.0-alpha.4"` to automatically receive future
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
product and attach the Pantrix `EventMonitor` when building your `Session` — every request is then
tracked (response body included), tagged `client: "alamofire"`, without changing the request:

```swift
import PantrixAlamofire

let session = Session(eventMonitors: [PantrixEventMonitor()])
session.request("https://api.example.com/users").responseDecodable(of: [User].self) { … }
```

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

**Latest release:** `1.0.0-alpha.4`

## License

Distributed under the terms of the [LICENSE](LICENSE) file in this repository.

---

<sub>This README is generated on every release by the source repo's <code>Scripts/make-readme.sh</code> — do not edit by hand.</sub>
