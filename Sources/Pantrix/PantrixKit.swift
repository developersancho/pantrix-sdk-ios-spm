
// The umbrella module consumers `import Pantrix` — the iOS analogue of Android's fused AAR.
// It fuses the shipped pieces so a single import exposes everything:
//   • `PantrixCore` — the closed `PantrixCore.xcframework` (facade, pipeline, collectors)
//
// compiled from source; only `PantrixCore` is the binary.
//
// The SwiftUI helpers (`View.trackScreen`, `.trackTap`, …) deliberately live in a SEPARATE, opt-in
// `PantrixSwiftUI` product and are NOT re-exported here: re-exporting them would drag SwiftUI.framework
// into the dyld graph of every host, including pure-UIKit ones. SwiftUI hosts add that product and
// `import PantrixSwiftUI` alongside this.
@_exported import PantrixCore
