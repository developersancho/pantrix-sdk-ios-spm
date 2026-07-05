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
3. Pick the version — currently **`1.0.0-alpha.2`** — and add the **`Pantrix`** library to your app target.

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/developersancho/pantrix-sdk-ios-spm.git", exact: "1.0.0-alpha.2"),
],
```

…and add the product to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "Pantrix", package: "pantrix-sdk-ios-spm"),
    ]
),
```

> `exact:` pins this release and also works for pre-releases. For a stable
> release you may prefer `from: "1.0.0-alpha.2"` to automatically receive future
> minor and patch updates.

## Usage

```swift
import Pantrix

// Shared entry point of the SDK.
let sdk = Pantrix.shared
print(sdk.hello())     // greeting from the SDK
print(sdk.version)     // the SDK's build version
```

## Versioning

This package follows [Semantic Versioning](https://semver.org). Pre-release
builds are tagged like `1.0.0-alpha.1` and must be referenced explicitly with
`exact:`, since SwiftPM excludes pre-releases from `from:` / range requirements.

**Latest release:** `1.0.0-alpha.2`

## License

Distributed under the terms of the [LICENSE](LICENSE) file in this repository.

---

<sub>This README is generated on every release by the source repo's <code>Scripts/make-readme.sh</code> — do not edit by hand.</sub>
